# Group ERP

One platform for a business group: Finance & GST, CRM, RMC, hot-mix, weighbridge, bricks, construction projects,
petrol bunk, fleet, purchase & stores, HR & payroll. Every module, screen and field can be switched on or off by
the platform and the group's admin. Phones keep working with no signal. AI runs on Zentrix ADK. Every change,
approval and AI action is in a tamper-evident audit log.

| Folder | What |
|---|---|
| `supabase/migrations/` | The backend: tables, security, switches, engine, posting, stock, business rules |
| `config/modules/*.mjs` | The 11 modules described field by field (62 record types, 881 fields) |
| `config/feature-registry.json` | Every switch (203) |
| `apps/web/` | Next.js app: office web app and installable, offline phone app |
| `ai/` | Zentrix ADK agents and tools |
| `docs/` | Blueprint, field-level specs, AI design, audit design, build plan |
| `scripts/` | Generators, test runner, local demo stack |

## How it works
- **Modules are data.** Each record type is described once in `config/modules`. `node scripts/gen-modules.mjs`
  generates its table, catalogue entry and audit tracking.
- **One engine for every screen.** `erp_catalog / erp_list / erp_get / erp_save / erp_set_status` apply, in one place:
  switches (plan → group → company → location → role → person), role actions, hidden fields (role ticks, switch
  config, rates/costs), numbering, workflow, approvals, required fields and locked records.
- **Every document posts itself.** Posting rules turn module documents into balanced journals. Changes re-post,
  cancellations reverse, nothing is deleted. Sales to a group company are tagged inter-company, mirrored in the
  other company's books, and removed from group totals. Stock moves come from GRNs, batches, issues and transfers.
- **Domain rules live in the database.** Some examples:
  - Bunk: nozzle sale, cash short, credit limits at the pump, dip vs book variance, tanker short and density, group-vehicle fuel.
  - RMC: credit check and override, batch deviation, challans to billing.
  - Weighbridge: tare drift, typed weights.
  - Purchase: 3-way match.
  - Projects: DPR progress, RA bill deductions.
  - HR: payroll with PF / ESI / PT and advance recovery.
  - Bricks: curing lots.
  - Hot-mix: temperature band.
- **Owner view.** Group dashboard, leakage board, trial balance (company or group), stock, billing runs.

## Run it locally

```bash
scripts/test-db.sh
```

```bash
scripts/dev/stack.sh
```

```bash
cd apps/web && cp .env.example .env.local && npm install && npm run build && npm start
```

`test-db.sh` runs every migration and 156 checks on a throwaway Postgres 16. `stack.sh` starts Postgres,
PostgREST and a dev sign-in gateway with the demo group loaded; it needs the `postgrest` binary on the PATH.
For `.env.local`, set `NEXT_PUBLIC_SUPABASE_URL=http://localhost:54321` and `NEXT_PUBLIC_SUPABASE_ANON_KEY=dev-anon`.
Demo logins (password `demo1234`): `owner@demo.in`, `cashier@demo.in`, `engineer@demo.in`, `operator@demo.in`,
`accounts@demo.in`. On the local stack, mobile numbers `9000000001`–`9000000005` also work with code `123456`.

## Deploy
1. Create a Supabase project and run `supabase link --project-ref <ref>`, then `supabase db push`.
   Do not apply `supabase/tests/*` or `supabase/dev/*` to production.
2. Create a public storage bucket `erp-files`.
3. Turn on phone sign-in (an SMS provider) in Supabase Auth.
4. Deploy `apps/web` to Vercel with the variables in `apps/web/.env.example`.
5. Create the first tenant, company and admin user with SQL; the admin does everything else in Super Admin.
6. AI: see `ai/README.md`.

See `docs/07-build-plan.md` for what is done and what is next.
