"""Moves sensor batches through the AI engine and stores what it finds.

    TelemetryBatch (pending) ──claim──► engine.analyze() ──► save_results()
                                                               │
                                          Detection rows ◄─────┘
                                                │
                                         spots.assign() → Defect (the spot)

Used by `manage.py process_telemetry` (in-process engine), by inline
processing after an upload (ROADGUARD_AI_PROCESS_INLINE), and by the HTTP
API for an external AI service (detection/views.py).
"""

import hmac
import logging
import math
from datetime import timedelta
from hashlib import sha256

from django.conf import settings
from django.core.exceptions import ValidationError
from django.db import transaction
from django.utils import timezone

from roadguard.models import HazardType, Severity
from telemetry.models import SensorReading, TelemetryBatch

from . import spots
from .engine import BatchInput, DetectionResult, Reading, load_engine
from .models import Detection

log = logging.getLogger(__name__)

# A batch claimed by an engine that never answered is offered again after this.
CLAIM_TIMEOUT = timedelta(minutes=10)
# How much of the trip's earlier data is given to the engine as context.
CONTEXT_SECONDS = 5
# A detection must lie within this distance of the batch's own GPS positions.
MAX_DETECTION_OFFSET_M = 150


def device_key(traveler_id):
    """A pseudonymous, stable id for a traveller's device/account.

    A keyed hash (HMAC with SECRET_KEY): the same traveller always gets the
    same key, so distinct phones can be counted per spot, but the key can't
    be turned back into the account without the server's secret.
    """
    return hmac.new(settings.SECRET_KEY.encode(), f'device:{traveler_id}'.encode(), sha256).hexdigest()


def _reading(row):
    return Reading(kind=row.kind, recorded_at=row.recorded_at, x=row.x, y=row.y, z=row.z,
                   lat=row.lat, lng=row.lng, speed_mps=row.speed_mps, gps_accuracy_m=row.gps_accuracy_m)


def batch_input(batch):
    """Build the engine's input for a batch: its readings + recent context."""
    readings = [_reading(r) for r in batch.readings.all()]
    context = []
    if readings:
        start = min(r.recorded_at for r in readings)
        context = [_reading(r) for r in SensorReading.objects.filter(
            batch__trip_id=batch.trip_id, batch__consent__traveler_id=batch.consent.traveler_id,
            recorded_at__gte=start - timedelta(seconds=CONTEXT_SECONDS), recorded_at__lt=start,
        ).exclude(batch=batch)]
    return BatchInput(batch_id=str(batch.id), trip_id=str(batch.trip_id),
                      readings=readings, context=context)


def claim(limit=10, batch_ids=None):
    """Mark up to `limit` batches as "processing" and return them.

    Pending batches are taken oldest first; a batch stuck in "processing" for
    longer than CLAIM_TIMEOUT is taken again. `skip_locked` lets several
    workers claim at the same time without getting the same batch.
    """
    now = timezone.now()
    with transaction.atomic():
        queryset = (TelemetryBatch.objects.select_for_update(skip_locked=True)
                    .filter(ai_status__in=[TelemetryBatch.AIStatus.PENDING, TelemetryBatch.AIStatus.PROCESSING])
                    .exclude(ai_status=TelemetryBatch.AIStatus.PROCESSING, ai_claimed_at__gt=now - CLAIM_TIMEOUT)
                    .order_by('received_at'))
        if batch_ids is not None:
            queryset = queryset.filter(pk__in=batch_ids)
        batches = list(queryset[:limit])
        TelemetryBatch.objects.filter(pk__in=[b.pk for b in batches]).update(
            ai_status=TelemetryBatch.AIStatus.PROCESSING, ai_claimed_at=now)
    return list(TelemetryBatch.objects.filter(pk__in=[b.pk for b in batches])
                .select_related('consent').order_by('received_at'))


def _distance_m(lat1, lng1, lat2, lng2):
    """Approximate distance in metres (equirectangular; fine for short distances)."""
    x = math.radians(lng2 - lng1) * math.cos(math.radians((lat1 + lat2) / 2))
    y = math.radians(lat2 - lat1)
    return 6_371_000 * math.hypot(x, y)


