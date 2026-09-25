"""Tests for the sensor model engine (ai_engine/).

Run with:  python manage.py test ai_engine

The test data are short excerpts of the AI team's training trips
(testdata/cmu_trip1_*.csv, from ai/Intelligent-Pothole-Detection/data/
Pothole_Non_Pothole/trip1_sensors.csv), replayed the way the RoadGuard app
sends them: separate accelerometer and gyroscope events at 10 Hz, in m/s².
The model has seen these trips, so these tests prove the plumbing
(features, units, timing, batching), not how accurate the model is on new roads.
"""

import csv
import uuid
import warnings
from datetime import datetime, timedelta, timezone as dt_timezone
from pathlib import Path

import numpy as np
from django.test import SimpleTestCase, TestCase, override_settings
from django.utils import timezone

from detection import pipeline
from detection.engine import BatchInput, Reading
from detection.models import Detection
from mobile.models import Traveler
from telemetry.models import CollectionConsent, SensorReading, TelemetryBatch

from .features import FEATURE_COLUMNS, window_features
from .preprocessing import STANDARD_GRAVITY, rotation_between
from .sensor_model import MissingSensorData, ModelFileError, PotholeEngine, load_bundle

TESTDATA = Path(__file__).resolve().parent / 'testdata'
POTHOLE_AT = 1492639065.7   # the marked pothole in cmu_trip1_pothole.csv (trip 1, pothole 0)


def trip_rows(name):
    """The excerpt's rows: time (s), lat, lng, speed (m/s), accel (g), gyro (rad/s)."""
    with open(TESTDATA / name, newline='') as f:
        return [{k: float(v) for k, v in row.items()} for row in csv.DictReader(f)]


def replay_start(rows):
    """Where the replay starts: the first row's time, moved onto the engine's 0.2 s clock."""
    return round(rows[0]['timestamp'] / 0.2) * 0.2


def pothole_time(rows):
    """When the marked pothole happens in the replay (see as_app_readings)."""
    index = min(range(len(rows)), key=lambda i: abs(rows[i]['timestamp'] - POTHOLE_AT))
    return replay_start(rows) + 0.2 * index


def as_app_readings(rows, speed=None, turn=None):
    """Replay rows like the app: 10 Hz accelerometer and gyroscope events, m/s².

    The training rows are real 5 Hz readings; they're replayed on an exact
    0.2 s clock (like a phone whose readings fall on the engine's ticks),
    with an extra accelerometer and gyroscope event halfway between rows, as
    a 10 Hz phone sends. Gyroscope events come 30 ms after the accelerometer,
    so the sensors are not in step, as on a real phone. `turn` rotates the
    phone (a 3×3 matrix); `speed` overrides the GPS speed.
    """
    readings, start = [], replay_start(rows)
    for index, (row, nxt) in enumerate(zip(rows, rows[1:] + rows[-1:])):
        for fraction in (0.0, 0.5):
            t = start + 0.2 * (index + fraction)
            acc = np.array([row[f'accelerometer{a}'] + fraction * (nxt[f'accelerometer{a}'] - row[f'accelerometer{a}'])
                            for a in 'XYZ']) * STANDARD_GRAVITY
            gyr = np.array([row[f'gyro{a}'] + fraction * (nxt[f'gyro{a}'] - row[f'gyro{a}']) for a in 'XYZ'])
            if turn is not None:
                acc, gyr = turn @ acc, turn @ gyr
            gps = dict(lat=row['latitude'], lng=row['longitude'],
                       speed_mps=row['speed'] if speed is None else speed, gps_accuracy_m=5.0)
            readings.append(Reading('acceleration', _utc(t), *acc, **gps))
            readings.append(Reading('angular_velocity', _utc(t + 0.03), *gyr, **gps))
        if nxt is row:
            break
    return sorted(readings, key=lambda r: r.recorded_at)


