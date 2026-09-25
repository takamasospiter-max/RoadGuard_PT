"""Tests for the AI engine socket and crowd sensing (grouping detections into spots).

Run with:  python manage.py test detection
"""

import io
import uuid
from datetime import timedelta

from django.core.management import call_command
from django.test import TestCase, override_settings
from django.utils import timezone
from rest_framework.test import APIClient

from mobile.models import Traveler
from roadguard.models import AuditLog, Defect, ReportSource, ReportStatus, Severity
from telemetry.models import CollectionConsent, SensorReading, TelemetryBatch

from . import pipeline, spots
from .engine import DetectionEngine, DetectionResult
from .models import Detection

SPOT = (-6.7924, 39.2083)   # a point on Morogoro Road, Dar es Salaam
METRE = 1 / 111_320           # roughly one metre in degrees near the equator


def detection(device, lat=SPOT[0], lng=SPOT[1], confidence=0.8, intensity=0.6, **extra):
    """Create a detection from `device` and group it."""
    d = Detection.objects.create(device_key=device, detected_at=timezone.now(), lat=lat, lng=lng,
                                 confidence=confidence, intensity=intensity, model_version='test', **extra)
    return spots.assign(d)


@override_settings(ROADGUARD_REVERSE_GEOCODE=False, SPOT_RADIUS_M=15, SPOT_MIN_CONFIDENCE=0.5,
                   SPOT_MIN_DEVICES_TO_TRACK=2, SPOT_MIN_DEVICES_TO_PUBLISH=3)
class SpotTests(TestCase):

    def test_spot_is_created_then_published_as_more_phones_agree(self):
        self.assertIsNone(detection('phone-a'))                       # 1 phone: waits
        spot = detection('phone-b', lat=SPOT[0] + 5 * METRE)            # 2 phones, 5 m apart: tracked
        self.assertIsNotNone(spot)
        self.assertEqual((spot.source, spot.status, spot.device_count), (ReportSource.DEVICE, ReportStatus.NEW, 2))
        self.assertIsNone(spot.published_at)                           # not alerted yet

        spot = detection('phone-c', lng=SPOT[1] + 4 * METRE)            # 3 phones: alerted to drivers
        self.assertEqual(spot.device_count, 3)
        self.assertIsNotNone(spot.published_at)
        self.assertEqual(Defect.objects.count(), 1)
        actions = set(AuditLog.objects.values_list('action', flat=True))
        self.assertTrue({'defect.auto_created', 'defect.auto_published'} <= actions)

    def test_same_phone_twice_counts_once(self):
        detection('phone-a')
        self.assertIsNone(detection('phone-a'))  # still only one distinct device

    def test_far_apart_detections_are_different_spots(self):
        detection('phone-a')
        self.assertIsNone(detection('phone-b', lat=SPOT[0] + 40 * METRE))  # 40 m away: separate

    def test_low_confidence_detections_are_ignored(self):
        detection('phone-a')
        self.assertIsNone(detection('phone-b', confidence=0.3))

    def test_severity_and_confidence_combine_across_phones(self):
        detection('phone-a', confidence=0.8, intensity=0.9)
        spot = detection('phone-b', confidence=0.6, intensity=0.8)
        # Combined confidence: 1 − (1−0.8)(1−0.6) = 0.92 → 92 %.
        self.assertAlmostEqual(spot.confidence, 92.0)
        # Weighted severity: (0.8·0.9 + 0.6·0.8) / 1.4 ≈ 0.857 → high.
        self.assertAlmostEqual(spot.severity_score, (0.8 * 0.9 + 0.6 * 0.8) / 1.4)
        self.assertEqual(spot.severity, Severity.HIGH)

    def test_detections_corroborate_a_travellers_photo_report(self):
        report = Defect.objects.create(road='Morogoro Road', region='Dar es Salaam', severity='medium',
                                       source=ReportSource.MANUAL, detected_at=timezone.now(),
                                       lat=SPOT[0], lng=SPOT[1], has_photo=True)
        for phone in ('phone-a', 'phone-b', 'phone-c'):
            spot = detection(phone, lat=SPOT[0] + 3 * METRE, intensity=0.95)
        self.assertEqual(spot.pk, report.pk)
        report.refresh_from_db()
        self.assertEqual((report.device_count, report.observation_count), (3, 4))  # 3 detections + the report
        self.assertEqual(report.severity, 'medium')      # an officer's/reporter's values are kept
        self.assertIsNotNone(report.published_at)        # but it now alerts drivers

    def test_resolved_defect_is_not_reopened(self):
        Defect.objects.create(road='R', region='X', severity='low', source=ReportSource.DEVICE,
                              status=ReportStatus.RESOLVED, detected_at=timezone.now(),
                              lat=SPOT[0], lng=SPOT[1])
        detection('phone-a')
        spot = detection('phone-b')
        self.assertEqual(spot.status, ReportStatus.NEW)   # a new spot, not the resolved one
        self.assertEqual(Defect.objects.count(), 2)

    def test_simulate_command(self):
        call_command('simulate_detections', lat=SPOT[0], lng=SPOT[1], devices=3, stdout=io.StringIO())
        spot = Defect.objects.get()
        self.assertTrue(spot.is_simulated)
        self.assertEqual(spot.device_count, 3)


