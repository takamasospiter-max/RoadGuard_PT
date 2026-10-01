# RoadGuard backend: Django + DRF + both AI models, served by gunicorn.
# Built and run by the repository's docker-compose.yml (service "backend").
#
# Build option WITH_PHOTO_AI (default 1):
#   1 = install the YOLO photo model's packages (ultralytics + CPU-only torch)
#   0 = leave them out: a smaller, faster build for slow connections. Photo
#       checks then fail softly and are recorded as "not run" (see
#       ai_engine/photo_model.py); everything else works the same.
FROM python:3.13-slim

ARG WITH_PHOTO_AI=1

# No .pyc files, unbuffered logs (so `docker compose logs` shows them at once).
ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1 \
    DJANGO_STATIC_ROOT=/app/staticfiles

WORKDIR /app

# OpenCV (pulled in by ultralytics) needs these system libraries.
RUN if [ "$WITH_PHOTO_AI" = "1" ]; then \
        apt-get update \
        && apt-get install -y --no-install-recommends libgl1 libglib2.0-0 \
        && rm -rf /var/lib/apt/lists/*; \
    fi

COPY requirements.txt .
# torch comes from PyTorch's CPU-only index: the default Linux package also
# pulls ~2 GB of NVIDIA GPU libraries that photo checks don't need. Installed
# first, so ultralytics (in requirements.txt) finds it already satisfied.
# Long timeouts and retries: torch is large and connections can be slow.
RUN set -eux; \
    PIP="pip install --timeout 120 --retries 10"; \
    if [ "$WITH_PHOTO_AI" = "1" ]; then \
        $PIP --index-url https://download.pytorch.org/whl/cpu torch==2.14.0 torchvision==0.29.0; \
        $PIP -r requirements.txt; \
    else \
        grep -v '^ultralytics' requirements.txt > /tmp/requirements-no-photo-ai.txt; \
        $PIP -r /tmp/requirements-no-photo-ai.txt; \
    fi; \
    $PIP gunicorn==23.0.0

# WhiteNoise serves the Django admin's static files from gunicorn (Django
# itself doesn't with debug off). A separate step, so changing it never
# re-runs the large torch download above.
RUN pip install --timeout 120 --retries 10 "whitenoise>=6,<7"

COPY . .

# Gather the Django admin's static files for WhiteNoise. collectstatic imports the
# settings, which require these values; dummy ones are fine at build time.
RUN DJANGO_SECRET_KEY=build-only DB_NAME=x DB_USER=x DB_PASSWORD=x \
    python manage.py collectstatic --noinput

# Run as an unprivileged user, not root.
RUN useradd --create-home --uid 1000 roadguard \
    && chmod +x docker-entrypoint.sh \
    && chown -R roadguard /app
USER roadguard

EXPOSE 8000
ENTRYPOINT ["./docker-entrypoint.sh"]