def _utc(seconds):
    return datetime.fromtimestamp(seconds, tz=dt_timezone.utc)


def run_like_uploads(engine, readings, seconds=1.0):
    """Feed readings in ~1 s batches with 5 s of context, as detection/pipeline.py does."""
    found = []
    start = readings[0].recorded_at
    while start <= readings[-1].recorded_at:
        end = start + timedelta(seconds=seconds)
        batch = [r for r in readings if start <= r.recorded_at < end]
        context = [r for r in readings if start - timedelta(seconds=5) <= r.recorded_at < start]
        if batch:
            found += engine.analyze(BatchInput('b', 't', batch, context))
        start = end
    return found


class FeatureTests(SimpleTestCase):
    """features.py computes exactly what the notebook computed."""

    def test_columns_match_the_model(self):
        bundle = load_bundle(str(TESTDATA.parent / 'models' / 'pothole_model_bundle.pkl'),
                             '2c2e9ec7bdc05113b4058419bf398d207097eae0bb413f003460d00b1810d3bc')
        self.assertEqual(list(bundle['classifier'].feature_names_in_), FEATURE_COLUMNS)
        self.assertEqual(len(FEATURE_COLUMNS), 34)

    def test_reproduces_the_notebooks_own_example(self):
        # Notebook cell 19, "Simulation 2 (Moving Vehicle + High Shock)":
        # the AI team's code gave confidence 0.4096825396825396.
        speed = [12.5] * 10
        accel = np.column_stack([
            [0.05, 0.08, 0.12, 0.45, 0.90, -0.65, 0.15, 0.05, 0.04, 0.05],
            [-0.98, -0.96, -0.85, -1.85, -0.20, -1.50, -0.95, -0.98, -0.97, -0.98],
            [0.18, 0.20, 0.35, 1.20, 0.85, -0.40, 0.25, 0.18, 0.19, 0.18]])
        gyro = np.column_stack([
            [0.01, 0.02, 0.05, 0.45, -0.35, 0.10, 0.02, 0.01, 0.01, 0.01],
            [0.00, 0.01, 0.08, -0.55, 0.40, -0.15, 0.03, 0.01, 0.00, 0.00],
            [0.00, 0.00, 0.02, 0.25, -0.18, 0.05, 0.01, 0.00, 0.00, 0.00]])
        engine = PotholeEngine()
        with warnings.catch_warnings():
            warnings.filterwarnings('ignore', message='X does not have valid feature names')
            probability = engine.classifier.predict_proba(
                np.array([window_features(speed, accel, gyro)]))[0, 1]
        self.assertAlmostEqual(probability, 0.4096825396825396, places=12)
        self.assertGreaterEqual(probability, engine.threshold)   # a pothole, as in the notebook

    def test_sample_standard_deviation(self):
        row = window_features([1, 2, 3, 4], np.zeros((4, 3)), np.zeros((4, 3)))
        self.assertAlmostEqual(row[1], np.std([1, 2, 3, 4], ddof=1))   # sdSpeed, like pandas .std()