def _check(result, batch_readings):
    """Validate one DetectionResult against the batch it came from."""
    if not isinstance(result, DetectionResult):
        raise ValidationError('The engine must return DetectionResult objects.')
    for value, name in ((result.latitude, 'latitude'), (result.longitude, 'longitude'),
                        (result.confidence, 'confidence')):
        if isinstance(value, bool) or not isinstance(value, (int, float)) or not math.isfinite(value):
            raise ValidationError(f'{name} must be a finite number.')
    if not (-90 <= result.latitude <= 90 and -180 <= result.longitude <= 180):
        raise ValidationError('Detection coordinates are out of range.')
    if not 0 <= result.confidence <= 1:
        raise ValidationError('confidence must be between 0 and 1.')
    if result.intensity is not None and (isinstance(result.intensity, bool)
                                         or not isinstance(result.intensity, (int, float))
                                         or not 0 <= result.intensity <= 1):
        raise ValidationError('intensity must be between 0 and 1.')
    if result.severity is not None and result.severity not in Severity.values:
        raise ValidationError('severity must be low, medium or high.')
    if result.hazard_type not in HazardType.values:
        raise ValidationError('hazard_type must be Pothole (road cracks are out of scope).')
    if timezone.is_naive(result.detected_at):
        raise ValidationError('detected_at must include a timezone.')
    if batch_readings:
        # The detection must fall inside the batch's time span (±2 s)...
        first = min(r.recorded_at for r in batch_readings)
        last = max(r.recorded_at for r in batch_readings)
        if not first - timedelta(seconds=2) <= result.detected_at <= last + timedelta(seconds=2):
            raise ValidationError('detected_at is outside the batch time range.')
        # ...and close to where the phone actually was.
        nearest = min(_distance_m(result.latitude, result.longitude, r.lat, r.lng) for r in batch_readings)
        if nearest > MAX_DETECTION_OFFSET_M:
            raise ValidationError('Detection location is too far from the batch GPS positions.')


def save_results(batch, results, model_version):
    """Store the engine's detections for a batch and group them into spots.

    All-or-nothing: if any result is invalid, nothing is saved and the
    ValidationError explains why.
    """
    readings = list(batch.readings.all())
    for result in results:
        _check(result, readings)

    key = device_key(batch.consent.traveler_id)
    with transaction.atomic():
        detections = Detection.objects.bulk_create([
            Detection(batch=batch, trip_id=batch.trip_id, device_key=key,
                      detected_at=r.detected_at, lat=r.latitude, lng=r.longitude,
                      hazard_type=r.hazard_type, confidence=r.confidence,
                      intensity=r.intensity, severity=r.severity,
                      model_version=model_version[:60])
            for r in results
        ])
        TelemetryBatch.objects.filter(pk=batch.pk).update(
            ai_status=TelemetryBatch.AIStatus.DONE, ai_processed_at=timezone.now(),
            ai_model_version=model_version[:60], ai_error='')
    for detection in detections:
        spots.assign(detection)
    return detections


def mark_failed(batch, error):
    """Record that the engine couldn't analyse this batch."""
    TelemetryBatch.objects.filter(pk=batch.pk).update(
        ai_status=TelemetryBatch.AIStatus.FAILED, ai_processed_at=timezone.now(),
        ai_error=str(error)[:500])


def process_pending(limit=50, batch_ids=None):
    """Run the in-process engine over pending batches. Returns (batches, detections)."""
    engine = load_engine()
    processed = found = 0
    for batch in claim(limit=limit, batch_ids=batch_ids):
        try:
            results = engine.analyze(batch_input(batch))
            found += len(save_results(batch, results, engine.model_version))
        except Exception as exc:  # one bad batch must not stop the others
            log.exception('AI engine failed on batch %s', batch.pk)
            mark_failed(batch, exc)
        processed += 1
    return processed, found
