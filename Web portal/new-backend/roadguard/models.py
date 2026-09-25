"""Database models for the RoadGuard web portal.

These mirror the SQLAlchemy models of the old FastAPI backend (archived in
backend-fastapi-archive.zip, app/models/) — same table names,
same enum values (which in turn match the frontend's src/types/index.ts) — so
the React dashboard can switch backends without changing the JSON shapes it
renders. Each model becomes one PostgreSQL table via Django migrations
(see roadguard/migrations/).
"""

import uuid

from django.core.validators import MaxValueValidator, MinValueValidator
from django.db import models, transaction
from django.utils import timezone


# ---------------------------------------------------------------------------
# Choice lists (enums). The stored value (right-hand side) is exactly what the
# frontend expects, e.g. "TARURA Officer" or "Under Repair".
# ---------------------------------------------------------------------------

class AccountStatus(models.TextChoices):
    """Whether a portal user / authority is enabled. Shared by both models."""
    ACTIVE = 'Active'
    INACTIVE = 'Inactive'


class UserRole(models.TextChoices):
    """Portal roles. Admin manages users/authorities; officers work with defects."""
    ADMIN = 'Admin'
    TARURA_OFFICER = 'TARURA Officer'


class Severity(models.TextChoices):
    """How dangerous a road defect is — drives marker/badge colours."""
    LOW = 'low'
    MEDIUM = 'medium'
    HIGH = 'high'


class ReportSource(models.TextChoices):
    """Where a defect came from: the mobile app user ("manual") or a sensor ("device")."""
    MANUAL = 'manual'
    DEVICE = 'device'


class ReportStatus(models.TextChoices):
    """The lifecycle a defect moves through as it is reviewed and fixed."""
    NEW = 'New'
    VERIFIED = 'Verified'
    UNDER_REPAIR = 'Under Repair'
    RESOLVED = 'Resolved'


class HazardType(models.TextChoices):
    """Hazard category. RoadGuard covers potholes only — road cracks are out of
    the project's scope and are rejected (see mobile/reports.py). Kept as a
    choice list so a category could be added in one place later."""
    POTHOLE = 'Pothole'


# ---------------------------------------------------------------------------
# Base class for models with readable ids like "RG-00131".
# ---------------------------------------------------------------------------

class PrefixedIdModel(models.Model):
    """Abstract base: gives a model a human-readable primary key.

    Ids like "AUTH-001" / "RG-00131" (rather than plain integers) serialize to
    exactly the id shape the frontend already renders. Subclasses set
    ID_PREFIX and ID_DIGITS; the id is generated automatically on first save.
    """
    ID_PREFIX = ''
    ID_DIGITS = 3

    id = models.CharField(primary_key=True, max_length=20, editable=False)

    class Meta:
        abstract = True  # no table of its own — only subclasses get tables

    def save(self, *args, **kwargs):
        if not self.id:
            with transaction.atomic():
                # Lock the existing rows so two requests creating records at
                # the same moment can't both compute the same "next" number.
                existing = (type(self).objects.select_for_update()
                            .filter(id__startswith=self.ID_PREFIX)
                            .values_list('id', flat=True))
                # Take the highest existing number and add one, e.g.
                # "RG-00147" -> 147 -> "RG-00148".
                numbers = [int(i[len(self.ID_PREFIX):]) for i in existing
                           if i[len(self.ID_PREFIX):].isdigit()]
                self.id = f'{self.ID_PREFIX}{max(numbers, default=0) + 1:0{self.ID_DIGITS}d}'
                return super().save(*args, **kwargs)
        return super().save(*args, **kwargs)


# ---------------------------------------------------------------------------
# Core records
# ---------------------------------------------------------------------------

class Authority(PrefixedIdModel):
    """A road authority taking part in the pilot (e.g. TARURA)."""
    ID_PREFIX = 'AUTH-'

    name = models.CharField(max_length=120)
    coverage_area = models.CharField(max_length=200)
    contact = models.CharField(max_length=200)
    status = models.CharField(max_length=20, choices=AccountStatus.choices,
                              default=AccountStatus.ACTIVE)

    class Meta:
        db_table = 'authorities'
        ordering = ['name']
        verbose_name_plural = 'authorities'

    def __str__(self):
        return f'{self.id} {self.name}'


