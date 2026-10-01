"""GraphQL resolvers for sensor-data sharing (`/api/v1/graphql/mobile/`, signed-in drivers only).

The request's authenticated Traveler is at `info.context.user` (set by
mobile.authentication.TravelerTokenAuthentication in the view).
"""

import json
import logging
import uuid
from datetime import timedelta
from hashlib import sha256

from django.conf import settings
from django.core.exceptions import ValidationError
from django.db import transaction
from django.utils import timezone

from mobile.validation import number, timestamp

from .models import CollectionConsent, SensorReading, TelemetryBatch

log = logging.getLogger(__name__)

# The sharing notice text version the app shows. Version 2 (2026-09-25) names
# the raw accelerometer (gravity included) that the AI model needs; drivers
# must accept the new text before sharing again.
NOTICE_VERSION = 2
CONSENT_LIFETIME = timedelta(hours=24)
MAX_BATCH_BYTES = 32 * 1024
MAX_READINGS_PER_BATCH = 20
# acceleration: raw accelerometer, m/s², gravity included (app notice v2; what the AI model reads).
# linear_acceleration: gravity removed (app notice v1). angular_velocity: gyroscope, rad/s.
SENSOR_KINDS = ('acceleration', 'linear_acceleration', 'angular_velocity')
GPS_FIELDS = {'latitude', 'longitude', 'speedMps', 'accuracyMeters', 'observedAt', 'isMocked'}


def _uuid(value):
    try:
        return uuid.UUID(str(value))
    except (ValueError, TypeError) as exc:
        raise ValidationError('A valid identifier is required.') from exc


def _consent_json(consent):
    return {'id': str(consent.id), 'tripId': str(consent.trip_id), 'version': consent.version,
            'grantedAt': consent.granted_at.isoformat(), 'expiresAt': consent.expires_at.isoformat(),
            'revoked': consent.revoked_at is not None}


def notice_version(_root, _info):
    return NOTICE_VERSION


def grant(_root, info, tripId, version, accepted):
    """The driver accepted the sharing notice for this trip."""
    if version != NOTICE_VERSION or accepted is not True:
        raise ValidationError('Explicit acceptance of the current collection notice is required.')
    consent = CollectionConsent.objects.create(
        traveler=info.context.user, trip_id=_uuid(tripId), version=version,
        expires_at=timezone.now() + CONSENT_LIFETIME)
    return _consent_json(consent)


def revoke(_root, info, id):
    """Withdraw one consent (only the driver's own)."""
    with transaction.atomic():
        consent = (CollectionConsent.objects.select_for_update()
                   .filter(pk=_uuid(id), traveler=info.context.user).first())
        if consent is None:
            raise ValidationError('Consent not found.')
        if consent.revoked_at is None:
            consent.revoked_at = timezone.now()
            consent.save(update_fields=['revoked_at'])
    return _consent_json(consent)


def revoke_all(_root, info):
    """Withdraw every active consent of this driver, on all devices. Returns how many."""
    return (CollectionConsent.objects.filter(traveler=info.context.user, revoked_at__isnull=True)
            .update(revoked_at=timezone.now()))


def _reading(event, now):
    """Validate one uploaded observation and turn it into SensorReading fields."""
    if not isinstance(event, dict) or set(event) != {'kind', 'at', 'x', 'y', 'z', 'gps'}:
        raise ValidationError('Unsupported observation fields.')
    if event['kind'] not in SENSOR_KINDS:
        raise ValidationError('Unsupported sensor kind.')
    gps = event['gps']
    if not isinstance(gps, dict) or set(gps) != GPS_FIELDS:
        raise ValidationError('Fresh GPS evidence is required.')
    lat, lng = number(gps['latitude'], 'latitude'), number(gps['longitude'], 'longitude')
    speed, accuracy = number(gps['speedMps'], 'speed'), number(gps['accuracyMeters'], 'accuracy')
    recorded_at, gps_at = timestamp(event['at'], 'at'), timestamp(gps['observedAt'], 'GPS time')
    # Same quality rules as the app: real (not mocked) GPS, accurate to 25 m,
    # and taken no more than 10 s before the sensor sample.
    if (gps['isMocked'] is not False or not -90 <= lat <= 90 or not -180 <= lng <= 180
            or not 0 <= speed <= 100 or not 0 < accuracy <= 25
            or recorded_at > now or not timedelta(0) <= recorded_at - gps_at <= timedelta(seconds=10)):
        raise ValidationError('Invalid, mocked, stale or inaccurate GPS observation.')
    x, y, z = (number(event[k], k) for k in ('x', 'y', 'z'))
    if any(abs(v) > 1000 for v in (x, y, z)):
        raise ValidationError('Sensor observation is out of range.')
    return dict(kind=event['kind'], recorded_at=recorded_at, x=x, y=y, z=z, lat=lat, lng=lng,
                speed_mps=speed, gps_accuracy_m=accuracy, gps_observed_at=gps_at)


