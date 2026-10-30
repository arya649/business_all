# AI: Group ERP on Zentrix ADK

`zentrix_erp/agents.py` defines the ERP's seven assistants and their tools for Zentrix ADK (`arya649/adk`).

How a request flows:
1. The app calls `/api/ai/agent` (Next.js). The server asks the database for the person's AI scopes
   (`ai_scopes`: plan ∩ switches ∩ role) and mints a 5-minute Zentrix token: `iss` = this product (partner),
   `cid` = the client group (customer), `sub` = the person.
2. Zentrix checks the token and runs the agent. Each tool calls the ERP through `ai_call` with a 2-minute
   Supabase token for that same person (claim `via = zentrix`), so RLS, switches and field hiding apply.
3. Every tool call is in the ERP audit log as `ai_agent` on behalf of the person, with the Zentrix correlation id,
   which also appears in Zentrix's own audit and usage records.
4. Agents never save anything. `propose_entry` returns a card; the person taps Save in the app.

Setup in Zentrix `clients.json`: add partner `group-erp` with entitlements `agent.*`, `extract.*` and the ERP
feature scopes (`<feature>.view`, `<feature>.create`); add each client group as a customer with id = its ERP
tenant id. Register `zentrix_erp.agents.AGENTS` with `build_runner`.

Not yet run against a live Zentrix server here: `arya649/adk` is private to this session, so the module is written
from its README API and needs a run with real keys. New `/v1/extract` document types for the ERP (GST invoice,
e-way bill, weighbridge slip, meter and dip readings, RC, insurance, bank statement, cube test report) are listed
in `docs/02-ai-layer.md` and still need adding on the Zentrix side.
