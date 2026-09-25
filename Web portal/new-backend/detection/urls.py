"""AI engine service routes, mounted at /api/v1/ai/ (see views.py for the protocol)."""

from django.urls import path

from . import views

urlpatterns = [
    path('batches/claim/', views.ClaimBatchesView.as_view(), name='ai-claim'),
    path('batches/<uuid:batch_id>/results/', views.BatchResultsView.as_view(), name='ai-results'),
    path('status/', views.AIStatusView.as_view(), name='ai-status'),
]
