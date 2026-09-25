"""Class-based DRF API views for the portal's data (defects, authorities, users, audit log).

Login/logout/activation endpoints live separately in auth_views.py.

Every view here requires a logged-in portal user (see
settings.REST_FRAMEWORK's DEFAULT_PERMISSION_CLASSES); some also require an
Admin (permissions.py). Every change is written to the audit log.
"""

import re
from html import escape

from django.conf import settings
from django.core.mail import EmailMessage
from django.db import transaction
from django.http import HttpResponse
from django.shortcuts import get_object_or_404
from django.utils import timezone
from rest_framework import status
from rest_framework.exceptions import APIException, PermissionDenied, ValidationError
from rest_framework.permissions import IsAuthenticated
from rest_framework.response import Response
from rest_framework.views import APIView

from . import audit
from .models import AccountStatus, AuditLog, Authority, Defect, OutboxEmail, PortalUser, UserRole
from .permissions import IsAdmin, IsAdminOrReadOnly
from .security import issue_invite_token
from .serializers import (AuditLogSerializer, AuthoritySerializer, DefectSerializer,
                          InviteUserSerializer, PortalUserSerializer)


# ---------------------------------------------------------------------------
# Reusable base views
# ---------------------------------------------------------------------------

class BadRequest(APIException):
    """A 400 error with a single readable message: {"detail": "..."}.

    (DRF's ValidationError wraps messages in lists, which is meant for
    per-field errors; this is for rule violations that aren't about one field.)
    """
    status_code = status.HTTP_400_BAD_REQUEST
    default_detail = 'Invalid request'


class AuditedViewMixin:
    """Adds `self.audit(...)`, which logs an action by the current user."""

    # Name used in audit entries, e.g. "defect" -> "defect.created".
    audit_resource = None

    def audit(self, action, obj_id, details=None):
        audit.record(
            actor=self.request.user,
            actor_email=self.request.user.email,
            action=f'{self.audit_resource}.{action}',
            resource_type=self.audit_resource,
            resource_id=obj_id,
            details=details,
            request=self.request,
        )


def changed_fields(serializer):
    """"changed: a, b" — the fields a PATCH/PUT actually sent, for the audit log."""
    return 'changed: ' + ', '.join(sorted(serializer.validated_data.keys()))


class ListCreateView(AuditedViewMixin, APIView):
    """GET a list of records / POST a new one.

    Subclasses set `model` and `serializer_class`. `filter_fields` lists the
    query-string parameters that filter the list by exact match, e.g.
    /api/v1/defects/?status=New&region=Arusha
    """

    model = None
    serializer_class = None
    filter_fields = ()

    def get_queryset(self):
        queryset = self.model.objects.all()
        for field in self.filter_fields:
            value = self.request.query_params.get(field)
            if value:
                queryset = queryset.filter(**{field: value})
        return queryset

    def get(self, request):
        serializer = self.serializer_class(self.get_queryset(), many=True)
        return Response(serializer.data)

    def post(self, request):
        serializer = self.serializer_class(data=request.data)
        # raise_exception=True sends a 400 with the field errors automatically.
        serializer.is_valid(raise_exception=True)
        obj = serializer.save()
        self.audit('created', obj.pk)
        return Response(serializer.data, status=status.HTTP_201_CREATED)


class DetailView(AuditedViewMixin, APIView):
    """GET / PUT / PATCH / DELETE one record by its id ("RG-00001", "AUTH-001", ...).

    Subclasses can override perform_update() / perform_destroy() to add rules.
    """

    model = None
    serializer_class = None

    def get_object(self, pk):
        # Answers 404 {"detail": "No Defect matches the given query."} if missing.
        return get_object_or_404(self.model, pk=pk)

    def get(self, request, pk):
        return Response(self.serializer_class(self.get_object(pk)).data)

    def put(self, request, pk):
        # PUT = replace the whole record (every required field must be sent).
        return self._update(request, pk, partial=False)

    def patch(self, request, pk):
        # PATCH = change only the fields that are sent.
        return self._update(request, pk, partial=True)

    def delete(self, request, pk):
        obj = self.get_object(pk)
        self.perform_destroy(obj)
        self.audit('deleted', pk)
        return Response(status=status.HTTP_204_NO_CONTENT)

    def _update(self, request, pk, partial):
        obj = self.get_object(pk)
        serializer = self.serializer_class(obj, data=request.data, partial=partial)
        serializer.is_valid(raise_exception=True)
        self.perform_update(serializer)
        return Response(serializer.data)

    def perform_update(self, serializer):
        """Save the change and log it. Override to add rules."""
        serializer.save()
        self.audit('updated', serializer.instance.pk, changed_fields(serializer))

    def perform_destroy(self, obj):
        obj.delete()


# ---------------------------------------------------------------------------
# Defects
# ---------------------------------------------------------------------------

