# 03 – Finance & GST, CRM

---

## Module 1 – Finance and GST (Tally / Zoho Books class)

### Core design: Posting Engine
Every module raises a **source document**; the Posting Engine converts it to a journal using **posting rules**
set in admin. Users never pick ledgers.

**posting_rule**: id, company_id, source_doc_type (e.g. `rmc.invoice`, `bunk.shift_close`, `weighbridge.purchase_grn`,
`hr.payroll_run`, `fleet.fuel_issue_internal`), conditions, lines[] each: side (Dr/Cr), ledger (fixed / from party /
from item category / from location), amount_expression (e.g. `taxable_value`, `cgst`, `round_off`), cost_centre_source.

**journal**: id, company_id, gstin_id, voucher_type (sales, purchase, receipt, payment, contra, journal, debit note,
credit note), voucher_no, date, narration, source_doc_type, source_doc_id, is_intercompany, counterparty_company_id,
status (draft / posted / reversed), posted_by (user / engine).

**journal_line**: journal_id, ledger_id, party_id, debit, credit, cost_centre_id, location_id, project_id,
vehicle_id, item_id, qty, bill_reference (for bill-wise outstanding: new ref / against ref / on account).

**ledger**: id, company_id, name, group (Tally-like groups: Sundry Debtors, Duties & Taxes, Direct Expenses...),
type, gst_applicable, tds_applicable, opening_balance, is_bank, bank details.

### Sales and purchase invoices – fields
invoice_no (series), date, party_id, billing/shipping address, place_of_supply (auto from shipping state),
gstin_id (our), reverse_charge, items[] (item, hsn, qty, uom, rate, discount, taxable, gst_rate, cgst/sgst/igst,
cess), tcs, round_off, total, due_date, linked_source_docs[] (challans, tickets, RA bill), e_invoice (irn, ack_no,
ack_date, signed_qr), eway_bill (ewb_no, valid_upto, vehicle_no, distance_km), terms, bank details on print.

### GST and compliance
- **E-invoice**: via GSP API (e.g. ClearTax, Masters India, IRIS, Cygnet). Auto-generate IRN on invoice save when
  company turnover > threshold. Store signed JSON + QR.
- **E-way bill**: auto from invoice or from **weighbridge/dispatch** (vehicle no. already known); Part-B update when
  vehicle changes; extension alerts before expiry.
- **GSTR-1** auto-prepared; **GSTR-2B** import and match with purchases (exact / partial / missing), vendor follow-up list
  for missing ITC; **GSTR-3B** working.
- **TDS** on payments: section by party/ledger, threshold tracking per FY, 26Q data, Form 16A tracking.
  **TCS** where applicable.
- **Bank reconciliation**: statement import (Excel/CSV/PDF + AA/API where bank supports), auto-match by amount +
  date + reference/UTR, AI suggestion for the rest.
- **Inter-company**: when party `is_group_company`, posting creates a mirror entry in the other company
  (sale in RMC ⇄ purchase in Infra) with a shared `ic_reference`; mismatch report; eliminated in consolidated P&L.
- **Consolidated P&L / Balance Sheet / Cash flow** for group, with drill to company → ledger → voucher → source.
- Period lock after GST filing.

### Creative features
- **Cash position, today and next 30 days**: bank + cash − payables due + expected collections (from customer payment
  behaviour).
- **Party 360**: one screen per party across all companies with outstanding, ageing, last payment, cheque bounces,
  and running orders. Lets you "stop fuel at the bunk because RMC dues are 90 days".
- **Cheque & PDC register** with deposit reminders.
- **Tally export** during transition (XML vouchers), so the auditor keeps using Tally the first year.

---

## Module 2 – CRM and Lead management (Zoho CRM / Bigin class)

### Lead capture sources
Website form, IndiaMART/JustDial webhooks, missed-call number, WhatsApp Business (click-to-chat), phone calls (call log
sync on salesperson's phone with consent), walk-in, tender portals (manual + alerts), referral.

### Lead – fields
lead_id, source, business_line (RMC / bitumen / bricks / infra contract / bunk fleet card), name, mobile, company,
site_location (map pin), requirement (grade/qty/date for RMC; MT for hot-mix; bricks count; tender details),
expected_value, stage, owner (salesperson, auto-assigned by area/business), next_follow_up_at, lost_reason,
duplicate_of, created_via.

### Pipelines per business (configured in admin)
- RMC: New → Site visit → Quote sent → Trial pour / sample → Negotiation → Order confirmed → Lost
- Infra/tenders: Identified → Documents bought → Pre-bid → Submitted → Technical qualified → L1/L2/L3 → Awarded → Work order → Lost
- Bunk fleet credit: Enquiry → KYC → Credit limit approval → Active

### Quotation
Party/lead, items with rates from **price list** (per business, per location, per customer category; changes need
approval), validity, transport charges by distance slab (auto from site pin), pump charges (RMC), terms,
PDF + WhatsApp share, version history, convert to Order in one tap (creates RMC order / sales order / project).

### Tender tracking (fields)
tender_id, portal, department, work name, EMD amount & mode & refund status, tender fee, estimated value, bid due
date, pre-bid date, our quoted %, competitors' quotes (after opening), result, documents (NIT, BOQ, corrigenda).
Alerts 7/3/1 days before due date. EMD/BG register with expiry.

### Creative features
- **Site-hunting map**: salespeople pin construction sites they see; repeat visits tracked; nearby sites shown
  ("3 sites within 2 km of today's RMC delivery").
- **Follow-up queue is the salesperson's home screen**: call button, WhatsApp template button, voice note → AI
  summary saved to lead.
- **Win/loss analysis** by reason, by rate difference, by salesperson.
- **Cross-sell across group**: an infra contractor buying RMC is offered bitumen, bricks and bunk credit card.
