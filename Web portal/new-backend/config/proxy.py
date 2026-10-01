"""Use the real client IP when running behind the Docker setup's nginx.

Behind a reverse proxy every request reaches Django from the proxy, so
REMOTE_ADDR is the proxy's address. nginx (Web portal/frontend/nginx.conf)
overwrites X-Forwarded-For with the address that connected to it, so with
ROADGUARD_BEHIND_PROXY=True that header holds the real client and replaces
REMOTE_ADDR here, before anything reads it: the login rate limit, the
mobile sign-up limit and the audit log.

Off by default: without a proxy in front, X-Forwarded-For is whatever the
client chose to send, and must not be trusted.
"""

from ipaddress import ip_address

from django.conf import settings


class TrustedProxyMiddleware:
    def __init__(self, get_response):
        self.get_response = get_response

    def __call__(self, request):
        if settings.ROADGUARD_BEHIND_PROXY:
            # nginx sends exactly one address; take the last one to be safe.
            forwarded = request.META.get('HTTP_X_FORWARDED_FOR', '').split(',')[-1].strip()
            try:
                request.META['REMOTE_ADDR'] = str(ip_address(forwarded))
            except ValueError:
                pass  # missing or malformed: keep the connecting address
        return self.get_response(request)