class DefectListView(ListCreateView):
    """GET /api/v1/defects/ (any user) — POST /api/v1/defects/ (Admin only)."""
    permission_classes = [IsAdminOrReadOnly]
    model = Defect
    serializer_class = DefectSerializer
    filter_fields = ('status', 'severity', 'region', 'source')
    audit_resource = 'defect'

    def get_queryset(self):
        # select_related loads each reviewer in the same query, so listing
        # 100 defects doesn't run 100 extra queries for reviewer names.
        return super().get_queryset().select_related('reviewed_by')


class DefectDetailView(DetailView):
    """One defect.

    GET   — any logged-in user
    PATCH — any logged-in user may *review* it (change status / review_note);
            only Admins may change other fields
    PUT / DELETE — Admin only
    """
    model = Defect
    serializer_class = DefectSerializer
    audit_resource = 'defect'

    # The fields that make up a review (SRS FR-DEF-3 / FR-MOD-2).
    REVIEW_FIELDS = {'status', 'review_note'}

    def get_permissions(self):
        # Different rules per HTTP method, as described in the docstring.
        if self.request.method in ('PUT', 'DELETE'):
            return [IsAdmin()]
        return [IsAuthenticated()]

    def patch(self, request, pk):
        # A TARURA Officer may only send review fields; anything else needs an
        # Admin. Read-only fields (id, reviewed_by, reviewed_at) are allowed
        # through because the serializer ignores them anyway.
        read_only = set(self.serializer_class.Meta.read_only_fields) | {'reviewed_by'}
        if not request.user.is_admin and set(request.data) - self.REVIEW_FIELDS - read_only:
            raise PermissionDenied('Only Admins can change fields other than status and review note')
        return super().patch(request, pk)

    def perform_update(self, serializer):
        data = serializer.validated_data
        if self.REVIEW_FIELDS & set(data):
            # This change is a review, so record who made it and when. The
            # values come from the logged-in session, never from the request
            # body (both fields are read-only in DefectSerializer).
            serializer.save(reviewed_by=self.request.user, reviewed_at=timezone.now())
            self.audit('reviewed', serializer.instance.pk, changed_fields(serializer))
        else:
            super().perform_update(serializer)


class DefectPhotoView(APIView):
    """GET /api/v1/defects/<id>/photo/ — the JPEG attached to a mobile-app report.

    Any logged-in portal user may view it, so officers can check the report.
    The photo was re-encoded on upload (mobile/reports.py), so it carries no
    EXIF/GPS metadata. It is never publicly accessible.
    """

    def get(self, request, pk):
        defect = get_object_or_404(Defect.objects.select_related('photo'), pk=pk)
        if defect.photo is None:
            return Response({'detail': 'This defect has no photo.'}, status=status.HTTP_404_NOT_FOUND)
        response = HttpResponse(bytes(defect.photo.content), content_type='image/jpeg')
        response['Cache-Control'] = 'private, no-store'
        response['Content-Disposition'] = f'inline; filename="{defect.pk}.jpg"'
        return response


class HealthView(APIView):
    """GET /api/v1/health/ — {"status": "ok"} if the server can query PostgreSQL + PostGIS.

    Public (no login) so monitoring tools and the README checks can call it.
    """
    authentication_classes = []
    permission_classes = []

    def get(self, request):
        from django.db import DatabaseError, connection
        try:
            with connection.cursor() as cursor:
                cursor.execute('SELECT postgis_lib_version()')
                postgis = cursor.fetchone()[0]
        except DatabaseError:
            return Response({'status': 'unavailable'}, status=status.HTTP_503_SERVICE_UNAVAILABLE)
        return Response({'status': 'ok', 'database': 'PostgreSQL', 'postgis': postgis})


# ---------------------------------------------------------------------------
# Authorities
# ---------------------------------------------------------------------------

class AuthorityListView(ListCreateView):
    """GET /api/v1/authorities/ (any user) — POST (Admin only)."""
    permission_classes = [IsAdminOrReadOnly]
    model = Authority
    serializer_class = AuthoritySerializer
    filter_fields = ('status',)
    audit_resource = 'authority'


class AuthorityDetailView(DetailView):
    """GET one authority (any user) — PUT / PATCH / DELETE (Admin only)."""
    permission_classes = [IsAdminOrReadOnly]
    model = Authority
    serializer_class = AuthoritySerializer
    audit_resource = 'authority'


# ---------------------------------------------------------------------------
# Portal users
# ---------------------------------------------------------------------------

class PortalUserListView(ListCreateView):
    """GET /api/v1/users/ — list portal users (any logged-in user).

    New users are *invited* through PortalUserInviteView rather than created
    here, so POST is not offered on this endpoint.
    """
    http_method_names = ['get', 'head', 'options']  # no POST
    model = PortalUser
    serializer_class = PortalUserSerializer
    filter_fields = ('role', 'status')
    audit_resource = 'user'


