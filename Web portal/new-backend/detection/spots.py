"""Combine detections from many drivers into monitored spots (Defects) and rate their severity.

For each new detection (confidence ≥ SPOT_MIN_CONFIDENCE):

1. Is there already a spot (any open Defect, including a traveller's photo
   report) within SPOT_RADIUS_M metres?  → the detection joins that spot.
2. Otherwise, do recent unassigned detections within SPOT_RADIUS_M of it
   come from at least SPOT_MIN_DEVICES_TO_TRACK different phones?
   → a new spot is created: Defect(source "device", status "New"), and it
   appears in the portal for officers to monitor.
3. Otherwise it waits, unassigned, for more phones to confirm it.

Every time a spot gains a detection, its numbers are recomputed:
- device_count      — how many different phones detected it;
- observation_count — how many detections in total (+1 for a photo report);
- confidence (0–100) — combined certainty across phones: 1 − Π(1 − cᵢ),
  using each phone's best confidence (several independent, fairly sure
  phones → very sure);
- severity_score (0–1) — confidence-weighted average of how hard each hit was;
  mapped to low / medium / high (below 0.4 / below 0.7 / above);
- published_at — set once device_count reaches SPOT_MIN_DEVICES_TO_PUBLISH:
  from then on drivers are alerted about it (see mobile/hazards.py).

Distances are computed by PostGIS (ST_DWithin on geography = true metres on
the Earth's surface), using the spatial indexes on both tables.
"""

from datetime import timedelta

from django.conf import settings
from django.db import connection, transaction
from django.utils import timezone

from mobile.places import road_and_region
from roadguard import audit
from roadguard.models import Defect, HazardType, ReportSource, ReportStatus, Severity

from .models import Detection

# Numeric value used for a detection that gives a severity label but no intensity.
SEVERITY_VALUE = {Severity.LOW: 0.25, Severity.MEDIUM: 0.55, Severity.HIGH: 0.85}
# An arbitrary fixed number identifying this module's PostgreSQL advisory lock.
SPOT_LOCK_ID = 7_220_001
SYSTEM_ACTOR = 'system:crowd-sensing'


def severity_level(score):
    """0–1 score → the portal's low / medium / high."""
    if score < 0.4:
        return Severity.LOW
    if score < 0.7:
        return Severity.MEDIUM
    return Severity.HIGH


def _nearest_open_defect(lat, lng):
    """Id of the closest non-resolved defect within SPOT_RADIUS_M, or None."""
    with connection.cursor() as cursor:
        cursor.execute(
            """
            SELECT id FROM defects
            WHERE status <> %s
              AND ST_DWithin(location, ST_SetSRID(ST_MakePoint(%s, %s), 4326)::geography, %s)
            ORDER BY ST_Distance(location, ST_SetSRID(ST_MakePoint(%s, %s), 4326)::geography)
            LIMIT 1
            """,
            [ReportStatus.RESOLVED, lng, lat, settings.SPOT_RADIUS_M, lng, lat],
        )
        row = cursor.fetchone()
    return row[0] if row else None


def _unassigned_nearby(detection):
    """Recent, confident, not-yet-grouped detections within SPOT_RADIUS_M (incl. this one)."""
    since = timezone.now() - timedelta(days=settings.SPOT_STALE_DAYS)
    with connection.cursor() as cursor:
        cursor.execute(
            """
            SELECT id FROM detections
            WHERE defect_id IS NULL AND confidence >= %s AND detected_at >= %s
              AND ST_DWithin(location, ST_SetSRID(ST_MakePoint(%s, %s), 4326)::geography, %s)
            """,
            [settings.SPOT_MIN_CONFIDENCE, since, detection.lng, detection.lat, settings.SPOT_RADIUS_M],
        )
        ids = [row[0] for row in cursor.fetchall()]
    return list(Detection.objects.filter(pk__in=ids))


def _weighted_centre(detections):
    """Confidence-weighted average position — the best estimate of where the pothole is."""
    total = sum(d.confidence for d in detections) or 1.0
    return (sum(d.lat * d.confidence for d in detections) / total,
            sum(d.lng * d.confidence for d in detections) / total)


