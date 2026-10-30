# 04 – RMC Plant, Weighbridge, Fleet & Machines

These three share data constantly: the weighbridge weighs the transit mixer, the fleet module tracks it on GPS,
the RMC module bills the load.

---

## Module 3 – RMC plant

### Masters (admin)
- **Mix design / grade**: grade (M10–M60, special), mix_id, version, cement kg/m³, fly ash/GGBS kg/m³, 20mm, 10mm,
  sand (M-sand/river) kg/m³, water L/m³, admixture L/m³ (brand), w/c ratio, slump target ± tolerance, approved_by,
  effective_from. **Cost per m³ auto-computed** from latest material rates.
- **Plant**: batching capacity m³/hr, silos[] (material, capacity), bins[], pumps (boom/line, capacity).
- **Distance slabs and transport rates**.

### Order – fields
order_no, customer, site (map pin + contact), grade, qty m³, pour date + start time, pour rate m³/hr required,
pump required (type), structural element (slab/column/footing), slump required, special instructions,
price (from quote/price list), credit check result, status.

### Pour scheduling
Calendar board (drag-and-drop) by plant: each order becomes a block; system computes trucks needed =
`(round-trip time ÷ pour interval)` using **GPS travel time** to site; flags clashes, pump double-booking, and silo
stock shortage for the day's plan.

### Batch entry (per load / trip)
batch_ticket_no, order_no, truck (scan RFID/QR), driver, qty m³ in this load, actual weights per material
(**auto-read from batching plant controller** via export file/OPC/Modbus where available; else manual),
deviation % vs mix design (red if > tolerance), water added, batch start/end time, operator.

### Transit mixer trip
trip_id, truck, load time, plant exit (weighbridge/GPS geofence), site arrival, pour start, pour end, site exit,
plant return, km (GPS), diesel (from fleet), waiting time at site, **returned concrete m³** and its disposal.

### Delivery challan (mobile, offline, printable)
challan_no (offline-reserved block), customer, site, grade, qty, truck, driver, time out, **customer sign on phone +
photo of receiver**, slump measured at site, remarks, GPS stamp. WhatsApp copy to customer automatically.

### Cube test records
sample_id, order, batch_ticket, date cast, no. of cubes, test ages (7, 28 configurable), results (load kN →
strength N/mm² auto), avg vs grade characteristic, pass/fail, lab (own / third-party), photo of report.
Auto-alert on failure + list of all pours from that batch/day.

### Billing
Invoice built automatically from signed challans (daily / per order / per fortnight as per customer setting), pump
charges, waiting charges beyond free time, short-load charges. Unbilled challans tracker.

### Accounting posts
Invoice → Sales; material consumption from batch weights → stock reduction + COGS; trip diesel → cost per m³.

### Creative features
- **Live "where's my concrete" link** for the customer (truck on map, ETA).
- **Real profit per m³ per order**: mix cost + diesel + driver + pump + waiting – what the customer paid.
- **Material reconciliation**: theoretical (from batches) vs actual (silo dips/stock count) for cement – the #1 RMC
  leakage.
- **Waiting-time charge evidence**: GPS timestamps auto-attached to the invoice.

---

## Module 5 – Weighbridge

### Hardware
Indicator (RS-232/USB/TCP) → **local gateway service** (small PC/Raspberry Pi at the weighbridge) that reads stable weight,
captures IP camera snapshots (front + top), reads RFID/UHF tag or ANPR plate, controls boom barrier/traffic light,
prints ticket; works fully offline and syncs.

### Weighment ticket – fields
ticket_no, type (purchase inward / sales dispatch / internal transfer / job-work / third-party paid weighing),
vehicle_no (from ANPR/RFID, editable with reason), vehicle_id, driver, party, linked document (PO / sales order /
RMC trip / bitumen dispatch / transfer), item, **first weight + time + images**, **second weight + time + images**,
gross, tare, net, **standard tare check** (vs vehicle master ± tolerance), deductions (moisture %, bags, dust),
final qty, rate (for paid weighing), operator, mode (auto / manual – manual needs reason and gets flagged).

### Linking
- Purchase: ticket net → GRN qty (vendor challan qty vs our weight → shortage auto debit note).
- Sales: ticket → dispatch/challan → invoice + e-way bill (vehicle and qty already known).

### Anti-fraud features (big leakage area)
- Weight accepted only when indicator is **stable for N seconds**; no typed weights unless toggle allows (then flagged).
- Camera snapshot mandatory at both weighments; **AI checks** it's the same vehicle and number plate.
- **Tare drift alert**: vehicle tare differs from its history (water tank filled, extra spare loaded).
- **Round-trip time check**: very short gap between first and second weighment.
- Daily weighbridge report to owner: tickets, manual overrides, deleted/cancelled tickets.
- Calibration certificate (legal metrology stamping) expiry reminder.

---

## Module 9 – Fleet and machines

### Data feeds
GPS devices (via vendor API or direct TCP from common Indian AIS-140 devices), fuel level sensors (capacitive),
CAN/engine-hour where available, FASTag statements, bunk internal fuel issues (Module 8), manual fills elsewhere.

### Trip – fields
trip_id, vehicle, driver, purpose (RMC delivery / material haul / site shifting / staff), from, to, linked doc
(RMC trip / dispatch / PO), start/end odo or hours, GPS km, load qty, revenue (internal or external), tolls.

### Fuel – fields
fill_id, vehicle, date/time, source (own bunk / outside bunk / tanker at site), litres, rate, amount, odometer/hour
meter (photo), bill photo, fuel sensor rise (auto), mismatch flag.

**Mileage vs norm per vehicle** (km/L for trucks, L/hr for machines) and **fuel drops while stationary** (theft).

### Service & maintenance
service schedule per vehicle model (every X km / Y hours / Z days), job cards (complaint, parts from store, labour,
vendor, downtime hrs), breakdown log with photos, AMC contracts.

### Tyres
serial-tracked: tyre_no, brand, purchase date, cost, fitted vehicle + position, fitment odo, removal odo, retreads,
km per tyre, scrap reason. Tyre rotation reminders.

### Documents
insurance, fitness, permit, PUC, road tax, national permit – expiry alerts 30/15/7 days to fleet manager & owner,
renewal workflow with cost.

### Machines (JCB, rollers, pavers)
engine hours, daily log (site, hours worked, idle hours, operator, fuel), hire-in/hire-out billing by hour/day/month.

### Creative features
- **Cost per km / per hour / per m³ delivered** for every vehicle; "should we sell this truck?" report.
- **Idle asset finder**: machines idle > 3 days at one site while another site is hiring the same machine.
- **Driver scorecard**: overspeed, harsh braking, mileage, late deliveries → incentive calculation in HR.