class FirstReadingEngine(DetectionEngine):
    """Test engine: 'finds' a pothole at the first reading with a big vertical jolt."""
    model_version = 'test-engine-1'

    def analyze(self, batch):
        return [DetectionResult(detected_at=r.recorded_at, latitude=r.lat, longitude=r.lng,
                                confidence=0.9, intensity=0.7)
                for r in batch.readings if r.kind == 'linear_acceleration' and abs(r.z) > 5][:1]


class BrokenEngine(DetectionEngine):
    model_version = 'broken'

    def analyze(self, batch):
        raise RuntimeError('model crashed')


def make_batch(traveler=None, z=9.0):
    """A consented, uploaded batch with two readings."""
    traveler = traveler or Traveler.objects.create(name='D', email=f'{uuid.uuid4().hex}@x.com', password_hash='x')
    consent = CollectionConsent.objects.create(traveler=traveler, trip_id=uuid.uuid4(),
                                               expires_at=timezone.now() + timedelta(hours=1))
    batch = TelemetryBatch.objects.create(id=uuid.uuid4(), consent=consent, trip_id=consent.trip_id,
                                          payload_digest='x')
    now = timezone.now()
    for kind, zz in (('linear_acceleration', z), ('angular_velocity', 0.1)):
        SensorReading.objects.create(batch=batch, kind=kind, recorded_at=now, x=0, y=0, z=zz,
                                     lat=SPOT[0], lng=SPOT[1], speed_mps=12, gps_accuracy_m=5,
                                     gps_observed_at=now - timedelta(seconds=1))
    return batch


@override_settings(ROADGUARD_REVERSE_GEOCODE=False)
class PipelineTests(TestCase):

    @override_settings(ROADGUARD_AI_ENGINE='detection.tests.FirstReadingEngine')
    def test_in_process_engine(self):
        batch = make_batch()
        self.assertEqual(pipeline.process_pending(), (1, 1))
        found = Detection.objects.get()
        self.assertEqual((found.batch_id, found.model_version), (batch.id, 'test-engine-1'))
        # The device is pseudonymous: a keyed hash, not the traveller's id.
        self.assertEqual(found.device_key, pipeline.device_key(batch.consent.traveler_id))
        self.assertNotIn(str(batch.consent.traveler_id), found.device_key)
        batch.refresh_from_db()
        self.assertEqual(batch.ai_status, 'done')

    @override_settings(ROADGUARD_AI_ENGINE='detection.tests.BrokenEngine')
    def test_engine_failure_marks_batch_failed(self):
        batch = make_batch()
        pipeline.process_pending()
        batch.refresh_from_db()
        self.assertEqual((batch.ai_status, batch.ai_error), ('failed', 'model crashed'))

    @override_settings(ROADGUARD_AI_ENGINE='detection.engine.NullEngine')
    def test_null_engine_processes_without_detections(self):
        make_batch()
        self.assertEqual(pipeline.process_pending(), (1, 0))


