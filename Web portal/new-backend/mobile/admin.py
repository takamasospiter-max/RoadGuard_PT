"""Django admin pages (/api/v1/admin/) for traveller accounts — for inspecting data during development."""

from django.contrib import admin

from .models import Traveler


@admin.register(Traveler)
class TravelerAdmin(admin.ModelAdmin):
    list_display = ('email', 'name', 'is_active', 'created_at')
    search_fields = ('email', 'name')
    list_filter = ('is_active',)
    # The password hash is never shown or edited here.
    exclude = ('password_hash',)
