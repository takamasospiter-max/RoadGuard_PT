"""Django admin page (/api/v1/admin/) for AI detections. Read-only: they're produced by the AI engine."""

from django.contrib import admin

from .models import Detection


@admin.register(Detection)
class DetectionAdmin(admin.ModelAdmin):
    list_display = ('detected_at', 'hazard_type', 'confidence', 'intensity', 'severity',
                    'defect', 'model_version', 'is_simulated')
    list_filter = ('is_simulated', 'model_version', 'severity')

    def has_add_permission(self, request):
        return False

    def has_change_permission(self, request, obj=None):
        return False
