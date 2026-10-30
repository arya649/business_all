# 02 – AI Layer (on Zentrix ADK)

The AI service is **Zentrix ADK** (`arya649/adk`), which already provides what an ERP-wide AI layer needs: a
stateless multi-tenant gateway, signed per-request tokens, scope checks at every step, guardrails, any AI provider with
fallback, per-call token cost, and a hash-chained audit log. The ERP does not re-implement any of that. It adds
ERP tools, ERP document types and ERP agents.

## How the tenant chains line up

| Zentrix ADK | Group ERP | Example |
|---|---|---|
| Platform | Zentrix (the AI service) | |
| Partner | **The ERP product** (us, selling the ERP) | `group-erp` |
| Customer | **Tenant** (one client business group) | `sri-group` |
| Subject | **App user** (or a service identity for scheduled jobs) | `user:40000…0b`, `svc:diesel-watchdog` |
| Entitlements (partner ∩ customer ∩ token) | **plan ∩ feature switches ∩ role permissions** | `agent.bunk_assistant`, `extract.weighbridge_slip` |

Both systems enforce the same three-layer rule, so a feature that is off in Super Admin can never be used through AI.

## Request flow

```
Mobile / web / WhatsApp
   │  user's Supabase session
   ▼
ERP server (Next.js route handler or Supabase Edge Function)
   1. resolved_features() for this user, company, location
   2. scopes = enabled AI features ∩ user's role permissions, e.g.
        "agent.site_assistant extract.gst_invoice infra.dpr.create purchase.indent.create"
   3. mint a 5-minute HS256 token with Zentrix TokenIssuer (partner key stays on the server)
        iss=group-erp  cid=<tenant>  sub=<user id>  scope=<scopes>  X-Correlation-ID=<uuid>
   ▼
Zentrix ADK  /v1/agents/<name>/run   /v1/extract   /v1/chat
   • checks the token and the tenant chain on every step
   • tools call back into the ERP with HttpConnector + the user's own Supabase JWT (on-behalf-of)
   ▼
Supabase (PostgREST / RPC)
   • RLS and user_can() apply exactly as if the user did it by hand
   • audit.log records actor = the user, actor_type = ai_agent, correlation_id = the Zentrix one
```

The `correlation_id` joins the two audit chains: Zentrix records *what the AI decided and what it cost*, the ERP
records *what data changed*. Every AI action can be traced end to end.

## Statelessness
Zentrix stores nothing. The ERP stores conversations it wants to keep in `ai_conversation` / `ai_message` tables
(per user, with RLS) and sends the history back with each call. Usage rows from Zentrix (`partner_id=group-erp,
customer_id=<tenant>`) are the basis for billing each client group for AI.

## New ERP document types for `/v1/extract`
Same pattern as the existing extractor schemas: fixed JSON shape, nulls for missing fields, checksums and format checks
in code, `uncertain_fields` for a person to confirm.

| document_type | Main fields | Used by |
|---|---|---|
| `gst_invoice` | supplier GSTIN/name, invoice no/date, place of supply, lines (HSN, qty, uom, rate, taxable, GST %), CGST/SGST/IGST, total, IRN, e-way bill no | GRN, purchase invoice, 3-way match |
| `eway_bill` | EWB no, date, valid till, from/to GSTIN, vehicle no, distance, items, value | Purchase inward, weighbridge |
| `delivery_challan` | challan no, date, party, items, qty, vehicle | Vendor deliveries |
| `weighbridge_slip` | slip no, vehicle no, gross, tare, net, date/time, weighbridge name | Third-party weighments, vendor slips |
| `meter_reading` | reading value, unit, meter type (nozzle totaliser, odometer, hour meter, electricity, water) | Bunk shift close, fleet fuel, bricks power |
| `dip_reading` | tank, dip mm, water mm, temperature, density | Bunk daily dip |
| `vehicle_rc` | reg no, owner, chassis, engine, class, fuel, reg/expiry dates | Vehicle master |
| `insurance_policy` | policy no, insurer, vehicle, IDV, period, premium | Fleet documents |
| `fitness_certificate`, `permit`, `puc_certificate` | number, vehicle, valid from/to | Fleet documents |
| `gst_certificate`, `udyam_certificate`, `pan_card` (exists) | registration details | Party KYC |
| `bank_statement` | account, period, transactions (date, narration, ref/UTR, debit, credit, balance) | Bank reconciliation |
| `cube_test_report` | sample id, grade, cast date, age, loads kN, strength N/mm² | RMC quality |
| `lab_report_bitumen` | bitumen %, gradation, Marshall stability/flow, density, voids | Hot-mix quality |
| `handwritten_register` | rows of a paper register (attendance, DPR, trip sheet) as a table | Migration from paper, sites with no app access |

