"""Tests for the mobile-app endpoints: accounts, photo + report upload, hazards,
places, routes and sensor-data sharing.

Run with:  python manage.py test mobile

External services (Photon, OSRM) are replaced with fixed fake replies, so the
tests need no internet connection.
"""

import io
import json
import uuid
from datetime import timedelta
from unittest import mock

from django.core.cache import cache
from django.core.files.uploadedfile import SimpleUploadedFile
from django.test import TestCase, override_settings
from django.utils import timezone
from PIL import Image
from rest_framework.test import APIClient

from roadguard.models import Defect, ReportSource, ReportStatus
from telemetry.models import SensorReading, TelemetryBatch

from .external import ExternalServiceError
from .models import Traveler, TravelerSession


def png_bytes(size=(64, 48)):
    """A small real PNG image."""
    buffer = io.BytesIO()
    Image.new('RGB', size, (200, 60, 40)).save(buffer, format='PNG')
    return buffer.getvalue()


def graphql(client, path, query, variables=None, **headers):
    return client.post(path, {'query': query, 'variables': variables or {}}, format='json', **headers)


SUBMIT = '''mutation Submit($input: AnonymousReportInput!) {
  submitAnonymousReport(input:$input) { id clientId status receivedAt } }'''
HAZARDS = '''query Hazards($bbox:BboxInput!) {
  publicHazards(bbox:$bbox,first:100) { id category severity latitude longitude confirmedAt updatedAt verification deviceCount } }'''
DAR_BBOX = {'west': 39.1, 'south': -6.9, 'east': 39.3, 'north': -6.7}


# Fast password hashing + no reverse-geocoding calls during tests.
@override_settings(PASSWORD_HASHERS=['django.contrib.auth.hashers.MD5PasswordHasher'],
                   ROADGUARD_REVERSE_GEOCODE=False)
class MobileTestCase(TestCase):
    def setUp(self):
        cache.clear()  # rate-limit counters live in the cache
        self.client = APIClient()

    def register(self, email='driver@example.com', password='a-long-passphrase-42'):
        res = self.client.post('/api/v1/mobile/auth/register/',
                               {'name': 'Driver One', 'email': email, 'password': password}, format='json')
        self.assertEqual(res.status_code, 201, res.content)
        return res.json()

    def upload_photo(self):
        res = self.client.post('/api/v1/anonymous/report-photos/',
                               {'photo': SimpleUploadedFile('p.png', png_bytes(), content_type='image/png')},
                               format='multipart')
        self.assertEqual(res.status_code, 201, res.content)
        return res.json()['photoToken']

    def report_input(self, token, lat=-6.7924, lng=39.2083, client_id=None):
        now = timezone.now()
        return {'clientId': client_id or str(uuid.uuid4()), 'category': 'POTHOLE', 'notes': 'deep hole',
                'latitude': lat, 'longitude': lng, 'speedMps': 0, 'accuracyMeters': 8,
                'observedAt': (now - timedelta(seconds=2)).isoformat(), 'recordedAt': now.isoformat(),
                'isDemo': False, 'isMocked': False, 'photoToken': token}


