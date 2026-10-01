"""Which client IP the backend sees: for the login rate limit and the audit log.

Run with:  python manage.py test roadguard

Without a proxy (runserver), the X-Forwarded-For header is ignored: any
client can send one, so trusting it would let an attacker dodge the login
rate limit by changing it on every attempt.

Behind the Docker setup's nginx (ROADGUARD_BEHIND_PROXY=True), every request
arrives from nginx, which overwrites X-Forwarded-For with the real client
address; that address is then used instead, so each user gets their own
rate limit and the audit log shows who really made the request.
"""

from django.core.cache import cache
from django.test import RequestFactory, SimpleTestCase, override_settings
from rest_framework.test import APIClient

from config.proxy import TrustedProxyMiddleware

from .models import AuditLog
from .tests import PortalTestCase, make_user


def remote_addr_seen(request):
    """A stand-in view: what REMOTE_ADDR looks like after the middleware."""
    return request.META.get('REMOTE_ADDR')


class TrustedProxyMiddlewareTests(SimpleTestCase):
    def request(self, **headers):
        return RequestFactory().get('/', REMOTE_ADDR='172.18.0.4', **headers)

    @override_settings(ROADGUARD_BEHIND_PROXY=False)
    def test_header_ignored_without_a_proxy(self):
        middleware = TrustedProxyMiddleware(remote_addr_seen)
        self.assertEqual(middleware(self.request(HTTP_X_FORWARDED_FOR='203.0.113.9')), '172.18.0.4')

    @override_settings(ROADGUARD_BEHIND_PROXY=True)
    def test_behind_the_proxy_the_forwarded_address_is_used(self):
        middleware = TrustedProxyMiddleware(remote_addr_seen)
        self.assertEqual(middleware(self.request(HTTP_X_FORWARDED_FOR='203.0.113.9')), '203.0.113.9')

    @override_settings(ROADGUARD_BEHIND_PROXY=True)
    def test_behind_the_proxy_without_the_header_nothing_changes(self):
        middleware = TrustedProxyMiddleware(remote_addr_seen)
        self.assertEqual(middleware(self.request()), '172.18.0.4')

    @override_settings(ROADGUARD_BEHIND_PROXY=True)
    def test_malformed_header_is_ignored(self):
        middleware = TrustedProxyMiddleware(remote_addr_seen)
        self.assertEqual(middleware(self.request(HTTP_X_FORWARDED_FOR='not-an-ip')), '172.18.0.4')


class LoginRateLimitTests(PortalTestCase):
    def failed_login(self, forwarded_for):
        return self.client.post('/api/v1/auth/login/', {'email': 'x@example.com', 'password': 'x'},
                                format='json', HTTP_X_FORWARDED_FOR=forwarded_for)

    @override_settings(ROADGUARD_BEHIND_PROXY=False)
    def test_a_fake_forwarded_address_cannot_dodge_the_limit(self):
        # Same caller, a different made-up X-Forwarded-For on every attempt.
        for i in range(10):
            self.failed_login(f'198.51.100.{i}')
        self.assertEqual(self.failed_login('198.51.100.99').status_code, 429)

    @override_settings(ROADGUARD_BEHIND_PROXY=True)
    def test_behind_the_proxy_each_user_has_their_own_limit(self):
        # Everyone arrives from nginx; one user using up their attempts must
        # not lock out another.
        for _ in range(10):
            self.failed_login('203.0.113.1')
        self.assertEqual(self.failed_login('203.0.113.1').status_code, 429)
        self.assertNotEqual(self.failed_login('203.0.113.2').status_code, 429)

    @override_settings(ROADGUARD_BEHIND_PROXY=True)
    def test_behind_the_proxy_the_audit_log_records_the_real_address(self):
        user = make_user('admin@example.com')
        self.client = APIClient(HTTP_X_FORWARDED_FOR='203.0.113.7')
        cache.clear()
        self.log_in(user)
        self.assertEqual(AuditLog.objects.filter(action='auth.login_succeeded').get().ip_address,
                         '203.0.113.7')
