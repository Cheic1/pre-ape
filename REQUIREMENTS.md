# REQUIREMENTS.md — Pre-APE

> **Canonical high-level requirements.** All design and test decisions trace here.
> Last updated: 2026-09-21

---

## 1. Product Goals

| # | Goal | Success Metric |
|---|------|----------------|
| G1 | Solar site survey in < 30 min | Median survey completion time |
| G2 | Data lives in installer's own Google Drive | Zero data loss; user can access files without the app |
| G3 | Zero cost until first paying customer | Infra spend = €0 during dev/pilot |
| G4 | Home-server-first, cloud-ready | Runs on a single Docker host; moves to managed services with no code changes |

---

## 2. Functional Requirements

### FR-1 — Onboarding Survey (4-step wizard)

| ID | Requirement | Notes |
|----|-------------|-------|
| FR-1.1 | Step 1: General data (address, area, height, orientation) | Defaults: **60 m²**, **2.7 m**, Rome coordinates |
| FR-1.2 | Browser geolocation on first render (web only) | One-shot `getCurrentPosition`; 8 s timeout; graceful fallback to defaults |
| FR-1.3 | Reverse geocode via Nominatim (OSM) | Address auto-filled from coordinates; editable |
| FR-1.4 | "Open map" button → OpenStreetMap in new tab | `url_launcher`; user copies coordinates back manually |
| FR-1.5 | Steps 2-4: roof data, shading, photos | Step 4 captures/skips photos |
| FR-1.6 | Client-side score calculation | `survey_provider.dart` holds scoring logic |

### FR-2 — Authentication

| ID | Requirement | Notes |
|----|-------------|-------|
| FR-2.1 | Google OAuth 2.0 login | Single sign-on; no custom auth |
| FR-2.2 | Session management | Backend validates tokens; frontend stores session |

### FR-3 — Data Storage & Export

| ID | Requirement | Notes |
|----|-------------|-------|
| FR-3.1 | Survey persists to PostgreSQL | Lat/lng, area, height, photos, score |
| FR-3.2 | Completed survey uploads to user's Google Drive | Folder per survey; structured JSON + photos |
| FR-3.3 | No vendor lock-in | User owns all data in their own Drive |

### FR-4 — Photo Analysis (future)

| ID | Requirement | Notes |
|----|-------------|-------|
| FR-4.1 | AI vision analysis of site photos | Wired to `ai_vision_service.py` (Ollama/OpenAI/Anthropic) |
| FR-4.2 | Climate zone auto-detection from coordinates | GPE headers |

### FR-5 — Future: WhatsApp Lead Intake

| ID | Requirement | Notes |
|----|-------------|-------|
| FR-5.1 | WhatsApp bot receives lead info | Not in current scope; architecture must not preclude this |

---

## 3. Non-Functional Requirements

| ID | Category | Requirement |
|----|----------|-------------|
| NF-1 | Performance | Survey page load < 2 s on 4G; full survey submit < 5 s |
| NF-2 | Availability | Home-server target: 95 % uptime (pilot); 99 % (production) |
| NF-3 | Security | HTTPS only; Google OAuth tokens not stored in plaintext; no PII logged |
| NF-4 | Mobile | Flutter web works on Chrome/Safari/Android WebView; native mobile is stretch goal |
| NF-5 | Accessibility | WCAG 2.1 AA for core wizard flow |
| NF-6 | Cost | €0 infra until first paying customer (self-hosted Docker) |

---

## 4. Architecture

```
┌──────────────┐     HTTPS      ┌──────────────┐
│  Flutter Web │ ──────────────▶│   FastAPI     │
│  (port 7031) │                │  (port 7031)  │
└──────────────┘                └──────┬───────┘
                                       │
                              ┌────────┼────────┐
                              ▼        ▼        ▼
                        PostgreSQL  Google   Nominatim
                        (port 5433) Drive API  (OSM)
```