class PortalUserInviteView(AuditedViewMixin, APIView):
    """POST /api/v1/users/invite/ — an Admin invites a new portal user.

    1. Creates the account as Inactive, with no password and no MFA yet.
    2. Emails the invitee an activation link (valid 7 days) that opens the
       frontend's /activate page, where they choose a password and scan the
       MFA QR code (see auth_views.AcceptInviteView).
    """
    permission_classes = [IsAdmin]
    audit_resource = 'user'

    def post(self, request):
        serializer = InviteUserSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)

        # atomic(): if sending the email fails, the new account is rolled
        # back too, so no one ends up with an account they were never told about.
        with transaction.atomic():
            # Starts Inactive: it can't log in until activated, and the
            # frontend's filters/badges already understand Active/Inactive.
            user = serializer.save(status=AccountStatus.INACTIVE)
            self._send_invite_email(user)

        self.audit('invited', user.pk, f'role={user.role}, authority={user.authority}')
        return Response(PortalUserSerializer(user).data, status=status.HTTP_201_CREATED)

    def _send_invite_email(self, user):
        link = f'{settings.FRONTEND_URL}/activate?token={issue_invite_token(user.pk)}'
        EmailMessage(
            subject='Activate your RoadGuard AI account',
            body=(
                f'Hi {user.name},\n\n'
                f'A RoadGuard AI portal account has been created for you as a {user.role}.\n'
                f'Activate it and set up your password + authenticator app here:\n\n'
                f'{link}\n\n'
                f'This link expires in 7 days.'
            ),
            to=[user.email],
        ).send()  # goes to whichever backend settings.MAILERS selects


class PortalUserDetailView(DetailView):
    """GET one user (any logged-in user) — PUT / PATCH / DELETE (Admin only)."""
    permission_classes = [IsAdminOrReadOnly]
    model = PortalUser
    serializer_class = PortalUserSerializer
    audit_resource = 'user'

    def perform_update(self, serializer):
        # Safety rules that stop an Admin from locking themselves out, since
        # getting back in would need direct database access.
        if serializer.instance.pk == self.request.user.pk:
            data = serializer.validated_data
            if data.get('status') == AccountStatus.INACTIVE:
                raise BadRequest("You can't deactivate your own account")
            if 'role' in data and data['role'] != UserRole.ADMIN:
                raise BadRequest("You can't remove your own Admin role")
        super().perform_update(serializer)

    def perform_destroy(self, obj):
        if obj.pk == self.request.user.pk:
            raise BadRequest("You can't delete your own account")
        obj.delete()


# ---------------------------------------------------------------------------
# Audit log
# ---------------------------------------------------------------------------

class AuditLogListView(APIView):
    """GET /api/v1/audit-log/?limit=200 — newest entries first (Admin only).

    Optional filters: ?action=auth.login_failed, ?actor_email=..., ?resource_type=defect
    """
    permission_classes = [IsAdmin]
    MAX_LIMIT = 1000

    def get(self, request):
        queryset = AuditLog.objects.all()  # already newest-first (model ordering)
        for field in ('action', 'actor_email', 'resource_type', 'resource_id'):
            value = request.query_params.get(field)
            if value:
                queryset = queryset.filter(**{field: value})

        # ?limit caps how many rows come back (default 200, never above MAX_LIMIT).
        try:
            limit = min(int(request.query_params.get('limit', 200)), self.MAX_LIMIT)
        except ValueError:
            raise ValidationError({'limit': 'Must be a whole number'})

        return Response(AuditLogSerializer(queryset[:max(limit, 0)], many=True).data)


# ---------------------------------------------------------------------------
# Development-only inbox
# ---------------------------------------------------------------------------

def dev_outbox(request):
    """GET /api/v1/dev/outbox/ — shows the emails stored by OutboxEmailBackend.

    Stands in for a real inbox during development so you can click
    activation links. Only routed when DEBUG=True (see config/urls.py).
    """
    emails = OutboxEmail.objects.all()
    if not emails:
        return HttpResponse('<p>No emails sent yet.</p>')

    def render_body(body):
        # Escape first (the content includes whatever an Admin typed), then
        # turn http(s) URLs into clickable links.
        return re.sub(r'(https?://\S+)', r'<a href="\1">\1</a>', escape(body))

    items = ''.join(
        f"<li style='margin-bottom:1.5em'>"
        f'<div><b>To:</b> {escape(e.to_email)}</div>'
        f'<div><b>Subject:</b> {escape(e.subject)}</div>'
        f'<div><b>Sent:</b> {e.created_at:%Y-%m-%d %H:%M:%S} UTC</div>'
        f"<pre style='white-space:pre-wrap;background:#f4f4f4;padding:.75em;border-radius:6px'>"
        f'{render_body(e.body)}</pre></li>'
        for e in emails
    )
    return HttpResponse(f"<h1>Dev Outbox</h1><ul style='list-style:none;padding:0'>{items}</ul>")