class PortalUser(PrefixedIdModel):
    """A dashboard account (Admin / TARURA Officer), SRS FR-USR-1..3.

    This is *not* Django's built-in auth User (that one is only used for the
    /admin/ site). Portal users log in through the /api/v1/auth/ endpoints with a
    password plus an authenticator-app code (MFA).
    """
    ID_PREFIX = 'USR-'

    name = models.CharField(max_length=120)
    email = models.EmailField(max_length=200, unique=True)
    phone = models.CharField(max_length=30, blank=True, null=True)
    role = models.CharField(max_length=20, choices=UserRole.choices)
    # Plain text rather than a FK to Authority: the frontend already uses
    # values like "System" that aren't authority rows.
    authority = models.CharField(max_length=120)
    status = models.CharField(max_length=20, choices=AccountStatus.choices,
                              default=AccountStatus.ACTIVE)
    last_active_at = models.DateTimeField(auto_now_add=True)
    created_at = models.DateTimeField(auto_now_add=True)

    # Salted hash made by Django's make_password() — never the plain password.
    # Empty (null) for an invited account until the invitee opens their
    # activation link and chooses a password themselves.
    password_hash = models.CharField(max_length=200, blank=True, null=True)
    # Base32 secret shared with the user's authenticator app (TOTP). Set at
    # the same moment as password_hash; login is refused while either is null.
    mfa_secret = models.CharField(max_length=64, blank=True, null=True)

    class Meta:
        db_table = 'portal_users'
        ordering = ['created_at']

    def __str__(self):
        return f'{self.id} {self.email}'

    # DRF's IsAuthenticated permission checks `request.user.is_authenticated`.
    # Anyone who reaches a view as a PortalUser has already passed
    # PortalSessionAuthentication, so this is always True for this model.
    @property
    def is_authenticated(self):
        return True

    @property
    def is_admin(self):
        """Shortcut used by the permission classes."""
        return self.role == UserRole.ADMIN


class ReportPhoto(models.Model):
    """A photo uploaded by the mobile app for an anonymous report.

    Upload flow (mobile/views.py): the app first uploads the photo and gets a
    one-time `photoToken`; it then submits the report with that token, which
    "claims" the photo. Only a hash of the token is stored. Unclaimed photos
    expire after 15 minutes and are deleted by `manage.py purge_expired_photos`.
    The image is re-encoded on upload, which strips EXIF/GPS/camera metadata.
    """
    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    token_hash = models.CharField(max_length=64, unique=True, editable=False)
    content = models.BinaryField(editable=False)  # the sanitized JPEG bytes
    sha256 = models.CharField(max_length=64, editable=False)
    created_at = models.DateTimeField(auto_now_add=True)
    expires_at = models.DateTimeField(db_index=True)

    class Meta:
        db_table = 'report_photos'


class Defect(PrefixedIdModel):
    """A road defect shown on the Dashboard, Map and Reports.

    Defects come from three places:
    - the portal (created by an Admin),
    - the mobile app — a traveller's anonymous photo report (source "manual"),
    - sensor detections — many phones detecting the same spot, grouped by
      detection/spots.py (source "device").

    PostGIS: besides `lat`/`lng`, the table has a `location` geography column
    that PostgreSQL computes from them automatically (added by migration
    0003 with raw SQL, so it isn't declared as a Django field). It has a
    spatial index and is used for "within X metres" and map-area queries.
    """
    ID_PREFIX = 'RG-'
    ID_DIGITS = 5

    hazard_type = models.CharField(max_length=20, choices=HazardType.choices,
                                   default=HazardType.POTHOLE)
    road = models.CharField(max_length=200)
    region = models.CharField(max_length=100)
    severity = models.CharField(max_length=10, choices=Severity.choices)
    status = models.CharField(max_length=20, choices=ReportStatus.choices,
                              default=ReportStatus.NEW)
    source = models.CharField(max_length=10, choices=ReportSource.choices)
    # 0–100, as the frontend renders it (`{confidence}%`); 100 for manual reports.
    confidence = models.FloatField(default=100.0,
                                   validators=[MinValueValidator(0), MaxValueValidator(100)])
    # How many separate reports/detections point at this same defect.
    observation_count = models.PositiveIntegerField(default=1)
    detected_at = models.DateTimeField()
    # WGS84 lat/lng — the flat numbers the frontend's Defect uses. PostgreSQL
    # derives the PostGIS `location` column from these (see class docstring).
    lat = models.FloatField(validators=[MinValueValidator(-90), MaxValueValidator(90)])
    lng = models.FloatField(validators=[MinValueValidator(-180), MaxValueValidator(180)])
    has_photo = models.BooleanField(default=False)

    # Filled in when someone reviews the defect (SRS FR-DEF-3 / FR-MOD-2).
    # reviewed_by / reviewed_at are always set by the server from the
    # logged-in user (see DefectDetailView), never accepted from the client.
    review_note = models.TextField(blank=True, null=True)
    reviewed_by = models.ForeignKey(PortalUser, on_delete=models.SET_NULL,
                                    blank=True, null=True, related_name='reviewed_defects',
                                    db_column='reviewed_by')
    reviewed_at = models.DateTimeField(blank=True, null=True)

    # --- Mobile-app report fields (source "manual" from the app; null otherwise) ---
    # The app's own UUID for the report. Unique, so a retried upload returns
    # the same defect instead of creating a duplicate.
    client_id = models.UUIDField(unique=True, blank=True, null=True, editable=False)
    notes = models.CharField(max_length=500, blank=True, default='')
    # The GPS evidence recorded with the report (the app requires the phone to
    # be stationary with accuracy of 25 m or better).
    gps_accuracy_m = models.FloatField(blank=True, null=True)
    gps_observed_at = models.DateTimeField(blank=True, null=True)
    # Hash of the submitted payload, to tell an honest retry from a different
    # report reusing the same client_id.
    payload_digest = models.CharField(max_length=64, blank=True, default='', editable=False)
    photo = models.OneToOneField(ReportPhoto, on_delete=models.PROTECT, blank=True, null=True,
                                 related_name='defect')

    # --- Crowd-sensing fields (maintained by detection/spots.py) ---
    # How many *different* phones detected this spot. Agreement between
    # separate devices is the evidence that it's a real pothole.
    device_count = models.PositiveIntegerField(default=0)
    # 0–1 combined severity measured from all detections (bigger jolt = higher).
    severity_score = models.FloatField(blank=True, null=True)
    last_detected_at = models.DateTimeField(blank=True, null=True)
    # When the spot first met the rule for alerting drivers (see settings
    # SPOT_MIN_DEVICES_TO_PUBLISH). Null = not yet published to drivers.
    published_at = models.DateTimeField(blank=True, null=True)
    # True when built only from simulated detections (manage.py
    # simulate_detections). Never shown to drivers unless
    # ROADGUARD_PUBLISH_SIMULATED is on (development only).
    is_simulated = models.BooleanField(default=False)

    # A server UUID for each defect. The mobile app requires report
    # acknowledgements to carry a UUID; the readable "RG-00012" id stays the
    # primary key used everywhere else.
    uuid = models.UUIDField(default=uuid.uuid4, unique=True, editable=False)
    created_at = models.DateTimeField(default=timezone.now, editable=False)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        db_table = 'defects'
        ordering = ['-detected_at']  # newest first
        indexes = [models.Index(fields=['status']), models.Index(fields=['region'])]

    def __str__(self):
        return f'{self.id} {self.road} ({self.severity})'


