"""Mobile-app routes, mounted under the API prefix by config/urls.py
(e.g. /api/v1/mobile/auth/login/, /api/v1/graphql/anonymous/)."""

from django.urls import path

from . import views

urlpatterns = [
    # Traveller accounts
    path('mobile/auth/register/', views.RegisterView.as_view(), name='mobile-register'),
    path('mobile/auth/login/', views.LoginView.as_view(), name='mobile-login'),
    path('mobile/auth/session/', views.SessionView.as_view(), name='mobile-session'),
    path('mobile/auth/logout/', views.LogoutView.as_view(), name='mobile-logout'),

    # Anonymous pothole report photo (step 1 of reporting)
    path('anonymous/report-photos/', views.ReportPhotoView.as_view(), name='report-photo-upload'),

    # GraphQL
    path('graphql/anonymous/', views.AnonymousGraphQLView.as_view(), name='graphql-anonymous'),
    path('graphql/mobile/', views.MobileGraphQLView.as_view(), name='graphql-mobile'),
]
