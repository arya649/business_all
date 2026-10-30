# 01 – Core Platform (build first)

Everything here is shared. No module stores its own customers, items, users or approvals.

---

## 0.1 Super Admin and multi-company setup

### Hierarchy

```
Group (1)
 └─ Company (n)            each has its own GSTIN(s), PAN, books, number series
     └─ Location (n)       type = Branch | Plant | Site | Bunk | Yard | Office | Warehouse
         └─ Sub-location   Silo, Tank, Bay, Store room, Block (bricks), Floor (site)
```

### Tables and fields

**group**: id, name, logo, financial_year_start (default 1 Apr), base_currency (INR), timezone, default_language.

**company**: id, group_id, legal_name, trade_name, PAN, TAN, CIN, logo, letterhead_template, books_start_date,
is_active, modules_enabled[] (from feature registry), owner_user_id.

**company_gstin** (one company can hold several states): id, company_id, gstin, state_code, registered_address,
e_invoice_enabled, e_invoice_threshold_crossed, gsp_credentials_ref (vault key), eway_enabled, filing_frequency (monthly / QRMP).

**location**: id, company_id, gstin_id, type, name, short_code (used in document numbers, e.g. `RMC-VJA`), address,
lat, lng, geofence_radius_m (for attendance and GPS trips), in_charge_user_id, cost_centre_id, is_active,
working_hours, weekly_off.

**number_series**: id, company_id, location_id, doc_type, prefix pattern `{CO}/{LOC}/{FY}/{SEQ:5}`,
next_value, reset_on (FY / never), offline_block_size (see offline sync).

### Users, roles and permissions

**user**: id, name, mobile (login ID; OTP login, no passwords for field staff), email, photo, preferred_language,
employee_id (link to HR), default_company_id, default_location_id, device_ids[], is_active, last_seen.

**role**: id, group_id, name (e.g. Plant Operator, Site Engineer, Accountant, Bunk Cashier, Owner), template_from,
ui_mode = `simple` | `standard` | `power`.

**permission** (role × module × action × scope):

| Field | Values |
|---|---|
| module | finance, crm, rmc, ... (from registry) |
| feature | e.g. `rmc.batch_entry`, `finance.journal` |
| actions | view, create, edit, delete, approve, export, print, see_rates, see_cost |
| scope | own records / own location / own company / all companies |
| field_masks | fields hidden for this role, e.g. `purchase_rate`, `salary` |
| time_lock | can edit only within N hours of creation |

**user_assignment**: user_id, company_id, location_ids[], role_id, valid_from, valid_to. One person can be a
Site Engineer at site A and a Store Keeper at site B.

### Feature toggles (the navamedu-style on/off)

Every module, screen, field group, report and integration is a node in `feature-registry.json`.
Super Admin flips them in a tree screen. Resolution order (most specific wins):

```
group default → company → location → role → user
```

**feature_flag**: id, feature_key, level (group/company/location/role/user), level_id, state (on / off / read_only / hidden),
config_json (e.g. for `rmc.cube_test`: `{ "ages": [7, 28], "min_samples": 3 }`), changed_by, changed_at.

Effects:
- **off**: menu, tiles, API endpoints, AI tools and reports for that feature disappear. Data is kept.
- **read_only**: visible, nothing can be created or edited (useful when closing a site).
- **hidden fields**: a field group (e.g. "Density" on tanker receipt) disappears from the form and is not required.
- Mobile app downloads the resolved flag set at login and on every sync, so toggles work offline too.

The Super Admin screen shows: tree with switches, a "preview as user" button (see the app exactly as a chosen user
would), and copy-settings-from-company.

### Problems this solves
- New company or new bunk set up in 10 minutes using **company templates** ("RMC company", "Bunk company") that
  pre-enable modules, roles, ledgers, number series and posting rules.
- Owner can see everything; a site engineer can't see rates; a cashier can't edit after shift close.

---

## 0.2 Common masters

One table per master, shared by all companies, with a `company_links` child so the same party can be a customer of
Company A and a vendor of Company B.

### Party (customers, vendors, sub-contractors, transporters, employees-as-payees, group companies)

