# Group ERP

One platform for a business group: Finance & GST, CRM, RMC, hot-mix, weighbridge, bricks, construction projects,
petrol bunk, fleet, purchase & stores, HR & payroll. Every feature can be switched on or off by the platform and the
group's admin. The mobile apps work offline. AI runs through Zentrix ADK. Every change is in a tamper-evident audit log.

- Blueprint and field-level specs: [`docs/`](docs/README.md)
- Stack and plan: [`docs/07-build-plan.md`](docs/07-build-plan.md)
- Audit design: [`docs/08-audit-and-logs.md`](docs/08-audit-and-logs.md)
- AI on Zentrix ADK: [`docs/02-ai-layer.md`](docs/02-ai-layer.md)

## Database (Supabase)

```
supabase/migrations/
  …0001_foundation.sql       tenants, companies, GSTINs, locations, users, feature switches, roles, user_can()
  …0002_audit.sql            append-only hash-chained audit log, record_history view, verify_chain()
  …0003_numbering.sql        document number series, offline number blocks for phones
  …0004_masters.sql          parties (with duplicate detection), items, vehicles, vehicle documents
  …0005_approvals.sql        multi-step approvals with self-approval block, escalation, approval trail
  …0006_feature_catalog.sql  GENERATED from config/feature-registry.json
```

Edit `config/feature-registry.json`, then regenerate the catalogue:

```bash
node scripts/gen-feature-catalog.mjs
```

Run every migration and test on a throwaway Postgres 16:

```bash
scripts/test-db.sh
```

Apply to a Supabase project:

```bash
supabase link --project-ref <ref>
```

```bash
supabase db push
```
