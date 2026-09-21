# AGENTS.md – Pre-APE

Two independent apps, git repo `Cheic1/pre-ape` (branch `main`), CI in `.github/workflows/build.yml` (flutter analyze + backend pytest + web/android/ios artifacts, Pages deploy on `main`).

- `backend/` – FastAPI API (Python `>=3.11`). Run/test from this dir.
- `frontend/` – Flutter app (Dart `>=3.3.0 <4.0.0`, `flutter_riverpod`). No Flutter SDK on host; builds run in Docker (`ghcr.io/cirruslabs/flutter:stable`, persistent `preape-pubcache`/`preape-gradle` volumes – `--rm` containers + tool timeouts leave the container alive, check `docker ps` before relaunching). Only `flutter_riverpod` + `cupertino_icons` in pubspec – pruned phantom/unused pins (vibration, geocoding_google, shimmer…); re-add with valid versions when the feature lands. Platform dirs (`android/`, `ios/`, `web/`) are **not committed** – regenerate with `flutter create --org com.preape --project-name pre_ape --platforms=... .` (safe: only adds missing files, never touches `lib/`). Entry `frontend/lib/main.dart` (must stay wrapped in `ProviderScope` or Riverpod crashes at runtime). Web needs existing `assets/fonts/Inter.ttf` (variable font, single file). Verified: `flutter analyze` clean, `flutter build web --release --base-href /pre-ape/` + `flutter build apk --debug` succeed; iOS never built locally (needs macOS).
- Ignore `frontend/backend/` (stale, only `.pytest_cache`) and `nav.sh` paths pointing at it.

## Backend

- Canonical entry: `backend/main.py` → serves on port **7031** (`python main.py`). App object is `main:app`; router lives in `backend/app/api/v1/__init__.py` (all schemas + endpoints in that one file, prefix `/api/v1`).
- Do NOT use `backend/app/__init__.py` – stale duplicate `FastAPI` app with the same routes. Edit the `app/api/v1` router instead.
- `backend/app/routers/` and `backend/app/schemas/` are empty; only service is `backend/app/services/ai_vision_service.py` (Ollama/OpenAI/Anthropic + cv2), currently **not wired** – the router's `analyze_generator_photo` is just an `asyncio.sleep` stub.
- DB: `backend/app/models/database.py` uses `sqlalchemy.dialects.postgresql.UUID` and creates the engine **at import time** from `DATABASE_URL` (default `postgresql://postgres:postgres@localhost:5433/pre_ape` – note non-standard port **5433**). Verified live as Docker container `pre_ape_postgres` (`0.0.0.0:5433->5432`, tables `users`/`surveys`/`photo_analyses`, `uuid-ossp` installed). No sqlite fallback, no compose file, no `.env` committed. Importing the app or running tests requires that DB up (plus `Base.metadata.create_all` on startup in `main.py:init_db`). Config via env/`.env`, see `backend/app/core/config.py`.
- Port inconsistencies are real, don't "fix" silently: server `7031`, `CORS_ORIGINS` = 3000/8080/7030, `GOOGLE_REDIRECT_URI` = `localhost:8000/...`. AI defaults: `AI_PROVIDER=ollama`, `OLLAMA_BASE_URL=http://localhost:11434`, model `llava:7b`.
- Tests: `backend/test_runner.py` just runs `pytest tests/test_api.py`. Run `python -m pytest tests/ -v` (or `python test_runner.py`) from `backend/`. Tests use `TestClient(main:app)` against the real DB; survey IDs must be valid UUIDs (invalid → 422, unknown → 404).
- Deps: system python here has **no** pytest/fastapi installed. `requirements.txt` is **incomplete** (missing `aiohttp`, `opencv-python`, `numpy`, … that `ai_vision_service.py` imports). Install from `pyproject.toml` (`pip install -e ".[dev]"` or equivalent), not just `requirements.txt`.

## Frontend

- Entry `frontend/lib/main.dart`; theme/router under `lib/core/`, 4-step wizard under `lib/features/onboarding/` (`survey_provider.dart` holds client-side score logic). `lib/models/`, `lib/services/`, `lib/features/pages/` are empty – no API client exists yet.
- Currently **does not compile**, known issues: `main.dart` and `app_router.dart` reference `OnboardingPage` without importing it; `step1-4_*.dart` import nonexistent `flutter_riverpod/flutter_riverprovider.dart` (and `flutter_provider.dart`); `survey_provider.dart` uses `ChangeNotifierProvider` but only imports `material.dart`. Fix imports toward `package:flutter_riverpod/flutter_riverpod.dart` before trusting `flutter analyze`.
- `frontend/test/` is empty – `flutter test` is a no-op. Per `frontend/README.md`, build web with `flutter clean && flutter pub get && flutter build web --release` on a machine with the SDK.