| Field | Notes |
|---|---|
| id, party_code | auto |
| display_name, legal_name | |
| party_types[] | customer, vendor, sub_contractor, transporter, credit_customer_bunk, govt_dept |
| is_group_company, group_company_id | **drives inter-company tagging automatically** |
| gstin, pan, gst_treatment | regular / composition / unregistered / SEZ / consumer. GSTIN validated live and name/address auto-filled |
| msme_udyam_no, msme_type | 45-day payment alert for MSME vendors |
| addresses[] | billing, shipping, site addresses with lat/lng (sites are delivery points for RMC/bitumen) |
| contacts[] | name, mobile, WhatsApp yes/no, role (accounts, site, purchase) |
| bank_accounts[] | for payments; penny-drop verification |
| tds_section, tds_rate, lower_deduction_cert | |
| credit_limit, credit_days, per company | |
| risk_score | computed: payment delays, bounced cheques, disputes |
| kyc_docs[] | GST cert, PAN, cancelled cheque |
| status | active / blocked (blocked = no new orders, no fuel on credit) |
| duplicates_check | fuzzy match on GSTIN, PAN, mobile, name before save |

### Item / material

item_code, name, local_name (shown to field users), photo, category (raw material, finished good, consumable,
spare, fuel, lube, service, asset), uom + alternate uoms with conversion (e.g. cement: bag ↔ MT, 1 bag = 0.05 MT;
aggregate: MT ↔ cft ↔ brass), hsn_sac, gst_rate, is_batch_tracked, is_serial_tracked (tyres, batteries),
reorder_level per location, standard_cost, valuation (FIFO / weighted avg), quality_params[] (e.g. bitumen:
penetration, softening point), weighbridge_item (Y/N), min/max moisture %.

### Vehicle / machine (one master used by Fleet, Weighbridge, RMC, Bunk, Infra)

vehicle_id, reg_no, type (transit mixer, tipper, tanker, JCB, roller, paver, DG set, car), owner (own / hired / customer),
owning_company_id, capacity (m³ / MT / KL), tare_weight_standard, rfid_tag, fastag, gps_device_id, fuel_sensor_id,
fuel_type, tank_capacity, expected_km_per_l or l_per_hr, odometer / hour meter current, assigned_driver_id,
current_location_id, documents (insurance, fitness, permit, PUC, RC, tax) each with expiry and file, status.

### Employee (from HR, visible to all as a picker)
### Project / site (from Infra, also a delivery location for RMC and bitumen)
### Chart of accounts and cost centres (from Finance)

### Problems this solves
- No more "Ravi Constructions" typed five different ways across bunk, RMC and accounts.
- One outstanding view per party across all companies (what they owe RMC + bunk + bitumen).

---

## 0.3 Approvals engine

**approval_rule**: id, doc_type (PO, indent, expense, price_change, credit_limit, credit_override, payment, journal,
discount, leave, advance, stock_adjustment, rate_contract), company_id, condition (expression, e.g.
`amount > 50000 && category == 'capital'`), steps[] each with approver (user / role / reporting manager / location head),
mode (any one / all), sla_hours, escalate_to, auto_approve_below.

**approval_request**: doc_type, doc_id, current_step, status, history[] (who, when, action, comment, voice_note,
location of approver).

Mobile approval card shows **only what the approver needs**: what, how much, vs last time, vs budget, who asked,
one photo, and two buttons. Approve from WhatsApp too ("Reply 1 to approve, 2 to reject").

Creative features:
- **Context on the card**: "This PO rate for 53-grade cement is ₹15 higher per bag than the last 3 POs."
- **Delegation** when the approver is on leave.
- **Credit override with a timer**: approve "dispatch 1 more load on credit for 24 hours".

---

## 0.4 Notifications

Channels: in-app push, WhatsApp (Business API via a BSP such as Gupshup / Interakt / Meta Cloud API), SMS (DLT-registered
templates), email.

**notification_rule**: event (e.g. `fleet.document_expiring`, `bunk.dip_variance`, `rmc.order_delayed`), condition,
recipients (role / user / party contact), channel, template_id (language-specific), quiet_hours, digest (instant /
hourly / daily).

**Owner daily summary (WhatsApp, 8 pm and 8 am)**: one image card + 6 lines:

```
Yesterday – Group
Sales ₹18.4L (RMC 9.1 · Bunk 6.2 · Bitumen 3.1)   Cash in ₹11.2L
Receivables ₹2.3Cr (₹41L > 60 days – top: XYZ Infra ₹12L)
Diesel used 4,120 L – 3 vehicles above norm (AP16 TX 4521 +18%)
RMC 212 m³ poured · 2 late deliveries
⚠ Bunk tank 2 variance −38 L · Insurance expiring: 4 vehicles
Tap for details →
```