class TravelerAccountTests(MobileTestCase):

    def test_register_session_logout(self):
        body = self.register()
        self.assertEqual(body['user']['email'], 'driver@example.com')
        self.assertEqual(len(body['token']), 43)
        # Only the token's hash is stored.
        self.assertFalse(TravelerSession.objects.filter(token_hash=body['token']).exists())

        auth = {'HTTP_AUTHORIZATION': f'Bearer {body["token"]}'}
        self.assertEqual(self.client.get('/api/v1/mobile/auth/session/', **auth).json()['user']['name'], 'Driver One')
        self.assertEqual(self.client.post('/api/v1/mobile/auth/logout/', {}, format='json', **auth).json(), {'ok': True})
        res = self.client.get('/api/v1/mobile/auth/session/', **auth)
        self.assertEqual(res.status_code, 401)
        self.assertIn('error', res.json())  # the shape the app reads

    def test_login_and_wrong_password(self):
        self.register()
        ok = self.client.post('/api/v1/mobile/auth/login/',
                              {'email': 'DRIVER@example.com', 'password': 'a-long-passphrase-42'}, format='json')
        self.assertEqual(ok.status_code, 200)
        bad = self.client.post('/api/v1/mobile/auth/login/',
                               {'email': 'driver@example.com', 'password': 'nope-nope-nope'}, format='json')
        self.assertEqual((bad.status_code, bad.json()), (401, {'error': 'Email or password is incorrect.'}))

    def test_duplicate_email_and_weak_password(self):
        self.register()
        dup = self.client.post('/api/v1/mobile/auth/register/',
                               {'name': 'X', 'email': 'Driver@Example.com', 'password': 'another-long-pass-9'},
                               format='json')
        self.assertEqual(dup.status_code, 409)
        weak = self.client.post('/api/v1/mobile/auth/register/',
                                {'name': 'Y', 'email': 'y@example.com', 'password': 'short'}, format='json')
        self.assertEqual(weak.status_code, 400)
        self.assertEqual(Traveler.objects.count(), 1)

    def test_sign_in_must_not_carry_existing_credentials(self):
        res = self.client.post('/api/v1/mobile/auth/login/', {'email': 'a@b.co', 'password': 'x'}, format='json',
                               HTTP_AUTHORIZATION='Bearer ' + 'a' * 43)
        self.assertEqual(res.status_code, 403)


class ReportTests(MobileTestCase):

    def test_photo_is_reencoded_without_metadata(self):
        self.upload_photo()
        from roadguard.models import ReportPhoto
        stored = Image.open(io.BytesIO(bytes(ReportPhoto.objects.get().content)))
        self.assertEqual(stored.format, 'JPEG')
        self.assertFalse(stored.getexif())

    def test_non_image_is_rejected(self):
        res = self.client.post('/api/v1/anonymous/report-photos/',
                               {'photo': SimpleUploadedFile('x.png', b'not an image')}, format='multipart')
        self.assertEqual(res.status_code, 400)

    def test_submit_creates_new_manual_defect_and_retry_is_idempotent(self):
        report = self.report_input(self.upload_photo())
        res = graphql(self.client, '/api/v1/graphql/anonymous/', SUBMIT, {'input': report})
        ack = res.json()['data']['submitAnonymousReport']
        uuid.UUID(ack['id'])  # the app requires a UUID here
        self.assertEqual((ack['clientId'], ack['status']), (report['clientId'], 'NEW'))

        defect = Defect.objects.get()
        self.assertEqual((defect.source, defect.status, defect.has_photo), (ReportSource.MANUAL, ReportStatus.NEW, True))
        self.assertEqual(defect.notes, 'deep hole')

        again = graphql(self.client, '/api/v1/graphql/anonymous/', SUBMIT, {'input': report}).json()
        self.assertEqual(again['data']['submitAnonymousReport']['id'], ack['id'])
        self.assertEqual(Defect.objects.count(), 1)

    def test_moving_or_demo_reports_are_rejected(self):
        for speed in (0.6, 12):  # above the 0.5 m/s standing-still limit
            report = dict(self.report_input(self.upload_photo()), speedMps=speed)
            res = graphql(self.client, '/api/v1/graphql/anonymous/', SUBMIT, {'input': report}).json()
            self.assertIn('Stop safely before reporting', res['errors'][0]['message'])
        report = dict(self.report_input(self.upload_photo()), isDemo=True)
        res = graphql(self.client, '/api/v1/graphql/anonymous/', SUBMIT, {'input': report}).json()
        self.assertIn('Demo or mocked', res['errors'][0]['message'])
        self.assertFalse(Defect.objects.exists())

    def test_gps_rules_match_the_app(self):
        # Small speed drift while standing still is accepted (the app allows ≤ 0.5 m/s)...
        report = dict(self.report_input(self.upload_photo()), speedMps=0.3)
        res = graphql(self.client, '/api/v1/graphql/anonymous/', SUBMIT, {'input': report}).json()
        self.assertEqual(res['data']['submitAnonymousReport']['status'], 'NEW')
        # ...but a position less accurate than 25 m is not (the app blocks it too).
        report = dict(self.report_input(self.upload_photo()), accuracyMeters=26)
        res = graphql(self.client, '/api/v1/graphql/anonymous/', SUBMIT, {'input': report}).json()
        self.assertIn('at most 25 metres', res['errors'][0]['message'])
        self.assertEqual(Defect.objects.count(), 1)

    def test_crack_reports_are_rejected(self):
        report = dict(self.report_input(self.upload_photo()), category='CRACK')
        res = graphql(self.client, '/api/v1/graphql/anonymous/', SUBMIT, {'input': report}).json()
        self.assertIsNone(res['data'])
        self.assertIn('Only potholes can be reported', res['errors'][0]['message'])
        self.assertFalse(Defect.objects.exists())

    def test_expired_photo_token_message_matches_the_app(self):
        token = self.upload_photo()
        from roadguard.models import ReportPhoto
        ReportPhoto.objects.update(expires_at=timezone.now() - timedelta(seconds=1))
        res = graphql(self.client, '/api/v1/graphql/anonymous/', SUBMIT, {'input': self.report_input(token)}).json()
        # road_api.dart checks for exactly this text before re-uploading the photo.
        self.assertIn('Photo token has expired.', res['errors'][0]['message'])

    def test_anonymous_endpoints_refuse_credentials(self):
        res = graphql(self.client, '/api/v1/graphql/anonymous/', HAZARDS, {'bbox': DAR_BBOX},
                      HTTP_AUTHORIZATION='Bearer ' + 'a' * 43)
        self.assertEqual(res.status_code, 403)

    def test_introspection_is_disabled(self):
        res = graphql(self.client, '/api/v1/graphql/anonymous/', '{ __schema { types { name } } }')
        self.assertEqual(res.status_code, 400)