@override_settings(ROADGUARD_REVERSE_GEOCODE=False, ROADGUARD_AI_API_KEY='test-key-123')
class AIEngineAPITests(TestCase):

    def setUp(self):
        self.ai = APIClient(HTTP_AUTHORIZATION='Api-Key test-key-123')

    def test_wrong_or_missing_key_is_refused(self):
        self.assertEqual(APIClient().get('/api/v1/ai/status/').status_code, 401)
        self.assertEqual(APIClient(HTTP_AUTHORIZATION='Api-Key nope').get('/api/v1/ai/status/').status_code, 401)

    def test_claim_then_post_results(self):
        batch = make_batch()
        claimed = self.ai.post('/api/v1/ai/batches/claim/', {'limit': 5}, format='json').json()['batches']
        self.assertEqual(claimed[0]['batchId'], str(batch.id))
        self.assertEqual(len(claimed[0]['readings']), 2)
        # A claimed batch isn't handed out twice.
        self.assertEqual(self.ai.post('/api/v1/ai/batches/claim/', {}, format='json').json()['batches'], [])

        reading = claimed[0]['readings'][0]
        res = self.ai.post(f'/api/v1/ai/batches/{batch.id}/results/', {
            'modelVersion': 'team-model-0.1',
            'detections': [{'detectedAt': reading['recordedAt'], 'latitude': reading['latitude'],
                            'longitude': reading['longitude'], 'confidence': 0.88, 'severity': 'high'}],
        }, format='json')
        self.assertEqual(res.json()['saved'], 1)
        self.assertEqual(Detection.objects.get().model_version, 'team-model-0.1')

    def test_results_far_from_the_batch_are_rejected(self):
        batch = make_batch()
        self.ai.post('/api/v1/ai/batches/claim/', {}, format='json')
        res = self.ai.post(f'/api/v1/ai/batches/{batch.id}/results/', {
            'modelVersion': 'm', 'detections': [{'detectedAt': timezone.now().isoformat(),
                                                'latitude': -3.38, 'longitude': 36.68, 'confidence': 0.9}]},
            format='json')
        self.assertEqual(res.status_code, 400)
        self.assertFalse(Detection.objects.exists())

    def test_results_for_an_unclaimed_batch_conflict(self):
        batch = make_batch()
        res = self.ai.post(f'/api/v1/ai/batches/{batch.id}/results/', {'modelVersion': 'm'}, format='json')
        self.assertEqual(res.status_code, 409)

    def test_ai_disabled_without_key(self):
        with self.settings(ROADGUARD_AI_API_KEY=''):
            self.assertEqual(self.ai.get('/api/v1/ai/status/').status_code, 401)


@override_settings(ROADGUARD_REVERSE_GEOCODE=False, SPOT_MIN_DEVICES_TO_TRACK=2,
                   SPOT_MIN_DEVICES_TO_PUBLISH=3, SPOT_MIN_CONFIDENCE=0.5)
class PortalAIViewTests(TestCase):
    """What the portal shows about the AI engine and about each spot."""

    def setUp(self):
        from roadguard.tests import PortalTestCase, make_user
        from django.core.cache import cache
        cache.clear()
        self.client = APIClient()
        # Reuse the portal tests' two-step login (password + MFA code).
        PortalTestCase.log_in(self, make_user('officer@example.com'))

    def test_overview_needs_login(self):
        self.assertEqual(APIClient().get('/api/v1/ai-engine/').status_code, 401)

    @override_settings(ROADGUARD_AI_ENGINE='detection.tests.BrokenEngine')
    def test_overview_counts_batches_and_shows_the_last_error(self):
        make_batch()
        pipeline.process_pending()
        body = self.client.get('/api/v1/ai-engine/').json()
        self.assertEqual(body['engine'], 'BrokenEngine')
        self.assertEqual(body['modelVersion'], 'broken')
        self.assertFalse(body['isPlaceholder'])
        self.assertEqual(body['batches']['failed'], 1)
        self.assertEqual(body['lastError']['message'], 'model crashed')

    @override_settings(ROADGUARD_AI_ENGINE='detection.engine.NullEngine')
    def test_overview_flags_the_placeholder_engine(self):
        body = self.client.get('/api/v1/ai-engine/').json()
        self.assertTrue(body['isPlaceholder'])
        self.assertEqual(body['detections']['total'], 0)

    def test_shown_to_drivers_matches_the_apps_rule(self):
        from mobile.hazards import visible_to_drivers
        for device in ('a', 'b', 'c'):          # 3 phones: published to drivers
            detection(device)
        detection('d', lat=SPOT[0] + 0.01)     # 1 phone elsewhere: nothing
        Defect.objects.create(road='R', region='X', severity='low', status=ReportStatus.VERIFIED,
                              source=ReportSource.MANUAL, detected_at=timezone.now(), lat=-6.7, lng=39.2)
        Defect.objects.create(road='R', region='X', severity='low', status=ReportStatus.NEW,
                              source=ReportSource.MANUAL, detected_at=timezone.now(), lat=-6.71, lng=39.2)
        listed = {d['id']: d['shown_to_drivers'] for d in self.client.get('/api/v1/defects/').json()}
        expected = set(visible_to_drivers().values_list('pk', flat=True))
        self.assertEqual({pk for pk, shown in listed.items() if shown}, expected)
        self.assertEqual(len(expected), 2)     # the crowd spot + the verified report
