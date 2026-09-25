"""`python manage.py process_telemetry` — run the in-process AI engine over new sensor batches.

    python manage.py process_telemetry               # process what's pending, then stop
    python manage.py process_telemetry --loop 10     # keep running, checking every 10 s

The engine is whatever settings.ROADGUARD_AI_ENGINE names (default: the
placeholder NullEngine, which finds nothing). Not needed when an external AI
service uses the HTTP API instead.
"""

import time

from django.core.management.base import BaseCommand

from detection.pipeline import process_pending


class Command(BaseCommand):
    help = 'Analyse pending sensor batches with the configured AI engine.'

    def add_arguments(self, parser):
        parser.add_argument('--limit', type=int, default=200,
                            help='Maximum batches per round (default 200).')
        parser.add_argument('--loop', type=int, default=0, metavar='SECONDS',
                            help='Keep running, waiting this many seconds between rounds.')

    def handle(self, *args, **options):
        while True:
            batches, detections = process_pending(limit=options['limit'])
            self.stdout.write(f'Processed {batches} batches, {detections} detections.')
            if not options['loop']:
                break
            time.sleep(options['loop'])
