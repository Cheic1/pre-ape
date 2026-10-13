# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

@AGENTS.md

`AGENTS.md` (imported above) is the source of truth for architecture, deploy shape and invariants. `README.md` is partly stale (it mentions Google OAuth/Drive and a `/pre-ape/` base href for local builds): trust `AGENTS.md` where they disagree.

## Commands

The host has no Flutter SDK and no Python deps; everything runs in Docker.

```bash
# Postgres for backend tests (port 5433 matches the default DATABASE_URL)
docker run -d --name tmp_preape_pg -e POSTGRES_PASSWORD=postgres -e POSTGRES_DB=pre_ape \
  -p 127.0.0.1:5433:5432 postgres:16

# Backend tests (full suite ~3 min because of PBKDF2)
docker run --rm --network host -v "$PWD/backend":/src -w /src python:3.11 \
  sh -c 'pip install -q -e ".[dev]" && python -m pytest tests/ -v'
# Single test: python -m pytest tests/test_api.py::TestClass::test_name -v   (or -k <expr>)

# Frontend: analyze + test (regenerate platform dirs first if missing)
docker run --rm -v preape-pubcache:/pubcache -v "$PWD/frontend":/project -w /project \
  ghcr.io/cirruslabs/flutter:stable \
  sh -c 'flutter pub get && flutter analyze && flutter test'
# Single test file: flutter test test/scoring_test.dart  (add --plain-name "<name>" for one test)

# Full image (Flutter web + FastAPI on one origin), as CI and Render build it
docker build -t pre-ape .
docker compose up -d        # home-server stack; needs .env (see .env.example)
```

`./verify.sh [flutter|backend|playwright]` is the local gate script (flutter analyze + backend pytest in Docker; uses containers `pre_ape_postgres` / `preape_pytest`).

## Cross-cutting rules

- The energy estimate lives only in `backend/app/core/energy/` (tests in `backend/tests/test_energy.py`); the frontend just renders `energy_result`. If the score → class mapping changes, update `frontend/lib/core/scoring.dart` too.
- Adding a survey field touches: the SQLAlchemy model (energy inputs usually go in `BuildingInputs` instead — no migration) + `_ADDITIVE_MIGRATIONS` (backend), the Pydantic schemas in `backend/app/api/v1/__init__.py` (`extra="forbid"`, so the client must not send unknown keys), `frontend/lib/models/survey.dart`, and `SurveyNotifier.loadFrom`/`toWire` in `survey_provider.dart`.
- CI (`.github/workflows/build.yml`) runs Postgres 15 and builds the Pages web bundle with `--base-href /pre-ape/`; the Docker image uses `--base-href /`.
