"""Driving routes with turn-by-turn steps, from an OSRM server.

GraphQL `drivingRoutes(origin, destination)` returns up to 3 alternatives.
Each route carries:
- coordinatesJson — the full road geometry, [[lng, lat], ...], for drawing
  the route and measuring progress along it;
- stepsJson — the manoeuvres ("Turn left onto Morogoro Road") with where
  they happen along the route, used by the app's navigation guidance.

Configure with ROADGUARD_OSRM_URL (default https://router.project-osrm.org,
the free public demo server: no uptime guarantee, max 1 request/second).
"""

import json
import math
import time
import uuid
from hashlib import sha256
from concurrent.futures import ThreadPoolExecutor
from concurrent.futures import TimeoutError as FuturesTimeout

from django.conf import settings
from django.core.cache import cache
from django.core.exceptions import ValidationError
from django.utils import timezone

from . import ratelimit
from .external import ExternalServiceError, check_base_url, get_json
from .validation import coordinates

# The app refuses routes with more points than this; long routes are thinned.
MAX_ROUTE_POINTS = 10_000

ORDINALS = {1: 'first', 2: 'second', 3: 'third', 4: 'fourth', 5: 'fifth', 6: 'sixth'}
COMPASS = ['north', 'northeast', 'east', 'southeast', 'south', 'southwest', 'west', 'northwest']


