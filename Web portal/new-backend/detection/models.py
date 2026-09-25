"""Pothole detections produced by the AI engine.

One Detection = "the AI thinks this phone hit a pothole here, at this time,
with this confidence". Detections from many phones at the same spot are
grouped into one Defect by detection/spots.py; the Defect is what officers
see in the portal and what drivers get alerted about.
"""

import uuid

from django.db import models

from roadguard.models import Defect, HazardType, Severity
from telemetry.models import TelemetryBatch


class Detection(models.Model):
    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    # The sensor batch the AI analysed (empty for simulated test detections).
    batch = models.ForeignKey(TelemetryBatch, on_delete=models.SET_NULL, blank=True, null=True,
                              related_name='detections')
    trip_id = models.UUIDField(blank=True, null=True)
    # Pseudonymous id of the phone/account that produced it: a keyed hash, so
    # "how many different phones saw this spot" can be counted without
    # storing who they are. See pipeline.device_key().
    device_key = models.CharField(max_length=64, db_index=True)

    detected_at = models.DateTimeField(db_index=True)
    lat = models.FloatField()
    lng = models.FloatField()
    hazard_type = models.CharField(max_length=20, choices=HazardType.choices, default=HazardType.POTHOLE)
    # How sure the AI is that this is a pothole, 0–1.
    confidence = models.FloatField()
    # How hard the hit was, 0–1 (optional; the AI may give this and/or `severity`).
    intensity = models.FloatField(blank=True, null=True)
    severity = models.CharField(max_length=10, choices=Severity.choices, blank=True, null=True)
    model_version = models.CharField(max_length=60)
    is_simulated = models.BooleanField(default=False)

    # The spot (Defect) this detection was grouped into; empty until enough
    # phones agree (see settings.SPOT_MIN_DEVICES_TO_TRACK).
    defect = models.ForeignKey(Defect, on_delete=models.SET_NULL, blank=True, null=True,
                               related_name='detections')
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        db_table = 'detections'
        ordering = ['-detected_at']

    def __str__(self):
        return f'{self.hazard_type} {self.confidence:.2f} at ({self.lat:.5f}, {self.lng:.5f})'
