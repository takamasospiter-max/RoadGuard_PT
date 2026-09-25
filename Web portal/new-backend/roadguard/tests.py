"""Automated tests for login + MFA, invitations, the audit log and review stamping.

Run with:  python manage.py test roadguard

Django creates a temporary, empty test database (test_roadguard_dev) for the
run and deletes it afterwards, so real data is never touched.
"""

from datetime import timedelta

import pyotp
from django.core import mail
from django.core.cache import cache
from django.test import TestCase, override_settings
from django.utils import timezone
from rest_framework.test import APIClient

from .models import AccountStatus, AdminSession, AuditLog, Defect, OutboxEmail, PortalUser, UserRole
from .security import MFA_CODE_INTERVAL_SECONDS, SESSION_COOKIE_NAME, hash_password


def make_user(email, role=UserRole.ADMIN, password='correct-horse', status=AccountStatus.ACTIVE):
    """Create a fully activated portal user (password + MFA secret)."""
    return PortalUser.objects.create(
        name=email.split('@')[0].title(), email=email, role=role, authority='TARURA',
        status=status, password_hash=hash_password(password), mfa_secret=pyotp.random_base32(),
    )


def current_code(user):
    """The code the user's authenticator app would show right now."""
    return pyotp.TOTP(user.mfa_secret, interval=MFA_CODE_INTERVAL_SECONDS).now()


# Real password hashing is deliberately slow (to resist guessing); a fast
# hasher keeps the test run short. Only affects tests.
@override_settings(PASSWORD_HASHERS=['django.contrib.auth.hashers.MD5PasswordHasher'])
class PortalTestCase(TestCase):
    """Shared helpers: a fresh API client, plus a log_in() that does both login steps."""

    def setUp(self):
        # The login rate limit is counted in the cache; clear it so each test starts fresh.
        cache.clear()
        self.client = APIClient()

    def log_in(self, user, password='correct-horse'):
        res = self.client.post('/api/v1/auth/login/', {'email': user.email, 'password': password},
                               format='json')
        self.assertEqual(res.status_code, 200, res.content)
        res = self.client.post('/api/v1/auth/verify-mfa/', {
            'pending_token': res.json()['pending_token'], 'code': current_code(user)}, format='json')
        self.assertEqual(res.status_code, 200, res.content)
        return res


