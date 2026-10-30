# 07 – Tech Stack, Build Plan, Risks

## Decision: Supabase + Next.js, one repository

```
group-erp/
  supabase/migrations/   database: tables, RLS, business rules, posting engine, audit   ← the real backend
  supabase/functions/    Edge Functions: GST/GSP calls, WhatsApp, Zentrix token minting, cron jobs
  apps/web/              Next.js (App Router): office web app + Super Admin + API routes
  apps/mobile/           Expo (React Native) with PowerSync for offline         (from Phase 1b)
  apps/gateway/          small Node service on site PCs: weighbridge scale, cameras, RFID, biometric, ATG
  packages/shared/       types generated from the database, feature keys, validation (zod)
  config/                feature-registry.json → generates the feature catalogue migration
```

Why not a separate backend server:
- **Rules live in Postgres**, next to the data: permissions (RLS + `user_can`), feature switches, numbering, approvals,
  posting to the ledger, and the audit log. Web, mobile, AI agents, the hardware gateway and imports all pass through
  the same rules, so nothing can bypass them.
- **Next.js handles screens and server-only work**: minting Zentrix tokens, file uploads, PDF printing, GSP calls
  (or Edge Functions for the same).
- Heavy or long jobs (bank statement matching, report snapshots) run as Edge Functions or a worker. If one grows
  large, it moves out without changing the database contract.

| Layer | Choice |
|---|---|
| Database / auth / storage | Supabase (Postgres 15+, RLS, phone OTP login, Storage for photos and documents) |
| Web | Next.js 15 App Router, TypeScript, Tailwind, shadcn/ui, AG Grid for power users |
| Mobile | Expo (React Native), one app with tiles chosen by role and feature switches |
| Offline | PowerSync (Postgres ↔ SQLite) with per-user sync rules |
| AI | Zentrix ADK (see `02-ai-layer.md`) |
| Messaging | WhatsApp Cloud API or a BSP, DLT SMS, email |
| GST | A GSP partner API for e-invoice, e-way bill and GSTR |
| Reports | Postgres views / materialised views; embedded Metabase for ad-hoc reports |

## Status

| Piece | State |
|---|---|
| Tenancy, companies, GSTINs, locations | built and tested |
| Feature switches (plan ceiling → tenant → company → location → role → user) | built and tested |
| Roles, permissions, `user_can()` | built and tested |
| Tamper-evident audit log, record history | built and tested |
| Document numbering with offline number blocks | built and tested |
| Masters: party, item, vehicle (with duplicate detection) | built and tested |
| Approvals engine | built and tested |
| Notifications, documents store, owner dashboard | next |
| Next.js web app (login, Super Admin, masters, approvals, history) | next |
| Finance posting engine, CRM | Phase 1 |

## Phases

| Phase | Scope | Duration (6–8 developers) |
|---|---|---|
| 0 | Discovery: one RMC plant, one bunk, one site, one weighbridge; collect every paper register and Excel | 3–4 weeks |
| 1 | Core + Finance + CRM + web app; mobile app shell with offline sync | 4–5 months |
| 2 | RMC + Weighbridge (with gateway) + Fleet (GPS/fuel) | 3–4 months |
| 3 | Infra projects + Purchase/Stores + HR/Payroll | 4 months |
| 4 | Bitumen + Bricks + Petrol bunk | 3 months |
| AI | Starts in Phase 1 (document reading, chat over masters) and grows with every module | continuous |

## Biggest risks
1. **Wrong posting rules make the books wrong.** Run in parallel with Tally for 2–3 months, with your CA signing off each rule.
2. **Field staff don't adopt it.** Test every mobile screen with a real attendant or operator; target under 30 seconds per entry.
3. **Hardware varies widely.** Standardise on 1–2 vendors per device type.
4. **GST API onboarding takes weeks.** Sign the GSP contract in month 1.
5. **Scope keeps growing.** Every feature has a switch, so ship lean versions first and switch more on later.
