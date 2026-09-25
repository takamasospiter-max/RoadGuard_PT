"""The AI engine "socket": the interface a pothole-detection model plugs into.

There are two ways to connect the AI engine — pick whichever suits the team:

1. In-process (Python): write a class that subclasses DetectionEngine and
   implements analyze(), then point settings ROADGUARD_AI_ENGINE at it, e.g.
       ROADGUARD_AI_ENGINE=ai_engine.model.PotholeEngine
   `manage.py process_telemetry` (or inline processing) calls it for every
   new sensor batch.

2. Separate service (any language): the service asks the backend for work
   and posts results back over HTTP — see detection/views.py and
   docs/AI_ENGINE_CONTRACT.md.

Both routes go through pipeline.save_results(), so everything after the
model (grouping into spots, severity, publishing to drivers) is identical.

Until the real model arrives, the default NullEngine finds nothing, and
`manage.py simulate_detections` can inject test detections.
"""

from dataclasses import dataclass, field
from datetime import datetime

from django.conf import settings
from django.utils.module_loading import import_string


@dataclass
class Reading:
    """One sensor sample, as given to the engine (plain data, no Django objects)."""
    kind: str             # "acceleration" (m/s², gravity included), "linear_acceleration"
                          # (m/s², gravity removed, older apps) or "angular_velocity" (rad/s)
    recorded_at: datetime  # UTC
    x: float
    y: float
    z: float
    lat: float
    lng: float
    speed_mps: float
    gps_accuracy_m: float


@dataclass
class BatchInput:
    """What the engine analyses: one uploaded batch plus a little history.

    A pothole hit can straddle two uploads (each batch is only ~1 second), so
    `context` holds the same trip's readings from the few seconds before the
    batch. Report detections only for moments inside `readings`, so the same
    hit isn't reported twice.
    """
    batch_id: str
    trip_id: str
    readings: list[Reading]
    context: list[Reading] = field(default_factory=list)


@dataclass
class DetectionResult:
    """One pothole the engine found."""
    detected_at: datetime          # when the hit happened (UTC)
    latitude: float
    longitude: float
    confidence: float              # 0–1: how sure the model is
    intensity: float | None = None  # 0–1: how hard the hit was (optional)
    severity: str | None = None     # "low" | "medium" | "high" (optional)
    hazard_type: str = 'Pothole'  # the only category RoadGuard accepts


class DetectionEngine:
    """Base class for an in-process AI engine."""

    # Stored with every detection, so results can be traced to a model version.
    model_version = 'unknown'

    def analyze(self, batch: BatchInput) -> list[DetectionResult]:
        """Return the potholes found in this batch (an empty list if none)."""
        raise NotImplementedError


class NullEngine(DetectionEngine):
    """Placeholder until the real AI engine is ready: never detects anything.

    Batches are still marked as processed, so the pipeline can be exercised
    end to end.
    """
    model_version = 'null-engine'

    def analyze(self, batch):
        return []


def load_engine() -> DetectionEngine:
    """Create the engine named in settings.ROADGUARD_AI_ENGINE."""
    engine_class = import_string(settings.ROADGUARD_AI_ENGINE)
    engine = engine_class()
    if not isinstance(engine, DetectionEngine):
        raise TypeError(f'{settings.ROADGUARD_AI_ENGINE} must subclass detection.engine.DetectionEngine')
    return engine