class LoginTests(PortalTestCase):

    def test_api_requires_login(self):
        self.assertEqual(self.client.get('/api/v1/defects/').status_code, 401)
        self.assertEqual(self.client.get('/api/v1/auth/me/').status_code, 401)

    def test_full_login_me_logout(self):
        user = make_user('admin@example.com')
        res = self.log_in(user)

        # The session cookie is set, and JavaScript can't read it (httponly).
        cookie = res.cookies[SESSION_COOKIE_NAME]
        self.assertTrue(cookie['httponly'])
        self.assertEqual(res.json(), {'id': user.pk, 'name': user.name,
                                      'email': user.email, 'role': 'Admin'})

        # Logged in: /me and the data endpoints work.
        self.assertEqual(self.client.get('/api/v1/auth/me/').json()['email'], user.email)
        self.assertEqual(self.client.get('/api/v1/defects/').status_code, 200)

        # Logout deletes the session on the server...
        self.assertEqual(self.client.post('/api/v1/auth/logout/').status_code, 204)
        self.assertFalse(AdminSession.objects.exists())
        # ...so reusing the old cookie value no longer works.
        self.client.cookies[SESSION_COOKIE_NAME] = cookie.value
        self.assertEqual(self.client.get('/api/v1/auth/me/').status_code, 401)

        actions = list(AuditLog.objects.values_list('action', flat=True))
        self.assertIn('auth.login_succeeded', actions)
        self.assertIn('auth.logout', actions)

    def test_wrong_password_and_unknown_email_look_the_same(self):
        make_user('admin@example.com')
        wrong_pw = self.client.post('/api/v1/auth/login/', {'email': 'admin@example.com',
                                                         'password': 'nope'}, format='json')
        unknown = self.client.post('/api/v1/auth/login/', {'email': 'ghost@example.com',
                                                        'password': 'nope'}, format='json')
        self.assertEqual(wrong_pw.status_code, 401)
        self.assertEqual(wrong_pw.json(), unknown.json())
        self.assertEqual(AuditLog.objects.filter(action='auth.login_failed').count(), 2)

    def test_wrong_mfa_code_is_rejected_and_audited(self):
        user = make_user('admin@example.com')
        token = self.client.post('/api/v1/auth/login/', {'email': user.email, 'password': 'correct-horse'},
                                 format='json').json()['pending_token']
        res = self.client.post('/api/v1/auth/verify-mfa/', {'pending_token': token, 'code': '000000'},
                               format='json')
        self.assertEqual(res.status_code, 401)
        self.assertEqual(res.json()['detail'], 'Incorrect code')
        self.assertTrue(AuditLog.objects.filter(action='auth.mfa_failed').exists())

    def test_forged_pending_token_is_rejected(self):
        user = make_user('admin@example.com')
        res = self.client.post('/api/v1/auth/verify-mfa/', {'pending_token': user.pk,
                                                         'code': current_code(user)}, format='json')
        self.assertEqual(res.status_code, 401)

    def test_idle_session_expires(self):
        user = make_user('admin@example.com')
        self.log_in(user)
        # Pretend the last request was 31 minutes ago (the idle timeout is 30).
        AdminSession.objects.update(last_seen_at=timezone.now() - timedelta(minutes=31))
        self.assertEqual(self.client.get('/api/v1/auth/me/').status_code, 401)
        self.assertFalse(AdminSession.objects.exists())

    def test_deactivated_user_is_logged_out_and_cannot_log_in(self):
        user = make_user('officer@example.com', role=UserRole.TARURA_OFFICER)
        self.log_in(user)
        PortalUser.objects.filter(pk=user.pk).update(status=AccountStatus.INACTIVE)
        self.assertEqual(self.client.get('/api/v1/defects/').status_code, 401)

        res = self.client.post('/api/v1/auth/login/', {'email': user.email, 'password': 'correct-horse'},
                               format='json')
        self.assertEqual(res.status_code, 403)

    def test_stale_cookie_does_not_block_logging_in_again(self):
        user = make_user('admin@example.com')
        self.client.cookies[SESSION_COOKIE_NAME] = 'expired-or-made-up'
        self.log_in(user)  # asserts both steps return 200

    def test_login_is_rate_limited(self):
        for _ in range(10):
            self.client.post('/api/v1/auth/login/', {'email': 'x@example.com', 'password': 'x'},
                             format='json')
        res = self.client.post('/api/v1/auth/login/', {'email': 'x@example.com', 'password': 'x'},
                               format='json')
        self.assertEqual(res.status_code, 429)


