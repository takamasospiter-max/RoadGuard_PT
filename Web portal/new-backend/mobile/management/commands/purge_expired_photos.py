"""`python manage.py purge_expired_photos` — delete uploaded photos never attached to a report.

A photo is uploaded first and claimed by the report a moment later. If the
report never arrives (app closed, no signal), the photo is useless after its
15-minute token expires; this removes those. Safe to run on a schedule.
"""

from django.core.management.base import BaseCommand
from django.utils import timezone

from roadguard.models import ReportPhoto


class Command(BaseCommand):
    help = 'Delete expired report photos that no report claimed.'

    def handle(self, *args, **options):
        deleted, _ = ReportPhoto.objects.filter(expires_at__lte=timezone.now(), defect__isnull=True).delete()
        self.stdout.write(self.style.SUCCESS(f'Deleted {deleted} expired unclaimed photos.'))