# ---------------------------------------------------------------------------
# Login sessions, audit trail and outgoing email
# ---------------------------------------------------------------------------

class AdminSession(models.Model):
    """A logged-in browser session for a PortalUser.

    The browser only ever holds `id` (a long random token) in an httpOnly
    cookie; it can't read or forge anything else. Keeping the session in the
    database is what makes logout, the 30-minute idle timeout and the 8-hour
    maximum lifetime enforceable on the server (see authentication.py).
    """
    id = models.CharField(primary_key=True, max_length=64)
    # Deleting a user also deletes their sessions, logging them out everywhere.
    portal_user = models.ForeignKey(PortalUser, on_delete=models.CASCADE,
                                    related_name='sessions')
    created_at = models.DateTimeField()
    # Updated on every authenticated request — the idle timeout counts from here.
    last_seen_at = models.DateTimeField()
    # Hard cut-off regardless of activity.
    expires_at = models.DateTimeField()

    class Meta:
        db_table = 'admin_sessions'

    def __str__(self):
        return f'session for {self.portal_user_id}'


class AuditLog(models.Model):
    """Who did what, to what, and when (SRS NFR-SEC-4).

    Rows are written by roadguard.audit.record() from every action worth
    tracking: logins, user/authority changes and defect reviews.
    """
    # Nullable: a failed login for an unknown email has no real account.
    # SET_NULL keeps the log entry if the user is deleted later; actor_email
    # below still says who it was.
    actor = models.ForeignKey(PortalUser, on_delete=models.SET_NULL, blank=True, null=True,
                              related_name='audit_entries', db_column='actor_id')
    actor_email = models.CharField(max_length=200)
    # A short dotted verb such as "auth.login_succeeded" or "defect.reviewed",
    # so entries are easy to filter and group.
    action = models.CharField(max_length=60)
    resource_type = models.CharField(max_length=40)  # e.g. "portal_user", "defect"
    resource_id = models.CharField(max_length=40, blank=True, null=True)
    details = models.TextField(blank=True, null=True)
    ip_address = models.GenericIPAddressField(blank=True, null=True)
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        db_table = 'audit_log'
        ordering = ['-created_at']  # newest first

    def __str__(self):
        return f'{self.created_at:%Y-%m-%d %H:%M} {self.actor_email} {self.action}'


class OutboxEmail(models.Model):
    """An email the portal "sent".

    No real mail provider is configured yet, so the OutboxEmailBackend
    (roadguard/email_backends.py) stores every outgoing email here instead.
    During development you can read them at /api/v1/dev/outbox/, for example to
    click an account-activation link.
    """
    to_email = models.CharField(max_length=200)
    subject = models.CharField(max_length=200)
    body = models.TextField()
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        db_table = 'outbox_emails'
        ordering = ['-created_at']

    def __str__(self):
        return f'{self.to_email}: {self.subject}'