class HazardTests(MobileTestCase):

    def make_defect(self, **fields):
        values = dict(road='Morogoro Road', region='Dar es Salaam', severity='high', source='manual',
                      detected_at=timezone.now(), lat=-6.79, lng=39.21)
        values.update(fields)
        return Defect.objects.create(**values)

    def hazards(self, bbox=DAR_BBOX):
        return graphql(self.client, '/api/v1/graphql/anonymous/', HAZARDS, {'bbox': bbox}).json()['data']['publicHazards']

    def test_only_confirmed_or_crowd_published_defects_are_public(self):
        self.make_defect(status=ReportStatus.NEW)                          # unreviewed report: hidden
        verified = self.make_defect(status=ReportStatus.VERIFIED, reviewed_at=timezone.now())
        self.make_defect(status=ReportStatus.RESOLVED)                     # fixed: hidden
        crowd = self.make_defect(status=ReportStatus.NEW, source='device', device_count=3,
                                 published_at=timezone.now(), last_detected_at=timezone.now())
        self.make_defect(status=ReportStatus.VERIFIED, lat=-3.38, lng=36.68)  # outside the map area

        hazards = {h['id']: h for h in self.hazards()}
        self.assertEqual(set(hazards), {verified.pk, crowd.pk})
        self.assertEqual(hazards[verified.pk]['verification'], 'CONFIRMED')
        self.assertEqual(hazards[verified.pk]['category'], 'POTHOLE')
        self.assertEqual(hazards[verified.pk]['severity'], 'HIGH')
        self.assertEqual(hazards[crowd.pk]['verification'], 'CROWD_REPORTED')

    def test_stale_and_simulated_crowd_spots_are_hidden(self):
        old = timezone.now() - timedelta(days=60)
        self.make_defect(status=ReportStatus.NEW, source='device', device_count=3,
                         published_at=old, last_detected_at=old)
        self.make_defect(status=ReportStatus.NEW, source='device', device_count=3, is_simulated=True,
                         published_at=timezone.now(), last_detected_at=timezone.now())
        self.assertEqual(self.hazards(), [])
        with self.settings(ROADGUARD_PUBLISH_SIMULATED=True):
            self.assertEqual(len(self.hazards()), 1)

    def test_oversized_map_area_is_rejected(self):
        res = graphql(self.client, '/api/v1/graphql/anonymous/', HAZARDS,
                      {'bbox': {'west': 30, 'south': -10, 'east': 40, 'north': 0}}).json()
        self.assertIn('at most 5 degrees', res['errors'][0]['message'])