def _compass(bearing):
    """0–360° → "north", "southeast", ... (8 directions)."""
    return COMPASS[int(((bearing or 0) + 22.5) % 360 // 45)]


def instruction_text(step):
    """A spoken/written English instruction for one OSRM step.

    OSRM describes a manoeuvre with a `type` (turn, merge, roundabout, ...) and
    an optional `modifier` (left, slight right, uturn, ...); see
    https://project-osrm.org/docs/v5.24.0/api/#stepmaneuver-object
    """
    maneuver = step['maneuver']
    kind = maneuver.get('type', 'turn')
    modifier = maneuver.get('modifier', '')
    name = (step.get('name') or step.get('ref') or '').strip()
    onto = f' onto {name}' if name else ''

    if kind == 'depart':
        return f'Head {_compass(maneuver.get("bearing_after"))}' + (f' on {name}' if name else '')
    if kind == 'arrive':
        side = f' on the {modifier}' if modifier in ('left', 'right') else ''
        return f'You have arrived at your destination{side}'
    if kind in ('roundabout', 'rotary', 'exit roundabout', 'exit rotary'):
        exit_number = maneuver.get('exit')
        if exit_number in ORDINALS:
            return f'At the roundabout, take the {ORDINALS[exit_number]} exit{onto}'
        return f'At the roundabout, exit{onto}'
    if kind == 'roundabout turn':
        return f'At the roundabout, turn {modifier}{onto}'
    if modifier == 'uturn':
        return f'Make a U-turn{onto}'
    if kind == 'merge':
        return f'Merge {modifier}{onto}'.replace('  ', ' ')
    if kind == 'on ramp':
        return f'Take the ramp on the {modifier}{onto}' if modifier else f'Take the ramp{onto}'
    if kind == 'off ramp':
        return f'Take the exit on the {modifier}{onto}' if modifier else f'Take the exit{onto}'
    if kind == 'fork':
        return f'Keep {modifier} at the fork{onto}'
    if kind == 'end of road':
        return f'At the end of the road, turn {modifier}{onto}'
    if kind in ('new name', 'continue', 'notification') or modifier == 'straight':
        return f'Continue{onto}' if name else 'Continue straight'
    # Plain turns: "Turn left", "Turn slight right onto ..."
    return f'Turn {modifier}{onto}' if modifier else f'Continue{onto}'


def _thin(points):
    """Keep at most MAX_ROUTE_POINTS points (always the first and last)."""
    if len(points) <= MAX_ROUTE_POINTS:
        return points
    stride = math.ceil(len(points) / (MAX_ROUTE_POINTS - 1))
    return points[::stride][:MAX_ROUTE_POINTS - 1] + [points[-1]]


def _steps(route):
    """Flatten OSRM legs/steps into the app's step list.

    `alongMeters` is where the manoeuvre happens, measured from the start of
    the route (the sum of the distances of all earlier steps). The app compares
    it with how far along the route the driver is to know what's coming next.
    """
    steps, along = [], 0.0
    for leg in route.get('legs', []):
        for step in leg.get('steps', []):
            maneuver = step['maneuver']
            lng, lat = maneuver['location']
            steps.append({
                'type': maneuver.get('type', 'turn'),
                'modifier': maneuver.get('modifier', ''),
                'exit': maneuver.get('exit'),
                'name': (step.get('name') or '').strip(),
                'instruction': instruction_text(step),
                'distanceMeters': round(float(step.get('distance', 0)), 1),
                'durationSeconds': round(float(step.get('duration', 0)), 1),
                'alongMeters': round(along, 1),
                'location': [lng, lat],
            })
            along += float(step.get('distance', 0))
    return steps


def driving_routes(_root, _info, origin, destination):
    """GraphQL resolver: up to 3 routes from origin to destination."""
    points = [coordinates(p['latitude'], p['longitude'], max_latitude=85)
              for p in (origin, destination)]
    if points[0] == points[1]:
        raise ValidationError('Choose different start and destination points.')
    try:
        base = check_base_url(settings.ROADGUARD_OSRM_URL)
    except ExternalServiceError as exc:
        raise ValidationError('Routing service is not configured securely.') from exc
    # 4 decimals = about 11 m: fine for routing, and lets a retry from (almost)
    # the same spot reuse a cached route (see _fetch_route).
    path = ';'.join(f'{lng:.4f},{lat:.4f}' for lat, lng in points)
    # polyline6 = OSRM's compact encoding of the route shape (several times
    # smaller than GeoJSON coordinates), decoded below.
    common = f'{base}/route/v1/driving/{path}?alternatives=true&overview=full&geometries=polyline6'

    # The public OSRM demo server allows at most one request per second; a
    # request arriving just after another waits briefly for its turn.
    # A cached detailed route needs no request at all, so no turn either.
    hit = _cached(common)
    if not (hit and hit[1]) and not ratelimit.wait_for_slot(
            'osrm', 'shared', limit=1, window_seconds=1, max_wait_seconds=1.5):
        raise ValidationError('Routing is busy. Please wait a moment and retry.')

    try:
        result = _fetch_route(common)
        if result.get('code') == 'NoRoute':
            return []
        if result.get('code') != 'Ok':
            raise ExternalServiceError('OSRM returned an error.')
        routes = []
        for route in result['routes'][:3]:
            shape = _coordinates(route['geometry'])
            distance, duration = float(route['distance']), float(route['duration'])
            if (len(shape) < 2 or not (math.isfinite(distance) and math.isfinite(duration))
                    or distance <= 0 or duration <= 0):
                raise ExternalServiceError('OSRM returned an invalid route.')
            routes.append({
                'id': str(uuid.uuid4()),
                'distanceMeters': distance,
                'durationSeconds': duration,
                'coordinatesJson': json.dumps(_thin(shape)),
                # Empty when only the quick (no-steps) answer arrived in time:
                # the app then drives the route without turn-by-turn prompts.
                'stepsJson': json.dumps(_steps(route)),
                'computedAt': timezone.now().isoformat(),
                'provider': 'OSRM / OpenStreetMap',
            })
        return routes
    except (ExternalServiceError, KeyError, TypeError, ValueError) as exc:
        # Never substitute a made-up route when the real one is unavailable.
        raise ValidationError('Live routing is unavailable. Check the connection and retry; '
                              'no sample route was substituted.') from exc


# --- Staying within the app's time limit ------------------------------------
# The app waits at most 20 s for an answer. Turn-by-turn steps make OSRM's
# reply ~10x larger (it lists every intersection), which on a slow connection
# can take 40 s+ for a long trip. So two requests run side by side:
#   - DETAILED (with steps) — preferred, given up to STEPS_BUDGET_SECONDS;
#   - QUICK (no steps) — started QUICK_DELAY_SECONDS later (the public OSRM
#     server allows one request per second), used only if DETAILED is late.
# The answer always comes within TOTAL_BUDGET_SECONDS.
#
# Requests the app gave up on keep running in the background; when they finish
# their reply is cached for ROUTE_CACHE_SECONDS, so tapping the destination
# again answers at once (a detailed reply replaces a quick one).
QUICK_DELAY_SECONDS = 1.1
STEPS_BUDGET_SECONDS = 14
TOTAL_BUDGET_SECONDS = 16
_pool = ThreadPoolExecutor(max_workers=8, thread_name_prefix='osrm')
ROUTE_CACHE_SECONDS = 15 * 60


def _cache_key(common_url):
    # The URL holds the server, the rounded start/end points and the options.
    return 'osrm-route:' + sha256(common_url.encode()).hexdigest()


def _cached(common_url):
    """(reply, has_steps) from the cache, or None."""
    return cache.get(_cache_key(common_url))


def _remember(common_url, future, has_steps):
    """When `future` succeeds, cache its reply (never let a quick one replace steps)."""
    def done(f):
        try:
            reply = f.result()
        except Exception:  # noqa: BLE001 - a failed request simply isn't cached
            return
        if reply.get('code') != 'Ok':
            return
        current = _cached(common_url)
        if has_steps or current is None or not current[1]:
            cache.set(_cache_key(common_url), (reply, has_steps), timeout=ROUTE_CACHE_SECONDS)
    future.add_done_callback(done)


def _fetch_route(common_url):
    """OSRM's reply, with turn-by-turn steps if they arrive in time, otherwise without."""
    hit = _cached(common_url)
    if hit is not None and hit[1]:
        return hit[0]  # a cached detailed route: nothing better to wait for
    started = time.monotonic()
    left = lambda budget: max(budget - (time.monotonic() - started), 0.05)

    detailed = _pool.submit(get_json, common_url + '&steps=true',
                            timeout=TOTAL_BUDGET_SECONDS, max_bytes=5_000_000)
    _remember(common_url, detailed, has_steps=True)
    try:  # a fast answer (short route, good connection) needs no second request
        return detailed.result(timeout=QUICK_DELAY_SECONDS)
    except FuturesTimeout:
        pass
    except Exception:  # noqa: BLE001 - the quick request below may still succeed
        pass
    if hit is not None:
        # A cached quick route; the detailed request above may still upgrade
        # the cache for next time. Answer now rather than make the driver wait.
        return hit[0]
    quick = _pool.submit(get_json, common_url + '&steps=false',
                         timeout=TOTAL_BUDGET_SECONDS, max_bytes=1_000_000)
    _remember(common_url, quick, has_steps=False)

    # 1. Wait for the detailed answer, up to its budget.
    try:
        return detailed.result(timeout=left(STEPS_BUDGET_SECONDS))
    except Exception:  # noqa: BLE001 - late or failed: fall back to the quick answer
        pass
    # 2. Otherwise the quick answer, within the total budget.
    try:
        return quick.result(timeout=left(TOTAL_BUDGET_SECONDS))
    except Exception as exc:  # noqa: BLE001
        raise ExternalServiceError('OSRM did not answer in time.') from exc


def _coordinates(geometry):
    """Route shape as [[lng, lat], ...] from a polyline6 string (or GeoJSON)."""
    if isinstance(geometry, str):
        return decode_polyline(geometry, precision=6)
    if geometry.get('type') != 'LineString':
        raise ExternalServiceError('OSRM returned an invalid route.')
    return geometry['coordinates']


def decode_polyline(encoded, precision=6):
    """Decode Google's encoded-polyline format (OSRM polyline6) → [[lng, lat], ...].

    Each coordinate is stored as the difference from the previous one, in
    5-bit chunks; see https://developers.google.com/maps/documentation/utilities/polylinealgorithm
    """
    factor = 10 ** precision
    coordinates, index, lat, lng = [], 0, 0, 0
    while index < len(encoded):
        values = []
        for _ in range(2):  # latitude, then longitude
            shift = result = 0
            while True:
                byte = ord(encoded[index]) - 63
                index += 1
                result |= (byte & 0x1F) << shift
                shift += 5
                if byte < 0x20:
                    break
            values.append(~(result >> 1) if result & 1 else result >> 1)
        lat += values[0]
        lng += values[1]
        coordinates.append([lng / factor, lat / factor])
    return coordinates
