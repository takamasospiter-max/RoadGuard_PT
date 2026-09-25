"""Mobile-app traveller accounts and their login sessions.

Travellers (drivers using the Flutter app) are completely separate from
portal users (roadguard.PortalUser): different table, different login, and a
traveller token can never open the web portal.
"""

import uuid

from django.db import models
from django.db.models.functions import Lower


class Traveler(models.Model):
    """A driver's account in the mobile app (Profile → Create account).

    An account is optional: reporting potholes and seeing hazards work
    anonymously. Signing in is only needed for sensor-data sharing, so
    readings can be linked to a consent.
    """
    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    name = models.CharField(max_length=160)
    email = models.EmailField(max_length=254)
    # Salted hash from Django's make_password(); never the plain password.
    password_hash = models.CharField(max_length=200)
    is_active = models.BooleanField(default=True)
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        db_table = 'travelers'
        constraints = [
            # One account per email, ignoring upper/lower case.
            models.UniqueConstraint(Lower('email'), name='travelers_email_unique_ci'),
        ]

    def __str__(self):
        return self.email

    # DRF's IsAuthenticated permission reads this; anyone who reaches a view
    # as a Traveler has already passed TravelerTokenAuthentication.
    @property
    def is_authenticated(self):
        return True


class TravelerSession(models.Model):
    """One signed-in phone. The app holds a random bearer token; the server
    keeps only its SHA-256 hash, so a leaked database can't be used to log in."""
    token_hash = models.CharField(max_length=64, primary_key=True)
    traveler = models.ForeignKey(Traveler, on_delete=models.CASCADE, related_name='sessions')
    created_at = models.DateTimeField(auto_now_add=True)
    expires_at = models.DateTimeField(db_index=True)

    class Meta:
        db_table = 'traveler_sessions'
