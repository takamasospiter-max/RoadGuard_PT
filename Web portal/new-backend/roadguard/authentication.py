"""DRF authentication: turns the session cookie into a logged-in PortalUser.

Configured as the only authentication class in settings.REST_FRAMEWORK, so
every API view runs this first. When it succeeds, views can use
`request.user` (the PortalUser) and `request.auth` (their AdminSession).
"""

from django.utils import timezone
from rest_framework import exceptions
from rest_framework.authentication import BaseAuthentication

from .models import AccountStatus, AdminSession
from .security import IDLE_TIMEOUT, SESSION_COOKIE_NAME


class PortalSessionAuthentication(BaseAuthentication):
    """Authenticate a request by its `roadguard_session` cookie."""

    def authenticate(self, request):
        token = request.COOKIES.get(SESSION_COOKIE_NAME)
        if not token:
            # No cookie: return None, meaning "not logged in". Public views
            # (login, accept-invite) still work; protected views answer 401
            # through their IsAuthenticated permission.
            return None

        # select_related fetches the user in the same query as the session.
        session = (AdminSession.objects.select_related('portal_user')
                   .filter(pk=token).first())
        if session is None:
            raise exceptions.AuthenticationFailed('Session not found')

        # Two separate expiry rules; breaking either one ends the session.
        now = timezone.now()
        if now >= session.expires_at or now >= session.last_seen_at + IDLE_TIMEOUT:
            session.delete()
            raise exceptions.AuthenticationFailed('Session expired')

        # A deactivated account is logged out immediately, not just blocked
        # at its next login.
        user = session.portal_user
        if user.status != AccountStatus.ACTIVE:
            session.delete()
            raise exceptions.AuthenticationFailed('This account has been deactivated')

        # Record this activity so the idle timeout starts counting again.
        # update() writes only this one column, without a full model save.
        AdminSession.objects.filter(pk=session.pk).update(last_seen_at=now)

        return (user, session)

    def authenticate_header(self, request):
        # Providing a value here makes DRF answer unauthenticated requests
        # with 401 Unauthorized instead of 403 Forbidden, so the frontend
        # can tell "please log in" apart from "you're not allowed".
        return 'Session'
