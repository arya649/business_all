# 06 – Bitumen / Hot-mix, Bricks, Petrol Bunk

---

## Module 4 – Bitumen / hot-mix plant

### Raw material inward
bitumen (VG-10/30/40, emulsion) via tanker (weighbridge ticket, temperature on arrival, test certificate, refinery
invoice), aggregates (by size), filler, fuel for burner (LDO/FO/diesel). Each inward → GRN + stock + quality record.

### Production batch – fields
batch_id, mix type (DBM, BC, SDBC, BM, WMM), job mix formula (JMF) version, aggregates % per bin, bitumen %, filler %,
batch size MT, **mix temperature** (target band from JMF, e.g. 150–165 °C), operator, burner fuel used, start/end time,
plant controller import (where available).

### Dispatch by weight
dispatch_no, order/project, tipper (weighbridge net), mix type, **temperature at dispatch** (probe photo),
site, laying temperature at site (from site engineer app), tarpaulin cover checklist, e-way bill, challan sign.

### Quality logs
bitumen content (extraction test), gradation, Marshall stability & flow, density, air voids, per batch/day;
pass/fail against JMF limits; lab photo.

### Billing
by MT dispatched (or by m² laid for laying contracts), linked to project BOQ if internal → inter-company.

### Creative features
- **Temperature chain**: plant → dispatch → arrival → laying, flagging loads rejected for low temperature
  (waste traced to transport delay).
- **Bitumen consumption reconciliation**: theoretical % × MT produced vs tanker stock dips.
- **Fuel per MT of mix** trend for burner efficiency.

---

## Module 6 – Bricks manufacturing (fly-ash / cement bricks, blocks, pavers)

### Recipe (admin)
product (fly-ash brick 230×110×75, solid block 6", paver 60mm...), per 1000 units: fly ash kg, cement kg, sand/stone
dust kg, lime/gypsum kg, water L; machine strokes per cycle.

### Daily production – supervisor mobile (one screen)
date, shift, machine, product, **good units produced** (counter or count), rejects at moulding, materials used
(auto from recipe, editable), operators (attendance), power units (meter photo), downtime reason.

### Curing stock
lot_id (date + machine), product, qty, curing yard/block, curing start, **ready date (configurable days, e.g. 14/21)**,
watering log (photo checklist), status: curing → ready → dispatched.

### Breakage
at curing, at stacking, at loading, in transit (reported by customer) – qty, photo, reason. **Breakage % by stage**.

### Dispatch
order, vehicle, qty (count; weighbridge optional), loading labour (piece-rate for HR), challan, invoice.

### Creative features
- **"Ready to sell" stock** is only cured stock; salespeople see what's ready by date.
- **Piece-rate wages** auto-computed from production and loading counts.
- **Cost per 1000 bricks** live (materials + power + labour + breakage).

---

## Module 8 – Petrol bunk (Petrometer / PetroSoft class)

### Masters
tanks (product MS/HSD/XP, capacity, **calibration chart** dip-mm → litres), dispensing units, nozzles (tank linked),
products with daily RSP (price change effective time), lubes (item master), credit customers (party with vehicle list,
limits, slips/cards), shifts, pump attendants.

### Shift open/close – attendant & manager mobile
- **Nozzle readings**: opening (auto = last closing), closing (photo of totaliser, number keypad), testing litres
  returned to tank, computed sale = closing − opening − testing.
- **Payment split**: cash (denomination count), UPI/POS (auto from bank/POS settlement where possible), fleet cards,
  **credit sales** (indent slips: customer, vehicle, product, litres, slip photo), internal fuel to group vehicles.
- **Shortage/excess** = expected collection − actual → attendant account.

### Tank management
- **Daily dip** (morning) with water dip, temperature, **density** (hydrometer) → litres via calibration chart, at 15 °C.
- **Tanker receipt**: invoice qty, compartment-wise dip before/after, density at receipt vs invoice density
  (adulteration check), decantation time, seal numbers, photos. Short receipt → claim with oil company.
- **Variance**: book stock (opening + receipts − sales) vs dip stock; daily and cumulative; alert beyond tolerance
  (e.g. 0.5% evaporation allowance configurable).
- **ATG integration** (automatic tank gauge) and dispenser/DU automation where available.

### DSR (daily stock & sales register)
auto-generated: per product opening, receipts, sales by nozzle, testing, closing book vs dip, variance, rate, value,
cash/bank deposits. Printable in oil-company format.

### Credit customers
indent slip / vehicle-wise sales, limit check at sale (offline cache of balances), fortnightly bills, statements on
WhatsApp, collection tracking.

### Internal issue to group vehicles
vehicle scan (RFID/QR on vehicle), litres, odometer photo → **inter-company sale** (bunk company → RMC/Infra company)
at transfer price + fleet module fuel record. **One entry, three outcomes**: bunk stock reduced, group vehicle fuel log,
inter-company invoice.

### Lubes stock
item, batch, sales at counter with bill, stock count.

### Creative features
- **Variance detective**: AI correlates tank variance with nozzle, attendant, shift, temperature, recent tanker receipt.
- **Price-change guard**: rate auto-updated at 6 am; readings at price-change time captured.
- **Cash deposit tracker**: cash collected vs deposited in bank, days pending.
- **Compliance**: PESO licence, weights & measures stamping of nozzles, fire NOC, calibration reminders.
