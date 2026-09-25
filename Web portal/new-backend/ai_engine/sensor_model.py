"""PotholeEngine: runs the AI team's sensor model on every uploaded sensor batch.

Enable it in `.env`:
    ROADGUARD_AI_ENGINE=ai_engine.sensor_model.PotholeEngine

For each batch (detection/pipeline.py calls analyze()):
1. Put the batch and the few seconds before it (`context`) on the 5 Hz clock
   (preprocessing.py).
2. Cut 2-second windows (10 points), lined up on a fixed 2-second clock, the
   same non-overlapping way the model was trained. Each window is judged
   exactly once: by the batch in which it ends (so a pothole that straddles
   two uploads is still seen whole, and never reported twice).
3. Skip windows below the model's speed gate (10 km/h): no prediction there.
4. Turn each window to the training orientation (optional), compute the 34
   features (features.py) and ask the Random Forest for a probability.
5. At or above the model's calibrated threshold (0.37) → a detection at the
   moment of the strongest jolt in the window, with a 0–1 hit strength.
6. Detections less than 2 s apart (the same pothole) are merged.

Why windows are not overlapping: measured on the training trips, sliding
windows (every 0.2 s or 1 s) gave about twice as many false alarms per km
(1.3–1.7/km) as the 2-second steps used in training (0.7/km), for the same
potholes found.
"""

import pickle
import warnings
from datetime import datetime, timezone as dt_timezone
from functools import lru_cache
from hashlib import sha256
from pathlib import Path

import numpy as np
from django.conf import settings

from detection.engine import DetectionEngine, DetectionResult

from .features import FEATURE_COLUMNS, window_features
from .preprocessing import SAMPLE_SECONDS, align_to_training, build_timeline

# Detections closer together than this are the same pothole (keep the surest).
MERGE_SECONDS = 2.0
# Hit strength (0–1) from the size of the jolt: how far the acceleration total
# moves away from its normal level in the window, in g. On the training trips
# the peak jolt was ~0.09 g on normal road (median) and 0.37 g / 0.67 g in
# pothole windows (median / 90th percentile). So 0.1 g → 0 and 0.8 g → 1:
# a typical pothole scores ~0.4 (medium) and a hard one ~0.8 (high).
# PROVISIONAL: to be agreed with the AI team.
JOLT_FLOOR_G = 0.1
JOLT_FULL_G = 0.8


class ModelFileError(Exception):
    """The model file is missing, altered, or unusable with this installation."""


class MissingSensorData(Exception):
    """The batch lacks the accelerometer readings the model needs."""


@lru_cache(maxsize=4)
def load_bundle(path, expected_sha256):
    """Load and check the model bundle once per process (cached afterwards).

    Checks, in order:
    - the file's SHA-256 matches the reviewed file: unpickling can run code,
      so an altered or unknown file is refused *before* it is opened;
    - it was saved with the same scikit-learn version as installed here
      (a mismatch can silently change predictions);
    - it expects exactly the features, window and sampling this engine produces.
    """
    try:
        data = Path(path).read_bytes()
    except OSError as exc:
        raise ModelFileError(f'Model file not found: {path}') from exc
    digest = sha256(data).hexdigest()
    if expected_sha256 and digest != expected_sha256.lower():
        raise ModelFileError(f'Model file checksum {digest[:12]}… does not match '
                             f'ROADGUARD_AI_MODEL_SHA256; refusing to load it.')

    from sklearn.exceptions import InconsistentVersionWarning
    with warnings.catch_warnings(record=True) as caught:
        warnings.simplefilter('always', InconsistentVersionWarning)
        bundle = pickle.loads(data)  # noqa: S301 - only the checksum-verified file gets here
    if any(issubclass(w.category, InconsistentVersionWarning) for w in caught):
        raise ModelFileError('The model was saved with a different scikit-learn version; '
                             'install the version in requirements.txt.')

    if list(bundle.get('feature_columns', [])) != FEATURE_COLUMNS:
        raise ModelFileError('The model expects different features than ai_engine/features.py computes.')
    if bundle.get('window_size_points') != 10 or float(bundle.get('sampling_frequency_hz', 0)) != 1 / SAMPLE_SECONDS:
        raise ModelFileError('The model expects a different window or sampling rate.')
    # One CPU core: the web server handles other requests at the same time.
    bundle['classifier'].n_jobs = 1
    bundle['sha256'] = digest
    return bundle