FAKE_OSRM = {
    'code': 'Ok',
    'routes': [{
        'distance': 1200.0, 'duration': 180.0,
        'geometry': {'type': 'LineString', 'coordinates': [[39.20, -6.79], [39.205, -6.792], [39.21, -6.795]]},
        'legs': [{'steps': [
            {'distance': 500, 'duration': 60, 'name': 'Morogoro Road',
             'maneuver': {'type': 'depart', 'bearing_after': 90, 'location': [39.20, -6.79]}},
            {'distance': 700, 'duration': 120, 'name': 'Bibi Titi Street',
             'maneuver': {'type': 'turn', 'modifier': 'left', 'location': [39.205, -6.792]}},
            {'distance': 0, 'duration': 0, 'name': '',
             'maneuver': {'type': 'arrive', 'modifier': 'right', 'location': [39.21, -6.795]}},
        ]}],
    }],
}


class PlacesAndRoutesTests(MobileTestCase):
    ROUTES = '''query R($o:CoordinateInput!,$d:CoordinateInput!) {
      drivingRoutes(origin:$o,destination:$d) { id distanceMeters durationSeconds coordinatesJson stepsJson provider } }'''

    @mock.patch('mobile.routing.get_json', return_value=FAKE_OSRM)
    def test_routes_include_turn_by_turn_steps(self, _fake):
        res = graphql(self.client, '/api/v1/graphql/anonymous/', self.ROUTES, {
            'o': {'latitude': -6.79, 'longitude': 39.20}, 'd': {'latitude': -6.795, 'longitude': 39.21}}).json()
        route = res['data']['drivingRoutes'][0]
        steps = json.loads(route['stepsJson'])
        self.assertEqual([s['instruction'] for s in steps], [
            'Head east on Morogoro Road',
            'Turn left onto Bibi Titi Street',
            'You have arrived at your destination on the right',
        ])
        # Where each manoeuvre happens along the route.
        self.assertEqual([s['alongMeters'] for s in steps], [0, 500, 1200])
        self.assertEqual(len(json.loads(route['coordinatesJson'])), 3)

    @mock.patch('mobile.routing.get_json', side_effect=ExternalServiceError('down'))
    def test_routing_failure_never_invents_a_route(self, _fake):
        res = graphql(self.client, '/api/v1/graphql/anonymous/', self.ROUTES, {
            'o': {'latitude': -6.79, 'longitude': 39.20}, 'd': {'latitude': -6.795, 'longitude': 39.21}}).json()
        self.assertIsNone(res['data'])
        self.assertIn('no sample route was substituted', res['errors'][0]['message'])

    @mock.patch('mobile.places.get_json', return_value={'features': [{
        'geometry': {'type': 'Point', 'coordinates': [39.28, -6.81]},
        'properties': {'name': 'Kariakoo Market', 'city': 'Dar es Salaam', 'country': 'Tanzania'}}]})
    def test_place_search(self, _fake):
        res = graphql(self.client, '/api/v1/graphql/anonymous/',
                      'query P($q:String!) { searchPlaces(query:$q) { label latitude longitude } }',
                      {'q': 'Kariakoo'}).json()
        self.assertEqual(res['data']['searchPlaces'][0]['label'], 'Kariakoo Market, Dar es Salaam, Tanzania')


