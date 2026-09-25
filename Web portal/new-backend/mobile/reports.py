"""Anonymous pothole reports from the mobile app → Defects in the portal.

Two steps, matching the app (core/services/road_api.dart):
1. stage_photo(): the photo is uploaded first and a one-time token returned.
2. submit_anonymous_report(): the report (GPS evidence + token) is submitted;
   it becomes a Defect with source "manual" and status "New" that officers
   review in the web portal.

"Anonymous" means no account, cookie or token is attached: the endpoints
reject requests that carry any.
"""

import json
import re
import secrets
import uuid
import warnings
from datetime import timedelta
from hashlib import sha256
from io import BytesIO

from django.core.exceptions import ValidationError
from django.db import IntegrityError, transaction
from django.utils import timezone
from PIL import Image, ImageOps, UnidentifiedImageError

from roadguard import audit
from roadguard.models import Defect, HazardType, ReportPhoto, ReportSource, ReportStatus, Severity

from .places import road_and_region
from .validation import coordinates, number, text, timestamp

MAX_PHOTO_BYTES = 15 * 1024 * 1024       # 15 MB upload limit
MAX_PHOTO_PIXELS = 24_000_000            # 24 megapixels (guards against "decompression bombs")
PHOTO_TOKEN_TTL = timedelta(minutes=15)  # time allowed between photo upload and report submit
TOKEN_PATTERN = re.compile(r'[A-Za-z0-9_-]{43}\Z')

# "Standing still" rule for manual reports, agreed 2026-09-25 and shared with
# the app's SafetyPolicy — change both together. A phone at rest often reports
# small GPS speed drift, so up to 0.5 m/s (1.8 km/h) counts as stationary.
# This is a deliberate exception to the SRS's strict zero-speed rule; set it
# to 0 (in the app too) to restore that rule.
MAX_STATIONARY_SPEED_MPS = 0.5
# A vaguer position can't reliably locate the pothole or be matched with
# sensor detections, which are grouped within 15 m.
MAX_GPS_ACCURACY_M = 25.0

# Mobile category names → portal hazard types. Potholes only: road cracks are
# outside RoadGuard's scope, so CRACK reports are refused (see _validated).
CATEGORIES = {'POTHOLE': HazardType.POTHOLE}

# Portal status → the status names the app understands.
MOBILE_STATUS = {
    ReportStatus.NEW: 'NEW',
    ReportStatus.VERIFIED: 'CONFIRMED',
    ReportStatus.UNDER_REPAIR: 'CONFIRMED',  # confirmed and still on the road
    ReportStatus.RESOLVED: 'RESOLVED',
}

ALLOWED_FIELDS = {'client_id', 'category', 'notes', 'latitude', 'longitude', 'speed_mps',
                  'accuracy_meters', 'observed_at', 'recorded_at', 'is_demo', 'is_mocked',
                  'photo_token'}
REQUIRED_FIELDS = ALLOWED_FIELDS - {'notes', 'is_mocked'}