class EngineTests(SimpleTestCase):
    """The whole engine, on real trip data sent the way the app sends it."""

    def setUp(self):
        self.engine = PotholeEngine()

    def test_finds_the_marked_pothole_once(self):
        rows = trip_rows('cmu_trip1_pothole.csv')
        found = run_like_uploads(self.engine, as_app_readings(rows))
        self.assertEqual(len(found), 1)
        hit = found[0]
        self.assertLess(abs(hit.detected_at.timestamp() - pothole_time(rows)), 2.0)   # at the right moment
        self.assertGreaterEqual(hit.confidence, self.engine.threshold)
        self.assertTrue(0 < hit.intensity <= 1)
        marked = min(rows, key=lambda r: abs(r['timestamp'] - POTHOLE_AT))
        self.assertAlmostEqual(hit.latitude, marked['latitude'], places=3)   # and the right place
        self.assertAlmostEqual(hit.longitude, marked['longitude'], places=3)

    def test_smooth_road_gives_nothing(self):
        self.assertEqual(run_like_uploads(self.engine, as_app_readings(trip_rows('cmu_trip1_smooth.csv'))), [])

    def test_speed_gate(self):
        # The same pothole at 2 m/s (7 km/h): below the model's 10 km/h gate.
        slow = as_app_readings(trip_rows('cmu_trip1_pothole.csv'), speed=2.0)
        self.assertEqual(run_like_uploads(self.engine, slow), [])

    def test_batch_size_does_not_matter(self):
        readings = as_app_readings(trip_rows('cmu_trip1_pothole.csv'))
        one_second = run_like_uploads(self.engine, readings, seconds=1.0)
        two_seconds = run_like_uploads(self.engine, readings, seconds=2.0)
        self.assertEqual([d.detected_at for d in one_second], [d.detected_at for d in two_seconds])

    def test_a_turned_phone_still_finds_it(self):
        # Phone lying flat, screen up (gravity on −Z instead of −Y).
        flat = rotation_between(np.array([0.052, -0.9698, 0.2383]), np.array([0, 0, -1.0]))
        rows = trip_rows('cmu_trip1_pothole.csv')
        found = run_like_uploads(self.engine, as_app_readings(rows, turn=flat))
        self.assertEqual(len(found), 1)
        self.assertLess(abs(found[0].detected_at.timestamp() - pothole_time(rows)), 2.0)

    def test_batch_without_the_needed_accelerometer_is_refused(self):
        old_app = [r for r in as_app_readings(trip_rows('cmu_trip1_smooth.csv')) if r.kind == 'angular_velocity']
        with self.assertRaisesMessage(MissingSensorData, '"acceleration"'):
            self.engine.analyze(BatchInput('b', 't', old_app[:20], []))

    def test_altered_model_file_is_refused(self):
        with self.assertRaisesMessage(ModelFileError, 'does not match'):
            load_bundle(str(TESTDATA.parent / 'models' / 'pothole_model_bundle.pkl'), '0' * 64)


@override_settings(ROADGUARD_AI_ENGINE='ai_engine.sensor_model.PotholeEngine', ROADGUARD_REVERSE_GEOCODE=False)
class PipelineTests(TestCase):
    """Through the real pipeline: stored batches in, a stored detection out."""

    def test_uploaded_batches_become_a_detection(self):
        traveler = Traveler.objects.create(name='D', email='d@example.com', password_hash='x')
        consent = CollectionConsent.objects.create(traveler=traveler, trip_id=uuid.uuid4(),
                                                   expires_at=timezone.now() + timedelta(hours=1))
        rows = trip_rows('cmu_trip1_pothole.csv')
        readings = as_app_readings(rows)
        # Upload in 20-reading batches, like the app (about 1 s each).
        for start in range(0, len(readings), 20):
            batch = TelemetryBatch.objects.create(id=uuid.uuid4(), consent=consent,
                                                  trip_id=consent.trip_id, payload_digest=str(start))
            SensorReading.objects.bulk_create([SensorReading(
                batch=batch, kind=r.kind, recorded_at=r.recorded_at, x=r.x, y=r.y, z=r.z,
                lat=r.lat, lng=r.lng, speed_mps=r.speed_mps, gps_accuracy_m=r.gps_accuracy_m,
                gps_observed_at=r.recorded_at) for r in readings[start:start + 20]])

        processed, found = pipeline.process_pending(limit=100)
        self.assertEqual((processed, found), (TelemetryBatch.objects.count(), 1))
        detection = Detection.objects.get()
        self.assertTrue(detection.model_version.startswith('rf34-balanced-2026-09-24+2c2e9ec7'))
        self.assertLess(abs(detection.detected_at.timestamp() - pothole_time(rows)), 2.0)
        self.assertFalse(TelemetryBatch.objects.filter(ai_status='failed').exists())