class InviteTests(PortalTestCase):

    def test_officer_cannot_invite(self):
        self.log_in(make_user('officer@example.com', role=UserRole.TARURA_OFFICER))
        res = self.client.post('/api/v1/users/invite/', {
            'name': 'New', 'email': 'new@example.com', 'role': 'TARURA Officer', 'authority': 'TARURA',
        }, format='json')
        self.assertEqual(res.status_code, 403)

    def test_invite_email_activate_then_log_in(self):
        admin = make_user('admin@example.com')
        self.log_in(admin)

        # 1. The Admin invites someone.
        res = self.client.post('/api/v1/users/invite/', {
            'name': 'New Officer', 'email': 'new@example.com', 'role': 'TARURA Officer',
            'authority': 'TARURA',
        }, format='json')
        self.assertEqual(res.status_code, 201, res.content)
        self.assertEqual(res.json()['status'], 'Inactive')
        invited = PortalUser.objects.get(email='new@example.com')
        self.assertIsNone(invited.password_hash)
        self.assertTrue(AuditLog.objects.filter(action='user.invited', resource_id=invited.pk).exists())

        # 2. An email with an activation link is sent. (During tests Django
        #    collects sent mail in mail.outbox instead of using MAILERS.)
        self.assertEqual(len(mail.outbox), 1)
        email = mail.outbox[0]
        self.assertEqual(email.to, ['new@example.com'])
        self.assertIn('http://localhost:5173/activate?token=', email.body)
        token = email.body.split('activate?token=')[1].split()[0]

        # 3. The invitee (not logged in) opens the link and sets a password.
        invitee = APIClient()
        res = invitee.post('/api/v1/auth/accept-invite/', {'token': token, 'password': 'my-new-password'},
                           format='json')
        self.assertEqual(res.status_code, 200, res.content)
        body = res.json()
        self.assertTrue(body['qr_code_data_uri'].startswith('data:image/png;base64,'))
        invited.refresh_from_db()
        self.assertEqual(invited.status, AccountStatus.ACTIVE)
        self.assertEqual(invited.mfa_secret, body['mfa_setup_key'])

        # 4. The link can't be used a second time.
        again = invitee.post('/api/v1/auth/accept-invite/', {'token': token, 'password': 'another-password'},
                             format='json')
        self.assertEqual(again.status_code, 409)

        # 5. They can now log in with their own password + MFA.
        self.client = invitee
        self.log_in(invited, password='my-new-password')

    def test_invited_user_cannot_log_in_before_activating(self):
        admin = make_user('admin@example.com')
        self.log_in(admin)
        self.client.post('/api/v1/users/invite/', {'name': 'N', 'email': 'n@example.com',
                                                'role': 'Admin', 'authority': 'System'}, format='json')
        res = APIClient().post('/api/v1/auth/login/', {'email': 'n@example.com', 'password': ''},
                               format='json')
        self.assertIn(res.status_code, (400, 401))

    def test_bad_invite_token_and_short_password(self):
        res = self.client.post('/api/v1/auth/accept-invite/', {'token': 'garbage', 'password': 'long-enough'},
                               format='json')
        self.assertEqual(res.status_code, 401)
        res = self.client.post('/api/v1/auth/accept-invite/', {'token': 'garbage', 'password': 'short'},
                               format='json')
        self.assertEqual(res.status_code, 400)

    def test_duplicate_email_is_rejected(self):
        self.log_in(make_user('admin@example.com'))
        res = self.client.post('/api/v1/users/invite/', {'name': 'Dup', 'email': 'admin@example.com',
                                                      'role': 'Admin', 'authority': 'System'},
                               format='json')
        self.assertEqual(res.status_code, 400)
        self.assertIn('already exists', str(res.json()))

    def test_admin_cannot_lock_themselves_out(self):
        admin = make_user('admin@example.com')
        self.log_in(admin)
        res = self.client.patch(f'/api/v1/users/{admin.pk}/', {'status': 'Inactive'}, format='json')
        self.assertEqual(res.status_code, 400)
        self.assertEqual(res.json(), {'detail': "You can't deactivate your own account"})


class OutboxEmailBackendTests(TestCase):

    def test_backend_stores_emails_in_the_database(self):
        from .email_backends import OutboxEmailBackend
        message = mail.EmailMessage(subject='Hello', body='Body text', to=['a@example.com'])
        self.assertEqual(OutboxEmailBackend().send_messages([message]), 1)
        stored = OutboxEmail.objects.get()
        self.assertEqual((stored.to_email, stored.subject, stored.body),
                         ('a@example.com', 'Hello', 'Body text'))


class DefectReviewTests(PortalTestCase):

    def setUp(self):
        super().setUp()
        self.defect = Defect.objects.create(
            road='Morogoro Road', region='Dar es Salaam', severity='high', source='device',
            detected_at=timezone.now(), lat=-6.79, lng=39.21)

    def test_review_is_stamped_from_the_logged_in_user(self):
        officer = make_user('officer@example.com', role=UserRole.TARURA_OFFICER)
        other = make_user('someone-else@example.com')
        self.log_in(officer)

        # The client tries to claim someone else did the review: that value is ignored.
        res = self.client.patch(f'/api/v1/defects/{self.defect.pk}/', {
            'status': 'Verified', 'review_note': 'Confirmed on site', 'reviewed_by': other.pk,
        }, format='json')
        self.assertEqual(res.status_code, 200, res.content)
        body = res.json()
        self.assertEqual(body['status'], 'Verified')
        self.assertEqual(body['reviewed_by'], officer.name)  # the name, for display
        self.assertIsNotNone(body['reviewed_at'])

        self.defect.refresh_from_db()
        self.assertEqual(self.defect.reviewed_by_id, officer.pk)
        self.assertTrue(AuditLog.objects.filter(action='defect.reviewed', actor=officer).exists())

    def test_officer_can_only_change_review_fields(self):
        self.log_in(make_user('officer@example.com', role=UserRole.TARURA_OFFICER))
        res = self.client.patch(f'/api/v1/defects/{self.defect.pk}/', {'road': 'Renamed'}, format='json')
        self.assertEqual(res.status_code, 403)
        self.assertEqual(self.client.delete(f'/api/v1/defects/{self.defect.pk}/').status_code, 403)

    def test_unreviewed_defect_has_no_reviewer(self):
        self.log_in(make_user('officer@example.com', role=UserRole.TARURA_OFFICER))
        body = self.client.get(f'/api/v1/defects/{self.defect.pk}/').json()
        self.assertIsNone(body['reviewed_by'])
        self.assertIsNone(body['reviewed_at'])