class RouteTimingTests(MobileTestCase):
    """Long routes on a slow connection must still answer within the app's 20 s limit."""
    ROUTES = PlacesAndRoutesTests.ROUTES
    TRIP = {'o': {'latitude': -6.79, 'longitude': 39.20}, 'd': {'latitude': -6.795, 'longitude': 39.21}}

    def test_polyline6_decoding(self):
        from .routing import decode_polyline
        # Google's documented example (precision 5): (38.5,-120.2), (40.7,-120.95), (43.252,-126.453)
        self.assertEqual(decode_polyline('_p~iF~ps|U_ulLnnqC_mqNvxq`@', precision=5),
                         [[-120.2, 38.5], [-120.95, 40.7], [-126.453, 43.252]])

    @mock.patch('mobile.routing.STEPS_BUDGET_SECONDS', 0.5)
    @mock.patch('mobile.routing.QUICK_DELAY_SECONDS', 0.1)
    def test_slow_turn_by_turn_answer_falls_back_to_the_quick_route(self):
        import time as _time
        without_steps = json.loads(json.dumps(FAKE_OSRM))
        for route in without_steps['routes']:
            route['legs'] = [{'steps': []}]

        def fake_get_json(url, **_kwargs):
            if 'steps=true' in url:
                _time.sleep(3)  # the detailed answer is still downloading...
                return FAKE_OSRM
            return without_steps  # ...but the quick one is back

        with mock.patch('mobile.routing.get_json', side_effect=fake_get_json):
            started = _time.monotonic()
            res = graphql(self.client, '/api/v1/graphql/anonymous/', self.ROUTES, self.TRIP).json()
            elapsed = _time.monotonic() - started
        route = res['data']['drivingRoutes'][0]
        self.assertEqual(json.loads(route['stepsJson']), [])   # no turn-by-turn this time
        self.assertEqual(route['distanceMeters'], 1200.0)       # but a real route
        self.assertLess(elapsed, 2.5)

    @mock.patch('mobile.routing.get_json', return_value=FAKE_OSRM)
    def test_steps_are_used_when_they_arrive_in_time(self, fake):
        res = graphql(self.client, '/api/v1/graphql/anonymous/', self.ROUTES, self.TRIP).json()
        self.assertEqual(len(json.loads(res['data']['drivingRoutes'][0]['stepsJson'])), 3)
        self.assertEqual(fake.call_count, 1)  # answered quickly: no second request
        self.assertIn('geometries=polyline6', fake.call_args.args[0])

    @mock.patch('mobile.routing.STEPS_BUDGET_SECONDS', 0.3)
    @mock.patch('mobile.routing.QUICK_DELAY_SECONDS', 0.1)
    def test_late_detailed_route_is_kept_for_the_retry(self):
        import time as _time
        calls = []

        def fake_get_json(url, **_kwargs):
            calls.append(url)
            if 'steps=true' in url:
                _time.sleep(1)  # too late for the first request...
                return FAKE_OSRM
            raise ExternalServiceError('slow link')  # ...and the quick one fails

        with mock.patch('mobile.routing.get_json', side_effect=fake_get_json):
            first = graphql(self.client, '/api/v1/graphql/anonymous/', self.ROUTES, self.TRIP).json()
            self.assertIn('errors', first)      # the driver sees "unavailable"
            _time.sleep(1.2)                    # the detailed reply lands in the background
            calls.clear()
            retry = graphql(self.client, '/api/v1/graphql/anonymous/', self.ROUTES, self.TRIP).json()
        # The retry is answered from the cache, with turn-by-turn steps, no new request.
        self.assertEqual(len(json.loads(retry['data']['drivingRoutes'][0]['stepsJson'])), 3)
        self.assertEqual(calls, [])


class RoadNameTests(MobileTestCase):
    """New defects get the nearest road's name and the Tanzanian region (Photon reverse lookup)."""

    @override_settings(ROADGUARD_REVERSE_GEOCODE=True)
    @mock.patch('mobile.places.get_json', return_value={'features': [{'properties': {
        'name': 'Morogoro Road', 'street': 'Bibi Titi Mohamed Road', 'osm_key': 'highway',
        'city': 'Dar es Salaam', 'state': 'Coastal Zone'}}]})
    def test_road_and_region(self, fake):
        from .places import road_and_region
        self.assertEqual(road_and_region(-6.8161, 39.2804), ('Morogoro Road', 'Dar es Salaam'))
        # Only roads are asked for, not the nearest building or city.
        self.assertIn('osm_tag=highway', fake.call_args.args[0])

    @override_settings(ROADGUARD_REVERSE_GEOCODE=True)
    @mock.patch('mobile.places.get_json', side_effect=ExternalServiceError('down'))
    def test_lookup_failure_uses_placeholders(self, _fake):
        from .places import UNKNOWN_REGION, UNKNOWN_ROAD, road_and_region
        self.assertEqual(road_and_region(-6.8, 39.2), (UNKNOWN_ROAD, UNKNOWN_REGION))