def stage_photo(upload):
    """Check and sanitize an uploaded photo; return (ReportPhoto, one-time token).

    The image is decoded and redrawn onto a blank canvas, then saved as a new
    JPEG. This drops everything except the pixels: EXIF (including GPS and
    camera serial numbers), IPTC, XMP and PNG text chunks.
    """
    if not hasattr(upload, 'read'):
        raise ValidationError('One JPEG or PNG photo is required.')
    raw = upload.read(MAX_PHOTO_BYTES + 1)
    if not raw or len(raw) > MAX_PHOTO_BYTES:
        raise ValidationError('Photo must contain between 1 byte and 15 MB.')
    try:
        with warnings.catch_warnings():
            # Treat Pillow's "suspiciously large image" warning as an error.
            warnings.simplefilter('error', Image.DecompressionBombWarning)
            with Image.open(BytesIO(raw)) as candidate:
                if candidate.format not in {'JPEG', 'PNG'}:
                    raise ValidationError('Only JPEG and PNG photos are accepted.')
                if candidate.width * candidate.height > MAX_PHOTO_PIXELS:
                    raise ValidationError('Photo exceeds the 24 megapixel limit.')
                if getattr(candidate, 'n_frames', 1) != 1:
                    raise ValidationError('Use a single still photo.')
                candidate.verify()  # detects truncated/corrupt files
            with Image.open(BytesIO(raw)) as candidate:
                upright = ImageOps.exif_transpose(candidate)  # apply the camera's rotation
                canvas = Image.new('RGB', upright.size, 'white')
                rgba = upright.convert('RGBA')
                canvas.paste(rgba, mask=rgba.getchannel('A'))
                output = BytesIO()
                canvas.save(output, format='JPEG', quality=90)
                content = output.getvalue()
    except ValidationError:
        raise
    except (UnidentifiedImageError, OSError, ValueError, SyntaxError,
            Image.DecompressionBombError, Image.DecompressionBombWarning) as exc:
        raise ValidationError('The photo could not be decoded safely.') from exc

    token = secrets.token_urlsafe(32)  # 43 characters; only its hash is stored
    photo = ReportPhoto.objects.create(
        token_hash=sha256(token.encode('ascii')).hexdigest(),
        content=content,
        sha256=sha256(content).hexdigest(),
        expires_at=timezone.now() + PHOTO_TOKEN_TTL,
    )
    return photo, token


def _validated(data):
    """Check every field of a submitted report; return clean values."""
    if not isinstance(data, dict):
        raise ValidationError('A report object is required.')
    if set(data) - ALLOWED_FIELDS:
        raise ValidationError('Report contains unsupported fields.')
    if REQUIRED_FIELDS - set(data):
        raise ValidationError('Report is missing required fields.')
    # Demo and GPS-spoofed ("mocked") reports are never accepted as evidence.
    if data['is_demo'] is not False or data.get('is_mocked', False) is not False:
        raise ValidationError('Demo or mocked evidence cannot be submitted.')
    try:
        client_id = uuid.UUID(str(data['client_id']))
    except (ValueError, TypeError, AttributeError) as exc:
        raise ValidationError({'client_id': 'A UUID is required.'}) from exc
    if data['category'] == 'CRACK':
        raise ValidationError({'category': 'Only potholes can be reported. Road cracks are outside RoadGuard’s scope.'})
    if data['category'] not in CATEGORIES:
        raise ValidationError({'category': 'Choose POTHOLE.'})

    lat, lng = coordinates(data['latitude'], data['longitude'])
    speed = number(data['speed_mps'], 'speed_mps')
    accuracy = number(data['accuracy_meters'], 'accuracy_meters')
    # Reports are only accepted from a traveller standing still with a good GPS
    # fix, so the recorded position is where the pothole actually is. These
    # limits match the app's SafetyPolicy (lib/core/models/safety_policy.dart).
    if not 0 <= speed <= MAX_STATIONARY_SPEED_MPS:
        raise ValidationError({'speed_mps': f'GPS speed must be between 0 and {MAX_STATIONARY_SPEED_MPS} m/s '
                                            '(standing still). Stop safely before reporting.'})
    if not 0 < accuracy <= MAX_GPS_ACCURACY_M:
        raise ValidationError({'accuracy_meters': 'GPS accuracy must be greater than 0 and at most '
                                                  f'{MAX_GPS_ACCURACY_M:g} metres.'})
    observed = timestamp(data['observed_at'], 'observed_at')
    recorded = timestamp(data['recorded_at'], 'recorded_at')
    now = timezone.now()
    if observed > now or recorded > now or not timedelta(0) <= recorded - observed <= timedelta(seconds=10):
        raise ValidationError('GPS evidence must be no more than 10 seconds old at recording; '
                              'timestamps cannot be in the future.')
    token = data['photo_token']
    if not isinstance(token, str) or not TOKEN_PATTERN.fullmatch(token):
        raise ValidationError({'photo_token': 'A valid photo token is required.'})
    return {
        'client_id': client_id, 'category': data['category'],
        'notes': text(data.get('notes', ''), 'notes', 500),
        'lat': lat, 'lng': lng, 'accuracy': accuracy,
        'observed_at': observed, 'recorded_at': recorded,
        'token_hash': sha256(token.encode('ascii')).hexdigest(),
    }


