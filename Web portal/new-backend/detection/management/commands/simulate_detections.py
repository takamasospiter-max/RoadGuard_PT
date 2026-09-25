"""`python manage.py simulate_detections` — inject fake AI detections for testing and demos.

Pretends that several different phones hit a pothole at one spot, so the
grouping, severity rating, portal display and driver alerts can be tried
before the real AI engine exists.

    python manage.py simulate_detections --lat -6.7924 --lng 39.2083 --devices 3
    python manage.py simulate_detections --lat -6.7924 --lng 39.2083 --devices 4 --intensity 0.9

Simulated detections are flagged (is_simulated). A spot built only from them
is visible in the portal but is NOT alerted to drivers unless
ROADGUARD_PUBLISH_SIMULATED=True (development only).
"""

import random
import uuid
from datetime import timedelta

from django.core.management.base import BaseCommand, CommandError
from django.utils import timezone

from detection import spots
from detection.models import Detection


class Command(BaseCommand):
    help = 'Create simulated pothole detections from several fake devices at one spot.'

    def add_arguments(self, parser):
        parser.add_argument('--lat', type=float, required=True)
        parser.add_argument('--lng', type=float, required=True)
        parser.add_argument('--devices', type=int, default=3, help='How many different phones (default 3).')
        parser.add_argument('--confidence', type=float, default=0.85, help='0–1 (default 0.85).')
        parser.add_argument('--intensity', type=float, default=0.6, help='0–1 hit strength (default 0.6).')
        parser.add_argument('--spread', type=float, default=4.0,
                            help='Random GPS scatter in metres around the spot (default 4).')

    def handle(self, *args, **o):
        if not (-90 <= o['lat'] <= 90 and -180 <= o['lng'] <= 180):
            raise CommandError('Coordinates are out of range.')
        if not 1 <= o['devices'] <= 50 or not 0 <= o['confidence'] <= 1 or not 0 <= o['intensity'] <= 1:
            raise CommandError('Use 1–50 devices and confidence/intensity between 0 and 1.')

        metres_to_degrees = 1 / 111_320  # roughly, near the equator
        defect = None
        for i in range(o['devices']):
            jitter = lambda: random.uniform(-o['spread'], o['spread']) * metres_to_degrees
            detection = Detection.objects.create(
                device_key=f'simulated-{uuid.uuid4().hex}',  # each one a "different phone"
                trip_id=uuid.uuid4(),
                detected_at=timezone.now() - timedelta(minutes=5 * (o['devices'] - i)),
                lat=o['lat'] + jitter(), lng=o['lng'] + jitter(),
                confidence=o['confidence'], intensity=o['intensity'],
                model_version='simulated', is_simulated=True,
            )
            defect = spots.assign(detection) or defect
            state = f'grouped into {defect.pk}' if defect else 'waiting for more devices'
            self.stdout.write(f'  device {i + 1}: detection {detection.pk} → {state}')

        if defect is None:
            self.stdout.write(self.style.WARNING('Not enough devices yet to create a spot.'))
            return
        defect.refresh_from_db()
        self.stdout.write(self.style.SUCCESS(
            f'Spot {defect.pk}: {defect.device_count} devices, {defect.observation_count} detections, '
            f'confidence {defect.confidence}%, severity {defect.severity} '
            f'(score {defect.severity_score:.2f}), published to drivers: {bool(defect.published_at)}'))
