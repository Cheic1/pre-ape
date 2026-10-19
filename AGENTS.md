# AGENTS.md – Pre-APE

SaaS MVP for surveyors (geometri): login → list of site surveys → 6-step wizard (data, building, envelope, systems, photos, results) saved to the server → HTML/PDF report. Repo `Cheic1/pre-ape`, CI in `.github/workflows/build.yml` (flutter analyze + test, backend pytest with Postgres service, root Docker image build, web/android/ios artifacts, Pages deploy on `main`).

- `backend/` – FastAPI API (Python `>=3.11`). Run/test from this dir.
- `frontend/` – Flutter app (Dart `>=3.3.0 <4.0.0`, `flutter_riverpod`, `http`, `shared_preferences`). No Flutter SDK on host; builds run in Docker (`ghcr.io/cirruslabs/flutter`, persistent `preape-pubcache` volume – `--rm` containers + tool timeouts leave the container alive, check `docker ps` before relaunching). Platform dirs (`android/`, `ios/`, `web/`) are **not committed** – regenerate with `flutter create --org com.preape --project-name pre_ape --platforms=... .` (only adds missing files). `assets/images/.gitkeep` must stay (pubspec lists the dir).
- Ignore `frontend/backend/` (stale) and `nav.sh` paths pointing at it.
- Deploy: see `GUIDA_DEPLOY.md` (Italian, user-facing).

## Deploy shape

- Root `Dockerfile`: stage 1 builds Flutter web (`--base-href /`), stage 2 `python:3.11-slim` runs `uvicorn main:app` on `$PORT` (default 7031) and serves the web build from `STATIC_DIR=/app/static` → **one origin, no CORS**. `ApiClient.resolveBaseUrl` uses the page origin on web unless `--dart-define=API_BASE_URL=...`.
- `docker-compose.yml` (home server): `app` on `127.0.0.1:${APP_PORT:-7032}` + `db` (postgres 16, volume `pgdata`, no published port). Needs `.env` (`SECRET_KEY`, `POSTGRES_PASSWORD`; template `.env.example`).
- Public URL `preape.cheic2.it`: the host's single cloudflared tunnel `home` sends `*.cheic2.it` to Nginx Proxy Manager; a service is published by adding it in the **CTM** panel (`/DATA/AppData/Script/native/app`, creates the NPM Proxy Host). The old `ctm` tunnel / `ctm.yml` from DEPLOY_PLAN.md is no longer running. Publishing is a production action: ask the user.
- `render.yaml`: Render free Blueprint (Docker, Frankfurt) + external Postgres (Neon) via `DATABASE_URL`.

## Backend

