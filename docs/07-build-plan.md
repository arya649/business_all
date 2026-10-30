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

Built and covered by automated tests (156 database checks), plus a browser walkthrough on desktop and phone sizes:

| Piece | State |
|---|---|
| Tenancy, companies, GSTINs, locations, users, roles | done |
| Switches at plan / group / company / location / role / person, with field hiding and real "preview as" | done |
| Tamper-evident audit log, History tab, audit search and chain check | done |
| Numbering (GST 16-character limit), offline number blocks | done |
| Masters with duplicate warnings; approvals with steps, escalation, no self-approval | done |
| Module engine and 62 record types across all 11 modules | done |
| Posting engine with inter-company mirror and reversals; stock ledger; trial balance; group elimination | done |
| Business rules for bunk, RMC, weighbridge, fleet, purchase, projects, HR, bricks, hot-mix; billing runs | done |
| Owner dashboard, leakage board | done |
| Web/phone app: tiles, forms, lists, approvals, dashboard, reports, Super Admin, sync screen, 5 languages, voice, camera, GPS | done |
| Offline: cached screens and pick-lists, outbox, phone-side numbering, retry and fix | done |
| AI: scopes, `ai_call` door, audit as AI, API proxy, assistant screen, Zentrix agents module | done, not yet run against live Zentrix |
| Step-by-step mode (one question per screen, read aloud, big buttons), Telugu and Hindi field names, colour tiles | done |
| P&L, balance sheet (group eliminated), ageing with WhatsApp reminders, party statement, day book, bunk DSR | done |
| GST files: e-invoice (INV-01), e-way bill, GSTR-1 JSON; period lock after filing | done (direct IRP upload needs a GSP) |
| Bank statement CSV import with automatic matching; Tally XML export | done |
| Licences & documents register with expiry alerts; owner's WhatsApp summary | done |
| Devices: weighbridge scale and biometric gateway for the site PC; GPS feed with fuel-drop alerts | done |
| Sales pipeline board; RMC pour schedule | done |

Not built yet:
- **GST:** direct IRN / e-way bill generation through a GSP (files are ready to upload by hand today); GSTR-2B matching; GSTR-3B.
- **Notifications:** automatic WhatsApp/SMS sending (needs a WhatsApp BSP account); today messages open in WhatsApp to send with one tap.
- **Hardware:** camera snapshots and ANPR on the weighbridge, tank gauge (ATG) and dispenser automation.
- **Field users:** a native Expo app (the web app installs on phones and works offline today); Tamil and Kannada field names.
- **Scale:** the first catalogue load takes 0.15–0.5 s per company; worth tuning for very large groups.

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