def assign(detection):
    """Group one detection into a spot. Returns the Defect, or None if it's waiting."""
    if detection.confidence < settings.SPOT_MIN_CONFIDENCE:
        return None  # too uncertain to count towards any spot

    # Run the lookup-then-create steps one at a time across all workers, so
    # two detections of the same new pothole can't create two spots.
    with transaction.atomic():
        with connection.cursor() as cursor:
            cursor.execute('SELECT pg_advisory_xact_lock(%s)', [SPOT_LOCK_ID])

        defect_id = _nearest_open_defect(detection.lat, detection.lng)
        if defect_id is not None:
            Detection.objects.filter(pk=detection.pk).update(defect_id=defect_id)
            return recompute(Defect.objects.select_for_update().get(pk=defect_id))

        group = _unassigned_nearby(detection)
        if len({d.device_key for d in group}) < settings.SPOT_MIN_DEVICES_TO_TRACK:
            return None  # not enough independent phones yet

        lat, lng = _weighted_centre(group)
        road, region = road_and_region(lat, lng)
        first_seen = min(d.detected_at for d in group)
        defect = Defect.objects.create(
            hazard_type=detection.hazard_type or HazardType.POTHOLE,
            road=road, region=region,
            severity=Severity.MEDIUM,  # replaced by recompute() below
            status=ReportStatus.NEW, source=ReportSource.DEVICE,
            confidence=0, observation_count=0, detected_at=first_seen,
            lat=lat, lng=lng, has_photo=False,
        )
        Detection.objects.filter(pk__in=[d.pk for d in group]).update(defect=defect)
        audit.record(actor=None, actor_email=SYSTEM_ACTOR, action='defect.auto_created',
                     resource_type='defect', resource_id=defect.pk,
                     details=f'{len(group)} detections from {len({d.device_key for d in group})} devices')
        return recompute(defect)


def recompute(defect):
    """Refresh a spot's crowd numbers from all its detections (see module docstring)."""
    detections = list(defect.detections.all())
    if not detections:
        return defect

    best_per_device = {}
    for d in detections:
        best_per_device[d.device_key] = max(best_per_device.get(d.device_key, 0.0), d.confidence)
    miss_probability = 1.0
    for confidence in best_per_device.values():
        miss_probability *= (1.0 - confidence)
    combined_confidence = 1.0 - miss_probability

    weighted = [(d.confidence, d.intensity if d.intensity is not None else SEVERITY_VALUE.get(d.severity))
                for d in detections]
    weighted = [(c, v) for c, v in weighted if v is not None]
    score = (sum(c * v for c, v in weighted) / sum(c for c, _ in weighted)) if weighted else None

    defect.device_count = len(best_per_device)
    defect.observation_count = len(detections) + (1 if defect.source == ReportSource.MANUAL else 0)
    defect.severity_score = score
    defect.last_detected_at = max(d.detected_at for d in detections)

    # For a sensor-built spot that no officer has reviewed yet, the crowd
    # numbers *are* the record: keep confidence, severity and position current.
    # Once an officer has reviewed it, or for a traveller's photo report, their
    # values are kept and only the counts above are updated.
    if defect.source == ReportSource.DEVICE and defect.reviewed_at is None:
        defect.confidence = round(combined_confidence * 100, 1)
        if score is not None:
            defect.severity = severity_level(score)
        defect.lat, defect.lng = _weighted_centre(detections)
        defect.is_simulated = all(d.is_simulated for d in detections)

    newly_published = (defect.published_at is None and defect.status == ReportStatus.NEW
                       and defect.device_count >= settings.SPOT_MIN_DEVICES_TO_PUBLISH)
    if newly_published:
        defect.published_at = timezone.now()
    defect.save()

    if newly_published:
        audit.record(actor=None, actor_email=SYSTEM_ACTOR, action='defect.auto_published',
                     resource_type='defect', resource_id=defect.pk,
                     details=f'confirmed by {defect.device_count} devices; now alerted to drivers')
    return defect
