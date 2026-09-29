"""Tests for the photo model (ai_engine/photo_model.py) and how reports use it.

Run with:  python manage.py test ai_engine

Most tests replace the model with a fake reply, so they run without the
"ultralytics" package. RealPhotoModelTests runs the real YOLO file and is
skipped when ultralytics isn't installed.
"""

import importlib.util
import io
import tempfile
from pathlib import Path
from unittest import mock, skipUnless

from django.core.management import call_command
from django.test import SimpleTestCase, TestCase, override_settings
from django.utils import timezone
from PIL import Image

from mobile.tests import SUBMIT, MobileTestCase, graphql
from roadguard.models import Defect, ReportPhoto
from roadguard.serializers import DefectSerializer
from roadguard.tests import PortalTestCase, make_user

from .photo_model import PhotoCheck, PhotoModelError, check_report_photo, load_model

HAS_ULTRALYTICS = importlib.util.find_spec('ultralytics') is not None

# What the fake model "finds": one pothole in the middle of the photo.
FOUND = PhotoCheck(confidence=0.81, boxes=[[0.25, 0.4, 0.75, 0.9, 0.81]],
                   model_version='yolov8-pothole-320+test')


def jpeg_bytes(size=(64, 48)):
    """A small real JPEG image."""
    buffer = io.BytesIO()
    Image.new('RGB', size, (90, 90, 90)).save(buffer, format='JPEG')
    return buffer.getvalue()


class LoadModelTests(SimpleTestCase):

    def test_altered_file_is_refused_before_loading(self):
        # A .pt file is a pickle: a file that doesn't match the reviewed
        # checksum must never reach Ultralytics/torch.
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder) / 'model.pt'
            path.write_bytes(b'not the reviewed model')
            with self.assertRaisesMessage(PhotoModelError, 'does not match'):
                load_model(str(path), '0' * 64)

    def test_missing_file(self):
        with self.assertRaisesMessage(PhotoModelError, 'not found'):
            load_model('does/not/exist.pt', '0' * 64)


class CheckReportPhotoTests(TestCase):

    def setUp(self):
        self.photo = ReportPhoto.objects.create(token_hash='a' * 64, content=jpeg_bytes(), sha256='b' * 64,
                                                expires_at=timezone.now())

    def test_result_is_saved_on_the_photo(self):
        with mock.patch('ai_engine.photo_model.check_photo', return_value=FOUND):
            check_report_photo(self.photo)
        self.photo.refresh_from_db()
        self.assertEqual(self.photo.ai_pothole_confidence, 0.81)
        self.assertEqual(self.photo.ai_boxes, [[0.25, 0.4, 0.75, 0.9, 0.81]])
        self.assertEqual(self.photo.ai_model_version, 'yolov8-pothole-320+test')
        self.assertEqual(self.photo.ai_error, '')
        self.assertIsNotNone(self.photo.ai_checked_at)

    def test_failure_is_recorded_not_raised(self):
        with mock.patch('ai_engine.photo_model.check_photo', side_effect=PhotoModelError('no model')), \
                self.assertLogs('ai_engine.photo_model', 'ERROR'):
            self.assertIsNone(check_report_photo(self.photo))
        self.photo.refresh_from_db()
        self.assertEqual(self.photo.ai_error, 'no model')
        self.assertIsNotNone(self.photo.ai_checked_at)


class ReportPhotoCheckTests(MobileTestCase):
    """Submitting a report runs the check; failures never block the report."""

    def submit(self):
        report = self.report_input(self.upload_photo())
        res = graphql(self.client, '/api/v1/graphql/anonymous/', SUBMIT, {'input': report}).json()
        self.assertNotIn('errors', res)
        return Defect.objects.select_related('photo').get()

    @override_settings(ROADGUARD_PHOTO_CHECK=True)
    def test_submitted_report_photo_is_checked(self):
        with mock.patch('ai_engine.photo_model.check_photo', return_value=FOUND) as check:
            defect = self.submit()
        check.assert_called_once()
        self.assertEqual(defect.photo.ai_boxes, FOUND.boxes)

    @override_settings(ROADGUARD_PHOTO_CHECK=True)
    def test_report_is_accepted_when_the_check_fails(self):
        with mock.patch('ai_engine.photo_model.check_photo', side_effect=RuntimeError('boom')), \
                self.assertLogs('ai_engine.photo_model', 'ERROR'):
            defect = self.submit()
        self.assertEqual(defect.photo.ai_error, 'boom')

    @override_settings(ROADGUARD_PHOTO_CHECK=False)
    def test_switched_off_means_not_checked(self):
        with mock.patch('ai_engine.photo_model.check_photo') as check:
            defect = self.submit()
        check.assert_not_called()
        self.assertIsNone(defect.photo.ai_checked_at)

    @override_settings(ROADGUARD_PHOTO_CHECK=False)
    def test_command_checks_photos_submitted_while_switched_off(self):
        self.submit()
        with mock.patch('ai_engine.photo_model.check_photo', return_value=FOUND), \
                mock.patch('roadguard.management.commands.check_report_photos.load_model'):
            call_command('check_report_photos', stdout=io.StringIO())
        self.assertEqual(ReportPhoto.objects.get().ai_boxes, FOUND.boxes)


class PortalPhotoCheckTests(PortalTestCase):
    """What the portal receives in each defect's photo_check field."""

    def setUp(self):
        super().setUp()
        self.photo = ReportPhoto.objects.create(token_hash='a' * 64, content=jpeg_bytes(), sha256='b' * 64,
                                                expires_at=timezone.now())
        self.defect = Defect.objects.create(road='R', region='X', severity='medium', source='manual',
                                            detected_at=timezone.now(), lat=-6.8, lng=39.2,
                                            has_photo=True, photo=self.photo)

    def photo_check(self):
        return DefectSerializer(Defect.objects.get(pk=self.defect.pk)).data['photo_check']

    def test_unchecked_photo_is_null(self):
        self.assertIsNone(self.photo_check())

    def test_found_and_failed(self):
        with mock.patch('ai_engine.photo_model.check_photo', return_value=FOUND):
            check_report_photo(self.photo)
        data = self.photo_check()
        self.assertEqual((data['status'], data['confidence'], data['boxes']),
                         ('pothole_found', 0.81, FOUND.boxes))

        with mock.patch('ai_engine.photo_model.check_photo', side_effect=RuntimeError('secret detail')), \
                self.assertLogs('ai_engine.photo_model', 'ERROR'):
            check_report_photo(self.photo)
        # Officers are told it failed; the error text stays in the server log.
        self.assertEqual(set(self.photo_check()), {'status', 'checked_at'})

    def test_defect_list_includes_it(self):
        with mock.patch('ai_engine.photo_model.check_photo', return_value=FOUND):
            check_report_photo(self.photo)
        self.log_in(make_user('officer@example.com'))
        res = self.client.get('/api/v1/defects/')
        self.assertEqual(res.status_code, 200, res.content)
        self.assertEqual(res.json()[0]['photo_check']['status'], 'pothole_found')


@skipUnless(HAS_ULTRALYTICS, 'ultralytics is not installed')
class RealPhotoModelTests(SimpleTestCase):
    """Runs the AI team's real model file (ai_engine/models/yolo-best.pt)."""

    def test_model_loads_and_a_blank_photo_has_no_pothole(self):
        from .photo_model import check_photo
        check = check_photo(jpeg_bytes((640, 480)))
        self.assertTrue(check.model_version.startswith('yolov8-pothole-320+01a4ad3e'))
        self.assertFalse(check.pothole_found)
        self.assertEqual(check.confidence, 0.0)