# Pinned so the test doesn't depend on the local .env (which may switch the real model on).
@override_settings(ROADGUARD_AI_ENGINE='detection.engine.NullEngine', ROADGUARD_AI_PROCESS_INLINE=False)
class SensorSharingTests(MobileTestCase):
    GRANT = 'mutation C($t:ID!) { grantCollectionConsent(tripId:$t,version:2,accepted:true) { id } }'
    UPLOAD = 'mutation U($i:TelemetryInput!) { uploadTelemetry(input:$i) { id accepted receivedAt } }'

    def events(self, count=4):
        now = timezone.now()
        gps = {'latitude': -6.79, 'longitude': 39.21, 'speedMps': 11.0, 'accuracyMeters': 6.0,
               'observedAt': (now - timedelta(seconds=1)).isoformat(), 'isMocked': False}
        # Notice v2 apps send the raw accelerometer ("acceleration", gravity included).
        return [{'kind': 'acceleration' if i % 2 == 0 else 'angular_velocity',
                 'at': now.isoformat(), 'x': 0.1 * i, 'y': -0.2, 'z': 9.0 if i == 2 else 0.3, 'gps': gps}
                for i in range(count)]

    def test_requires_a_signed_in_traveller(self):
        res = graphql(self.client, '/api/v1/graphql/mobile/', 'query { collectionNoticeVersion }')
        self.assertEqual(res.status_code, 401)

    def test_consent_upload_retry_and_withdraw(self):
        auth = {'HTTP_AUTHORIZATION': f'Bearer {self.register()["token"]}'}
        trip = str(uuid.uuid4())
        consent = graphql(self.client, '/api/v1/graphql/mobile/', self.GRANT, {'t': trip}, **auth).json()
        consent_id = consent['data']['grantCollectionConsent']['id']

        batch = {'id': str(uuid.uuid4()), 'consentId': consent_id, 'tripId': trip,
                 'eventsJson': json.dumps(self.events())}
        ack = graphql(self.client, '/api/v1/graphql/mobile/', self.UPLOAD, {'i': batch}, **auth).json()
        self.assertTrue(ack['data']['uploadTelemetry']['accepted'])
        self.assertEqual(SensorReading.objects.count(), 4)
        # New batches wait for the AI engine.
        self.assertEqual(TelemetryBatch.objects.get().ai_status, 'pending')

        # An identical retry is acknowledged again without storing twice.
        graphql(self.client, '/api/v1/graphql/mobile/', self.UPLOAD, {'i': batch}, **auth)
        self.assertEqual(SensorReading.objects.count(), 4)

        # After withdrawing consent, uploads are refused.
        graphql(self.client, '/api/v1/graphql/mobile/', 'mutation { revokeMyCollectionConsents }', **auth)
        batch2 = dict(batch, id=str(uuid.uuid4()))
        res = graphql(self.client, '/api/v1/graphql/mobile/', self.UPLOAD, {'i': batch2}, **auth).json()
        self.assertIn('withdrawn', res['errors'][0]['message'])

    @override_settings(ROADGUARD_AI_ENGINE='ai_engine.sensor_model.PotholeEngine',
                       ROADGUARD_AI_PROCESS_INLINE=True, ROADGUARD_AI_MODEL_SHA256='0' * 64)
    def test_upload_succeeds_even_if_the_model_cannot_load(self):
        # A wrong checksum makes the model refuse to load: the upload must still
        # be acknowledged, and the batch waits for a later analysis run.
        auth = {'HTTP_AUTHORIZATION': f'Bearer {self.register()["token"]}'}
        trip = str(uuid.uuid4())
        consent_id = graphql(self.client, '/api/v1/graphql/mobile/', self.GRANT, {'t': trip}, **auth).json()[
            'data']['grantCollectionConsent']['id']
        batch = {'id': str(uuid.uuid4()), 'consentId': consent_id, 'tripId': trip,
                 'eventsJson': json.dumps(self.events())}
        with self.assertLogs('telemetry.services', level='ERROR'):
            ack = graphql(self.client, '/api/v1/graphql/mobile/', self.UPLOAD, {'i': batch}, **auth).json()
        self.assertTrue(ack['data']['uploadTelemetry']['accepted'])
        self.assertEqual(TelemetryBatch.objects.get().ai_status, 'pending')

    def test_the_old_notice_must_be_accepted_again(self):
        # Version 1 didn't mention the raw accelerometer, so it's no longer enough.
        auth = {'HTTP_AUTHORIZATION': f'Bearer {self.register()["token"]}'}
        old = self.GRANT.replace('version:2', 'version:1')
        res = graphql(self.client, '/api/v1/graphql/mobile/', old, {'t': str(uuid.uuid4())}, **auth).json()
        self.assertIn('current collection notice', res['errors'][0]['message'])
        version = graphql(self.client, '/api/v1/graphql/mobile/', 'query { collectionNoticeVersion }', **auth).json()
        self.assertEqual(version['data']['collectionNoticeVersion'], 2)

    def test_mocked_gps_is_rejected(self):
        auth = {'HTTP_AUTHORIZATION': f'Bearer {self.register()["token"]}'}
        trip = str(uuid.uuid4())
        consent_id = graphql(self.client, '/api/v1/graphql/mobile/', self.GRANT, {'t': trip}, **auth).json()[
            'data']['grantCollectionConsent']['id']
        events = self.events()
        events[0]['gps'] = dict(events[0]['gps'], isMocked=True)
        res = graphql(self.client, '/api/v1/graphql/mobile/', self.UPLOAD, {'i': {
            'id': str(uuid.uuid4()), 'consentId': consent_id, 'tripId': trip,
            'eventsJson': json.dumps(events)}}, **auth).json()
        self.assertIn('mocked', res['errors'][0]['message'])
        self.assertFalse(SensorReading.objects.exists())


