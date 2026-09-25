"""DRF authentication for the mobile app: `Authorization: Bearer <token>`."""

import re
from hashlib import sha256

from django.utils import timezone
from rest_framework import exceptions
from rest_framework.authentication import BaseAuthentication

from .models import TravelerSession

# The app's tokens are exactly 43 URL-safe characters (secrets.token_urlsafe(32)).
BEARER_PATTERN = re.compile(r'Bearer ([A-Za-z0-9_-]{43})')


def hash_token(token):
    """Only this hash is stored in the database (see TravelerSession)."""
    return sha256(token.encode('ascii')).hexdigest()


def find_session(request):
    """The valid TravelerSession for this request's bearer token, or None."""
    match = BEARER_PATTERN.fullmatch(request.META.get('HTTP_AUTHORIZATION', ''))
    if match is None:
        return None
    return (TravelerSession.objects.select_related('traveler')
            .filter(token_hash=hash_token(match.group(1)),
                    expires_at__gt=timezone.now(),
                    traveler__is_active=True)
            .first())


class TravelerTokenAuthentication(BaseAuthentication):
    """Turns a valid bearer token into `request.user` = the Traveler.

    Requests carrying cookies are refused: the app never sends cookies, so
    one appearing means a browser (or a mistake) — and mixing portal cookies
    with traveller tokens is exactly what this separation prevents.
    """

    def authenticate(self, request):
        if request.META.get('HTTP_COOKIE'):
            raise exceptions.AuthenticationFailed('Use the traveler token without cookies.')
        session = find_session(request)
        if session is None:
            raise exceptions.AuthenticationFailed('Your session has expired. Please sign in again.')
        return (session.traveler, session)

    def authenticate_header(self, request):
        # Makes DRF answer 401 (not 403) when authentication fails.
        return 'Bearer'
