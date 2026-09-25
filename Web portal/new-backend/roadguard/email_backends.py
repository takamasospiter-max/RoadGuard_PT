"""A Django email backend that stores emails in the database instead of sending them.

Selected in settings.MAILERS. Code that sends email uses Django's normal
EmailMessage(...).send(), so switching to a real SMTP server later is a
settings change only, e.g.
    MAILERS = {'default': {'BACKEND': 'django.core.mail.backends.smtp.EmailBackend', ...}}
"""

from django.core.mail.backends.base import BaseEmailBackend

from .models import OutboxEmail


class OutboxEmailBackend(BaseEmailBackend):
    """Save each outgoing email as an OutboxEmail row (readable at /api/v1/dev/outbox/)."""

    def send_messages(self, email_messages):
        # Django hands us a list of EmailMessage objects; return how many were "sent".
        sent = 0
        for message in email_messages:
            OutboxEmail.objects.create(
                to_email=', '.join(message.to),
                subject=message.subject,
                body=message.body,
            )
            sent += 1
        return sent
