"""Mobile-app endpoints (class-based DRF APIViews).

    POST /api/v1/mobile/auth/register/      create a traveller account → {user, token, expiresAt}
    POST /api/v1/mobile/auth/login/         sign in                    → {user, token, expiresAt}
    GET  /api/v1/mobile/auth/session/       who is signed in           → {user, expiresAt}
    POST /api/v1/mobile/auth/logout/        end this session           → {ok: true}
    POST /api/v1/anonymous/report-photos/   upload a report photo      → {photoToken, expiresAt}
    POST /api/v1/graphql/anonymous/             reports, hazards, places, routes (no sign-in)
    POST /api/v1/graphql/mobile/                sensor-data sharing (signed in)

Errors use the shape the app reads: {"error": "message"} for REST calls and
{"errors": [{"message"}]} for GraphQL.
"""

import secrets
from datetime import timedelta

from django.contrib.auth.hashers import check_password, make_password
from django.contrib.auth.password_validation import (
    CommonPasswordValidator, MinimumLengthValidator, NumericPasswordValidator,
    UserAttributeSimilarityValidator, validate_password,
)
from django.core.exceptions import ValidationError
from django.core.validators import validate_email
from django.db import IntegrityError, transaction
from django.utils import timezone
from rest_framework import exceptions, status
from rest_framework.parsers import JSONParser, MultiPartParser
from rest_framework.permissions import AllowAny, IsAuthenticated
from rest_framework.renderers import JSONRenderer
from rest_framework.response import Response
from rest_framework.views import APIView

from . import ratelimit, reports
from .authentication import TravelerTokenAuthentication, hash_token
from .graphql import executor
from .graphql.schema import anonymous_schema, mobile_schema
from .models import Traveler, TravelerSession
from .validation import messages, text

SESSION_LIFETIME = timedelta(days=7)
MAX_GRAPHQL_BYTES = 64 * 1024

# Traveller passwords: at least 12 characters (the app's sign-up form asks
# for the same), not a common password, not all digits, not like the email/name.
TRAVELER_PASSWORD_VALIDATORS = [
    MinimumLengthValidator(min_length=12), CommonPasswordValidator(),
    NumericPasswordValidator(), UserAttributeSimilarityValidator(user_attributes=('email', 'name')),
]
# Checking a password against this when the email is unknown makes a wrong
# email take as long as a wrong password, so response times don't reveal
# which emails have accounts.
_DUMMY_HASH = make_password('roadguard-timing-equaliser')


# ---------------------------------------------------------------------------
# Base classes
# ---------------------------------------------------------------------------

class MobileView(APIView):
    """Common behaviour for the mobile endpoints.

    - JSON in and out only; responses are never cached (Cache-Control: no-store).
    - Any error becomes {"error": "message"}, which the app shows to the user.
    """
    authentication_classes = []
    permission_classes = [AllowAny]
    renderer_classes = [JSONRenderer]
    parser_classes = [JSONParser]

    def handle_exception(self, exc):
        if isinstance(exc, (exceptions.NotAuthenticated, exceptions.AuthenticationFailed)):
            message = str(exc.detail) if exc.detail else 'Please sign in again.'
            return Response({'error': message}, status=status.HTTP_401_UNAUTHORIZED)
        if isinstance(exc, exceptions.APIException):
            detail = exc.detail
            if isinstance(detail, dict):
                detail = ' '.join(str(v[0] if isinstance(v, list) else v) for v in detail.values())
            elif isinstance(detail, list):
                detail = ' '.join(str(v) for v in detail)
            return Response({'error': str(detail)}, status=exc.status_code)
        return super().handle_exception(exc)

    def finalize_response(self, request, response, *args, **kwargs):
        response = super().finalize_response(request, response, *args, **kwargs)
        response['Cache-Control'] = 'no-store'
        return response


class AnonymousMobileView(MobileView):
    """For endpoints that must stay anonymous: refuse requests carrying a cookie
    or an Authorization header, so nothing can link a report to a person."""

    def initial(self, request, *args, **kwargs):
        super().initial(request, *args, **kwargs)
        if request.META.get('HTTP_COOKIE') or request.META.get('HTTP_AUTHORIZATION'):
            raise exceptions.PermissionDenied('Anonymous endpoints require a request without cookies or Authorization.')


class SignedInMobileView(MobileView):
    """For endpoints that need a signed-in traveller (bearer token)."""
    authentication_classes = [TravelerTokenAuthentication]
    permission_classes = [IsAuthenticated]


def user_json(traveler):
    """The traveller as the app's Traveler.fromJson() reads it."""
    return {'id': str(traveler.pk), 'name': traveler.name, 'email': traveler.email,
            'role': 'traveler', 'emailVerified': False}


def start_session(traveler):
    """Create a session and return the app's sign-in reply, including the token (shown only once)."""
    token = secrets.token_urlsafe(32)
    expires = timezone.now() + SESSION_LIFETIME
    TravelerSession.objects.create(token_hash=hash_token(token), traveler=traveler, expires_at=expires)
    return {'user': user_json(traveler), 'token': token, 'expiresAt': expires.isoformat()}


# ---------------------------------------------------------------------------
# Traveller accounts
# ---------------------------------------------------------------------------

