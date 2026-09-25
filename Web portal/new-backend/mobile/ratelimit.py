"""A tiny fixed-window rate limiter on top of Django's cache.

Used where DRF's per-view throttles don't fit: per-email login attempts, and
the shared "one request per second" limit for the free Photon/OSRM services.

Note: the default cache (LocMemCache) is per process, which is fine for
`runserver`. With several worker processes in production, configure a shared
cache (e.g. Redis or Django's database cache) so the limits are shared too.
"""

import time
from hashlib import sha256

from django.core.cache import cache


def allow(kind, identifier, *, limit, window_seconds):
    """Count one attempt; return False once `limit` attempts happened in the window.

    The identifier (an email, an IP, ...) is hashed so no raw personal data
    ends up in the cache.
    """
    key = 'ratelimit:' + sha256(f'{kind}:{identifier}'.encode()).hexdigest()
    # add() only sets the key if it's missing, starting a new window at 0.
    cache.add(key, 0, timeout=window_seconds)
    try:
        attempts = cache.incr(key)
    except ValueError:  # the key expired between add() and incr()
        cache.set(key, 1, timeout=window_seconds)
        attempts = 1
    return attempts <= limit


def wait_for_slot(kind, identifier, *, limit, window_seconds, max_wait_seconds):
    """Like allow(), but wait up to `max_wait_seconds` for a free slot.

    Used for the shared 1-request/second limit of the free map services: when
    two app requests arrive together (e.g. place search then route), the second
    waits a moment instead of failing with "busy". Returns False if no slot
    freed up in time.
    """
    deadline = time.monotonic() + max_wait_seconds
    while True:
        if allow(kind, identifier, limit=limit, window_seconds=window_seconds):
            return True
        if time.monotonic() >= deadline:
            return False
        time.sleep(0.2)  # re-check a few times per window