| Component | Tech | Hosting (Phase 1) | Hosting (Phase 2) |
|-----------|------|-------------------|-------------------|
| Frontend | Flutter web | Docker on home server | Vercel / Cloudflare Pages (free) |
| API | FastAPI + Uvicorn | Docker on home server | Railway / Fly.io (~€5-7/mo) |
| Database | PostgreSQL 15 | Docker `pre_ape_postgres` | Supabase / Neon free tier |
| Auth | Google OAuth 2.0 | Free | Free |
| Maps | OpenStreetMap + Nominatim | Free (self-hosted or public) | Free |
| Storage | Google Drive (user's own) | Free | Free |
| Domain | DuckDNS → Cloudflare | €0 | ~€8/yr |

**Port map (do not change without updating this doc):**
- FastAPI: **7031**
- PostgreSQL: **5433** → container `pre_ape_postgres`
- API prefix: `/api/v1`

---

## 5. Test Strategy

| Level | Tool | Coverage Target |
|-------|------|-----------------|
| Unit | `flutter test` | Survey provider logic, scoring, geolocation parsing |
| Integration | `pytest` + `TestClient` | All API endpoints against real Postgres |
| E2E | Manual / Playwright (future) | Full survey → Drive upload flow |
| Static | `flutter analyze` | Zero warnings before any merge |
| Backend lint | `ruff` / `flake8` | All Python files |

**Test data rules:**
- Survey IDs must be valid UUIDs (invalid → 422, unknown → 404)
- Tests use `TestClient(main:app)` — requires running Postgres

---

## 6. Release Checklist

- [ ] `flutter analyze` passes clean (zero issues)
- [ ] `pytest tests/ -v` passes against clean DB
- [ ] All FR-1.x features functional in Chrome, Safari, Android WebView
- [ ] Google OAuth login/logout cycle works end-to-end
- [ ] Survey data persists to Postgres with correct schema
- [ ] Google Drive upload creates folder + JSON + photos
- [ ] HTTPS valid (Let's Encrypt or Cloudflare)
- [ ] No PII in logs; `.env` not committed
- [ ] `REQUIREMENTS.md` updated with any scope changes

---

## 7. Risks

| Risk | Impact | Mitigation |
|------|--------|------------|
| Geolocation denied by user | Survey starts with Rome defaults; address must be entered manually | Explicit fallback + editable field |
| Google Drive API quota hit | Uploads fail for heavy users | Retry with backoff; queue uploads; warn user |
| Home server downtime | App unavailable | Phase 2 migration to managed hosting; status page |
| AI vision service unreliable | Photo analysis returns errors | Graceful degradation: survey completes without analysis |
| Flutter web perf on low-end mobile | Slow render on cheap Android | Lazy-load heavy widgets; optimize bundle size |
| Scope creep (WhatsApp, native mobile) | Delays core release | Strict phase gating; FR-5 explicitly out of scope for v1 |

---

## 8. Legal APE Compliance (Italy)

> This section captures mandatory fields for a real *Attestato di Prestazione Energetica* so the wizard can collect legally valid data.

### 8.1 Scope & Validity (must-have)

| Field | When | Why |
|-------|------|-----|
| *Destinazione d'uso* (Res/Non-res) | Always | Determines UNI TS 11300 calculation path |
| *Oggetto attestato* (intero edificio / unità / gruppo) | Always | Defines calculation scope |
| Numero unità immobiliari | Always | Needed for centralised-system splitting |
| *Motivazione* (vendita / locazione / ristrutturazione / …) | Always | Legal trigger for APE issuance |
| Comune (ISTAT) + zona climatica | Always | Drives degree-days and thresholds |
| Anno di costruzione | Always | Fallback envelope assumptions |
| Superficie utile riscaldata (m²) | Always | Denominator for performance indices |
| Volume lordo riscaldato (m³) | Always | S/V ratio and thermal mass |
| Coordinate GIS | Always | Required by SIAPE and solar exposure |
| At least 1 site visit | Always | APE is invalid without it |
| CTI-certified software | Always | Legal calculation requirement |

### 8.2 Envelope & Systems (core inputs)

- Envelope: opaque transmittance (U or construction-era tables), windows (frame + glass), thermal bridges (ψ), orientation/tilt, inertia class.
- Systems: type, fuel vector, nominal power, year, seasonal efficiency η, regional CIT code when ≥ 10 kW.
- If a system is absent but legally required for simulation, mark as *Impianto simulato in quanto assente*.

### 8.3 Output Indices (must appear on APE)

- EPH,nd, YIE, EPgl,nren, EPgl,ren, CO₂ emissions, exported energy (even 0), energy class A4–G.

### 8.4 Recommendation Section

- At least one recommended intervention with projected class after improvement.

---

## 9. Sprint Change Log

| Date | Change | Files |
|------|--------|-------|
| 2026-09-21 | Survey defaults (60 m², 2.7 m, Rome coords); geolocation + Nominatim; OSM map button; `url_launcher` | `survey_provider.dart`, `step1_general_data.dart`, `web_geolocation.dart`, `web_geolocation_stub.dart`, `pubspec.yaml` |
| 2026-09-21 | Add legal APE field baseline (Italy) | `REQUIREMENTS.md` |
