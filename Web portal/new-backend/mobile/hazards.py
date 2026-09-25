"""`publicHazards`: the hazards the app shows on its live map and warns drivers about.

A defect is shown to drivers when either:

- CONFIRMED — an officer marked it Verified or Under Repair in the portal; or
- CROWD_REPORTED — it's still New, but enough *different* phones detected the
  same spot (detection/spots.py sets `published_at` once
  settings.SPOT_MIN_DEVICES_TO_PUBLISH is reached), and a phone detected it
  again within the last settings.SPOT_STALE_DAYS days.

Never shown: Resolved defects, new reports nobody has corroborated, and
defects built only from simulated test detections (unless
ROADGUARD_PUBLISH_SIMULATED is switched on for development).

The map-area filter runs in PostGIS on the defects' spatial index.
"""

from datetime import timedelta

from django.conf import settings
from django.core.exceptions import ValidationError
from django.db.models import Q
from django.db.models.expressions import RawSQL
from django.utils import timezone

from roadguard.models import Defect, ReportStatus

from .validation import number

CONFIRMED_STATUSES = (ReportStatus.VERIFIED, ReportStatus.UNDER_REPAIR)


def _bbox(value):
    """Validate a {west, south, east, north} map area (at most 5° per side)."""
    west, south, east, north = (number(value[k], k) for k in ('west', 'south', 'east', 'north'))
    if not (-180 <= west < east <= 180 and -90 <= south < north <= 90):
        raise ValidationError('Provide a valid west/south/east/north bounding box.')
    if east - west > 5 or north - south > 5:
        raise ValidationError('Limit each map query to a viewport of at most 5 degrees per axis.')
    return west, south, east, north


def visible_to_drivers():
    """Queryset of every defect drivers may currently see (any location)."""
    fresh_since = timezone.now() - timedelta(days=settings.SPOT_STALE_DAYS)
    crowd = Q(status=ReportStatus.NEW, published_at__isnull=False, last_detected_at__gte=fresh_since)
    if not settings.ROADGUARD_PUBLISH_SIMULATED:
        crowd &= Q(is_simulated=False)
    return Defect.objects.filter(Q(status__in=CONFIRMED_STATUSES) | crowd)


def is_visible_to_drivers(defect):
    """The same rule as visible_to_drivers(), for one defect already loaded.

    Used by the portal to badge "Shown to drivers" without a query per row.
    Keep the two in step: tests check they agree.
    """
    if defect.status in CONFIRMED_STATUSES:
        return True
    fresh_since = timezone.now() - timedelta(days=settings.SPOT_STALE_DAYS)
    return (defect.status == ReportStatus.NEW and defect.published_at is not None
            and defect.last_detected_at is not None and defect.last_detected_at >= fresh_since
            and (settings.ROADGUARD_PUBLISH_SIMULATED or not defect.is_simulated))


def in_area(queryset, west, south, east, north):
    """Keep only defects inside the rectangle, using the PostGIS `location` column.

    `&&` means "bounding boxes overlap" and is answered from the GiST spatial
    index; ST_MakeEnvelope builds the rectangle in WGS84 (SRID 4326).
    """
    inside = RawSQL(
        'SELECT id FROM defects WHERE location && ST_MakeEnvelope(%s, %s, %s, %s, 4326)::geography',
        (west, south, east, north),
    )
    return queryset.filter(pk__in=inside)


def public_hazards(_root, _info, bbox, first=100):
    """GraphQL resolver for `publicHazards(bbox, first)`."""
    if not 1 <= first <= 100:
        raise ValidationError('Use first between 1 and 100.')
    hazards = in_area(visible_to_drivers(), *_bbox(bbox)).order_by('-updated_at')[:first]

    results = []
    for defect in hazards:
        confirmed = defect.status in CONFIRMED_STATUSES
        results.append({
            'id': defect.pk,
            'category': defect.hazard_type.upper(),   # "Pothole" → "POTHOLE"
            'severity': defect.severity.upper(),      # "high" → "HIGH"
            'latitude': defect.lat,
            'longitude': defect.lng,
            # When it became visible to drivers: the officer's review, or
            # the moment the crowd evidence crossed the threshold.
            'confirmedAt': ((defect.reviewed_at if confirmed else defect.published_at)
                            or defect.updated_at).isoformat(),
            'updatedAt': defect.updated_at.isoformat(),
            # Lets the app say "confirmed" only when an officer confirmed it.
            'verification': 'CONFIRMED' if confirmed else 'CROWD_REPORTED',
            'observationCount': defect.observation_count,
            'deviceCount': defect.device_count,
        })
    return results
