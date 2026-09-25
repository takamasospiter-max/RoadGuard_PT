"""Login, MFA, account activation and logout endpoints (all under /api/v1/auth/).

How logging in works:

  1. POST /api/v1/auth/login/       email + password
         -> {"mfa_required": true, "pending_token": "..."}
     The pending token only proves the password was right; it grants no access.
  2. POST /api/v1/auth/verify-mfa/  pending_token + 6-digit authenticator code
         -> the user's details, plus an httpOnly `roadguard_session` cookie
  3. Every later request sends that cookie automatically;
     PortalSessionAuthentication (authentication.py) checks it.

  GET  /api/v1/auth/me/      who is logged in (the frontend calls this on page load)
  POST /api/v1/auth/logout/  deletes the session on the server and clears the cookie

Activating an invited account:

  POST /api/v1/auth/accept-invite/  token from the email link + a new password
       -> the MFA secret as a QR code (plus the raw key) to add to an authenticator app
"""

from django.conf import settings
from django.db import transaction
from django.utils import timezone
from rest_framework import status
from rest_framework.permissions import AllowAny, IsAuthenticated
from rest_framework.response import Response
from rest_framework.throttling import ScopedRateThrottle
from rest_framework.views import APIView

from . import audit
from .models import AccountStatus, AdminSession, PortalUser
from .security import (ABSOLUTE_SESSION_LIFETIME, SESSION_COOKIE_NAME, generate_mfa_secret,
                       hash_password, issue_mfa_pending_token, new_session_token,
                       qr_code_data_uri, read_invite_token, read_mfa_pending_token,
                       totp_provisioning_uri, verify_password, verify_totp_code)
from .serializers import (AcceptInviteSerializer, CurrentUserSerializer, LoginSerializer,
                          VerifyMfaSerializer)


def error(message, status_code):
    """A JSON error response in the {"detail": "..."} shape the frontend reads."""
    return Response({'detail': message}, status=status_code)


class PublicAuthView(APIView):
    """Base for endpoints used *before* logging in (login, verify-mfa, accept-invite).

    authentication_classes = [] makes DRF skip the session-cookie check here.
    Otherwise a stale cookie left over from an expired session would block
    the very request meant to start a new one.
    """
    authentication_classes = []
    permission_classes = [AllowAny]
    # Rate limit (settings.REST_FRAMEWORK['DEFAULT_THROTTLE_RATES']['auth']),
    # counted per IP address, to slow down password and code guessing.
    throttle_classes = [ScopedRateThrottle]
    throttle_scope = 'auth'


class LoginView(PublicAuthView):
    """Step 1 of login: check email + password, then ask for the MFA code."""

    def post(self, request):
        body = LoginSerializer(data=request.data)
        body.is_valid(raise_exception=True)
        email = body.validated_data['email'].strip()
        password = body.validated_data['password']

        # iexact: "Jane@Example.com" and "jane@example.com" are the same account.
        user = PortalUser.objects.filter(email__iexact=email).first()

        # The same message whether the email is unknown or the password is
        # wrong. Saying "that email exists" would help an attacker find real
        # accounts. An invited-but-not-activated account has no password
        # yet, so verify_password() fails for it the same way.
        if user is None or not verify_password(password, user.password_hash):
            audit.record(actor=user, actor_email=email, action='auth.login_failed',
                         resource_type='portal_user', resource_id=user.pk if user else None,
                         details='incorrect email or password', request=request)
            return error('Incorrect email or password', status.HTTP_401_UNAUTHORIZED)

        # Only checked after a correct password, so this reveals nothing new
        # to someone guessing.
        if user.status != AccountStatus.ACTIVE:
            return error('This account has been deactivated', status.HTTP_403_FORBIDDEN)
        if not user.mfa_secret:
            return error('MFA is not set up for this account yet', status.HTTP_403_FORBIDDEN)

        return Response({'mfa_required': True, 'pending_token': issue_mfa_pending_token(user.pk)})


