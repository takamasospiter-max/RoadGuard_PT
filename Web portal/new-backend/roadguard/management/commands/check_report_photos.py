"""`python manage.py check_report_photos` — run the AI photo check on stored report photos.

Checks the photos of submitted reports that haven't been checked yet: photos
from before the check was switched on (ROADGUARD_PHOTO_CHECK), or submitted
while it was off. Works whether or not ROADGUARD_PHOTO_CHECK is on.

    python manage.py check_report_photos                 # unchecked photos only
    python manage.py check_report_photos --retry-failed  # also photos whose check failed
    python manage.py check_report_photos --all           # re-check every photo (e.g. after a new model)
"""

from django.conf import settings
from django.core.management.base import BaseCommand, CommandError

from ai_engine.photo_model import PhotoModelError, check_report_photo, load_model
from roadguard.models import ReportPhoto


class Command(BaseCommand):
    help = 'Run the AI photo check (YOLOv8) on report photos that have not been checked.'

    def add_arguments(self, parser):
        parser.add_argument('--retry-failed', action='store_true',
                            help='Also re-check photos whose previous check failed.')
        parser.add_argument('--all', action='store_true',
                            help='Re-check every submitted report photo.')

    def handle(self, *args, **options):
        # Load the model first, so a missing package or wrong file stops the
        # command with one clear message instead of failing on every photo.
        try:
            load_model(settings.ROADGUARD_PHOTO_MODEL_PATH, settings.ROADGUARD_PHOTO_MODEL_SHA256)
        except PhotoModelError as exc:
            raise CommandError(str(exc)) from exc

        # Only photos attached to a report: unclaimed uploads expire and are purged.
        photos = ReportPhoto.objects.filter(defect__isnull=False)
        if not options['all']:
            pending = photos.filter(ai_checked_at__isnull=True)
            if options['retry_failed']:
                pending = pending | photos.exclude(ai_error='')
            photos = pending

        checked = found = failed = 0
        for photo in photos.order_by('created_at').iterator(chunk_size=20):
            result = check_report_photo(photo)
            checked += 1
            if result is None:
                failed += 1
            elif result.pothole_found:
                found += 1
        self.stdout.write(self.style.SUCCESS(
            f'Checked {checked} photo(s): pothole found in {found}, '
            f'none found in {checked - found - failed}, failed {failed}.'))
