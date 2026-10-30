# 08 – Audit and Logs: who added, changed, approved, printed or exported what

Implemented in `supabase/migrations/20261030000002_audit.sql`, tested in `supabase/tests/10_core_test.sql`.

## What is recorded

| Event | How | Example |
|---|---|---|
| Every insert, update and delete on a tracked table | Trigger `zz_audit` (`select audit.track('public.x')`) | Accountant changed party mobile 98765… → 91234… |
| Approvals | Rows in `approval_action` (tracked) | Plant head approved PO-114 from mobile, owner from WhatsApp |
| Business events that are not row changes | `audit.log_event('invoice.printed', …)` | Invoice printed 3 times, report exported, login, AI tool call |

Every record holds: tenant, sequence number, time, table and record, action, **actor**, actor type
(user / service / ai_agent / hardware / system), **on behalf of** (for AI and devices), source (web / mobile / api / ai /
hardware / sync), device id, IP, GPS, correlation id, **reason**, changed fields, and the full **before and after** values.

## How the context gets there
- From the app: request headers `x-source`, `x-device-id`, `x-geo`, `x-reason`, `x-correlation-id` (the Supabase
  client sets them globally per device).
- From server code: `audit.set_context(...)` inside the transaction.
- **Actor type and on-behalf-of are accepted only from server code**, never from headers, so a client cannot pose as an
  AI agent or another user. The actor is always `auth.uid()` from the verified session.

## Why it can be trusted
- **Append-only.** Updates, deletes and truncates are refused for every application role, and blocked by trigger
  even for the table owner.
- **Hash chain per tenant.** Each record's hash covers the previous hash. `audit.verify_chain(tenant)` reports altered
  records, missing records and a removed tail. The tests prove it catches a superuser editing or deleting rows.
- **External anchor (to build):** a cron job copies each tenant's `audit.chain_head` hash to Zentrix audit storage
  (S3 with Object Lock) every hour, so even a full database rewrite is detectable.
- **Edit lock (to build with Finance):** after GST filing, edits need a reason and an approval, and both are logged.

## Who can see it
Tenant admins, plus roles given `core.audit` → `view`. Other users see nothing, and other tenants never see another
tenant's records. Every screen gets a **History** tab from the `record_history` view: who, when, from where,
what changed, and why.

## Application logs (separate from the audit log)
Errors, slow queries and integration failures (GSP, WhatsApp, hardware gateway) go to Supabase logs and the Next.js
server log, shipped to one log store with ERROR alerts. They never contain business data. Zentrix keeps its own
application log, audit chain and usage records, joined to ours by correlation id.
