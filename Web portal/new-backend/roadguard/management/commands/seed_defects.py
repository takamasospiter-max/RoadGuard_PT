"""`python manage.py seed_defects` — fill the defects table with sample data.

The same 14 records the frontend once hard-coded (and the old FastAPI backend's scripts/
seed_defects.py loaded into the FastAPI database), so the Dashboard, Map and
Reports pages have something to show during development.

Safe to run more than once: records whose id already exists are skipped.
"""

from datetime import datetime, timezone

from django.core.management.base import BaseCommand

from roadguard.models import Defect, HazardType, ReportSource, ReportStatus, Severity

# Short names so each record fits on one line below.
H, M, L = Severity.HIGH, Severity.MEDIUM, Severity.LOW
NEW, VER, REP, RES = (ReportStatus.NEW, ReportStatus.VERIFIED,
                      ReportStatus.UNDER_REPAIR, ReportStatus.RESOLVED)
DEV, MAN = ReportSource.DEVICE, ReportSource.MANUAL

# (id, road, region, severity, status, source, confidence, observations, detected_at (UTC), lat, lng, has_photo)
RECORDS = [
    ('RG-00118', 'Morogoro Road', 'Dar es Salaam', H, NEW, DEV, 94, 6, '2026-09-18T09:42', -6.7924, 39.2083, False),
    ('RG-00119', 'Morogoro Road', 'Dar es Salaam', H, VER, DEV, 91, 9, '2026-09-17T14:05', -6.7929, 39.2091, True),
    ('RG-00120', 'Morogoro Road', 'Dar es Salaam', M, REP, DEV, 82, 4, '2026-09-15T08:20', -6.7918, 39.2076, False),
    ('RG-00124', 'Mandela Road', 'Dar es Salaam', M, VER, DEV, 89, 5, '2026-09-18T08:15', -6.8035, 39.2695, False),
    ('RG-00127', 'Sokoine Road', 'Arusha', L, RES, DEV, 76, 3, '2026-09-10T11:30', -3.3869, 36.6830, False),
    ('RG-00131', 'Old Moshi Road', 'Arusha', M, REP, DEV, 85, 7, '2026-09-16T07:55', -3.3910, 36.6902, True),
    ('RG-00133', 'Kenyatta Road', 'Mwanza', H, NEW, MAN, 62, 1, '2026-09-19T08:12', -2.5164, 32.9175, True),
    ('RG-00134', 'Makongoro Road', 'Mwanza', L, NEW, MAN, 58, 1, '2026-09-19T07:48', -2.5201, 32.9033, False),
    ('RG-00135', 'Uhuru Street', 'Dodoma', M, VER, DEV, 88, 5, '2026-09-14T16:10', -6.1630, 35.7516, False),
    ('RG-00136', 'Dodoma–Iringa Road', 'Dodoma', H, REP, DEV, 93, 8, '2026-09-12T13:22', -6.1795, 35.7398, True),
    ('RG-00139', 'Mbeya–Tunduma Highway', 'Mbeya', L, RES, DEV, 71, 2, '2026-09-05T10:00', -8.9094, 33.4608, False),
    ('RG-00141', 'Uzunguni Road', 'Mbeya', H, VER, DEV, 90, 6, '2026-09-13T09:05', -8.9150, 33.4502, True),
    ('RG-00144', 'Independence Avenue', 'Tanga', M, NEW, MAN, 55, 1, '2026-09-19T06:40', -5.0692, 39.0962, False),
    ('RG-00147', 'Morogoro–Dodoma Highway', 'Morogoro', L, RES, DEV, 79, 3, '2026-09-08T12:15', -6.8235, 37.6612, False),
]


class Command(BaseCommand):
    help = 'Load 14 sample defects (skips ids that already exist).'

    def handle(self, *args, **options):
        existing = set(Defect.objects.values_list('id', flat=True))
        to_create = [
            Defect(
                id=rid, hazard_type=HazardType.POTHOLE, road=road, region=region,
                severity=sev, status=st, source=src, confidence=conf, observation_count=obs,
                detected_at=datetime.fromisoformat(ts).replace(tzinfo=timezone.utc),
                lat=lat, lng=lng, has_photo=photo,
            )
            for (rid, road, region, sev, st, src, conf, obs, ts, lat, lng, photo) in RECORDS
            if rid not in existing
        ]
        # bulk_create inserts them all in one query. The ids are given
        # explicitly, so PrefixedIdModel.save() (which would generate new
        # ones) isn't needed.
        Defect.objects.bulk_create(to_create)
        self.stdout.write(self.style.SUCCESS(
            f'Seeded {len(to_create)} defects ({len(RECORDS) - len(to_create)} already present, skipped).'))
