"""Safe HTTP calls to the external map services (Photon for places, OSRM for routes).

Rules applied to every call:
- HTTPS only, and the configured URL may not contain credentials or a query;
- redirects are refused (a redirect could send data somewhere unexpected);
- a timeout, and a hard cap on how many bytes are read;
- replies are requested gzip-compressed (several times smaller, which matters
  on a slow connection); the cap also applies after decompression, so a
  small "zip bomb" can't expand into gigabytes;
- only coordinates or the search text are sent — never who is asking.
"""

import json
import zlib
from urllib.parse import urlsplit
from urllib.request import HTTPRedirectHandler, Request, build_opener

USER_AGENT = 'RoadGuardAI/0.2 (road-safety research project)'


class ExternalServiceError(Exception):
    """The external service is misconfigured, unreachable or returned bad data."""


class _NoRedirect(HTTPRedirectHandler):
    """Makes urllib treat any redirect as an error instead of following it."""

    def redirect_request(self, *args, **kwargs):
        return None


def check_base_url(base_url):
    """The configured service URL without a trailing slash, if it is safe to use."""
    base_url = base_url.rstrip('/')
    parts = urlsplit(base_url)
    if parts.scheme != 'https' or not parts.netloc or parts.username or parts.query or parts.fragment:
        raise ExternalServiceError('The external service URL is not configured securely.')
    return base_url


def get_json(url, *, timeout=12, max_bytes=1_000_000):
    """GET `url` and parse the JSON reply, enforcing the rules above."""
    request = Request(url, headers={'User-Agent': USER_AGENT, 'Accept': 'application/json',
                                    'Accept-Encoding': 'gzip'})
    try:
        with build_opener(_NoRedirect()).open(request, timeout=timeout) as response:
            raw = response.read(max_bytes + 1)
            gzipped = response.headers.get('Content-Encoding', '').lower() == 'gzip'
    except Exception as exc:  # network errors, HTTP errors, refused redirects
        raise ExternalServiceError('The external service could not be reached.') from exc
    if len(raw) > max_bytes:
        raise ExternalServiceError('The external service reply was too large.')
    if gzipped:
        raw = _gunzip(raw, max_bytes)
    try:
        return json.loads(raw)
    except ValueError as exc:
        raise ExternalServiceError('The external service reply was not valid JSON.') from exc


def _gunzip(data, max_bytes):
    """Decompress a gzip reply, refusing anything that expands past `max_bytes`."""
    inflater = zlib.decompressobj(wbits=16 + zlib.MAX_WBITS)  # 16+: expect a gzip header
    try:
        # max_length stops decompression early; leftover input means "too big".
        raw = inflater.decompress(data, max_bytes + 1)
    except zlib.error as exc:
        raise ExternalServiceError('The external service reply was not valid gzip.') from exc
    if len(raw) > max_bytes or inflater.unconsumed_tail:
        raise ExternalServiceError('The external service reply was too large.')
    return raw