def _digest(values, photo_sha256):
    """A fingerprint of the report, used to recognise an identical retry."""
    canonical = {
        'client_id': str(values['client_id']), 'category': values['category'],
        'notes': values['notes'], 'lat': values['lat'], 'lng': values['lng'],
        'accuracy': values['accuracy'], 'observed_at': values['observed_at'].isoformat(),
        'recorded_at': values['recorded_at'].isoformat(), 'photo': photo_sha256,
    }
    return sha256(json.dumps(canonical, sort_keys=True).encode()).hexdigest()


def submit_anonymous_report(data):
    """Create (or, for an identical retry, return) the Defect for a mobile report."""
    values = _validated(data)
    # Look up the road name *before* opening the transaction, so the (slow,
    # external) request doesn't hold database locks.
    road, region = road_and_region(values['lat'], values['lng'])
    digest = None
    try:
        with transaction.atomic():
            photo = ReportPhoto.objects.select_for_update().filter(token_hash=values['token_hash']).first()
            if photo is None:
                raise ValidationError({'photo_token': 'Photo token is unavailable.'})
            digest = _digest(values, photo.sha256)

            # Same client_id seen before: an honest retry (e.g. the app never
            # received our reply) gets the original defect back.
            existing = Defect.objects.select_for_update().filter(client_id=values['client_id']).first()
            if existing:
                if existing.payload_digest != digest:
                    raise ValidationError('This client ID has already been used for a different report.')
                return existing
            if photo.expires_at <= timezone.now():
                # The app looks for exactly this message to upload the photo again.
                raise ValidationError({'photo_token': 'Photo token has expired. Upload the photo again.'})
            if Defect.objects.filter(photo=photo).exists():
                raise ValidationError({'photo_token': 'Photo token has already been used.'})

            defect = Defect.objects.create(
                hazard_type=CATEGORIES[values['category']],
                road=road, region=region,
                # Travellers don't rate severity; "medium" is a neutral starting
                # point that officers adjust when they review the report.
                severity=Severity.MEDIUM,
                status=ReportStatus.NEW,
                source=ReportSource.MANUAL,
                confidence=100.0,
                observation_count=1,
                detected_at=values['recorded_at'],
                lat=values['lat'], lng=values['lng'],
                has_photo=True,
                client_id=values['client_id'], notes=values['notes'],
                gps_accuracy_m=values['accuracy'], gps_observed_at=values['observed_at'],
                payload_digest=digest, photo=photo,
            )
    except IntegrityError as exc:
        # Two uploads raced for the same client_id; if the other one stored the
        # identical report, treat this as a retry.
        existing = Defect.objects.filter(client_id=values['client_id']).first()
        if existing and digest is not None and existing.payload_digest == digest:
            return existing
        raise ValidationError('The report conflicts with an existing submission.') from exc

    audit.record(actor=None, actor_email='mobile:anonymous', action='defect.reported',
                 resource_type='defect', resource_id=defect.pk,
                 details=f'mobile app report, category={values["category"]}')
    return defect


def acknowledgement(defect):
    """The reply the app expects after submitting: {id, clientId, status, receivedAt}."""
    return {
        'id': str(defect.uuid),
        'clientId': str(defect.client_id),
        'status': MOBILE_STATUS[defect.status],
        'receivedAt': defect.created_at.isoformat(),
    }
