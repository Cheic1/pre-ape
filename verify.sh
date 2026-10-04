#!/usr/bin/env bash
# verify.sh — gate locale Pre-APE (MACRO_TASKS M2, owner backend-architect).
#
# Lane:
#   flutter     flutter analyze in Docker  -> GATE  (exit code reale)
#   backend     backend pytest in Docker   -> GATE  (exit code reale)
#   playwright  npx playwright test        -> soft `|| true` finché non esiste
#                playwright.config.*, GATE da quando la config esiste
#
# Uso:
#   ./verify.sh                  # tutte le lane
#   ./verify.sh backend          # solo una/sottinsieme: flutter|backend|playwright
#
# Exit code: 0 solo se TUTTI i gate passano (la lane soft non conta).
# Nessun timeout stretto su pytest: la suite deve poter superare i ~60s
# richiesti dalle iterazioni PBKDF2 (niente 401 al posto di 429 su host saturo).
set -u

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FLUTTER_IMAGE="ghcr.io/cirruslabs/flutter:stable"
PYTEST_CONTAINER="preape_pytest"
PG_CONTAINER="pre_ape_postgres"
FAIL=0

log() { printf '\n[verify] %s\n' "$*"; }

gate() { # gate <nome-lane> <funzione>
    local name="$1" fn="$2"
    log "GATE ${name}: inizio"
    if "${fn}"; then
        log "GATE ${name}: OK"
    else
        log "GATE ${name}: FAILED"
        FAIL=1
    fi
}

# --- flutter analyze (docker) -------------------------------------------------
lane_flutter() {
    # Volumi persistenti come da AGENTS.md (pub cache condivisa tra run).
    # Il mount espone anche le platform dir locali (android/ ios/ web/).
    docker run --rm \
        -v "${ROOT}/frontend:/workspace" \
        -v preape-pubcache:/root/.pub-cache \
        -w /workspace \
        "${FLUTTER_IMAGE}" \
        bash -lc "flutter pub get && flutter analyze"
}

# --- backend pytest (docker) -------------------------------------------------
ensure_pytest_container() {
    if docker inspect "${PG_CONTAINER}" >/dev/null 2>&1; then
        [ "$(docker inspect -f '{{.State.Running}}' "${PG_CONTAINER}")" = "true" ] \
            || docker start "${PG_CONTAINER}" >/dev/null \
            || { log "Postgres ${PG_CONTAINER} non avviabile"; return 1; }
    else
        log "Container Postgres ${PG_CONTAINER} assente (serve pre_ape su :5433)"
        return 1
    fi
    if docker inspect "${PYTEST_CONTAINER}" >/dev/null 2>&1; then
        [ "$(docker inspect -f '{{.State.Running}}' "${PYTEST_CONTAINER}")" = "true" ] \
            || docker start "${PYTEST_CONTAINER}" >/dev/null \
            || { log "Container ${PYTEST_CONTAINER} non avviabile"; return 1; }
    else
        # Ricreazione fedele alla spec: python:3.11, deps da pyproject (non
        # requirements.txt, che è incompleto), rete host verso Postgres :5433.
        log "Creo il container ${PYTEST_CONTAINER} (primo avvio: pip install -e '.[dev]')"
        docker run -d --name "${PYTEST_CONTAINER}" --network host \
            -v "${ROOT}/backend:/app" \
            -v preape_pipcache:/root/.cache/pip \
            -w /app python:3.11 sleep infinity >/dev/null || return 1
        docker exec -w /app "${PYTEST_CONTAINER}" pip install -e ".[dev]" || return 1
    fi
}

lane_backend() {
    ensure_pytest_container || return 1
    docker exec -w /app "${PYTEST_CONTAINER}" python -m pytest tests/ -v
}

# --- playwright (E2E, M10) ---------------------------------------------------
playwright_config() {
    find "${ROOT}" -maxdepth 3 -name 'playwright.config.*' \
        -not -path '*/node_modules/*' 2>/dev/null | head -n1
}

lane_playwright() {
    local cfg
    cfg="$(playwright_config)"
    if [ -z "${cfg}" ]; then
        log "playwright: nessun playwright.config.* — niente da eseguire"
        return 1  # assorbito dal `|| true` qui sotto finché la config non esiste
    fi
    log "playwright: config trovata (${cfg}) — lane da gate"
    (cd "$(dirname "${cfg}")" && npx playwright test)
}

# --- dispatch ----------------------------------------------------------------
LANES="${*:-flutter backend playwright}"
for lane in ${LANES}; do
    case "${lane}" in
        flutter)    gate flutter lane_flutter ;;
        backend)    gate backend lane_backend ;;
        playwright)
            if [ -z "$(playwright_config)" ]; then
                lane_playwright || true   # M2: soft finché non esiste playwright.config.*
            else
                gate playwright lane_playwright
            fi
            ;;
        *)
            log "Lane sconosciuta: ${lane} (uso: flutter|backend|playwright)"
            FAIL=1
            ;;
    esac
done

if [ "${FAIL}" -eq 0 ]; then
    log "TUTTI I GATE VERDI"
else
    log "GATE IN ROSSO"
fi
exit "${FAIL}"
