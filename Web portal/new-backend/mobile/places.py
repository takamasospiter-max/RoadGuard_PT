"""Place search and reverse geocoding through Photon (OpenStreetMap data).

- search_places(): the app's destination search box (GraphQL `searchPlaces`).
- road_and_region(): turns a coordinate into a road name and region for new
  defects, so officers see "Morogoro Road, Dar es Salaam" in the portal
  instead of bare numbers. Best effort: placeholders are used if Photon is
  unreachable or disabled.

Configure with ROADGUARD_PHOTON_URL (default https://photon.komoot.io, a free
public service with no uptime guarantee).
"""

from hashlib import sha256
from urllib.parse import urlencode

from django.conf import settings
from django.core.cache import cache
from django.core.exceptions import ValidationError

from . import ratelimit
from .external import ExternalServiceError, check_base_url, get_json
from .validation import number

UNKNOWN_ROAD = 'Unnamed road'
UNKNOWN_REGION = 'Unknown region'


def _label(properties):
    """"Name, Street, City, Region, Country" from a Photon feature, skipping blanks/repeats."""
    parts = []
    for field in ('name', 'street', 'city', 'state', 'country'):
        value = properties.get(field)
        if isinstance(value, str) and value.strip() and value.strip() not in parts:
            parts.append(value.strip()[:180])
    return ', '.join(parts)


def search_places(_root, _info, query):
    """GraphQL resolver: up to 6 places matching `query` → [{label, latitude, longitude}]."""
    query = ' '.join(query.split())  # collapse repeated whitespace
    if not 3 <= len(query) <= 160 or any(ord(c) < 32 for c in query):
        raise ValidationError('Enter a place name between 3 and 160 characters.')
    try:
        base = check_base_url(settings.ROADGUARD_PHOTON_URL)
    except ExternalServiceError as exc:
        raise ValidationError('Place search is not configured securely.') from exc

    # Identical searches within 10 minutes are answered from the cache.
    key = 'places:' + sha256(f'{base}/{query.casefold()}'.encode()).hexdigest()
    cached = cache.get(key)
    if cached is not None:
        return cached
    # Photon's public server asks for gentle use: at most 1 request per second.
    # (A search typed right after another waits briefly for its turn.)
    if not ratelimit.wait_for_slot('photon', 'shared', limit=1, window_seconds=1,
                                   max_wait_seconds=1.5):
        raise ValidationError('Please wait a moment before searching again.')

    try:
        data = get_json(f"{base}/api/?{urlencode({'q': query, 'limit': 6, 'lang': 'en'})}",
                        max_bytes=262_144)
        results = []
        for feature in data['features'][:6]:
            geometry = feature['geometry']
            if geometry['type'] != 'Point' or len(geometry['coordinates']) != 2:
                continue
            lng, lat = (number(v, 'coordinate') for v in geometry['coordinates'])
            label = _label(feature.get('properties') or {})
            if label and -85 <= lat <= 85 and -180 <= lng <= 180:
                results.append({'label': label, 'latitude': lat, 'longitude': lng})
    except (ExternalServiceError, KeyError, TypeError, ValidationError) as exc:
        raise ValidationError('Place search is unavailable. Retry or choose a point on the map.') from exc

    cache.set(key, results, timeout=600)
    return results


def road_and_region(lat, lng):
    """(road, region) for a coordinate, or placeholders if unknown / disabled."""
    if not settings.ROADGUARD_REVERSE_GEOCODE:
        return UNKNOWN_ROAD, UNKNOWN_REGION
    try:
        base = check_base_url(settings.ROADGUARD_PHOTON_URL)
        # osm_tag=highway: ask for the nearest ROAD, not the nearest map object
        # (which is often a building or the city itself).
        query = urlencode({'lat': f'{lat:.6f}', 'lon': f'{lng:.6f}', 'limit': 1,
                           'lang': 'en', 'osm_tag': 'highway'})
        data = get_json(f'{base}/reverse?{query}', timeout=5, max_bytes=65_536)
        properties = data['features'][0]['properties']
    except (ExternalServiceError, KeyError, IndexError, TypeError):
        return UNKNOWN_ROAD, UNKNOWN_REGION

    def clean(value, limit):
        return value.strip()[:limit] if isinstance(value, str) and value.strip() else None

    # The result is a road, so its own "name" is the road name ("Morogoro Road").
    # ("street" can hold a different, neighbouring road, so it's only a fallback.)
    road = ((clean(properties.get('name'), 200) if properties.get('osm_key') == 'highway' else None)
            or clean(properties.get('street'), 200) or UNKNOWN_ROAD)
    # Region: in Tanzania OSM's "city" is the region used by the portal
    # ("Dar es Salaam", "Arusha"); "state" is the wider zone ("Coastal Zone").
    region = (clean(properties.get('city'), 100) or clean(properties.get('county'), 100)
              or clean(properties.get('state'), 100) or UNKNOWN_REGION)
    return road, region
