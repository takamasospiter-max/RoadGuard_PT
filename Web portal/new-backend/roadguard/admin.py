"""Registers the models with Django's built-in admin site (/api/v1/admin/).

Handy for inspecting data during development. Log in there with a Django
superuser (`python manage.py createsuperuser`), which is separate from
portal users.
"""

from django.contrib import admin

from .models import AdminSession, AuditLog, Authority, Defect, OutboxEmail, PortalUser


@admin.register(Defect)
class DefectAdmin(admin.ModelAdmin):
    list_display = ('id', 'road', 'region', 'severity', 'status', 'source', 'detected_at')
    list_filter = ('status', 'severity', 'source', 'region')
    search_fields = ('id', 'road', 'region')


@admin.register(Authority)
class AuthorityAdmin(admin.ModelAdmin):
    list_display = ('id', 'name', 'coverage_area', 'status')


@admin.register(PortalUser)
class PortalUserAdmin(admin.ModelAdmin):
    list_display = ('id', 'name', 'email', 'role', 'status')
    list_filter = ('role', 'status')
    search_fields = ('name', 'email')
    # Never shown or edited here. Use `manage.py create_admin` or the
    # invitation flow to set credentials.
    exclude = ('password_hash', 'mfa_secret')


@admin.register(AuditLog)
class AuditLogAdmin(admin.ModelAdmin):
    """Read-only: an audit trail that can be edited can't be trusted."""
    list_display = ('created_at', 'actor_email', 'action', 'resource_type', 'resource_id', 'ip_address')
    list_filter = ('action', 'resource_type')
    search_fields = ('actor_email', 'resource_id', 'details')

    def has_add_permission(self, request):
        return False

    def has_change_permission(self, request, obj=None):
        return False

    def has_delete_permission(self, request, obj=None):
        return False


@admin.register(OutboxEmail)
class OutboxEmailAdmin(admin.ModelAdmin):
    list_display = ('created_at', 'to_email', 'subject')


@admin.register(AdminSession)
class AdminSessionAdmin(admin.ModelAdmin):
    """Deleting a session here logs that browser out."""
    list_display = ('portal_user', 'created_at', 'last_seen_at', 'expires_at')
    # The session id is effectively a password, so it isn't shown.
    exclude = ('id',)

    def has_add_permission(self, request):
        return False
