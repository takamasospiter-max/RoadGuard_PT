#!/bin/sh
# Start-up for the backend container (see Dockerfile):
# 1. apply any new database migrations, so the schema always matches the code;
# 2. start gunicorn, the production web server, on port 8000.
# Any arguments replace step 2, e.g. `docker compose run backend python manage.py test`.
set -e

python manage.py migrate --noinput

if [ "$#" -gt 0 ]; then
    exec "$@"
fi

# 3 worker processes is plenty for one PC. The long timeout lets the first
# photo check finish while torch and the YOLO model load (a few seconds).
exec gunicorn config.wsgi:application \
    --bind 0.0.0.0:8000 \
    --workers "${GUNICORN_WORKERS:-3}" \
    --timeout 120 \
    --access-logfile - \
    --error-logfile -