The existing `driving_licence`, `aadhaar_card` and `bank_cheque` cover driver and employee onboarding.

## ERP agents (`/v1/agents/<name>/run`)

Each agent is a Zentrix `Agent` whose tools are thin wrappers over ERP RPCs, each with a scope equal to the ERP feature key.

| Agent | Who uses it | Tools (scope = feature key) |
|---|---|---|
| `site_assistant` | Site engineer | `infra.dpr.create`, `infra.labour_attendance.create`, `infra.material_request.create`, `purchase.stock.view` |
| `plant_assistant` | RMC / hot-mix / bricks supervisor | `rmc.orders.view`, `rmc.pour_schedule.view`, `rmc.batch_entry.create`, `bricks.daily_production.create` |
| `bunk_assistant` | Bunk manager | `bunk.dsr.view`, `bunk.tanks.view`, `bunk.shift.view`, `bunk.credit_customers.view` |
| `fleet_assistant` | Fleet manager | `fleet.fuel_log.view`, `fleet.trips.view`, `fleet.service.create`, `fleet.documents.view` |
| `accounts_assistant` | Accountant | `finance.bank_reconciliation.*`, `finance.gst.gstr2b_match.view`, `finance.ledger.view` |
| `owner_assistant` | Owner | read-only views across companies: sales, cash, receivables, leakage board, approvals |
| `admin_assistant` | Tenant admin | drafts roles, feature switches and approval rules as proposals; an admin applies them |

Rules for every tool:
- **Reads run directly. Writes return a draft** that the app shows as a confirmation card. Only the user's tap commits
  it, unless the tenant turns `ai.write_actions.config.require_confirm` off for that feature.
- Tools never receive the service-role key. They use the user's JWT, so RLS limits what they can reach.
- Text from customers, vendors and documents is data, never instructions (Zentrix guardrails screen tool results).

## Proactive agents (service identity, `X-Channel: automation`)
Run on a schedule (Supabase cron → Edge Function → Zentrix) with a service subject per tenant. Findings go to the
leakage board and to WhatsApp per notification rules.

1. **Diesel watchdog**: fuel issued vs GPS km / engine hours vs norm; fuel drops while stationary.
2. **Weighbridge watchdog**: tare drift, manual weights, short gaps between weighments, missing camera images.
3. **Unbilled work finder**: challans and dispatches with no invoice after N days.
4. **Collections**: polite reminders in the customer's language, with an escalation schedule.
5. **Stock anomaly**: consumption vs production ratios (cement/m³, fly ash/1000 bricks, bitumen %/MT).
6. **Compliance**: GST/TDS/PF/ESI due dates, licence and vehicle document expiries.
7. **Owner brief**: the 8 am / 8 pm WhatsApp summary.

## Feature switches for AI (in the registry)
`ai.chat`, `ai.voice_entry`, `ai.ocr`, `ai.write_actions`, `ai.proactive.*`. All of them sit under the plan ceiling,
so AI can be sold as an add-on per client group.
