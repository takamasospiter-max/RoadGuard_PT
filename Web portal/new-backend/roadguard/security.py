"""Security helpers: passwords, MFA (authenticator-app) codes, signed tokens.

Everything security-sensitive lives in this one module so the rules
(timeouts, token lifetimes, hashing) are easy to find and review.
"""

import base64
import io
import secrets
from datetime import timedelta

import pyotp
import qrcode
from django.contrib.auth.hashers import check_password, make_password
from django.core import signing

# ---------------------------------------------------------------------------
# Timing rules (SRS session requirements)
# ---------------------------------------------------------------------------

# A session ends after this long with no requests at all...
IDLE_TIMEOUT = timedelta(minutes=30)
# ...and after this long in total, however active it is.
ABSOLUTE_SESSION_LIFETIME = timedelta(hours=8)

# After a correct password, the user has this long to enter their MFA code
# before they must start the login again.
MFA_PENDING_TTL_SECONDS = 5 * 60

# How often the authenticator code changes. The usual default is 30 seconds;
# 60 gives people more time to type it. Some apps (notably Google
# Authenticator) always use 30s and ignore this; codes still work because
# verify_totp_code() also accepts the neighbouring code.
MFA_CODE_INTERVAL_SECONDS = 60

# How long an invitation (account activation) link stays valid.
INVITE_TOKEN_TTL_SECONDS = 7 * 24 * 60 * 60

# Name of the cookie that carries the session id in the browser.
SESSION_COOKIE_NAME = 'roadguard_session'

# "Salts" keep the two kinds of signed token separate: an MFA-pending token
# can never be used as an invite token or the other way round, even though
# both are signed with the same SECRET_KEY.
_MFA_PENDING_SALT = 'roadguard.mfa-pending-login'
_INVITE_SALT = 'roadguard.account-invite'

# Minimum password length — the same rule the activation page checks in the
# browser (frontend/src/pages/ActivateAccountPage.tsx), enforced here too.
MIN_PASSWORD_LENGTH = 8


# ---------------------------------------------------------------------------
# Passwords
# ---------------------------------------------------------------------------

def hash_password(password: str) -> str:
    """Return a salted, slow hash of `password` (Django's PBKDF2 by default).

    Only this hash is stored — the plain password is never saved anywhere.
    """
    return make_password(password)


def verify_password(password: str, password_hash: str | None) -> bool:
    """True if `password` matches the stored hash. A missing hash never matches."""
    if not password_hash:
        return False
    return check_password(password, password_hash)


# ---------------------------------------------------------------------------
# MFA — time-based one-time codes (TOTP, RFC 6238)
# ---------------------------------------------------------------------------

def generate_mfa_secret() -> str:
    """A new random Base32 secret, the format every authenticator app expects."""
    return pyotp.random_base32()


def _totp(secret: str) -> pyotp.TOTP:
    """Code generator for one user's secret, using our code interval."""
    return pyotp.TOTP(secret, interval=MFA_CODE_INTERVAL_SECONDS)


def totp_provisioning_uri(secret: str, email: str) -> str:
    """An otpauth:// link describing the account for an authenticator app.

    Turned into a QR code (see qr_code_data_uri) for the user to scan; the raw
    secret is the manual-entry fallback.
    """
    return _totp(secret).provisioning_uri(name=email, issuer_name='RoadGuard AI')


def verify_totp_code(secret: str, code: str) -> bool:
    """True if `code` is the current code for `secret`.

    valid_window=1 also accepts the previous and next code, so a login
    doesn't fail just because the code changed while it was being typed.
    """
    return _totp(secret).verify(code.strip(), valid_window=1)


def qr_code_data_uri(data: str) -> str:
    """Render `data` as a QR code PNG and return it as a data: URI.

    The frontend drops this straight into <img src=...>, so the browser doesn't
    need its own QR library just for the activation screen.
    """
    image = qrcode.make(data)
    buffer = io.BytesIO()
    image.save(buffer, format='PNG')
    encoded = base64.b64encode(buffer.getvalue()).decode('ascii')
    return f'data:image/png;base64,{encoded}'


# ---------------------------------------------------------------------------
# Signed, self-expiring tokens (no database row needed)
# ---------------------------------------------------------------------------

def issue_mfa_pending_token(portal_user_id: str) -> str:
    """Proof that the password step passed, carried to the MFA step.

    It is signed with SECRET_KEY, so it can't be forged, and it expires after
    MFA_PENDING_TTL_SECONDS. On its own it grants no access at all.
    """
    return signing.dumps(portal_user_id, salt=_MFA_PENDING_SALT)


def read_mfa_pending_token(token: str) -> str | None:
    """The user id inside a valid MFA-pending token, or None if it's forged/expired."""
    try:
        return signing.loads(token, salt=_MFA_PENDING_SALT, max_age=MFA_PENDING_TTL_SECONDS)
    except signing.BadSignature:  # also covers SignatureExpired
        return None


def issue_invite_token(portal_user_id: str) -> str:
    """The token placed in an invitation email's activation link."""
    return signing.dumps(portal_user_id, salt=_INVITE_SALT)


def read_invite_token(token: str) -> str | None:
    """The user id inside a valid invite token, or None if it's forged/expired."""
    try:
        return signing.loads(token, salt=_INVITE_SALT, max_age=INVITE_TOKEN_TTL_SECONDS)
    except signing.BadSignature:
        return None


def new_session_token() -> str:
    """32 random bytes, URL-safe — unguessable. This is all the session cookie holds."""
    return secrets.token_urlsafe(32)
