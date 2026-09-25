"""Sensor data shared by signed-in drivers during a trip.

Flow (app: core/services/trip_collection.dart):
1. The driver agrees to the sharing notice → a CollectionConsent for that trip.
2. While driving, the phone uploads batches of up to 20 readings
   (accelerometer / gyroscope + the GPS fix at that moment) → TelemetryBatch
   with its SensorReading rows.
3. Each new batch waits with ai_status "pending" until the AI engine analyses
   it (see detection/ — the "AI engine socket").
"""

import uuid

from django.db import models

from mobile.models import Traveler


class CollectionConsent(models.Model):
    """A driver's explicit agreement to share sensor data for one trip.

    Lasts at most 24 hours and can be withdrawn at any time; uploads are
    refused once it has expired or been revoked.
    """
    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    traveler = models.ForeignKey(Traveler, on_delete=models.CASCADE, related_name='consents')
    trip_id = models.UUIDField()                  # the app's own trip id
    version = models.PositiveSmallIntegerField(default=1)  # version of the notice agreed to
    granted_at = models.DateTimeField(auto_now_add=True)
    expires_at = models.DateTimeField()
    revoked_at = models.DateTimeField(blank=True, null=True)

    class Meta:
        db_table = 'collection_consents'


class TelemetryBatch(models.Model):
    """One upload of up to 20 sensor readings."""

    class AIStatus(models.TextChoices):
        PENDING = 'pending'        # waiting for the AI engine
        PROCESSING = 'processing'  # claimed by the AI engine, results not back yet
        DONE = 'done'              # analysed (with or without detections)
        FAILED = 'failed'          # the engine reported an error for this batch

    # The app generates the id, so a retried upload is recognised as the same batch.
    id = models.UUIDField(primary_key=True)
    consent = models.ForeignKey(CollectionConsent, on_delete=models.PROTECT, related_name='batches')
    trip_id = models.UUIDField()
    payload_digest = models.CharField(max_length=64)  # fingerprint of the readings
    received_at = models.DateTimeField(auto_now_add=True)

    ai_status = models.CharField(max_length=12, choices=AIStatus.choices,
                                 default=AIStatus.PENDING, db_index=True)
    ai_claimed_at = models.DateTimeField(blank=True, null=True)
    ai_processed_at = models.DateTimeField(blank=True, null=True)
    ai_model_version = models.CharField(max_length=60, blank=True, default='')
    ai_error = models.CharField(max_length=500, blank=True, default='')

    class Meta:
        db_table = 'telemetry_batches'
        ordering = ['received_at']


class SensorReading(models.Model):
    """One accelerometer or gyroscope sample with the GPS fix taken at that time.

    kind "acceleration":        x/y/z in m/s², raw accelerometer (gravity included).
    kind "linear_acceleration": x/y/z in m/s² with gravity removed (older app versions).
    kind "angular_velocity":    x/y/z in rad/s (rotation rate).
    Axes are the phone's own axes (it can be mounted in any orientation).

    PostGIS: like defects, the table has a `location` geography column
    computed from lat/lng (added by migration 0002 with raw SQL).
    """
    batch = models.ForeignKey(TelemetryBatch, on_delete=models.CASCADE, related_name='readings')
    kind = models.CharField(max_length=24)
    recorded_at = models.DateTimeField(db_index=True)  # when the sensor sample was taken
    x = models.FloatField()
    y = models.FloatField()
    z = models.FloatField()
    lat = models.FloatField()
    lng = models.FloatField()
    speed_mps = models.FloatField()
    gps_accuracy_m = models.FloatField()
    gps_observed_at = models.DateTimeField()

    class Meta:
        db_table = 'sensor_readings'
        ordering = ['recorded_at', 'id']