class SharedLimitWaitTests(TestCase):
    """The 1-request/second limit for the free map services waits, not fails."""

    def setUp(self):
        cache.clear()

    def test_second_request_waits_for_the_next_window(self):
        from time import monotonic
        from . import ratelimit
        # First request takes the slot at once.
        self.assertTrue(ratelimit.wait_for_slot('t', 'x', limit=1, window_seconds=1, max_wait_seconds=1.5))
        started = monotonic()
        # Second one, straight after, is let through once the window ends.
        self.assertTrue(ratelimit.wait_for_slot('t', 'x', limit=1, window_seconds=1, max_wait_seconds=1.5))
        self.assertGreater(monotonic() - started, 0.1)

    def test_gives_up_after_max_wait(self):
        from . import ratelimit
        self.assertTrue(ratelimit.wait_for_slot('t', 'y', limit=1, window_seconds=5, max_wait_seconds=0.3))
        self.assertFalse(ratelimit.wait_for_slot('t', 'y', limit=1, window_seconds=5, max_wait_seconds=0.3))


class GzipReplyTests(TestCase):
    """External replies arrive gzip-compressed; decompression is size-capped."""

    def test_normal_reply_is_decompressed(self):
        import gzip
        from .external import _gunzip
        body = json.dumps({'code': 'Ok'}).encode()
        self.assertEqual(_gunzip(gzip.compress(body), 1000), body)

    def test_zip_bomb_is_refused(self):
        import gzip
        from .external import _gunzip
        bomb = gzip.compress(b'0' * 5_000_000)  # ~5 KB compressed, 5 MB unpacked
        with self.assertRaises(ExternalServiceError):
            _gunzip(bomb, 1_000_000)

    def test_corrupt_gzip_is_refused(self):
        from .external import _gunzip
        with self.assertRaises(ExternalServiceError):
            _gunzip(b'not gzip at all', 1000)
