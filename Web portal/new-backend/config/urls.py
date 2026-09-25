"""All URLs of the RoadGuard backend, under ONE base path.

Every route lives below settings.API_PREFIX (default "api/v1/", set with
ROADGUARD_API_PREFIX), so each client needs a single base URL:

    http://<server>/api/v1/            ← the base URL
        auth/..., defects/..., users/..., ai-engine/...   web portal (roadguard/urls.py)
        mobile/auth/..., anonymous/..., graphql/...       mobile app (mobile/urls.py)
        ai/...                                            external AI engine service (detection/urls.py)
        health/                                           is the server up?
        admin/                                            Django's admin site
        dev/outbox/                                       emails "sent" in development (DEBUG only)

The website reads the base URL from VITE_API_URL and the app from
ROADGUARD_API_URL (+ this prefix), so changing the prefix here means
changing those two settings too.
"""
from django.conf import settings
from django.contrib import admin
from django.urls import include, path

from roadguard.views import HealthView, dev_outbox

api_routes = [
    # The REST API the React portal talks to.
    path('', include('roadguard.urls')),
    # Mobile app: traveller accounts, anonymous report photos, GraphQL.
    path('', include('mobile.urls')),
    # AI engine service API (authenticated with an API key).
    path('ai/', include('detection.urls')),
    # Is the server up and can it reach PostgreSQL + PostGIS?
    path('health/', HealthView.as_view(), name='health'),
    # Django's built-in admin site (uses Django's own superuser accounts,
    # created with `manage.py createsuperuser`; separate from portal users).
    path('admin/', admin.site.urls),
]

if settings.DEBUG:
    # Development-only page listing the emails the portal "sent"
    # (roadguard/email_backends.py). Never routed in production.
    api_routes.append(path('dev/outbox/', dev_outbox, name='dev-outbox'))

urlpatterns = [path(settings.API_PREFIX, include(api_routes))]
