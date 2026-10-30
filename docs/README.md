# Group ERP – Master Blueprint

One platform, one login, one set of masters, 11 business modules. Every module can be
switched on or off by Super Admin per company, branch, role, and user, on web and mobile.
AI can read and act across all of it.

## Files in this blueprint

| File | Contents |
|---|---|
| `01-core-platform.md` | Multi-company setup, feature toggles, masters, approvals, notifications, owner dashboard, audit, offline sync, UX rules |
| `02-ai-layer.md` | AI on Zentrix ADK: tenant mapping, ERP document types, agents, watchdogs |
| `03-finance-crm.md` | Finance and GST, CRM and leads, field by field |
| `04-rmc-weighbridge-fleet.md` | RMC plant, weighbridge, fleet and machines |
| `05-infra-purchase-hr.md` | Construction projects, purchase and stores, HR and payroll |
| `06-bitumen-bricks-bunk.md` | Hot-mix plant, bricks, petrol bunk |
| `feature-registry.json` | Full on/off tree for every module, screen and feature (drives Super Admin toggles) |
| `07-build-plan.md` | Tech stack decision, status, phases, risks |
| `08-audit-and-logs.md` | Who added, changed, approved, printed or exported what |

## The five rules that run through every module

1. **Capture once, at the source.** The weighbridge operator's ticket becomes the RMC challan, the
   stock movement, the invoice line and the ledger entry. Nobody types it twice.
2. **Every operational record posts to Finance automatically.** Each module has a posting rule
   (configured in admin, not by users) that turns its document into a journal.
3. **Internal or external is decided by the master, not the user.** If the customer is a group
   company, the transaction is tagged inter-company and eliminated in group reports.
4. **Field users see big buttons, photos and numbers, not forms.** Max 5 inputs per screen,
   everything else defaulted, scanned, weighed or picked from a photo list. Telugu / Tamil /
   Hindi / Kannada / English, plus voice input.
5. **Works with no network.** Every mobile screen saves locally first and syncs when signal returns.
   The user never sees "network error".

## System map

```
                         ┌───────────────────────────────┐
                         │  SUPER ADMIN (web)            │
                         │  companies · toggles · rules  │
                         └──────────────┬────────────────┘
                                        │
  ┌──────────── CORE ───────────────────┼──────────────────────────────────┐
  │ Tenancy & RBAC · Masters · Approvals · Notifications · Audit · Docs    │
  │ Posting Engine → Finance ledger · Sync server · AI gateway             │
  └───┬───────┬────────┬────────┬───────┬────────┬────────┬───────┬──────┘
      │       │        │        │       │        │        │       │
   Finance  CRM      RMC   Weighbridge Fleet  Infra  Purchase   HR
                     Bitumen   Bricks   Petrol bunk
      │                                                         │
  Web app (office)      Mobile app (field, offline)      WhatsApp bot / voice
  Hardware gateway: scale · camera · RFID/ANPR · biometric · GPS · fuel sensor · ATG/DU
```