class CredentialsView(AnonymousMobileView):
    """Shared checks for register/login: text fields, email format."""

    def fields(self, request, names):
        data = request.data
        if not isinstance(data, dict) or set(data) != set(names):
            raise exceptions.ValidationError('Please check the form fields.')
        values = {}
        try:
            for name in names:
                if name == 'password':
                    # Passwords are used exactly as typed (no trimming).
                    password = data[name]
                    if not isinstance(password, str) or not 1 <= len(password) <= 1024:
                        raise ValidationError('Please check your email and password.')
                    values[name] = password
                else:
                    values[name] = text(data[name], name, 254, required=True)
            values['email'] = values['email'].lower()
            validate_email(values['email'])
        except ValidationError as exc:
            raise exceptions.ValidationError(messages(exc)) from exc
        return values


class RegisterView(CredentialsView):
    """POST /api/v1/mobile/auth/register/ {name, email, password} → 201 {user, token, expiresAt}"""

    def post(self, request):
        # At most 20 new accounts per hour from one network address.
        if not ratelimit.allow('mobile-register', request.META.get('REMOTE_ADDR', ''), limit=20, window_seconds=3600):
            return Response({'error': 'Too many attempts. Please try again later.'}, status=429)
        values = self.fields(request, ('name', 'email', 'password'))
        if len(values['name']) > 160:
            return Response({'error': 'Enter your name (up to 160 characters).'}, status=400)

        traveler = Traveler(name=values['name'], email=values['email'])
        try:
            validate_password(values['password'], user=traveler, password_validators=TRAVELER_PASSWORD_VALIDATORS)
        except ValidationError as exc:
            return Response({'error': ' '.join(exc.messages)}, status=400)
        traveler.password_hash = make_password(values['password'])
        try:
            with transaction.atomic():
                traveler.save()
                reply = start_session(traveler)
        except IntegrityError:  # the email is already registered
            return Response({'error': 'Unable to create this account. Try signing in or use another email.'},
                            status=409)
        return Response(reply, status=201)


class LoginView(CredentialsView):
    """POST /api/v1/mobile/auth/login/ {email, password} → {user, token, expiresAt}"""

    def post(self, request):
        values = self.fields(request, ('email', 'password'))
        # At most 10 attempts per email per 10 minutes, against password guessing.
        if not ratelimit.allow('mobile-login', values['email'], limit=10, window_seconds=600):
            return Response({'error': 'Too many attempts. Please try again later.'}, status=429)
        traveler = Traveler.objects.filter(email__iexact=values['email'], is_active=True).first()
        valid = check_password(values['password'], traveler.password_hash if traveler else _DUMMY_HASH)
        if traveler is None or not valid:
            return Response({'error': 'Email or password is incorrect.'}, status=401)
        return Response(start_session(traveler))


class SessionView(SignedInMobileView):
    """GET /api/v1/mobile/auth/session/ → {user, expiresAt} (401 if the token is no longer valid)"""

    def get(self, request):
        return Response({'user': user_json(request.user), 'expiresAt': request.auth.expires_at.isoformat()})


class LogoutView(SignedInMobileView):
    """POST /api/v1/mobile/auth/logout/ → {ok: true}. Deletes the session on the server."""

    def post(self, request):
        request.auth.delete()  # request.auth is the TravelerSession
        return Response({'ok': True})


# ---------------------------------------------------------------------------
# Anonymous report photo
# ---------------------------------------------------------------------------

class ReportPhotoView(AnonymousMobileView):
    """POST /api/v1/anonymous/report-photos/ (multipart, one file field "photo") → 201 {photoToken, expiresAt}"""
    parser_classes = [MultiPartParser]

    def post(self, request):
        if request.data.keys() - {'photo'} or len(request.FILES.getlist('photo')) != 1:
            return Response({'error': 'Supply exactly one photo and no additional fields.'}, status=400)
        try:
            photo, token = reports.stage_photo(request.FILES['photo'])
        except ValidationError as exc:
            return Response({'error': messages(exc)}, status=400)
        return Response({'photoToken': token, 'expiresAt': photo.expires_at.isoformat()}, status=201)


# ---------------------------------------------------------------------------
# GraphQL endpoints
# ---------------------------------------------------------------------------

class GraphQLMixin:
    """POST a GraphQL request {query, variables, operationName} to `schema`."""
    schema = None

    def post(self, request):
        size = int(request.META.get('CONTENT_LENGTH') or 0)
        if request.content_type != 'application/json' or size > MAX_GRAPHQL_BYTES:
            return Response({'errors': [{'message': 'Use a JSON object no larger than 64 KiB.'}]}, status=400)
        reply, code = executor.run(self.schema, request.data, request)
        return Response(reply, status=code)

    def handle_exception(self, exc):
        # Keep GraphQL's {"errors": [...]} shape for these endpoints (plus
        # "error", which the app's account client reads on failures).
        response = super().handle_exception(exc)
        message = response.data.get('error', 'Request failed.') if isinstance(response.data, dict) else 'Request failed.'
        response.data = {'errors': [{'message': message}], 'error': message}
        return response


class AnonymousGraphQLView(GraphQLMixin, AnonymousMobileView):
    """POST /api/v1/graphql/anonymous/ — reports, hazards, place search, routes."""
    schema = anonymous_schema


class MobileGraphQLView(GraphQLMixin, SignedInMobileView):
    """POST /api/v1/graphql/mobile/ — sensor-data consent and uploads (signed in)."""
    schema = mobile_schema