class VerifyMfaView(PublicAuthView):
    """Step 2 of login: check the authenticator code, then start a session."""

    def post(self, request):
        body = VerifyMfaSerializer(data=request.data)
        body.is_valid(raise_exception=True)

        # The pending token says which user passed step 1 (and that it was < 5 min ago).
        user_id = read_mfa_pending_token(body.validated_data['pending_token'])
        if user_id is None:
            return error('Login has expired — start again', status.HTTP_401_UNAUTHORIZED)

        user = PortalUser.objects.filter(pk=user_id).first()
        # Re-checked here in case the account was deactivated in the few
        # minutes between the two steps.
        if user is None or user.status != AccountStatus.ACTIVE or not user.mfa_secret:
            return error('Login has expired — start again', status.HTTP_401_UNAUTHORIZED)

        if not verify_totp_code(user.mfa_secret, body.validated_data['code']):
            audit.record(actor=user, actor_email=user.email, action='auth.mfa_failed',
                         resource_type='portal_user', resource_id=user.pk, request=request)
            return error('Incorrect code', status.HTTP_401_UNAUTHORIZED)

        # Both steps passed: create the server-side session.
        now = timezone.now()
        session = AdminSession.objects.create(
            id=new_session_token(),
            portal_user=user,
            created_at=now,
            last_seen_at=now,
            expires_at=now + ABSOLUTE_SESSION_LIFETIME,
        )
        user.last_active_at = now
        user.save(update_fields=['last_active_at'])

        audit.record(actor=user, actor_email=user.email, action='auth.login_succeeded',
                     resource_type='portal_user', resource_id=user.pk, request=request)

        response = Response(CurrentUserSerializer(user).data)
        response.set_cookie(
            SESSION_COOKIE_NAME,
            session.id,
            max_age=int(ABSOLUTE_SESSION_LIFETIME.total_seconds()),
            httponly=True,   # JavaScript can't read it, so a script injected into the page can't steal it
            samesite='Lax',  # not sent on requests started by other websites (CSRF protection)
            # Only over HTTPS when enabled (.env DJANGO_SECURE_COOKIES=True).
            # Off for local http://localhost development.
            secure=settings.SECURE_AUTH_COOKIES,
        )
        return response


class AcceptInviteView(PublicAuthView):
    """Activate an invited account: set the password and generate the MFA secret.

    The Admin who sent the invite never sees or chooses either of them.
    """

    def post(self, request):
        body = AcceptInviteSerializer(data=request.data)
        body.is_valid(raise_exception=True)

        invalid = 'This invitation link is invalid or has expired'
        user_id = read_invite_token(body.validated_data['token'])
        if user_id is None:
            return error(invalid, status.HTTP_401_UNAUTHORIZED)

        with transaction.atomic():
            # select_for_update locks the row, so two clicks on the same link
            # at the same moment can't both activate the account.
            user = PortalUser.objects.select_for_update().filter(pk=user_id).first()
            if user is None:
                return error(invalid, status.HTTP_401_UNAUTHORIZED)

            # The signed token stays valid for 7 days even after use. This check
            # stops it being used again, e.g. if the email was forwarded.
            if user.password_hash:
                return error('This invitation has already been used', status.HTTP_409_CONFLICT)

            user.password_hash = hash_password(body.validated_data['password'])
            user.mfa_secret = generate_mfa_secret()
            user.status = AccountStatus.ACTIVE
            user.save(update_fields=['password_hash', 'mfa_secret', 'status'])

        audit.record(actor=user, actor_email=user.email, action='account.activated',
                     resource_type='portal_user', resource_id=user.pk, request=request)

        # The frontend shows the QR code for scanning and the raw key as a
        # manual-entry fallback. This is the only time the secret is shown.
        return Response({
            'email': user.email,
            'mfa_setup_key': user.mfa_secret,
            'qr_code_data_uri': qr_code_data_uri(totp_provisioning_uri(user.mfa_secret, user.email)),
        })


class MeView(APIView):
    """GET /api/v1/auth/me/ — the logged-in user, or 401 if the session is missing/expired.

    The frontend calls this on every page load to find out whether its
    cookie is still valid, since JavaScript can't read an httpOnly cookie.
    """
    permission_classes = [IsAuthenticated]

    def get(self, request):
        return Response(CurrentUserSerializer(request.user).data)


class LogoutView(APIView):
    """POST /api/v1/auth/logout/ — end the current session."""
    permission_classes = [IsAuthenticated]

    def post(self, request):
        user = request.user
        # request.auth is the AdminSession returned by PortalSessionAuthentication.
        # Deleting the row is what makes logout real: the old cookie is
        # useless even if someone copied it.
        request.auth.delete()

        audit.record(actor=user, actor_email=user.email, action='auth.logout',
                     resource_type='portal_user', resource_id=user.pk, request=request)

        response = Response(status=status.HTTP_204_NO_CONTENT)
        response.delete_cookie(SESSION_COOKIE_NAME, samesite='Lax')
        return response