class AuditLogTests(PortalTestCase):

    def test_only_admins_can_read_the_audit_log(self):
        self.log_in(make_user('officer@example.com', role=UserRole.TARURA_OFFICER))
        self.assertEqual(self.client.get('/api/v1/audit-log/').status_code, 403)

    def test_admin_sees_newest_entries_first_with_filters(self):
        admin = make_user('admin@example.com')
        self.log_in(admin)
        self.client.post('/api/v1/authorities/', {'name': 'TARURA', 'coverage_area': 'Tanzania',
                                               'contact': 'info@tarura.go.tz'}, format='json')

        entries = self.client.get('/api/v1/audit-log/').json()
        self.assertEqual(entries[0]['action'], 'authority.created')  # newest first
        self.assertEqual(entries[0]['actor_email'], admin.email)
        self.assertEqual(entries[0]['ip_address'], '127.0.0.1')

        only_logins = self.client.get('/api/v1/audit-log/?action=auth.login_succeeded').json()
        self.assertTrue(only_logins)
        self.assertTrue(all(e['action'] == 'auth.login_succeeded' for e in only_logins))


class DefectPhotoTests(PortalTestCase):
    """Officers can see the photo a traveller took; nobody else can."""

    def setUp(self):
        super().setUp()
        from .models import ReportPhoto
        self.jpeg = b'\xff\xd8\xff\xe0 fake jpeg bytes \xff\xd9'
        photo = ReportPhoto.objects.create(token_hash='a' * 64, content=self.jpeg, sha256='b' * 64,
                                           expires_at=timezone.now() + timedelta(minutes=15))
        common = dict(road='Morogoro Road', region='Dar es Salaam', severity='high',
                      source='manual', detected_at=timezone.now(), lat=-6.79, lng=39.21)
        self.with_photo = Defect.objects.create(has_photo=True, photo=photo, **common)
        # Sample data: flagged as having a photo, but no image stored.
        self.flag_only = Defect.objects.create(has_photo=True, **common)

    def test_logged_in_user_gets_the_jpeg(self):
        self.log_in(make_user('admin@example.com'))
        res = self.client.get(f'/api/v1/defects/{self.with_photo.pk}/photo/')
        self.assertEqual(res.status_code, 200)
        self.assertEqual(res['Content-Type'], 'image/jpeg')
        self.assertEqual(res.content, self.jpeg)
        self.assertIn('no-store', res['Cache-Control'])

    def test_photo_needs_login(self):
        self.assertEqual(self.client.get(f'/api/v1/defects/{self.with_photo.pk}/photo/').status_code, 401)

    def test_has_photo_only_when_an_image_is_stored(self):
        self.log_in(make_user('admin@example.com'))
        flags = {d['id']: d['has_photo'] for d in self.client.get('/api/v1/defects/').json()}
        self.assertTrue(flags[self.with_photo.pk])
        self.assertFalse(flags[self.flag_only.pk])
        self.assertEqual(self.client.get(f'/api/v1/defects/{self.flag_only.pk}/photo/').status_code, 404)


class BaseUrlTests(TestCase):
    """Every backend path lives under one base path (settings.API_PREFIX, config/urls.py)."""

    def test_everything_is_under_the_prefix(self):
        from django.conf import settings
        self.assertEqual(settings.API_PREFIX, 'api/v1/')
        self.assertEqual(self.client.get('/api/v1/health/').status_code, 200)
        # Portal, mobile and AI routes all answer under the prefix (401 = route exists, needs login).
        self.assertEqual(self.client.get('/api/v1/defects/').status_code, 401)
        self.assertEqual(self.client.get('/api/v1/mobile/auth/session/').status_code, 401)
        self.assertEqual(self.client.get('/api/v1/ai/status/').status_code, 401)

    def test_old_paths_are_gone(self):
        for old in ('/health/', '/api/defects/', '/graphql/anonymous/', '/api/mobile/auth/login/', '/admin/'):
            self.assertEqual(self.client.get(old).status_code, 404, old)