Customer-facing: RMC order confirmed / truck left plant (with live link) / delivered + challan PDF; invoice sent;
payment reminder; bunk credit statement.

---

## 0.5 Owner dashboard

Drill path: **Group → Company → Location → Document**. Every number is tappable down to the source record and photo.

Tiles: Sales today / MTD / vs last month, Cash & bank balance, Receivables ageing, Payables due this week, Diesel
consumed and cost vs norm, Production (m³ RMC, MT hot-mix, bricks), Project progress % vs plan and billing,
Fleet utilisation, Stock value by location, Pending approvals, Alerts.

Creative features:
- **"What changed?" button**: AI explains the biggest movements vs yesterday / last week in plain language.
- **Leakage board**: one screen listing money leaks found by rules: diesel variance, weighbridge mismatch, tank
  variance, unbilled challans, idle machines, material over-consumption vs BOQ, cash shortages.
- **Unbilled work tracker**: delivered but not invoiced (RMC challans, bitumen dispatch, sub-con work) – usually the
  biggest silent loss.

---

## 0.6 Audit log and documents

**audit_log** (append-only, cannot be edited even by Super Admin): table, record_id, action, before_json, after_json,
user_id, device_id, ip, geo, timestamp, source (web / mobile / api / ai_agent / hardware), reason (mandatory for edits
after lock).

**document_store**: id, entity_type, entity_id, doc_category (licence, tender, work order, drawing, GST cert,
insurance, PESO licence, pollution consent, calibration cert), file, version, issued_on, expiry_on, reminder_days[],
tags, OCR text (searchable), uploaded_by.

Creative features:
- **Expiry calendar** for every licence and certificate across the group (PESO, weights & measures stamping,
  pollution board, factory licence, labour licence, vehicle papers).
- **Photo evidence everywhere**: every photo is stamped with time, GPS and user, and cannot be picked from the
  gallery when the toggle "camera only" is on.
- **Record lock**: periods lock after GST filing; edits need a reason and approval.

---

## 0.7 Offline sync (applies to every mobile screen)

Design: local-first.

- Each device has a local SQLite database holding the user's slice (their locations, masters, open documents,
  resolved flags). Recommended engine: **PowerSync** or **ElectricSQL** on Postgres, or **WatermelonDB** with a
  custom sync endpoint.
- Every record has `uuid` generated on device, `created_offline`, `device_id`, `sync_status`, `version`.
- **Document numbers offline**: the device reserves a block of numbers from the series (e.g. 50 challan numbers)
  while online, so challans printed offline still have valid legal numbers.
- **Conflict rule**: operational entries are append-only (readings, trips, weights), so they never conflict. For
  editable records, last-writer-wins per field plus an audit entry; for money fields, conflicts go to a review queue.
- Photos upload in the background, compressed, resumable.
- Sync indicator is a small coloured dot, never a blocking dialog. "37 entries waiting to send" if offline > 2 hours,
  and the supervisor is alerted if a device hasn't synced for 24 hours.
- Bluetooth printers (challans, bunk receipts) work offline.

---

## 0.8 UX rules for non-technical users (mandatory for every screen)

1. **Home = tiles of today's jobs**, not menus. A bunk cashier sees: "Open shift · Nozzle readings · Credit sale · Close shift".
2. **Max 5 inputs per screen.** Everything else defaults (date, location, user, shift, rate, GST).
3. **Pick, don't type**: photo grids of items/vehicles, recent-first lists, scan (QR, RFID, number plate), weigh, voice.
4. **Numbers keypad only** where a number is expected; huge font; show unit beside the box (L, MT, m³).
5. **Instant sanity checks in plain words**: "Reading is lower than last shift (12,450). Check again?" – not error codes.
6. **Local language + voice**: every label translated; mic button on every text field; AI turns speech into the form.
7. **Undo for 10 minutes** instead of "Are you sure?" popups.
8. **Colour meanings fixed app-wide**: green done, amber needs attention, red stopped/loss.
9. **Three UI modes per role**: Simple (field), Standard (office), Power (accounts/admin – grids, bulk edit, shortcuts).
10. **Training built in**: 30-second video on each tile's first use; "Ask" button opens the AI helper.
11. **All complexity lives in admin**: posting rules, tax rules, number series, approval chains, formulas, norms,
    templates – configured once by admin, invisible to users.
