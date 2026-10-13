# syntax=docker/dockerfile:1
# Pre-APE — single image: Flutter web app + FastAPI API on one origin.
#   docker build -t pre-ape .
#   docker run -p 7031:7031 -e DATABASE_URL=... -e SECRET_KEY=... pre-ape
# Listens on $PORT (default 7031): the PaaS (Render, Railway, Fly) sets it.

# ---- 1) Flutter web build ---------------------------------------------------
FROM ghcr.io/cirruslabs/flutter:3.44.0 AS web
WORKDIR /src
COPY frontend/pubspec.yaml frontend/pubspec.lock ./
RUN flutter pub get
COPY frontend/ ./
# Platform dirs are not committed: (re)generate web/ without touching lib/.
RUN flutter create --org com.preape --project-name pre_ape --platforms=web . \
 && flutter build web --release --base-href / --no-web-resources-cdn

# ---- 2) API runtime ---------------------------------------------------------
FROM python:3.11.10-slim AS api
ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1 \
    STATIC_DIR=/app/static \
    PORT=7031
WORKDIR /app
COPY backend/requirements.txt ./
RUN pip install -r requirements.txt
COPY backend/main.py ./
COPY backend/app ./app
COPY --from=web /src/build/web ./static
RUN useradd --system --uid 10001 preape && chown -R preape /app
USER preape
EXPOSE 7031
HEALTHCHECK --interval=30s --timeout=5s --start-period=20s --retries=3 \
  CMD python -c "import os,urllib.request; urllib.request.urlopen(f'http://127.0.0.1:{os.environ.get(\"PORT\",\"7031\")}/health', timeout=4)"
CMD ["sh", "-c", "exec uvicorn main:app --host 0.0.0.0 --port ${PORT} --proxy-headers --forwarded-allow-ips='*'"]
