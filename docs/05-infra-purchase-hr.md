# 05 – Infra Projects, Purchase & Stores, HR & Payroll

---

## Module 7 – Infra / construction projects (Powerplay / Onsite class)

### Project – fields
project_id, name, client (party, often govt dept), work order no & date, contract value, start/end dates, LD clause,
retention %, security deposit, mobilisation advance & recovery %, site location (geofence), project manager,
site engineers[], company executing (and GSTIN), price escalation clause.

### BOQ
boq_item: item_no, description, unit, contract qty, rate, amount, **material norms** (e.g. M25 per m³ → linked to RMC
order; bricks per m² → Bricks module; bitumen mix MT per m² → Bitumen), labour norms, sub-contractor assigned.
Excel import of BOQ.

### Daily progress report (DPR) – site engineer mobile, offline
date, weather, boq_item, qty done today, location/chainage/floor, photos (mandatory, geo-stamped), manpower by trade
(from attendance), machines used (hours), materials consumed, hindrances (client delay, rain, drawing pending),
next day plan. **Voice-to-DPR** via AI.

### Measurement book & RA bills
measurement entries (L × B × D, nos) per BOQ item → cumulative qty → RA bill: previous + this bill + cumulative,
deductions (retention, SD, mobilisation recovery, TDS, GST TDS, labour cess, materials supplied by client),
net payable, client certified qty (often lower) → **difference tracker**.

### Labour
attendance by face photo + geofence on supervisor phone (works offline), trade, gang/contractor, OT, wages per day,
muster roll export as per labour law formats.

### Site material
material request (MR) → purchase indent or **transfer from another site/central store** → receipt at site (GRN with
photo) → issue to BOQ item → **consumption vs norm** report.

### Sub-contractor
work order (scope, BOQ items, rates), measurements, bills, deductions (materials supplied, advances, retention, TDS),
payment.

### Creative features
- **Project health one-pager**: % physical vs % financial vs % time elapsed, billed vs certified vs received,
  material over-consumption, labour productivity.
- **Photo timeline per BOQ item** – settles disputes with clients and sub-contractors.
- **Hindrance register auto-built from DPRs** – evidence for extension of time and escalation claims.
- **Cash-flow forecast per project** from billing schedule and client payment history.

---

## Module 10 – Purchase and stores (Zoho Inventory / Odoo class)

### Flow
Indent (site/plant/bunk) → approval → **central buying** groups indents across companies → RFQ to vendors →
comparative statement (auto L1) → PO (with approval) → delivery → **weighbridge ticket / GRN** →
quality check → vendor invoice → **3-way match** → payment.

### Key fields
- **Indent**: location, items, qty, required by, purpose/BOQ item/vehicle, priority, photo (for spares).
- **PO**: vendor, items, rates, taxes, delivery location(s), schedule, freight terms, payment terms, rate contract ref,
  validity, approval trail.
- **GRN**: PO ref, vendor challan no & qty, received qty (or weighbridge net), accepted, rejected + reason, batch,
  photos, store location/bin, received by.
- **3-way match**: PO rate × GRN qty vs invoice; tolerance set in admin; mismatches go to accounts queue with reason.

### Stock
item × location × bin × batch; transfers between locations/companies (inter-company → sale/purchase automatically;
same company → stock transfer, e-way bill if needed); issues to cost centre/vehicle/BOQ; physical count via mobile
(blind count – counter doesn't see system qty); adjustment with approval.

### Creative features
- **Rate contracts and price history**: every PO line shows last 5 rates across all companies.
- **Group-wide stock visibility**: before buying, see if another site has surplus.
- **Vendor scorecard**: on-time, short supply, quality rejections, rate competitiveness.
- **Reorder suggestions** using consumption trend + lead time.

---

## Module 11 – HR and Payroll (Zoho Payroll / greytHR class)

### Employee – fields
emp_code, name, photo, mobile, Aadhaar (masked, consent), PAN, UAN, ESIC no, bank, company, location, department,
designation, grade, employment type (permanent / contract / daily wage / driver / operator), contractor (for contract
labour), DOJ, salary structure, shift, weekly off, reporting manager, documents (licence for drivers with expiry).

### Attendance
biometric devices (ZKTeco / eSSL via push API or SDK), mobile with face + geofence (offline), shifts (rotational at plants
and bunk), OT rules, late/early, regularisation requests with approval, leave types and balances.

### Payroll
structure (basic, DA, HRA, allowances, incentives from other modules – e.g. driver trip incentive, bunk sales
incentive), statutory: **PF (12/12, EDLI), ESI, Professional Tax (state), LWF, TDS** on salary; advances & loan
recovery; salary hold; arrears; payslips on WhatsApp in local language; bank transfer file; posting to Finance by
cost centre/location.

### Contract labour
contractor master, labour per contractor, attendance, wage register, contractor bill verification against
attendance, PF/ESI compliance proof from contractor (challans uploaded) before payment.

### Creative features
- **Cashless advances**: employee requests on phone → approval → UPI payout → auto recovery in payroll.
- **Payroll pre-check**: AI lists anomalies before run (someone with 31 days present in a 30-day month, OT spikes).
- **Incentives pulled automatically from operations** (trips, m³ delivered, litres sold) – no Excel.