class PotholeEngine(DetectionEngine):
    """The Random Forest sensor model from ai/Intelligent-Pothole-Detection (see models/MODEL.md)."""

    # Stored with every detection. The date is when the model was trained;
    # the suffix is the start of the model file's checksum.
    model_version = 'rf34-balanced-2026-09-24+2c2e9ec7'

    def __init__(self):
        bundle = load_bundle(settings.ROADGUARD_AI_MODEL_PATH, settings.ROADGUARD_AI_MODEL_SHA256)
        self.classifier = bundle['classifier']
        self.threshold = float(bundle['calibrated_threshold'])
        self.window_points = int(bundle['window_size_points'])
        self.min_speed_mps = float(bundle['speed_gate_min_speed_kmh']) / 3.6  # 10 km/h → 2.78 m/s
        self.accel_kind = settings.ROADGUARD_AI_ACCEL_KIND
        self.align_gravity = settings.ROADGUARD_AI_ALIGN_GRAVITY
        self.model_version = f"rf34-balanced-2026-09-24+{bundle['sha256'][:8]}"

    # -- the DetectionEngine interface ------------------------------------------------

    def analyze(self, batch):
        if not batch.readings:
            return []
        if not any(r.kind == self.accel_kind for r in batch.readings):
            kinds = sorted({r.kind for r in batch.readings})
            raise MissingSensorData(
                f'The model needs "{self.accel_kind}" readings, but this batch only has '
                f'{", ".join(kinds)}. Update the app, or change ROADGUARD_AI_ACCEL_KIND.')

        timeline = build_timeline(batch.context + batch.readings, self.accel_kind)
        if timeline is None:
            return []
        windows = self._windows_for_batch(timeline, batch)
        candidates = self._judge(timeline, windows)
        return [self._result(timeline, index, probability)
                for index, probability in _merge(timeline, candidates)]

    # -- steps --------------------------------------------------------------------------

    def _windows_for_batch(self, timeline, batch):
        """Start positions of the complete windows that end within this batch.

        A window "belongs" to the batch holding the first reading at or after
        its end: it ends after the last reading before this batch (the end
        of the context) and no later than the batch's last reading.
        """
        batch_times = [r.recorded_at.timestamp() for r in batch.readings]
        batch_start, batch_end = min(batch_times), max(batch_times)
        earlier = [r.recorded_at.timestamp() for r in batch.context
                   if r.recorded_at.timestamp() < batch_start]
        after = max(earlier) if earlier else batch_start - SAMPLE_SECONDS

        n, size = len(timeline.ticks), self.window_points
        starts = []
        for i in range(n - size + 1):
            if timeline.ticks[i] % size:          # windows start on the 2-second clock
                continue
            if timeline.ticks[i + size - 1] - timeline.ticks[i] != size - 1:
                continue                           # not 10 consecutive ticks
            if not timeline.valid[i:i + size].all():
                continue                           # a sensor gap inside the window
            if after < timeline.times[i + size - 1] <= batch_end:
                starts.append(i)
        return starts

    def _judge(self, timeline, starts):
        """(start, probability) for windows at or above the threshold."""
        size, rows, kept = self.window_points, [], []
        for i in starts:
            window = slice(i, i + size)
            speed = timeline.speed[window]
            if speed.mean() < self.min_speed_mps:
                continue  # the model's speed gate: stopped or crawling
            accel, gyro = timeline.accel[window], timeline.gyro[window]
            if self.align_gravity:
                accel, gyro = align_to_training(accel, gyro)
            rows.append(window_features(speed, accel, gyro))
            kept.append(i)
        if not rows:
            return []
        with warnings.catch_warnings():
            # The model was fitted on a table with column names; a plain array
            # in the same column order (FEATURE_COLUMNS, checked at load) is fine.
            warnings.filterwarnings('ignore', message='X does not have valid feature names')
            probabilities = self.classifier.predict_proba(np.vstack(rows))[:, 1]
        return [(i, float(p)) for i, p in zip(kept, probabilities) if p >= self.threshold]

    def _result(self, timeline, start, probability):
        """A detection at the strongest jolt of the window starting at `start`."""
        window = slice(start, start + self.window_points)
        total = np.sqrt((timeline.accel[window] ** 2).sum(axis=1))
        # How far the acceleration total strays from its normal level (the
        # window's median: about 1 g with gravity included).
        jolt = np.abs(total - np.median(total))
        peak = start + int(np.argmax(jolt))
        intensity = float(np.clip((jolt.max() - JOLT_FLOOR_G) / (JOLT_FULL_G - JOLT_FLOOR_G), 0, 1))
        return DetectionResult(
            detected_at=datetime.fromtimestamp(float(timeline.times[peak]), tz=dt_timezone.utc),
            latitude=float(timeline.lat[peak]), longitude=float(timeline.lng[peak]),
            confidence=round(probability, 4), intensity=round(intensity, 3))


def _merge(timeline, candidates):
    """Keep one detection per pothole: windows less than MERGE_SECONDS apart are merged."""
    merged = []
    for start, probability in sorted(candidates):
        if merged and timeline.times[start] - timeline.times[merged[-1][0]] < MERGE_SECONDS + 1e-6:
            if probability > merged[-1][1]:
                merged[-1] = (start, probability)
            continue
        merged.append((start, probability))
    return merged
