# RoadGuard AI — Web Portal

The web admin portal and shared backend for **RoadGuard AI**, a road-condition monitoring platform for TARURA (Tanzania Rural and Urban Roads Agency).

- **Admins and TARURA officers** use the web portal to see reported road defects (potholes) on a dashboard and map, review them, and manage portal users and road authorities.
- **Drivers** use the mobile app. It sends anonymous photo reports, shares phone sensor data, shows live hazards, and navigates turn by turn with voice warnings about potholes ahead.
- **The same backend serves both.** An AI engine turns the drivers' sensor data into pothole detections, and when several drivers' phones detect the same spot, other drivers are warned.

| Part | Folder | Stack |
|---|---|---|
| Backend (REST + GraphQL API) | [`new-backend/`](new-backend/) | Django 6.1 + Django REST framework 3.18, graphql-core, PostgreSQL 17 + **PostGIS 3.6** |
| Web portal | [`frontend/`](frontend/) | React 19 + TypeScript + Vite, axios, TanStack Query, Leaflet |
| Mobile app | `D:\ROADGUARD\Mobile app` (outside this folder) | Flutter 3.47 / Dart 3.13 |

---

## Contents

1. [Project requirements checklist](#1-project-requirements-checklist)
2. [Folder layout](#2-folder-layout)
3. [Getting started](#3-getting-started)
4. [Configuration (.env)](#4-configuration-env)
5. [API reference](#5-api-reference)
6. [How login with MFA works](#6-how-login-with-mfa-works)
7. [Inviting and activating users](#7-inviting-and-activating-users)
8. [Who can do what (roles)](#8-who-can-do-what-roles)
9. [Defect review stamping](#9-defect-review-stamping)
10. [Audit log](#10-audit-log)
11. [Emails during development](#11-emails-during-development)
12. [How the frontend calls the API (axios)](#12-how-the-frontend-calls-the-api-axios)
13. [Running the tests](#13-running-the-tests)
14. [Useful commands](#14-useful-commands)
15. [Connecting the mobile app](#15-connecting-the-mobile-app)
16. [Navigation (turn-by-turn)](#16-navigation-turn-by-turn)
17. [Crowd sensing: many drivers, one spot, one severity](#17-crowd-sensing-many-drivers-one-spot-one-severity)
18. [The AI engine socket](#18-the-ai-engine-socket)
19. [PostGIS](#19-postgis)
20. [History: the old FastAPI backend](#20-history-the-old-fastapi-backend)
21. [Known limitations and next steps](#21-known-limitations-and-next-steps)

---

## 1. Project requirements checklist

| # | Requirement | Status | Where |
|---|---|---|---|
| 1 | Django models | ✅ | [`roadguard/models.py`](new-backend/roadguard/models.py) (`Defect`, `ReportPhoto`, `Authority`, `PortalUser`, `AdminSession`, `AuditLog`, `OutboxEmail`), [`mobile/models.py`](new-backend/mobile/models.py) (`Traveler`, `TravelerSession`), [`telemetry/models.py`](new-backend/telemetry/models.py) (`CollectionConsent`, `TelemetryBatch`, `SensorReading`), [`detection/models.py`](new-backend/detection/models.py) (`Detection`) |
| 2 | Connection to an external database | ✅ | [`new-backend/config/settings.py`](new-backend/config/settings.py) `DATABASES` connects to PostgreSQL + PostGIS; the host, port, name, user and password are read from `new-backend/.env` |
| 3 | Django migrations | ✅ | `roadguard/migrations/` (`0001`–`0003`), `mobile/`, `telemetry/` and `detection/migrations/`. `0003` also enables PostGIS and adds the spatial columns |
| 4 | DRF class-based `APIView` endpoints | ✅ | Portal: [`roadguard/views.py`](new-backend/roadguard/views.py), [`auth_views.py`](new-backend/roadguard/auth_views.py). Mobile: [`mobile/views.py`](new-backend/mobile/views.py). AI engine: [`detection/views.py`](new-backend/detection/views.py) |
| 5 | React uses axios to consume the endpoints | ✅ | [`frontend/src/lib/api.ts`](frontend/src/lib/api.ts): one shared axios instance used by every data module in `frontend/src/lib/` |

On top of these, the backend has:
- **Portal security and oversight** (sections 6–10): login with an authenticator-app code (MFA), user invitations by email, an audit log and server-side review stamping.
- **The mobile side** (sections 15–19): the mobile app connection, turn-by-turn navigation, crowd sensing with spot severity, the AI engine socket and PostGIS.

---

## 2. Folder layout

```
Web portal/
├── README.md                         ← this file
├── backend-fastapi-archive.zip       ← old FastAPI backend, kept for reference (see §20)
├── frontend/                         ← React app
│   └── src/
│       ├── lib/api.ts                ← axios instance + error handling
│       ├── lib/auth.ts               ← login, verify-mfa, me, logout, accept-invite
│       ├── lib/defects.ts            ← defect API calls
│       ├── lib/authorities.ts        ← authority API calls
│       ├── lib/users.ts              ← user API calls
│       ├── pages/                    ← Login, Activate, Dashboard, Map, Reports, Users
│       └── context/AuthContext.tsx   ← who is logged in (asks /api/v1/auth/me/)
└── new-backend/                      ← Django project
    ├── manage.py
    ├── requirements.txt
    ├── .env / .env.example           ← settings and secrets (.env is not committed)
    ├── config/                       ← project settings and root URLs
    │   ├── settings.py
    │   └── urls.py
    ├── docs/AI_ENGINE_CONTRACT.md    ← how the AI engine plugs in (for the AI team)
    ├── mobile/                       ← mobile-app API (see §15)
    │   ├── models.py                 ← Traveler accounts + sessions
    │   ├── views.py                  ← register/login/session/logout, photo upload, GraphQL endpoints
    │   ├── graphql/                  ← *.graphql schemas, resolver wiring, safe executor
    │   ├── reports.py                ← photo sanitising + anonymous report → Defect
    │   ├── hazards.py                ← publicHazards: what drivers see and are warned about
    │   ├── routing.py                ← OSRM routes with turn-by-turn steps
    │   └── places.py                 ← Photon place search + road/region names
    ├── telemetry/                    ← sensor-data sharing: consent, batches, readings
    ├── detection/                    ← AI engine socket + crowd sensing (see §17, §18)
    │   ├── engine.py                 ← the interface a model implements (DetectionEngine)
    │   ├── pipeline.py               ← batches → engine → detections
    │   ├── spots.py                  ← group detections into spots, rate severity, publish
    │   └── views.py                  ← HTTP API for an external AI service (/api/v1/ai/...)
    └── roadguard/                    ← the portal app
        ├── models.py                 ← database tables
        ├── serializers.py            ← JSON ↔ model conversion and validation
        ├── views.py                  ← data endpoints (defects, authorities, users, audit log)
        ├── auth_views.py             ← login / MFA / activation / logout endpoints
        ├── authentication.py         ← turns the session cookie into the logged-in user
        ├── permissions.py            ← Admin vs officer rules
        ├── security.py               ← password hashing, MFA codes, signed tokens, timeouts
        ├── audit.py                  ← writes audit-log entries
        ├── email_backends.py         ← stores outgoing emails in the database
        ├── admin.py                  ← Django admin site registrations
        ├── tests.py                  ← automated tests
        ├── urls.py                   ← /api/v1/... routes
        ├── migrations/
        └── management/commands/
            └── create_admin.py       ← create the first Admin account
```

---

## 3. Getting started

### Prerequisites

- **Python 3.13** (on this PC: `C:\laragon\bin\python\python-3.13`)
- **Node.js** 20+ (on this PC: v25)
- **PostgreSQL 17**, running as the Windows service `postgresql-x64-17` on port 5432
- **PostGIS 3.6** for PostgreSQL 17 (installed on this PC, see §19)
- For the mobile app: **Flutter** (on this PC: `C:\flutter`) and **adb** (Android platform tools)

### Step 1: Database (one-time)

The database, its user and PostGIS already exist on this PC. On a new machine:

1. **Install PostGIS.** Start menu → *Application Stack Builder* → PostgreSQL 17 → *Spatial Extensions* → *PostGIS 3.6 Bundle for PostgreSQL 17*. See §19 for the manual method.
2. Log in to Postgres as the `postgres` superuser (with **SQL Shell (psql)** or **pgAdmin**) and run:

```sql
CREATE ROLE roadguard WITH LOGIN PASSWORD 'roadguard_dev_password' CREATEDB;
CREATE DATABASE roadguard_dev OWNER roadguard;

-- Enable PostGIS (needs the superuser). In template1 too, so the temporary
-- test databases the test run creates get PostGIS automatically.
\c roadguard_dev
CREATE EXTENSION IF NOT EXISTS postgis;
\c template1
CREATE EXTENSION IF NOT EXISTS postgis;
```

`CREATEDB` is needed because the test run creates a temporary test database.

### Step 2: Backend

```powershell
cd "D:\ROADGUARD\Web portal\new-backend"

# First time only: create the virtual environment and install packages
C:\laragon\bin\python\python-3.13\python -m venv .venv
.venv\Scripts\python -m pip install -r requirements.txt
copy .env.example .env        # then edit .env (see section 4)

# Create or update the database tables
.venv\Scripts\python manage.py migrate

# First time only: create your first Admin account (asks for email, name, password)
$env:PYTHONUTF8=1             # lets the terminal draw the MFA QR code
.venv\Scripts\python manage.py create_admin

# Start the API on http://localhost:8000
.venv\Scripts\python manage.py runserver
```

`create_admin` prints a QR code and a setup key. Add the account to an authenticator app (Microsoft Authenticator, Authy, 2FAS, Google Authenticator, …) by scanning the QR code or typing the key.

> The `venv/` folder next to `.venv/` is an old, broken environment copied from another machine. It isn't used and can be deleted.

### Step 3: Frontend

```powershell
cd "D:\ROADGUARD\Web portal\frontend"
npm install          # first time only
npm run dev          # http://localhost:5173
```

Open http://localhost:5173 and log in with the Admin account from step 2: password first, then the 6-digit code from your authenticator app.

### Starting the portal (every time)

The frontend and backend are two separate programs. **Both must be running** for the portal to work, each in its own terminal window.

**Terminal 1: backend (API)**

```powershell
cd "D:\ROADGUARD\Web portal\new-backend"
.venv\Scripts\python manage.py runserver
```

Leave it running. It should end with `Starting development server at http://127.0.0.1:8000/`.

**Terminal 2: frontend (website)**

```powershell
cd "D:\ROADGUARD\Web portal\frontend"
npm run dev
```

Leave it running. It shows `Local: http://localhost:5173/`.

Then open **http://localhost:5173** in your browser and log in.

**Terminal 3 (optional): the mobile app**, with an Android phone connected by USB. See §15 for details.

```powershell
adb reverse tcp:8000 tcp:8000      # the phone's localhost:8000 → this PC's backend
cd "D:\ROADGUARD\Mobile app"
flutter run --dart-define=ROADGUARD_API_URL=http://127.0.0.1:8000
```

**Terminal 4 (optional): the AI engine**, once an in-process model is configured (see §18):

```powershell
cd "D:\ROADGUARD\Web portal\new-backend"
.venv\Scripts\python manage.py process_telemetry --loop 10
```

To stop a server, press `Ctrl + C` in its terminal.

### First run on this PC

On this PC the virtual environment, packages, database and tables are already set up. The database has **no portal accounts** yet, though, so before the first login, run this in Terminal 1 (before `runserver`):

```powershell
cd "D:\ROADGUARD\Web portal\new-backend"
$env:PYTHONUTF8=1                                  # lets the terminal draw the QR code
.venv\Scripts\python manage.py create_admin        # your email, name and password
```

Scan the QR code that `create_admin` prints with an authenticator app, or type the setup key it shows. You only need to do this once.

### How the frontend connects to the backend

```
 Browser  ──►  http://localhost:5173   (frontend, Vite dev server, Terminal 2)
    │
    │  axios requests (with the session cookie)
    ▼
 http://localhost:8000/api/v1/...          (backend, Django, Terminal 1)
    │
    ▼
 PostgreSQL  roadguard_dev on localhost:5432   (Windows service, always running)
```

- The frontend knows where the API is from `VITE_API_URL`, which defaults to `http://localhost:8000/api/v1` (see [`frontend/src/lib/api.ts`](frontend/src/lib/api.ts)).
- The backend only accepts browser requests from the addresses in `CORS_ALLOWED_ORIGINS` (default `http://localhost:5173`).
- Both of these are already set correctly. You only need to change them if you use different ports or addresses.

### Checking that everything is connected

| Check | How | Expected |
|---|---|---|
| Database is running | PowerShell: `Get-Service postgresql-x64-17` | `Status: Running` |
| Backend, database and PostGIS work | Open http://localhost:8000/api/v1/health/ | `{"status": "ok", "database": "PostgreSQL", "postgis": "3.6.2"}` |
| Backend is running | Open http://localhost:8000/api/v1/auth/me/ | `{"detail": "Authentication credentials were not provided."}`. That's correct: it means the API is up and you're just not logged in there |
| Frontend is running | Open http://localhost:5173 | The RoadGuard login page |
| They're connected | Log in at http://localhost:5173 | You reach the dashboard. With sample data loaded, defects appear on the map and in reports |

### Troubleshooting

| Problem | Cause and fix |
|---|---|
| Login page says **"Could not reach the server"** | The backend isn't running. Start Terminal 1 (`runserver`) |
| **"Incorrect email or password"** | Wrong details, or no account exists yet. Run `create_admin` (it also resets the password of an existing account) |
| **"Incorrect code"** | The authenticator code expired or the phone's clock is off. Use the newest code. To reset MFA, run `create_admin` again with the same email |
| **"Request was throttled"** (429) | More than 10 login attempts in a minute. Wait a minute and try again |
| Logged out unexpectedly | Normal after 30 minutes of inactivity, or 8 hours in total. Log in again |
| Dashboard is empty | No defects yet. RoadGuard only holds real data: defects appear when travellers report potholes from the app, or when phones detect them |
| Backend error mentioning `password authentication failed` or `connection refused` | PostgreSQL isn't running, or `.env` has the wrong database details. Check `Get-Service postgresql-x64-17` and the `DB_*` values in `new-backend/.env` |
| Browser console shows a **CORS** error | The frontend is on a different address than `CORS_ALLOWED_ORIGINS` allows, e.g. `127.0.0.1:5174`. Add it in `new-backend/.env` and restart the backend |
| `npm run dev` says port 5173 is in use | Another copy is already running. Close it, or use the address Vite prints and add it to `CORS_ALLOWED_ORIGINS` |
| `runserver` says port 8000 is in use | Another copy is already running. Close the other terminal |
| Mobile app says **"Cannot reach road services"** everywhere | The phone lost its connection to this PC (after a reinstall or restart). See §15, *Restoring the connection* |

---

## 4. Configuration (.env)

All settings live in `new-backend/.env`, which is ignored by git. `.env.example` shows the expected shape.

| Variable | Example | Meaning |
|---|---|---|
| `DJANGO_SECRET_KEY` | *(long random string)* | Signs tokens and invite links. Keep it secret. Generate one with `python -c "from django.core.management.utils import get_random_secret_key as g; print(g())"` |
| `DJANGO_DEBUG` | `True` | Debug mode. Use `False` in production (it also hides `/api/v1/dev/outbox/`) |
| `DJANGO_ALLOWED_HOSTS` | `localhost,127.0.0.1` | Host names the server answers to |
| `DB_NAME` | `roadguard_dev` | PostgreSQL database |
| `DB_USER` | `roadguard` | PostgreSQL user |
| `DB_PASSWORD` | `roadguard_dev_password` | PostgreSQL password |
| `DB_HOST` | `localhost` | Database server address (change this to use a remote server) |
| `DB_PORT` | `5432` | Database server port |
| `CORS_ALLOWED_ORIGINS` | `http://localhost:5173,http://127.0.0.1:5173` | Websites allowed to call the API from a browser |
| `FRONTEND_URL` | `http://localhost:5173` | Used to build activation links in invitation emails |
| `DJANGO_SECURE_COOKIES` | `False` | `True` sends the session cookie over HTTPS only. Turn on when served over HTTPS |
| `AUTH_RATE_LIMIT` | `10/minute` | Login / MFA / activation attempts allowed per IP address |
| `DEFAULT_FROM_EMAIL` | `RoadGuard AI <no-reply@roadguard.local>` | Sender address for emails (optional) |
| **Mobile app services** | | |
| `ROADGUARD_PHOTON_URL` | `https://photon.komoot.io` | Place search and road names (free public server, no uptime guarantee) |
| `ROADGUARD_OSRM_URL` | `https://router.project-osrm.org` | Driving routes (free public demo server, at most 1 request per second) |
| `ROADGUARD_REVERSE_GEOCODE` | `True` | Look up road and region names for new defects |
| **AI engine socket** (§18) | | |
| `ROADGUARD_AI_ENGINE` | `detection.engine.NullEngine` | In-process model class. The default finds nothing; `ai_engine.sensor_model.PotholeEngine` runs the AI team's sensor model (§18) |
| `ROADGUARD_AI_PROCESS_INLINE` | `False` | `True` analyses each sensor batch the moment it's uploaded |
| `ROADGUARD_AI_API_KEY` | *(empty)* | Key for an external AI service (`/api/v1/ai/…`). Empty = those endpoints are off |
| `ROADGUARD_AI_ACCEL_KIND` | `acceleration` | Accelerometer readings the sensor model reads: raw with gravity (as in training) or `linear_acceleration` |
| `ROADGUARD_AI_ALIGN_GRAVITY` | `True` | Turn each window to the training phone orientation (upright portrait) |
| `ROADGUARD_AI_MODEL_PATH` / `ROADGUARD_AI_MODEL_SHA256` | the bundled model / its checksum | The model file, and the checksum it must match before it's loaded |
| **Crowd sensing** (§17) | | |
| `SPOT_RADIUS_M` | `15` | Detections this close together count as the same pothole |
| `SPOT_MIN_CONFIDENCE` | `0.5` | Detections less certain than this are ignored for spots |
| `SPOT_MIN_DEVICES_TO_TRACK` | `2` | Different phones needed before a spot appears in the portal |
| `SPOT_MIN_DEVICES_TO_PUBLISH` | `3` | Different phones needed before drivers are alerted |
| `SPOT_STALE_DAYS` | `30` | A crowd-only spot stops being alerted after this long without new detections |
| `ROADGUARD_PUBLISH_SIMULATED` | `False` | Development only: also alert drivers about spots built from simulated detections |

The frontend has one optional setting: `VITE_API_URL` (default `http://localhost:8000/api/v1`). To change it, put it in `frontend/.env`.

---

## 5. API reference

**One base URL for everything (2026-09-25).** Every backend path, whether portal, mobile app, AI engine, health check, admin site or dev outbox, lives under one base path, `settings.API_PREFIX` (default `api/v1/`, set with `ROADGUARD_API_PREFIX` in `.env`), defined once in [`config/urls.py`](new-backend/config/urls.py). Each client builds every request from one setting:

| Client | Its one setting | Paths are relative to it |
|---|---|---|
| Web portal | `VITE_API_URL` = `http://localhost:8000/api/v1` ([`frontend/src/lib/api.ts`](frontend/src/lib/api.ts)) | `/defects/`, `/auth/login/`, … |
| Mobile app | `ROADGUARD_API_URL` = server address (`http://127.0.0.1:8000`) + `apiPrefix` (`api/v1/`) in `lib/core/config/api_config.dart` | `mobile/auth/login/`, `graphql/anonymous/`, … |

If you change the prefix, change it in the backend `.env`, `VITE_API_URL` and `apiPrefix` together.

All endpoints are under `http://localhost:8000/api/v1/`. Every route ends with a `/`. Request and response bodies are JSON. Errors come back as `{"detail": "message"}`, or for invalid input as `{"field": ["message", ...]}`.

### Authentication, `auth_views.py`

| Method | Path | Login needed | What it does |
|---|---|---|---|
| POST | `auth/login/` | No | Step 1: `{email, password}` → `{mfa_required: true, pending_token}` |
| POST | `auth/verify-mfa/` | No | Step 2: `{pending_token, code}` → the user, plus the session cookie |
| POST | `auth/accept-invite/` | No | `{token, password}` → `{email, mfa_setup_key, qr_code_data_uri}` |
| GET | `auth/me/` | Yes | The logged-in user `{id, name, email, role}`, or 401 |
| POST | `auth/logout/` | Yes | Ends the session (204) |

### Data, `views.py`

| Method | Path | Who | What it does |
|---|---|---|---|
| GET | `defects/` | Any user | List defects, newest first. Filters: `?status=`, `?severity=`, `?region=`, `?source=` |
| POST | `defects/` | Admin | Create a defect |
| GET | `defects/<id>/` | Any user | One defect |
| PATCH | `defects/<id>/` | Any user* | Review it (`status`, `review_note`). *Other fields: Admin only |
| PUT / DELETE | `defects/<id>/` | Admin | Replace or delete a defect |
| GET | `authorities/` | Any user | List authorities. Filter: `?status=` |
| POST | `authorities/` | Admin | Create an authority |
| GET / PUT / PATCH / DELETE | `authorities/<id>/` | GET: any user; others: Admin | One authority |
| GET | `users/` | Any user | List portal users. Filters: `?role=`, `?status=` |
| POST | `users/invite/` | Admin | Invite a new user (see §7) |
| GET / PUT / PATCH / DELETE | `users/<id>/` | GET: any user; others: Admin | One user |
| GET | `audit-log/` | Admin | Audit entries, newest first. `?limit=` (default 200, max 1000), `?action=`, `?actor_email=`, `?resource_type=`, `?resource_id=` |
| GET | `defects/<id>/photo/` | Any user | The traveller's JPEG attached to a mobile-app report (404 if none). Shown in the Reports and Map panels (§9) |
| GET | `defects/<id>/detections/` | Any user | The sensor detections grouped into this spot: phones, times, confidence, intensity |

IDs are readable strings: defects `RG-00001`, authorities `AUTH-001`, users `USR-001`.

### Mobile app, `mobile/views.py`

| Method | Path | Sign-in | What it does |
|---|---|---|---|
| POST | `/api/v1/mobile/auth/register/` | No | `{name, email, password}` (password ≥ 12 characters) → `{user, token, expiresAt}` |
| POST | `/api/v1/mobile/auth/login/` | No | `{email, password}` → `{user, token, expiresAt}` |
| GET | `/api/v1/mobile/auth/session/` | Bearer token | `{user, expiresAt}`, or 401 when the token has expired |
| POST | `/api/v1/mobile/auth/logout/` | Bearer token | Ends the session: `{ok: true}` |
| POST | `/api/v1/anonymous/report-photos/` | None allowed | Multipart field `photo` (JPEG/PNG ≤ 15 MB) → `{photoToken, expiresAt}` (15 minutes) |
| POST | `/api/v1/graphql/anonymous/` | None allowed | `submitAnonymousReport`, `publicHazards`, `searchPlaces`, `drivingRoutes`. Schema: [`mobile/graphql/anonymous.graphql`](new-backend/mobile/graphql/anonymous.graphql) |
| POST | `/api/v1/graphql/mobile/` | Bearer token | `grantCollectionConsent`, `uploadTelemetry`, `revokeCollectionConsent`, `revokeMyCollectionConsents`. Schema: [`mobile/graphql/mobile.graphql`](new-backend/mobile/graphql/mobile.graphql) |

Traveller accounts are separate from portal users. A traveller token can't open the portal, and anonymous endpoints refuse any request that carries a cookie or token, so a report can't be linked to a person. Mobile errors come back as `{"error": "message"}` for REST calls, and as `{"errors": [{"message"}]}` for GraphQL.

### AI engine service, `detection/views.py` (header `Authorization: Api-Key <ROADGUARD_AI_API_KEY>`)

| Method | Path | What it does |
|---|---|---|
| POST | `/api/v1/ai/batches/claim/` | `{limit}` → the next pending sensor batches, with readings and 5 s of context |
| POST | `/api/v1/ai/batches/<batchId>/results/` | `{modelVersion, detections: [...]}`, or `{modelVersion, error}` |
| GET | `/api/v1/ai/status/` | How many batches are pending, processing, done or failed |

Field-by-field details: [`new-backend/docs/AI_ENGINE_CONTRACT.md`](new-backend/docs/AI_ENGINE_CONTRACT.md).

### Example: a defect

```json
{
  "id": "RG-00118",
  "hazard_type": "Pothole",
  "road": "Morogoro Road",
  "region": "Dar es Salaam",
  "severity": "high",
  "status": "Verified",
  "source": "device",
  "confidence": 94.0,
  "observation_count": 6,
  "detected_at": "2026-09-18T09:42:00Z",
  "lat": -6.7924,
  "lng": 39.2083,
  "has_photo": false,
  "review_note": "Confirmed on site",
  "reviewed_by": "Jane Doe",
  "reviewed_at": "2026-09-24T13:30:39Z",
  "notes": "",
  "device_count": 4,
  "severity_score": 0.82,
  "last_detected_at": "2026-09-24T12:10:02Z",
  "published_at": "2026-09-23T08:15:40Z",
  "is_simulated": false
}
```

The last six fields are read-only.
- `notes` is the traveller's note on a mobile report.
- The rest are the crowd-sensing numbers (§17): how many different phones detected the spot, its measured severity (0–1), when a phone last hit it, and when drivers started being alerted.

Allowed values: `hazard_type` is `Pothole` (road cracks are out of scope and rejected). `severity` is `low` / `medium` / `high`. `status` is `New` / `Verified` / `Under Repair` / `Resolved`. `source` is `manual` / `device`. User `role` is `Admin` / `TARURA Officer`. User and authority `status` is `Active` / `Inactive`.

### Other pages

| URL | What |
|---|---|
| http://localhost:8000/api/v1/dev/outbox/ | Emails the portal "sent" (only when `DJANGO_DEBUG=True`, see §11) |
| http://localhost:8000/api/v1/admin/ | Django's admin site, for looking at the data. Needs a Django superuser: `manage.py createsuperuser`. These accounts are separate from portal users |
| http://localhost:8000/api/v1/defects/ in a browser | DRF's browsable API. You must be logged in through the portal first, because it uses the same cookie |

---

## 6. How login with MFA works

```
 Browser                                   Django
   │ POST /api/v1/auth/login/ {email, password}  │  checks the password hash
   │ ────────────────────────────────────────▶│
   │ ◀──────── {pending_token}                │  signed, valid 5 minutes, grants no access
   │                                          │
   │ POST /api/v1/auth/verify-mfa/               │  checks the 6-digit authenticator code
   │      {pending_token, code}               │
   │ ────────────────────────────────────────▶│  creates an AdminSession row
   │ ◀──────── user + Set-Cookie: roadguard_session (httpOnly)
   │                                          │
   │ any later request (cookie sent automatically)
   │ ────────────────────────────────────────▶│  PortalSessionAuthentication checks the session
```

- **Password storage:** passwords are stored only as salted hashes (Django's PBKDF2). The plain password is never saved.
- **MFA codes:** they're standard TOTP codes, the kind every authenticator app generates. They change every **60 seconds**, and the code just before or after the current one is also accepted. Some apps, such as Google Authenticator, always use 30 seconds; those codes still work.
- **Session limits:** a session ends after **30 minutes without activity**, or **8 hours** in total, whichever comes first.
- **Logout:** it deletes the session on the server, so a copied cookie stops working.
- **Deactivated users:** deactivating a user logs them out immediately.
- **Wrong email or wrong password:** both give the same error, so the login page can't be used to discover which emails have accounts.
- **Rate limit:** login, MFA and activation are limited to **10 attempts per minute per IP address**. The limit can be changed in `.env`.
- **The session cookie:** it is `httpOnly`, so page scripts can't read it, and `SameSite=Lax`, so it isn't sent on requests started by other websites. It's `Secure` when `DJANGO_SECURE_COOKIES=True`.

**Lost your authenticator app?** Run `manage.py create_admin` again with the same email. It resets the password and MFA secret and logs out all of that account's sessions.

---

## 7. Inviting and activating users

1. An Admin opens **Users & Authorities → Add user** and fills in name, email, role and authority. The page calls `POST /api/v1/users/invite/`.
2. The account is created as **Inactive**, with no password and no MFA yet.
3. An email with an activation link is sent. In development it's saved to the outbox (§11). The link looks like `http://localhost:5173/activate?token=...` and is valid for **7 days**.
4. The invitee opens the link and chooses a password of at least 8 characters. The page calls `POST /api/v1/auth/accept-invite/`.
5. The account becomes **Active**, and the page shows a QR code, plus the setup key as a backup, to add to an authenticator app.
6. The invitee can now log in. The link cannot be used a second time.

The Admin never sees or chooses the invitee's password or MFA secret.

---

## 8. Who can do what (roles)

| Action | TARURA Officer | Admin |
|---|:---:|:---:|
| View dashboard, map, reports, users, authorities | ✅ | ✅ |
| Review a defect (change status / add a review note) | ✅ | ✅ |
| Create, edit other fields of, or delete defects | ❌ | ✅ |
| Invite, edit, deactivate or delete users | ❌ | ✅ |
| Add or edit authorities | ❌ | ✅ |
| Read the audit log | ❌ | ✅ |

Safety rules: an Admin **can't deactivate, demote or delete their own account**. This stops the last Admin from locking everyone out.

The rules are in [`permissions.py`](new-backend/roadguard/permissions.py) and on each view in [`views.py`](new-backend/roadguard/views.py).

---

## 9. Defect review stamping

When anyone changes a defect's `status` or `review_note`, the server records:

- `reviewed_by`: the **logged-in user**. The API returns their name, for example "Last reviewed by Jane Doe".
- `reviewed_at`: the current time.

These two values always come from the session. If a request sends `reviewed_by` or `reviewed_at`, they are ignored, so no one can claim a review was done by someone else. Each review also creates a `defect.reviewed` audit entry.

### Seeing the traveller's photo

A pothole reported from the mobile app comes with the photo the traveller took. Officers and Admins see it while reviewing:

- **Reports** page → click a report → the review panel shows the photo under *Camera evidence*.
- **Map** page → click a marker → **View Details** → same photo.
- Click the photo to see it full-screen. Click anywhere or press **Esc** to close.

How it works:

| Part | File | What it does |
|---|---|---|
| Backend | `roadguard/views.py`: `DefectPhotoView` | `GET /api/v1/defects/<id>/photo/` returns the JPEG to **logged-in portal users only** (401 otherwise). Sent with `Cache-Control: private, no-store`, so browsers don't keep a copy |
| Backend | `roadguard/serializers.py` | `has_photo` is `true` only when an image is really stored (sample defects had the flag without an image) |
| Frontend | `src/lib/defects.ts`: `fetchDefectPhoto()` | Loads the photo **with axios** (`responseType: 'blob'`), so the login cookie is sent |
| Frontend | `src/components/reports/DefectPhoto.tsx` | Shows it: loading state, thumbnail, full-screen view, and a clear message if the photo can't be loaded |

The photo was re-encoded when uploaded (`mobile/reports.py`), so it has **no GPS or camera metadata**. The traveller's identity is never attached: reports are anonymous.

---

## 10. Audit log

Every important action is recorded in the `audit_log` table: who did it, what, to which record, when, and from which IP address.

| Action | When |
|---|---|
| `auth.login_succeeded` / `auth.login_failed` / `auth.mfa_failed` / `auth.logout` | Logging in and out |
| `user.invited` / `account.activated` | Invitations |
| `user.updated` / `user.deleted` | User changes (with the list of changed fields) |
| `authority.created` / `authority.updated` / `authority.deleted` | Authority changes |
| `defect.created` / `defect.updated` / `defect.reviewed` / `defect.deleted` | Defect changes |
| `defect.reported` | A traveller's anonymous photo report arrived from the mobile app (actor `mobile:anonymous`, no IP stored) |
| `defect.auto_created` / `defect.auto_published` | Crowd sensing created a spot from several phones' detections, or started alerting drivers (actor `system:crowd-sensing`) |

Read it with `GET /api/v1/audit-log/` (Admins only), or at http://localhost:8000/api/v1/admin/. The admin site shows it read-only: entries can't be edited or deleted there.

If a user is deleted, their audit entries stay, and `actor_email` still says who it was.

---

## 11. Emails during development

No real mail server is set up yet. Outgoing emails, currently only invitations, are **saved in the database** (table `outbox_emails`) instead of being sent. To read them and click activation links, open:

**http://localhost:8000/api/v1/dev/outbox/**

This page exists only when `DJANGO_DEBUG=True`.

To send real email later, change `MAILERS` in [`config/settings.py`](new-backend/config/settings.py) to Django's SMTP backend and add the mail server details. No other code needs to change.

---

## 12. How the frontend calls the API (axios)

All HTTP calls go through **one axios instance** in [`frontend/src/lib/api.ts`](frontend/src/lib/api.ts):

```ts
export const api = axios.create({
  baseURL: import.meta.env.VITE_API_URL ?? 'http://localhost:8000/api/v1',
  withCredentials: true,              // send the session cookie with every request
  headers: { 'Content-Type': 'application/json' },
})
```

- **Errors:** a response interceptor turns every failed request into an `ApiError(message, status)`. The pages catch it and show `err.message`. It understands both of DRF's error formats.
- **Helper functions:** `apiGet`, `apiPost` and `apiPatch` wrap the instance, and the data modules (`defects.ts`, `authorities.ts`, `users.ts`, `auth.ts`) call them.
- **Field names:** each data module converts the API's snake_case fields (`coverage_area`) to the frontend's camelCase (`coverageArea`).

Before axios, the same file was a small wrapper around the browser's built-in `fetch()`. axios now does the work that wrapper did by hand: building URLs, encoding and decoding JSON, and treating 4xx/5xx responses as errors.

**Cross-origin setup:** the frontend (port 5173) and API (port 8000) are different origins. The browser therefore only allows the requests because Django sends CORS headers for the origins in `CORS_ALLOWED_ORIGINS`, and allows cookies with `CORS_ALLOW_CREDENTIALS = True`.

---

## 13. Running the tests

```powershell
cd "D:\ROADGUARD\Web portal\new-backend"
.venv\Scripts\python manage.py test            # everything (90 tests)
.venv\Scripts\python manage.py test roadguard  # or one app: roadguard, mobile, detection, ai_engine
```

| App | Tests | What they cover |
|---|---|---|
| `roadguard` | 24 | Portal login + MFA, logout, wrong password or code, forged tokens, idle expiry, deactivation, rate limiting, invite → activate → login, role permissions, review stamping, audit log, email outbox, traveller photo (login required, `has_photo` only when stored) |
| `mobile` | 35 | Traveller register/login/session/logout; photo sanitising (EXIF removed); report → `New` defect, retries, expired photo token; crack reports rejected; GPS rules (≤ 0.5 m/s accepted, faster or > 25 m refused); what `publicHazards` shows (confirmed, crowd, stale, simulated, map area); OSRM steps (faked); route timing (steps late → quick route; late reply cached for the retry; polyline decoding); gzip replies (zip bombs refused); road/region names; Photon search (faked); shared 1 request/second limit waits instead of failing; consent + telemetry upload, retries, withdrawal, mocked GPS; notice v2 required; an upload still succeeds if the model can't load |
| `detection` | 20 | Spots created at 2 phones and published at 3; same phone counted once; distance and confidence rules; combined confidence and severity maths; corroborating a photo report; resolved defects not reopened; in-process engine; failing engine; the external AI HTTP API (keys, claims, results, validation); the portal's AI engine card; "shown to drivers" matches the app's rule |
| `ai_engine` | 11 | The sensor model: the notebook's own example reproduced exactly; features and model columns match; a real pothole found once through batching and the real pipeline; smooth road and slow driving give nothing; a turned phone still works; an old-app batch and an altered model file are refused |

Django runs them against a **temporary test database** (`test_roadguard_dev`) that is deleted afterwards, so your real data is never touched. External services (OSRM, Photon) are faked in the tests, so they don't need internet access.

Mobile app:

```powershell
cd "D:\ROADGUARD\Mobile app"
flutter test test/domain/navigation_guide_test.dart   # the 8 navigation tests
flutter test                                          # the whole suite
```

> **Flutter suite: 154 pass, 0 fail** (2026-09-25). `flutter analyze` reports no issues.
>
> **Demo mode removed (production app):**
> - **Removed from the app:** sample hazards and routes, the sample map and alert, the "sample routes" banner, the sample-photo generator, the voice "demo warning", the presentation-mode switch (`ROADGUARD_PRESENTATION`), and every `isDemo` flag and DEMO / SAMPLE / PREVIEW label.
> - **Old data:** demo reports or alerts saved on a phone by an older build are skipped when loading, so they can never be shown or uploaded as real. A very old saved trip without a route map gets a neutral "can't resume" screen.
> - **Tests:** they now use their own fixtures (`test/support/photos.dart`, inline routes). Tests that only covered demo behaviour were deleted.
> - **Also fixed:** `trip_collection_test.dart`, which didn't compile (missing `permissions` argument).
>
> **Fixed on 2026-09-25:**
> - **GPS safety rules (4 tests):** the app and backend now agree (§15, *Reporting rules*).
> - **44 tests written for older screens:** rewritten for the current screens, keeping what each one checks. Tests of removed features (the sample-report mode, the trip hazard list) were deleted or replaced with checks of the current screen.
> - **Real app bugs these tests exposed, now fixed in the app:**
>   - Onboarding pages overflowed with large text or in landscape; they now scroll.
>   - The trip's bottom sheet could be taller than the screen and cover the map and My location button. It's now capped at 55% of the screen, and its Pause / Finish trip buttons are always visible.
>   - The trip screen showed no speed and no GPS error. It now shows the speed, or the problem with **Retry location** and **Open location settings** buttons.
>   - A denied location permission on Explore failed silently. It now explains itself, with an **Open settings** button.
>   - The "Loading map tiles…" label blocked dragging the map. It no longer catches touches.
>   - A photo could be taken while the app was in the background. It can't any more.
>   - The bottom tabs didn't tell screen readers which tab is selected. They do now.
>   - Map pins and the hazard count called every hazard "confirmed". Crowd-reported hazards are now labelled as such.
>   - The privacy page said guests can use the app without an account, which is no longer true since sign-in is required.

Frontend checks:

```powershell
cd "D:\ROADGUARD\Web portal\frontend"
npm run build        # type-checks and builds
npx oxlint src       # lint
```

---

## 14. Useful commands

Run these from `new-backend/`, with `.venv\Scripts\python manage.py <command>`.

| Command | What it does |
|---|---|
| `runserver` | Start the API on port 8000 |
| `migrate` | Apply database migrations |
| `makemigrations roadguard` | Create a new migration after changing `models.py` |
| `create_admin` | Create or reset a portal Admin: prints the MFA QR code and setup key. Non-interactive: `--email --name --password` |
| `createsuperuser` | Create a login for the Django admin site (`/api/v1/admin/`) |
| `process_telemetry` | Run the in-process AI engine over new sensor batches. `--loop 10` keeps it running |
| `simulate_detections --lat -6.7924 --lng 39.2083 --devices 3` | Fake detections from several phones, to try spots and alerts without the AI |
| `purge_expired_photos` | Delete uploaded report photos that no report claimed. Safe to schedule |
| `test` | Run the tests |
| `check` | Check the project for configuration problems |

---

## 15. Connecting the mobile app

The Flutter app (`D:\ROADGUARD\Mobile app`) talks to this same backend. It was built for a slightly different backend, and `new-backend/mobile/` reproduces the same URLs, GraphQL names and JSON, so the app connects without changes to how it talks to the server.

```
 Phone (Flutter app)
   ├─ REST     /api/v1/mobile/auth/...          traveller accounts (bearer token)
   ├─ REST     /api/v1/anonymous/report-photos/ photo for a report (no identity)
   ├─ GraphQL  /api/v1/graphql/anonymous/           report, live hazards, place search, routes (no identity)
   └─ GraphQL  /api/v1/graphql/mobile/              sensor-data consent + uploads (bearer token)
                         │
                   new-backend (Django)  ──►  PostgreSQL + PostGIS  ◄──  web portal (officers)
```

**Running it on a phone (USB):**

1. Start the backend (`runserver`, Terminal 1).
2. Connect the Android phone by USB with USB debugging on, then run `adb reverse tcp:8000 tcp:8000`. The phone's `127.0.0.1:8000` now reaches this PC.
3. Run `flutter run --dart-define=ROADGUARD_API_URL=http://127.0.0.1:8000` from `D:\ROADGUARD\Mobile app`.

The app accepts plain `http://` only for `localhost` in debug builds. Any other address, including this PC's Wi-Fi address, must be `https://`, so use the USB tunnel for local testing and HTTPS for a deployed server.

**Running it over Wi-Fi (no cable):** the app still uses `http://127.0.0.1:8000`, and a *wireless* ADB tunnel carries that to this PC. No app change and no firewall rule are needed.

1. Put the phone on the same network as the PC. On this PC that's the **Windows Mobile Hotspot** (PC = `192.168.137.1`).
2. Make sure the app was **built with the server address** (a debug build). Otherwise it shows *"Account connection is not configured"*:
   ```powershell
   cd "D:\ROADGUARD\Mobile app"
   flutter build apk --debug --dart-define=ROADGUARD_API_URL=http://127.0.0.1:8000
   adb install -r build\app\outputs\flutter-apk\app-debug.apk
   ```
3. With the backend running, run (the first time, with the phone plugged in by USB):
   ```powershell
   powershell -ExecutionPolicy Bypass -File "D:\ROADGUARD\Mobile app\tool\connect_wifi.ps1"
   ```
   It switches ADB to Wi-Fi, checks `/api/v1/health/`, creates the tunnel (`adb reverse tcp:8000 tcp:8000`) and opens the app. Then unplug the cable.
4. **Re-run the script** after the phone or PC restarts, the Wi-Fi/hotspot changes, or the app is reinstalled: the tunnel doesn't survive these. Without a cable, pass the address from *Developer options → Wireless debugging*: `connect_wifi.ps1 -Device 192.168.137.146:5555`.

#### Restoring the connection

**Signs the connection is lost:** the app says *"Cannot reach road services"* or *"Cannot reach account services"* on every screen, and the backend terminal shows no new requests from the phone.

**First check the backend is running** (in any PowerShell window):

```powershell
curl.exe http://127.0.0.1:8000/api/v1/health/
# expected: {"status":"ok","database":"PostgreSQL","postgis":"3.6.2"}
```

If it doesn't answer, start it (Terminal 1, §3) before anything else.

Then pick the case that matches what happened:

| What happened | What to do |
|---|---|
| App was reinstalled, or VS Code / `flutter run` re-installed it | The ADB link is still there, only the tunnel is gone: `adb -s 192.168.137.146:5555 reverse tcp:8000 tcp:8000` |
| PC restarted, or ADB was restarted (`adb kill-server`) | `adb connect 192.168.137.146:5555` then `adb -s 192.168.137.146:5555 reverse tcp:8000 tcp:8000` |
| **Phone** restarted | The phone forgets Wi-Fi ADB mode. Plug in the USB cable once and run `connect_wifi.ps1` (no arguments). Unplug afterwards |
| Hotspot/Wi-Fi changed, or the phone got a new address | Find the phone's new IP: Windows **Settings → Network & internet → Mobile hotspot** lists connected devices, or on the phone **Settings → About phone → IP address**. Then `connect_wifi.ps1 -Device <new IP>:5555` (or with USB, no arguments) |
| Not sure | Plug in the USB cable and run `connect_wifi.ps1` with no arguments: it redoes every step |

The script in one go:

```powershell
powershell -ExecutionPolicy Bypass -File "D:\ROADGUARD\Mobile app\tool\connect_wifi.ps1"                              # phone on USB
powershell -ExecutionPolicy Bypass -File "D:\ROADGUARD\Mobile app\tool\connect_wifi.ps1" -Device 192.168.137.146:5555  # no cable
```

The same steps by hand, if the script can't be used:

```powershell
adb devices                                          # the phone must be listed as "device"
adb connect 192.168.137.146:5555                     # Wi-Fi link (use the phone's current IP)
adb -s 192.168.137.146:5555 reverse tcp:8000 tcp:8000   # the tunnel
adb -s 192.168.137.146:5555 reverse --list           # must show: tcp:8000 tcp:8000
```

**Check it worked:** open the app and search for a place (e.g. "Dodoma"). Results should appear, and the backend terminal shows `POST /api/v1/graphql/anonymous/ ... 200`.

If `adb devices` shows the phone as **`unauthorized`**, unlock the phone and accept the *"Allow USB debugging?"* prompt. If it shows **`offline`**, run `adb disconnect` and connect again.

If the app says **"Account connection is not configured"**, the tunnel is fine: the app was built without the server address. Rebuild it with `--dart-define=ROADGUARD_API_URL=http://127.0.0.1:8000` (step 2 above). The VS Code **"Mobile app"** launch setting already includes it.

Verified 2026-09-25 on a Pixel 4 (Android 13): a login attempt from the phone reached the server over Wi-Fi (`POST /api/v1/mobile/auth/login/ 401`), and the app showed the server's reply.

**What connects to what:**

| In the app | Backend | Result in the portal |
|---|---|---|
| Profile → Create account / Log in | `/api/v1/mobile/auth/...` | A traveller account (separate from portal users) |
| Report a pothole (photo, standing still, GPS ≤ 25 m) | photo upload + `submitAnonymousReport` | A **`New` defect**, source `manual`, with photo (viewable in the portal, §9), note, and road/region looked up from the position |
| Explore map / Alerts | `publicHazards` every 5 s | Shows **Verified** and **Under Repair** defects, and crowd-reported spots (§17) |
| Destination search | `searchPlaces` (Photon) | — |
| Directions → Start | `drivingRoutes` (OSRM) + turn-by-turn steps | — |
| Trip → Sensor sharing (signed in) | `grantCollectionConsent` + `uploadTelemetry` | Sensor batches waiting for the AI engine (§18) |

**Reporting rules (GPS): the app and the backend enforce the same limits.** Before 2026-09-25 the app accepted speeds up to 0.5 m/s and accuracy up to 50 m, while the backend demanded exactly 0 m/s and 25 m. So a report the app let you save could be **refused on upload**. The agreed rules are now identical on both sides:

| Rule | Limit | Why |
|---|---|---|
| Standing still | GPS speed **≤ 0.5 m/s** (1.8 km/h) | A phone at rest often reports small speed drift, so demanding exactly 0 blocked genuine reports |
| GPS accuracy | **≤ 25 m** | A vaguer position can't locate the pothole, or be matched with sensor detections (grouped within 15 m) |
| Freshness | GPS fix ≤ 10 s old, not in the future | The position must be where the phone was when the photo was taken |
| Real GPS | Not mocked | Only genuine evidence is accepted (the app has no demo mode) |
| Category | **Potholes only** | Road cracks are outside RoadGuard's scope; a crack report is refused with a clear message (2026-09-25) |

⚠️ The 0.5 m/s allowance is a **deliberate exception to the SRS**, which asks for strictly zero speed. To restore the strict rule, set `MAX_STATIONARY_SPEED_MPS = 0` in [`mobile/reports.py`](new-backend/mobile/reports.py) **and** `stationarySpeedThresholdMps: 0` in the app's `lib/core/models/safety_policy.dart`. Always change both together.

**What drivers see is decided by `publicHazards`** ([`mobile/hazards.py`](new-backend/mobile/hazards.py)):

| Portal status | Shown to drivers? |
|---|---|
| New: a traveller's photo report nobody has checked yet | ❌ Not until an officer verifies it, or enough phones detect the same spot |
| New: crowd spot confirmed by ≥ 3 different phones | ✅ As "reported by drivers, not yet verified" |
| Verified / Under Repair | ✅ As "confirmed" |
| Resolved | ❌ Removed from the map |

**App changes made for this:**
- **Turn-by-turn navigation** (§16).
- **Hazard wording:** alerts now say "confirmed" only when an officer confirmed the hazard.
- **Sensor sharing reachable again:** its controls had been left inside commented-out code, so the option couldn't be reached. There's now a **Sensor sharing** button on the trip screen.


---

## 16. Navigation (turn-by-turn)

The trip screen now guides the driver the way Google Maps or Waze do:

- **Directions banner:** the next manoeuvre with its arrow and distance ("300 m · Turn left onto Morogoro Road"), plus "Then …" when two manoeuvres come close together.
- **Voice directions:** an early heads-up ("In 350 metres, turn left onto …"), a reminder close to the turn, and "Turn left onto …" at the turn. Prompts come earlier at higher speed, each is spoken once, and they wait a few seconds after a hazard warning so they never talk over it. Voice follows the app's voice setting.
- **Live time and distance remaining**, and an updated arrival time.
- **Automatic rerouting:** after three GPS fixes in a row clearly off the route (more than 50 m, with more slack when GPS is poor), the app says "Rerouting" and asks for a new route from the current position to the same destination, at most once every 30 seconds.
- **Arrival:** "You have arrived at your destination".
- **Pothole warnings along the route** keep working as before, now labelled "confirmed" or "reported by drivers".

Where it lives:
- **Backend:** [`mobile/routing.py`](new-backend/mobile/routing.py) asks OSRM for `steps=true`, turns each manoeuvre into English text, and sends it as `stepsJson`. Each step includes `alongMeters`, its position along the route.
- **App:** `lib/modules/trips/presentation/providers/navigation_guide.dart` holds the logic (progress, next manoeuvre, off-route check, voice prompts, all unit-tested), and `live_services_screens.dart` (`LiveTripScreen`) shows it.

Limits:
- **Foreground only:** guidance runs only while the trip screen is open. It stops when the app goes to the background, like location does.
- **No live traffic:** the public OSRM demo server has no traffic data and no lane guidance.
- **Old trips:** routes saved before this change have no steps, and show "no turn-by-turn guidance".

**On a slow internet connection** (checked 2026-09-25 from Dodoma: a 735 km route reply is ~200 KB with steps). The app waits at most 20 s, so the backend keeps within that:

| Measure | What it does |
|---|---|
| Compressed replies | Map services are asked for **gzip**, so replies are several times smaller. Decompression stops at the size cap, so a malicious reply can't fill memory |
| Two requests side by side | One **with** turn-by-turn steps, one **without** (smaller). The detailed one is used if it arrives within ~14 s, otherwise the plain one, always within 16 s. Without steps the route is still drawn and followed, just without spoken turns |
| Route cache (15 min) | A reply that arrives **after** the app gave up is kept. Choosing the same destination again from about the same place (within ~11 m) is answered **instantly**, with steps when they arrived |
| Waiting its turn | The free OSRM and Photon servers allow 1 request per second. A request arriving right after another now waits up to 1.5 s instead of failing with "busy" |

If the app says *"Live routing is unavailable"*, the PC's internet was too slow for that attempt. Choose the destination again: the retry usually comes from the cache.

**Trip times** are shown as "45 min", or "9 h 19 min" for long trips (was "559 min"). The formatting is in the app's `lib/core/utils/trip_time.dart`.

---

## 17. Crowd sensing: many drivers, one spot, one severity

When the AI engine reports a pothole in a driver's sensor data, that's one **detection**. [`detection/spots.py`](new-backend/detection/spots.py) combines the detections of many drivers into one monitored **spot** (a `Defect`):

```
 driver A's phone ─┐
 driver B's phone ─┼─ detections within 15 m ──► one spot ──► portal (2+ phones)
 driver C's phone ─┘                                     └──► drivers alerted (3+ phones)
```

- **Same pothole:** detections within `SPOT_RADIUS_M` (15 m) of each other, measured by PostGIS in real metres. A detection near an existing open defect, including a traveller's photo report, joins it and corroborates it.
- **Monitored:** once **2 different phones** agree, the spot appears in the portal as a `New` defect with source `device`.
- **Alerted:** once **3 different phones** agree, drivers are warned ("reported by drivers, not yet verified"). An officer's **Verified** makes it "confirmed". **Resolved** removes it.
- **Severity of the spot:**
  - `severity_score` is the confidence-weighted average of how hard each phone hit it (0–1).
  - It's shown as `low` below 0.4, `medium` below 0.7, and `high` above.
  - `confidence` combines the phones: 1 − Π(1 − each phone's best confidence). For example, three phones at 80 % give 99.2 %.
  - `device_count` and `observation_count` show how much evidence there is.
  - The spot's position is the confidence-weighted centre of the hits.
- **Officer review:** once an officer has reviewed a spot, their severity and position are kept, and only the counts keep updating.
- **Expiry:** a crowd-only spot with no new detection for 30 days stops being alerted.
- **Counting phones:** each phone counts once, however often it hits the spot. Phones are identified by a keyed hash of the traveller account, so they're counted without storing who they are.

All thresholds are settings (§4). Officers can see the evidence behind a spot at `GET /api/v1/defects/<id>/detections/`. Every automatic step is written to the audit log (`defect.auto_created`, `defect.auto_published`).

**Try it without the AI:** `manage.py simulate_detections --lat -6.7924 --lng 39.2083 --devices 3`. Simulated spots show in the portal, but are only alerted to drivers when `ROADGUARD_PUBLISH_SIMULATED=True`.

---

## 18. The AI engine socket

The AI model isn't ready yet, so the backend has a ready-made **socket** for it. Everything around the model already works: collecting data, storing detections, grouping, severity and alerts. The model only has to answer "where and when did this phone hit a pothole?" for each sensor batch.

Two ways to connect it:

| | In-process (Python) | Separate service (any language) |
|---|---|---|
| How | Subclass `DetectionEngine` in [`detection/engine.py`](new-backend/detection/engine.py), implement `analyze(batch)`, set `ROADGUARD_AI_ENGINE=your.module.YourEngine` | The service calls `POST /api/v1/ai/batches/claim/`, runs the model, then `POST /api/v1/ai/batches/<id>/results/`, authenticated with `ROADGUARD_AI_API_KEY` |
| Runs | `manage.py process_telemetry --loop 10`, or on every upload with `ROADGUARD_AI_PROCESS_INLINE=True` | Wherever the model lives (e.g. a GPU machine) |

Every uploaded batch waits as `pending` until the engine answers. It then becomes `done` (with zero or more detections) or `failed` (with the error). A claimed batch that gets no answer within 10 minutes is offered again. Detections are checked before they're stored: they must fall within the batch's time span and within 150 m of where the phone actually was.

**Hand this to the AI team:** [`new-backend/docs/AI_ENGINE_CONTRACT.md`](new-backend/docs/AI_ENGINE_CONTRACT.md) describes the exact input (sensor kinds, units, axes, context window) and output, with code and HTTP examples.

Until then, the default `NullEngine` marks batches as processed without finding anything.

### The sensor model is connected (2026-09-25)

The AI team's Random Forest (`ai/Intelligent-Pothole-Detection`) runs in-process as **`ai_engine.sensor_model.PotholeEngine`**. Switch it on in `.env`:

```
ROADGUARD_AI_ENGINE=ai_engine.sensor_model.PotholeEngine
ROADGUARD_AI_PROCESS_INLINE=True
```

**Restart `runserver` fully after changing `.env`** (Ctrl+C, start again). Its auto-reload keeps the values it started with.

| File | What it does |
|---|---|
| `ai_engine/models/pothole_model_bundle.pkl` + `MODEL.md` | The model, its origin, metrics and checksum |
| `ai_engine/preprocessing.py` | The phone's separate 10 Hz accelerometer and gyroscope events → one 5 Hz timeline (nearest real reading per 0.2 s tick); m/s² → g; each window turned to the training orientation |
| `ai_engine/features.py` | The 34 features, copied from the AI team's notebook (cells 3 and 19) |
| `ai_engine/sensor_model.py` | 2-second windows on a fixed clock, 10 km/h speed gate, probability ≥ 0.37 → detection at the strongest jolt, hit strength 0–1, repeats merged. The model file is only loaded if its checksum matches and the scikit-learn version is the same |
| `ai_engine/tests.py` | Reproduces the notebook's own example exactly (0.4097), finds a real marked pothole once, nothing on smooth road or below 10 km/h, works with the phone turned, refuses an altered model file |

**What the app sends for it:** the raw accelerometer (`acceleration`, gravity included) instead of the gravity-removed one. The sharing notice is now **version 2**, so drivers accept the new wording once.

**How good is it?** Replaying the five training trips (13.5 km) through the whole engine found 92 of 96 potholes, with about 2 false alarms per km per phone. It has never seen Tanzanian roads or Android phones, so expect worse. The 3-phone rule (§17) keeps single-phone false alarms away from drivers. Open points for the AI team are listed in `ai_engine/models/MODEL.md`.

**In the portal:**
- The Dashboard's **AI engine** card shows the model, batches waiting, analysed and failed, and detections.
- Each defect's panel shows the phones, confidence, severity score and the individual detections, and whether drivers are being warned.

---

## 19. PostGIS

PostGIS 3.6.2 is installed on this PC's PostgreSQL 17 and enabled in `roadguard_dev` and `template1`.

- **Where it's used:** the `defects`, `sensor_readings` and `detections` tables each have a `location` column of type `geography(Point, 4326)`, which PostgreSQL **computes itself** from `lat`/`lng`. The columns are created with raw SQL in the migrations, so they can never disagree with the numbers. Each has a GiST spatial index.
- **What it's used for:**
  - "Within 15 m" when grouping detections into spots (`ST_DWithin`, real metres on the Earth's surface).
  - "Inside this map area" for the app's live hazard map (`&&` with `ST_MakeEnvelope`).
- **Why not GeoDjango:** Django's GIS module (GeoDjango) needs the large GDAL library installed on every developer's Windows machine. Raw PostGIS SQL gives the same database features without that setup.
- **Check it:** http://localhost:8000/api/v1/health/ reports the PostGIS version.

**How it was installed here:** the official PostGIS bundle zip for PostgreSQL 17 was copied into `C:\Program Files\PostgreSQL\17`, **adding new files only**. Seven libraries in the bundle (OpenSSL, curl, zlib, iconv, lz4, zstd) already existed in PostgreSQL in different versions and were **left untouched**, so PostgreSQL itself is unchanged. The extension was then enabled as the `postgres` user (step 1 of §3). On another machine, Stack Builder (§3) does the same job.

---

## 20. History: the old FastAPI backend

This portal first had a **FastAPI + SQLAlchemy + Alembic** backend in a `backend/` folder. On 2026-09-24 it was rebuilt in Django (`new-backend/`) to meet the project requirements. Everything was ported: the models, the endpoints, login with MFA, invitations, the audit log, review stamping and the helper scripts. The frontend was switched from `fetch()` to axios at the same time.

Differences from the FastAPI version:

- **PostGIS:** FastAPI stored only a PostGIS `location` column. Django keeps plain `lat` / `lng` numbers and has PostgreSQL compute the PostGIS `location` column from them (§19). The JSON the frontend receives is the same.
- **Deactivated users:** they are logged out immediately and can't log in. In FastAPI they could still log in.
- **Rate limit:** added to login, MFA and activation.
- **Admin self-protection:** an Admin also can't demote or delete themselves. FastAPI only prevented self-deactivation.
- **Health check:** `/api/v1/health/` now also reports the PostGIS version.
- **Mobile app:** the mobile endpoints came from a separate project (`D:\RoadGuard_Full_Clean\backend`). They were ported into `new-backend/mobile/`, so the app and the portal now share one backend and one database.

The old code is kept in **`backend-fastapi-archive.zip`** for reference. It's the source only, without its `.venv`, which was built on Linux and couldn't run here. The zip includes the old `.env` with that setup's database password and secret key, so **don't share it publicly**. Nothing in the current project depends on it.

---

## 21. Known limitations and next steps

- **The AI model:** the sensor model is connected (§18) but was trained on 5 trips in the USA with iPhones. Expect false alarms until it's retrained on Tanzanian roads and Android phones; open questions are in `ai_engine/models/MODEL.md`.
- **Alerts only in the foreground:** navigation guidance and hazard warnings work only while the trip screen is open. Alerts with the screen locked or the app in the background, and push notifications, need background location plus Firebase Cloud Messaging in the app, and push support in the backend.
- **Rate limits per process:** the mobile login, register, place-search and routing limits use Django's default in-memory cache, which is per process. With several server processes in production, configure a shared cache (e.g. Redis) so the limits are shared too.
- **Public map services:** OSRM and Photon default to free public servers with no uptime guarantee and strict usage limits. Run your own, or use a paid provider, for real traffic.
- **One account, one phone:** crowd sensing counts phones by traveller account, so one person with several accounts could count as several phones. Registration is rate-limited, but a stronger device check would help.
- **Real email:** invitations go to the `/api/v1/dev/outbox/` page, not to real inboxes. Configure SMTP in `MAILERS` before real use (§11).
- **ID reuse:** new IDs are "highest existing number + 1". If the newest record is deleted, its ID is given to the next new record, and old audit entries could then point at the wrong one. A small counter table would fix this.
- **HTTPS:** before deploying, set `DJANGO_DEBUG=False`, `DJANGO_SECURE_COOKIES=True`, real `DJANGO_ALLOWED_HOSTS` and `CORS_ALLOWED_ORIGINS`, and a new `DJANGO_SECRET_KEY`.
- **Proxy IP addresses:** behind a reverse proxy, audit IP addresses will show the proxy's address until `X-Forwarded-For` handling is added.
- **Audit log UI:** the frontend has no page for the audit log yet. Admins can use the API or `/api/v1/admin/`.
- **Database passwords:** the local `postgres` superuser password is `postgres`. Change it if this machine is reachable from a network.
