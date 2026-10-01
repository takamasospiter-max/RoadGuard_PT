"""The AI team's photo model (YOLOv8): looks for potholes in travellers' report photos.

Turn it on in `.env`:

    ROADGUARD_PHOTO_CHECK=True

What happens to each report photo (mobile/reports.py calls check_report_photo()
once the report is saved):

    sanitized JPEG (stored in ReportPhoto.content)
        │  YOLOv8 (models/yolo-best.pt), images resized to 320 px as in training
        ▼
    boxes around potholes, each with a 0–1 confidence
        │  check_photo()   keep boxes ≥ ROADGUARD_PHOTO_MIN_CONFIDENCE
        ▼
    stored on the ReportPhoto → shown to officers in the portal next to the photo

The result is ADVICE for the officer reviewing the report: it never changes
the report's status, severity or whether drivers are warned. The model is
modest (mAP50 0.55, precision 0.52, recall 0.54), so "no pothole found" must
not be read as "no pothole there".

The model and how it was trained: models/MODEL.md.
"""

import logging
from dataclasses import dataclass, field
from functools import lru_cache
from hashlib import sha256
from io import BytesIO
from pathlib import Path

from django.conf import settings
from django.utils import timezone
from PIL import Image

logger = logging.getLogger(__name__)

# The image size the model was trained at (the notebook's imgsz=320).
IMAGE_SIZE = 320


class PhotoModelError(Exception):
    """The photo model file is missing, altered, or can't be run here."""


@dataclass
class PhotoCheck:
    """What the model saw in one photo.

    boxes: one entry per pothole found, [x1, y1, x2, y2, confidence], with the
    corners as fractions (0–1) of the photo's width and height, so the portal
    can draw them over the photo at any size.
    """
    confidence: float                 # the surest box's confidence, 0 if none
    boxes: list = field(default_factory=list)
    model_version: str = ''

    @property
    def pothole_found(self):
        return bool(self.boxes)


@lru_cache(maxsize=2)
def load_model(path, expected_sha256):
    """Load and check the YOLO model once per process (cached afterwards).

    A .pt file is a pickle, which can run code when it is opened, so the file's
    SHA-256 must match the reviewed file *before* it is handed to Ultralytics.
    Returns (model, version string stored with every result).
    """
    try:
        data = Path(path).read_bytes()
    except OSError as exc:
        raise PhotoModelError(f'Photo model file not found: {path}') from exc
    digest = sha256(data).hexdigest()
    if expected_sha256 and digest != expected_sha256.lower():
        raise PhotoModelError(f'Photo model checksum {digest[:12]}… does not match '
                              f'ROADGUARD_PHOTO_MODEL_SHA256; refusing to load it.')
    # Importing ultralytics replaces Pillow's Image.open for the whole process
    # (ultralytics.utils.patches). Its version fails on unreadable files with
    # ModuleNotFoundError (it tries an optional HEIC library), so a bad photo
    # upload (mobile/reports.py) crashed instead of being refused. Put Pillow's
    # own function back; the model doesn't need it, as check_photo() hands it
    # an image that is already open.
    pillow_open = Image.open
    try:
        # Imported here, not at the top: torch takes a few seconds to import,
        # and the rest of the backend (and its tests) must work without it.
        from ultralytics import YOLO
    except ImportError as exc:
        raise PhotoModelError('The photo model needs the "ultralytics" package: '
                              'pip install -r requirements.txt') from exc
    finally:
        Image.open = pillow_open

    model = YOLO(str(path), task='detect')
    names = list(model.names.values())
    if names != ['pothole']:
        raise PhotoModelError(f'Expected a model with the one class "pothole", got {names}.')
    return model, f'yolov8-pothole-320+{digest[:8]}'


def check_photo(jpeg_bytes):
    """Run the photo model on one image (JPEG/PNG bytes) → PhotoCheck."""
    model, version = load_model(settings.ROADGUARD_PHOTO_MODEL_PATH,
                                settings.ROADGUARD_PHOTO_MODEL_SHA256)
    with Image.open(BytesIO(jpeg_bytes)) as image:
        image = image.convert('RGB')
        # One photo at a time on the CPU; verbose=False keeps the server log clean.
        result = model.predict(image, imgsz=IMAGE_SIZE, conf=settings.ROADGUARD_PHOTO_MIN_CONFIDENCE,
                               device='cpu', verbose=False)[0]

    # xyxyn = box corners as fractions of the photo size; conf = 0–1 confidence.
    boxes = [[round(float(v), 4) for v in (*xyxy, conf)]
             for xyxy, conf in zip(result.boxes.xyxyn.tolist(), result.boxes.conf.tolist())]
    boxes.sort(key=lambda box: box[4], reverse=True)  # surest first
    return PhotoCheck(confidence=boxes[0][4] if boxes else 0.0, boxes=boxes, model_version=version)


def check_report_photo(photo):
    """Check a stored ReportPhoto and save the result on it.

    Never raises: a report must be accepted even if the AI check fails. On a
    failure the error is saved (the portal shows "photo check failed") and
    `manage.py check_report_photos --retry-failed` can try again later.
    Returns the PhotoCheck, or None if it failed.
    """
    try:
        check = check_photo(bytes(photo.content))
    except Exception as exc:  # noqa: BLE001 - any failure is recorded, never raised
        logger.exception('Photo check failed for report photo %s', photo.pk)
        photo.ai_error = str(exc)[:500] or exc.__class__.__name__
        photo.ai_checked_at = timezone.now()
        photo.save(update_fields=['ai_error', 'ai_checked_at'])
        return None

    photo.ai_pothole_confidence = check.confidence
    photo.ai_boxes = check.boxes
    photo.ai_model_version = check.model_version
    photo.ai_error = ''
    photo.ai_checked_at = timezone.now()
    photo.save(update_fields=['ai_pothole_confidence', 'ai_boxes', 'ai_model_version',
                              'ai_error', 'ai_checked_at'])
    return check
