"""Django admin pages (/api/v1/admin/) for sensor-data sharing. Read-only: uploaded data is evidence."""

from django.contrib import admin

from .models import CollectionConsent, TelemetryBatch


class ReadOnlyAdmin(admin.ModelAdmin):
    def has_add_permission(self, request):
        return False

    def has_change_permission(self, request, obj=None):
        return False


@admin.register(CollectionConsent)
class CollectionConsentAdmin(ReadOnlyAdmin):
    list_display = ('id', 'traveler', 'trip_id', 'granted_at', 'expires_at', 'revoked_at')


@admin.register(TelemetryBatch)
class TelemetryBatchAdmin(ReadOnlyAdmin):
    list_display = ('id', 'trip_id', 'received_at', 'ai_status', 'ai_model_version')
    list_filter = ('ai_status',)
