"""`python manage.py create_admin` — create (or reset) a portal Admin account.

Solves the first-login problem: new users are invited by an Admin, so the
very first Admin has to be created from the command line. Running it again
for an existing email resets that account's password and MFA secret, which
is also the recovery path for a lost authenticator app.

Interactive:      python manage.py create_admin
Non-interactive:  python manage.py create_admin --email a@b.c --name "Jane Doe" --password "..."
"""

import getpass
import io

import qrcode
from django.core.management.base import BaseCommand, CommandError
from django.db import transaction

from roadguard.models import AccountStatus, PortalUser, UserRole
from roadguard.security import (MFA_CODE_INTERVAL_SECONDS, MIN_PASSWORD_LENGTH,
                                generate_mfa_secret, hash_password, totp_provisioning_uri)


class Command(BaseCommand):
    help = 'Create or reset a portal Admin account (password + fresh MFA secret).'

    def add_arguments(self, parser):
        # All optional: anything not given on the command line is asked for.
        parser.add_argument('--email')
        parser.add_argument('--name')
        parser.add_argument('--password',
                            help='Avoid on shared machines; it stays in shell history. '
                                 'Leave it out to be prompted instead.')

    def handle(self, *args, **options):
        email = (options['email'] or input('Email: ')).strip()
        name = (options['name'] or input('Name: ')).strip()
        # getpass hides what's typed.
        password = options['password'] or getpass.getpass('Password: ')

        if not email or not name:
            raise CommandError('Email and name are required.')
        if len(password) < MIN_PASSWORD_LENGTH:
            raise CommandError(f'Password must be at least {MIN_PASSWORD_LENGTH} characters.')

        mfa_secret = generate_mfa_secret()
        with transaction.atomic():
            user = PortalUser.objects.filter(email__iexact=email).first()
            if user is None:
                user = PortalUser(email=email, role=UserRole.ADMIN, authority='System')
                action = 'Created'
            else:
                action = 'Reset'
            user.name = name
            user.role = UserRole.ADMIN
            user.status = AccountStatus.ACTIVE
            user.password_hash = hash_password(password)
            user.mfa_secret = mfa_secret
            user.save()  # new accounts get their USR-... id here
            # Log out any existing sessions, since the credentials just changed.
            user.sessions.all().delete()

        self.stdout.write(self.style.SUCCESS(f'\n{action} Admin account {user.pk} <{user.email}>'))
        self._print_qr_code(totp_provisioning_uri(mfa_secret, user.email))

        self.stdout.write(f'\nCan\'t scan? Enter this setup key manually: {mfa_secret}')
        self.stdout.write(f'(Codes change every {MFA_CODE_INTERVAL_SECONDS} seconds.)\n')
        self.stdout.write('Or print the current code without an app:')
        self.stdout.write(f'  python -c "import pyotp; print(pyotp.TOTP(\'{mfa_secret}\', '
                          f'interval={MFA_CODE_INTERVAL_SECONDS}).now())"\n')

    def _print_qr_code(self, uri):
        """Draw the QR code with block characters so it can be scanned from the terminal.

        It's drawn into a string first: some terminals (e.g. the Windows console
        with its default cp1252 encoding) can't show the block characters. In
        that case, print a note and rely on the setup key printed afterwards.
        """
        qr = qrcode.QRCode(border=1)
        qr.add_data(uri)
        qr.make()
        drawing = io.StringIO()
        qr.print_ascii(out=drawing, invert=True)
        try:
            self.stdout.write('\nScan this QR code with an authenticator app '
                              '(Microsoft Authenticator, Authy, 2FAS, ...):\n')
            self.stdout.write(drawing.getvalue())
        except UnicodeEncodeError:
            self.stdout.write(self.style.WARNING(
                '(This terminal can\'t draw the QR code. Use the setup key below, or run '
                '`set PYTHONUTF8=1` (cmd) / `$env:PYTHONUTF8=1` (PowerShell) first to see it.)'))