- Entry `backend/main.py` (`main:app`); `init_db()` runs in the lifespan (skip with `SKIP_INIT_DB=1`): `create_all` + idempotent `ALTER TABLE … ADD COLUMN IF NOT EXISTS` list `_ADDITIVE_MIGRATIONS` (no Alembic yet – add new columns there too). Body limit 16 MB (413). `/` is API info only when no static build is present; with a build, unknown paths fall back to `index.html`.
- Router: all schemas + endpoints in `backend/app/api/v1/__init__.py` (prefix `/api/v1`, contract documented in its module docstring). `backend/app/__init__.py` is intentionally empty.
- Auth: email+password, PBKDF2 600k (`app/core/security.py`), JWT HS256, 7-day expiry, strict `Bearer` scheme, in-memory per-IP rate limit on `/auth/*` (`app/core/rate_limit.py`, single-process only).
- Admin: email in `ADMIN_EMAILS` (CSV env, case-insensitive; `is_admin(user)`, `is_admin` in the login/register response). Endpoints in `app/api/v1/admin.py` under `/api/v1/admin` (`require_admin`: 401/403): users with counts, any user's surveys (view/edit with re-estimate/delete), documents, delete user (`?confirm_email=`, cascade surveys + photo_analyses + documents; 409 on self). Every admin call except `GET /admin/audit` writes an `admin_audit_log` row in the same transaction. Normal `/surveys` endpoints stay owner-only for admins too.
- Surveys: owned by `user_id` (others' surveys → 404). `GET /surveys` returns summaries without photos. Photos are stored inline as data-URLs (`photos` dict + `additional_photos` list, JPEG/PNG/WebP only, ≤1M chars each, ≤8 slots / ≤6 extra). Energy inputs live in the `building` JSON column (`app.core.energy.inputs.BuildingInputs`). `energy_score`/`estimated_class`/`energy_result`/climate zone are computed **only server-side** by `app/core/energy/` (simplified UNI/TS 11300 seasonal balance, classes A4…G vs the DM 26/06/2015 reference building, climate data from `app/data/comuni_climatici.csv`, rebuilt by `scripts/build_climate_data.py`) on every create/update and by `POST /estimate`; clients sending them get 422 (`extra="forbid"`). `frontend/lib/core/scoring.dart` only maps score → class letter (`round(score/100*9)` from G). Tests: `tests/test_energy.py`.
- The estimate is a preliminary assessment from few survey data, **not** an APE – keep the UI/report wording ("stima preliminare/indicativa").
- DB: Postgres only (`sqlalchemy.dialects.postgresql.UUID`), engine created at import from `DATABASE_URL` (default `postgresql://postgres:postgres@localhost:5433/pre_ape`; `postgres://` URLs are normalized; `pool_pre_ping`). Tests need a real Postgres with `uuid-ossp`, e.g. `docker run -d --name tmp_preape_pg -e POSTGRES_PASSWORD=postgres -e POSTGRES_DB=pre_ape -p 127.0.0.1:5433:5432 postgres:16`.
- Deps: runtime deps only in `pyproject.toml` `dependencies` (mirrored in `requirements.txt`, used by the Dockerfile); `[dev]` for tests, `[ai]` for the unwired `app/services/ai_vision_service.py`, `[extras]` for future features. Host python has no deps: run tests in `python:3.11` with `pip install -e ".[dev]"` and `--network host`. Full suite ~3 min (PBKDF2).
- Legal: privacy notice / terms / DPA (Italian) in `backend/app/legal/*.md`, served by `GET /legal/{privacy|termini|dpa}` with `{{PLACEHOLDER}}`s filled from `LEGAL_*` settings. `register` requires `accept_terms: true`; `users.terms_version` vs `app.legal.LEGAL_VERSION` → `terms_accepted` in login/register; `POST /auth/accept-terms`. Bump `LEGAL_VERSION` on substantive text changes (everyone re-accepts). Frontend: `lib/features/legal/` (page, consent text, `TermsGate` dialog). Tests: `tests/test_legal.py`, `test/legal_test.dart`.
- `AI vision` is not wired: `analyze_generator_photo` is an `asyncio.sleep` stub.

## Frontend

- `lib/main.dart` → `AuthGate` (must stay inside `ProviderScope`): `LoginPage` (`features/auth/`) or `SurveyListPage` (`features/surveys/`); the wizard `OnboardingPage` is pushed on top. `authProvider` persists the JWT with shared_preferences; any `UnauthorizedException` → `handleUnauthorized()` (pop to first route).
- Wizard state: `features/onboarding/survey_provider.dart` (`SurveyNotifier`: `startNew`, `loadFrom(SurveyRead)`, `toWire`, `save(api, complete:)`, `dirty`). `windowType` is `"<frame> <glass>"` client-side ↔ `window_frame`/`window_glass` on the wire. Save/exit UI via `features/onboarding/survey_save.dart`.
- Wire DTOs `lib/models/survey.dart`, client `lib/services/api_client.dart` (inject `http.Client`; tests use `MockClient`).
- Tests in `frontend/test/` (scoring, report, media, API client, SaaS flow, wizard steps, widgets): `flutter test`.
- E2E against the real stack: Flutter web renders to canvas; enable semantics by clicking `flt-semantics-placeholder`, then use roles. Obscured/new-route text fields often aren't fillable via semantics – click + `keyboard.type`.
