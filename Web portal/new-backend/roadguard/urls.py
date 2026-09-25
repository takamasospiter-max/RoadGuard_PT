"""API routes, all mounted under /api/v1/ by config/urls.py."""

from django.urls import path

from detection.views import AIEngineOverviewView, DefectDetectionsView

from . import auth_views, views

urlpatterns = [
    # --- Authentication (auth_views.py) ---
    path('auth/login/', auth_views.LoginView.as_view(), name='auth-login'),
    path('auth/verify-mfa/', auth_views.VerifyMfaView.as_view(), name='auth-verify-mfa'),
    path('auth/accept-invite/', auth_views.AcceptInviteView.as_view(), name='auth-accept-invite'),
    path('auth/me/', auth_views.MeView.as_view(), name='auth-me'),
    path('auth/logout/', auth_views.LogoutView.as_view(), name='auth-logout'),

    # --- Defects ---
    path('defects/', views.DefectListView.as_view(), name='defect-list'),
    path('defects/<str:pk>/', views.DefectDetailView.as_view(), name='defect-detail'),
    # The photo attached to a mobile-app report (JPEG).
    path('defects/<str:pk>/photo/', views.DefectPhotoView.as_view(), name='defect-photo'),
    # The sensor detections grouped into this spot (detection/views.py).
    path('defects/<str:pk>/detections/', DefectDetectionsView.as_view(), name='defect-detections'),

    # --- Authorities ---
    path('authorities/', views.AuthorityListView.as_view(), name='authority-list'),
    path('authorities/<str:pk>/', views.AuthorityDetailView.as_view(), name='authority-detail'),

    # --- Portal users ("invite/" is listed before "<pk>/" so it isn't read as a user id) ---
    path('users/', views.PortalUserListView.as_view(), name='user-list'),
    path('users/invite/', views.PortalUserInviteView.as_view(), name='user-invite'),
    path('users/<str:pk>/', views.PortalUserDetailView.as_view(), name='user-detail'),

    # --- AI engine at a glance (dashboard card; detection/views.py) ---
    path('ai-engine/', AIEngineOverviewView.as_view(), name='ai-engine-overview'),

    # --- Audit log (Admin only) ---
    path('audit-log/', views.AuditLogListView.as_view(), name='audit-log'),
]
