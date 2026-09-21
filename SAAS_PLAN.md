# SAAS_PLAN.md — Pre-APE (1-page summary)

> Full requirements → `REQUIREMENTS.md`. This doc covers business logic and delivery only.
> Last updated: 2026-09-21

---

## Target Buyer

Small/medium solar installers in Italy (1-10 person teams). Current pain: 2+ hour site surveys, photos lost in WhatsApp/email, no standard process.

**Value:** Survey in < 30 min → data auto-saved to installer's Google Drive → structured JSON for PV design tools.

---

## Build vs Buy

| Concern | Decision | Why |
|---------|----------|-----|
| Auth | **Google OAuth** (buy) | Free, zero maintenance, user already has account |
| Maps | **OpenStreetMap + Nominatim** (build) | Free, no API key, excellent Italy coverage |
| File storage | **Google Drive** (build, user's own) | Free, user owns data, no lock-in |
| Billing | **Stripe** (buy, later) | Only when first paying customer |
| Database | **Supabase / Neon** (buy, later) | Free tier now; self-hosted Postgres on home server |

---

## Hosting Progression

| Phase | Infra Cost | Frontend | Backend | Database |
|-------|-----------|----------|---------|----------|
| **Now** (dev/pilot) | €0 | Docker on home server | Docker on home server | Docker `pre_ape_postgres` |
| **First customer** | ~€5-15/mo | Vercel (free) | Railway/Render (~€5-7) | Supabase/Neon free tier |
| **10+ customers** | ~€30-60/mo | Vercel (free) | Railway Pro (~€15-25) | Supabase Pro (~€15-25) |

Domain: DuckDNS now (€0), migrate to Cloudflare (~€8/yr) with first customer.

---

## Next Deliverables

1. Fix Flutter import errors → `flutter analyze` clean
2. Wire Google OAuth (login endpoint + session management)
3. Drive upload service (create folder, upload files)
4. Deploy frontend to Vercel (static build)
5. Deploy backend to Railway/Render + managed Postgres

---

## Differentiation (Blue Ocean)

|  | Eliminate | Reduce |
|--|-----------|--------|
| **vs spreadsheets** | Manual data entry, lost photos | Survey time: hours → minutes |
| **vs pro tools** | Expensive licences, vendor lock-in | Cost (€0 until value proven) |

|  | Raise | Create |
|--|-------|--------|
| **vs spreadsheets** | Data ownership (your Drive) | WhatsApp lead intake (future) |
| **vs pro tools** | Simplicity (4-step wizard) | Community of Italian installers |
