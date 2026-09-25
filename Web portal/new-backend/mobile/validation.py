"""Strict input checks shared by the mobile endpoints.

Each helper either returns a clean value or raises Django's ValidationError
with a message that is safe to show to the user.
"""

import math
from datetime import datetime, timezone as dt_timezone

from django.core.exceptions import ValidationError
from django.utils import timezone
from django.utils.dateparse import parse_datetime


def number(value, field):
    """A finite float. Booleans, strings, NaN and infinity are rejected."""
    # bool is a subclass of int in Python, so exclude it explicitly.
    if isinstance(value, bool) or not isinstance(value, (int, float)):
        raise ValidationError({field: 'A finite number is required.'})
    try:
        result = float(value)
    except (OverflowError, ValueError) as exc:
        raise ValidationError({field: 'A finite number is required.'}) from exc
    if not math.isfinite(result):
        raise ValidationError({field: 'A finite number is required.'})
    return 0.0 if result == 0 else result  # turns -0.0 into 0.0


def timestamp(value, field):
    """An ISO-8601 timestamp *with* a timezone, converted to UTC."""
    if isinstance(value, str):
        try:
            value = parse_datetime(value)
        except (ValueError, OverflowError) as exc:
            raise ValidationError({field: 'A valid timezone-aware timestamp is required.'}) from exc
    if not isinstance(value, datetime) or timezone.is_naive(value):
        raise ValidationError({field: 'A valid timezone-aware timestamp is required.'})
    return value.astimezone(dt_timezone.utc)


def text(value, field, limit, *, required=False):
    """Trimmed text of at most `limit` characters, without NUL bytes."""
    if not isinstance(value, str):
        raise ValidationError({field: 'A text value is required.'})
    if '\x00' in value:
        raise ValidationError({field: 'Text cannot contain a null character.'})
    value = value.strip()
    if len(value) > limit or (required and not value):
        raise ValidationError({field: f"Provide {'1' if required else '0'}–{limit} characters."})
    return value


def coordinates(latitude, longitude, *, max_latitude=90):
    """A (lat, lng) pair within valid ranges."""
    lat, lng = number(latitude, 'latitude'), number(longitude, 'longitude')
    if not -max_latitude <= lat <= max_latitude or not -180 <= lng <= 180:
        raise ValidationError('Coordinates are out of range.')
    return lat, lng


def messages(error):
    """Flatten a ValidationError into one readable sentence for the app."""
    return '; '.join(error.messages)
