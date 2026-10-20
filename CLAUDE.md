# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

Pre-APE is a pre-survey assistant for Italian energy performance certificates (APE, D.Lgs. 192/2005, D.M. 26/06/2015): a Flutter app (web first, plus Android/iOS) and a FastAPI backend. UI strings, docs and commit history are mostly in Italian. `AGENTS.md` holds older agent notes; where it disagrees with this file (e.g. "frontend does not compile", "`frontend/test/` is empty"), the code has moved on.

## Commands

### Backend (run from `backend/`)

```bash
pip install -e ".[dev]"          # use pyproject.toml; requirements.txt is incomplete
python main.py                   # serves main:app on :7031, runs init_db() first
python -m pytest tests/ -v       # whole suite
python -m pytest tests/test_api.py::TestHealth::test_health_endpoint -v   # single test
```

Tests and even importing the app need a live PostgreSQL: `app/models/database.py` builds the engine at import time from `DATABASE_URL` (default `postgresql://postgres:postgres@localhost:5433/pre_ape`, note port **5433**). Locally this is the Docker container `pre_ape_postgres`; CI uses a `postgres:15` service on 5432 and overrides `DATABASE_URL`. Tests hit the real DB via `TestClient(main.app)` with no fixtures/cleanup. Survey IDs must be valid UUIDs (malformed → 422, unknown → 404).

### Frontend (run from `frontend/`)

There is usually no Flutter SDK on the host; use Docker:

```bash
docker run --rm -v preape-pubcache:/pubcache -v $(pwd):/project -w /project \
  ghcr.io/cirruslabs/flutter:stable sh -c "flutter pub get && flutter analyze"
# same image, other commands:
#   flutter test                                  (all tests)
#   flutter test test/scoring_test.dart           (single file; add --plain-name '<name>' for one test)
#   flutter build web --release --base-href /pre-ape/
python3 -m http.server 7032 -d build/web          # serve at http://localhost:7032/pre-ape/
```

Timed-out `--rm` containers can stay alive; check `docker ps` before relaunching.

Platform dirs (`android/`, `ios/`, `web/`) are gitignored and regenerated with `flutter create --org com.preape --project-name pre_ape --platforms=web,android,ios .` (only adds missing files, never touches `lib/`). CI does this before every build.

### CI

`.github/workflows/build.yml`: `flutter analyze`, backend pytest against Postgres, web build (deployed to GitHub Pages on `main`), debug APK, unsigned iOS build.

## Architecture

```
Flutter web ──▶ FastAPI :7031 (/api/v1) ──▶ PostgreSQL :5433
```

The frontend does **not** call the backend yet: there is no API client, and all survey state and scoring are client-side.

### Backend

- Real entry point is `backend/main.py` (`main:app`). All schemas and endpoints live in one file, `backend/app/api/v1/__init__.py` (router prefix `/api/v1`: surveys CRUD, photo-analyses, `/surveys/{id}/results`, plus an `asyncio.sleep` stub for generator-photo analysis).
- `backend/app/__init__.py` is a stale duplicate FastAPI app with the same routes. It is the only place `CORSMiddleware` is mounted, so `main:app` currently has **no CORS**. Edit the v1 router, not this file (removal is planned as TEAM_REVIEW P1-A1).
- Models (`users`, `surveys`, `photo_analyses`, Postgres `UUID` columns) are in `app/models/database.py`; settings via pydantic-settings/env in `app/core/config.py`.
- `app/services/ai_vision_service.py` (Ollama/OpenAI/Anthropic + OpenCV) is not wired into any endpoint.
- No auth or ownership checks yet: every survey is readable/writable by anyone (known IDOR, planned JWT + `user_id` filter).
- Port mismatches in config are known and not to be silently "fixed": server 7031, `CORS_ORIGINS` 3000/8080/7030, `GOOGLE_REDIRECT_URI` on :8000.

### Frontend

- `lib/main.dart` must keep the app wrapped in `ProviderScope` (Riverpod). Routing is a trivial `onGenerateRoute` in `lib/core/routing/app_router.dart` that always shows `OnboardingPage`.
- The app is a 4-step wizard in `lib/features/onboarding/` (general data → building envelope → systems → photos). Shared state is `SurveyData` held by `SurveyNotifier` (a `ChangeNotifier`) exposed as `surveyProvider` (`ChangeNotifierProvider`) in `survey_provider.dart`.
- `lib/core/scoring.dart` is the single source of the score formula (`computeScore`) and the score → energy class mapping (A4…G). `report_builder.dart` and `widgets/energy_gauge.dart` delegate to it; `kEnergyClassLetters` must stay aligned with `EnergyClass.classes` in the gauge. `test/scoring_test.dart` pins current values (default survey = 32.6), so a formula change means updating those tests deliberately.
- Browser-only features (geolocation, Leaflet/OSM map, file picker, download) use conditional imports: `foo_stub.dart` by default, `if (dart.library.js_interop) foo.dart` for web. Add both sides when adding web interop, and keep `dart:js_interop`/`package:web` out of the stubs so mobile builds keep compiling.
- Reverse geocoding goes to Nominatim directly from the client.
- Web build assumes `--base-href /pre-ape/` and needs `assets/fonts/Inter.ttf`.

## Process and planning docs

- `V_CYCLE_PROCESS.md`: team protocol. New decisions (scope, stack, deploy, pricing, personal data) go through a decision phase with acceptance criteria (`AC-#`) before coding; items already approved in the `TEAM_REVIEW.md` roadmap (P1–P3, e.g. `P1-A1`, `P2-B4`) can be implemented directly. Completed work is logged in `REQUIREMENTS.md` (FR/NFR + sprint log), and commits reference the roadmap ID.
- `REQUIREMENTS.md` §8 lists the legally required APE fields the wizard must cover.
- `DEPLOY_PLAN.md`: production today is the home server. The web build is served on :7032 and exposed through the cloudflared tunnel `ctm` at https://preape.cheic2.it/pre-ape/; the API is not exposed yet. The approved target is a single docker-compose (Caddy + nginx web + api + db, DB port never public).
- Ignore `nav.sh` (hard-coded paths to an old layout).
