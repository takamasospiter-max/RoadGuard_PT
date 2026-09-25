# RoadGuard AI — Admin Portal

Web admin portal for RoadGuard AI, an AI-powered road condition monitoring platform built for TARURA (Tanzania Rural and Urban Roads Agency). React + TypeScript frontend, FastAPI + PostgreSQL/PostGIS backend.

## Prerequisites

- **Node.js** 20+ (frontend)
- **Python** 3.11+ (backend)
- **PostgreSQL** with the **PostGIS** extension available (backend)

Node/npm behave identically across operating systems, so the frontend commands below are the same everywhere. The backend needs a Python virtual environment activated differently per shell, so it gets a table.

## Running the backend

First time only — creates the virtual environment, installs dependencies, and generates a `.env`:

| Platform | Command |
|---|---|
| Linux / macOS | `cd backend && ./setup.sh` |
| Windows (PowerShell) | `cd backend; .\setup.ps1` |
| Windows (Command Prompt) | `cd backend && setup.bat` |

The script prints what it *can't* automate — installing PostgreSQL/PostGIS itself and creating the `roadguard`/`roadguard_dev` database — since that depends on your own Postgres install. Full details, including the exact SQL, are in **[backend/README.md](backend/README.md)**.

Every time after that, to start it:

| Platform | Command |
|---|---|
| Linux / macOS | `cd backend && ./run.sh` |
| Windows (PowerShell) | `cd backend; .\run.ps1` |
| Windows (Command Prompt) | `cd backend && run.bat` |

Or, with the virtual environment already active, the plain command behind all of those:
```
uvicorn app.main:app --reload
```

Serves at `http://localhost:8000`. Check it's up at `http://localhost:8000/health`.

## Running the frontend

First time only:
```
npm install
```

Then, every time, on any platform:
```
npm run dev
```

Serves at `http://localhost:5173`. It expects the backend running on `http://localhost:8000` (configurable via `VITE_API_URL` — copy `.env.example` to `.env` to override).

## Running both together

Two terminals, one for each — order doesn't matter, but the frontend won't be able to log in or load data until the backend is also up:

```
# terminal 1
cd backend && ./run.sh      # or .\run.ps1 / run.bat on Windows

# terminal 2
npm run dev
```

Open `http://localhost:5173/login`. If you don't already have an account, create one from the backend folder with the venv active:
```
python scripts/create_admin.py
```

## Project structure

```
src/            React + TypeScript frontend (this is the Vite project root)
backend/        FastAPI + PostgreSQL/PostGIS backend — see backend/README.md
```

## Other frontend commands

```
npm run build     # type-check + production build
npm run lint       # oxlint
npm run preview    # preview a production build locally
```