def ingest(_root, info, input):
    """Store one batch of readings (`uploadTelemetry`). Safe to retry.

    A refused batch is logged with the reason: the app only shows "Upload
    paused", and the reason otherwise stays inside the GraphQL reply.
    """
    try:
        return _ingest(info, input)
    except ValidationError as exc:
        log.warning('Telemetry batch %s refused: %s [%s]', input.get('id'), '; '.join(exc.messages),
                    _consent_diagnosis(info, input))
        raise


def _consent_diagnosis(info, input):
    """Which part of the consent check failed, for the refusal log (no personal data)."""
    try:
        consent = CollectionConsent.objects.filter(pk=_uuid(input.get('consentId'))).first()
    except ValidationError:
        return f'consentId not a UUID: {input.get("consentId")!r}'
    if consent is None:
        return f'no consent {input.get("consentId")}'
    sent_trip = input.get('tripId')
    try:
        trip_matches = consent.trip_id == _uuid(sent_trip)
    except ValidationError:
        trip_matches = False
    return (f'consent {consent.id}: same traveller={consent.traveler_id == info.context.user.id}, '
            f'trip sent={sent_trip} stored={consent.trip_id} match={trip_matches}, '
            f'revoked={consent.revoked_at is not None}, expired={consent.expires_at <= timezone.now()}')


def _ingest(info, input):
    batch_id, consent_id, trip_id = (_uuid(input[k]) for k in ('id', 'consentId', 'tripId'))
    raw = input['eventsJson']
    if len(raw.encode('utf-8')) > MAX_BATCH_BYTES:
        raise ValidationError('A telemetry batch is limited to 32 KiB.')
    try:
        events = json.loads(raw)
    except (ValueError, RecursionError) as exc:
        raise ValidationError('Invalid telemetry JSON.') from exc
    if not isinstance(events, list) or not 1 <= len(events) <= MAX_READINGS_PER_BATCH:
        raise ValidationError('Provide 1–20 raw observations.')

    now = timezone.now()
    readings = [_reading(event, now) for event in events]
    digest = sha256(json.dumps({'trip': str(trip_id), 'consent': str(consent_id), 'events': events},
                               sort_keys=True, separators=(',', ':')).encode()).hexdigest()

    with transaction.atomic():
        # Locking the consent row makes uploads and "withdraw" wait for each other.
        consent = (CollectionConsent.objects.select_for_update()
                   .filter(pk=consent_id, traveler=info.context.user, trip_id=trip_id).first())
        if consent is None or consent.revoked_at is not None or consent.expires_at <= now:
            raise ValidationError('Collection consent is missing, expired or withdrawn.')
        if any(not consent.granted_at <= r['recorded_at'] <= consent.expires_at for r in readings):
            raise ValidationError('Observations must have been captured during consent.')

        # A retry of an already stored batch is acknowledged again, unchanged.
        existing = TelemetryBatch.objects.filter(pk=batch_id).first()
        if existing:
            if existing.consent_id != consent.id or existing.payload_digest != digest:
                raise ValidationError('This batch identifier has a different payload.')
            return {'id': str(existing.id), 'accepted': True, 'receivedAt': existing.received_at.isoformat()}

        batch = TelemetryBatch.objects.create(id=batch_id, consent=consent, trip_id=trip_id,
                                              payload_digest=digest)
        SensorReading.objects.bulk_create([SensorReading(batch=batch, **r) for r in readings])

    # Optionally hand the batch to the in-process AI engine straight away
    # (otherwise `manage.py process_telemetry` or the external AI service picks it up).
    if settings.ROADGUARD_AI_PROCESS_INLINE:
        from detection.pipeline import process_pending
        try:
            process_pending(limit=1, batch_ids=[batch.id])
        except Exception:  # noqa: BLE001 - e.g. the model file can't be loaded
            # The batch is already stored, so the upload still succeeds; it stays
            # "pending" for `manage.py process_telemetry` to retry later.
            log.exception('Inline AI processing failed for batch %s', batch.id)

    return {'id': str(batch.id), 'accepted': True, 'receivedAt': batch.received_at.isoformat()}
