import { f, party, item, vehicle } from "./_dsl.mjs";

const MIXES = ["DBM", "BC", "SDBC", "BM", "MSS", "PMC", "WMM", "GSB"];

export default {
  module: "bitumen",
  label: "Bitumen / hot-mix plant",
  entities: [
    {
      key: "bitumen.jmf", feature: "bitumen.jmf", label: "Job mix formula", kind: "master", scope: "location", title: "mix_type", workflow: true,
      fields: [
        f.select("mix_type", "Mix", MIXES, { required: true, list: true }),
        f.text("jmf_code", "JMF code", { required: true, list: true }),
        f.percent("bitumen_pct", "Bitumen %", { required: true, list: true }),
        f.select("bitumen_grade", "Bitumen grade", ["VG10", "VG30", "VG40", "CRMB55", "CRMB60", "PMB40", "emulsion_RS1", "emulsion_SS1"]),
        f.number("mix_temp_min_c", "Mix temperature min", { unit: "°C", default: "150" }),
        f.number("mix_temp_max_c", "Mix temperature max", { unit: "°C", default: "165" }),
        f.number("laying_temp_min_c", "Laying temperature min", { unit: "°C", default: "120" }),
        f.json("gradation", "Gradation limits", { help: '{"26.5mm": [100,100], "19mm": [79,100], ...}' }),
        f.number("marshall_stability_min_kn", "Marshall stability min", { unit: "kN" }),
        f.money("cost_per_mt", "Cost per MT", { sensitive: "cost" }),
        f.money("price_per_mt", "Price per MT", { sensitive: "rates" }),
      ],
      children: [{
        name: "bins", label: "Aggregate proportions", fields: [
          item("item_id", "Aggregate / filler", { required: true }),
          f.percent("pct", "% of aggregate", { required: true }),
        ],
      }],
    },
    {
      key: "bitumen.batch", feature: "bitumen.production_batch", label: "Production batch", plural: "Production batches", kind: "transaction",
      scope: "location", numbering: "HM/{LOC}/{FY}/{SEQ:6}", dated: true, mobile: true, icon: "flame", title: "doc_no",
      description: "Each batch with temperature. Materials used come off stock; temperature outside the JMF band is flagged.",
      fields: [
        f.ref("jmf_id", "JMF", "bitumen.jmf", { required: true, quick: true, list: true }),
        f.qty("batch_mt", "Batch", { unit: "MT", required: true, quick: true, list: true, check: "batch_mt > 0" }),
        f.number("mix_temp_c", "Mix temperature", { unit: "°C", required: true, quick: true, list: true }),
        f.bool("temp_alert", "Temperature outside band", { list: true }),
        f.qty("bitumen_kg", "Bitumen used", { unit: "kg" }),
        f.qty("burner_fuel_l", "Burner fuel", { unit: "L" }),
        f.datetime("start_at", "Start", { default: "now()" }),
        f.datetime("end_at", "End"),
        f.select("source", "Weights from", ["plant_controller", "manual"], { default: "manual" }),
      ],
      children: [{
        name: "materials", label: "Materials", fields: [
          item("item_id", "Material", { required: true }),
          f.qty("qty_kg", "Qty", { unit: "kg", required: true }),
        ],
      }],
      stock: [{ child: "materials", item: "item_id", qty: "qty_kg", dir: "out" }],
    },
    {
      key: "bitumen.dispatch", feature: "bitumen.dispatch", label: "Hot-mix dispatch", plural: "Hot-mix dispatches", kind: "transaction",
      scope: "location", numbering: "HD/{LOC}/{FY}/{SEQ:5}", dated: true, mobile: true, icon: "truck", amount: "amount",
      fields: [
        party("party_id", "Customer / project", { required: true, quick: true, list: true }),
        f.select("mix_type", "Mix", MIXES, { required: true, quick: true, list: true }),
        f.ref("weighbridge_ticket_id", "Weighbridge ticket", "weighbridge.ticket"),
        f.ref("vehicle_id", "Tipper", "vehicle", { quick: true }),
        f.text("vehicle_no", "Vehicle no"),
        f.qty("net_mt", "Net", { unit: "MT", required: true, quick: true, list: true }),
        f.number("dispatch_temp_c", "Temperature at dispatch", { unit: "°C", quick: true }),
        f.photo("temp_photo", "Probe photo"),
        f.bool("tarpaulin_covered", "Tarpaulin covered", { quick: true }),
        f.number("arrival_temp_c", "Temperature at site", { unit: "°C" }),
        f.number("laying_temp_c", "Laying temperature", { unit: "°C" }),
        f.select("site_acceptance", "Site", ["accepted", "rejected_low_temp", "rejected_other"]),
        f.text("site_name", "Site / chainage"),
        f.money("rate_per_mt", "Rate per MT", { sensitive: "rates" }),
        f.calc("amount", "Amount", "money", "round(net_mt * coalesce(rate_per_mt, 0), 2)", { sensitive: "rates", list: true }),
        f.select("billing_status", "Billing", ["unbilled", "billed", "not_billable"], { default: "unbilled", list: true }),
      ],
    },
    {
      key: "bitumen.quality_test", feature: "bitumen.quality_lab", label: "Quality test", kind: "log", scope: "location", dated: true, title: "mix_type",
      fields: [
        f.select("mix_type", "Mix", MIXES, { required: true, list: true }),
        f.ref("batch_id", "Batch", "bitumen.batch"),
        f.percent("bitumen_content_pct", "Bitumen content (extraction)", { list: true }),
        f.number("marshall_stability_kn", "Marshall stability", { unit: "kN" }),
        f.number("flow_mm", "Flow", { unit: "mm" }),
        f.number("density", "Density", { unit: "g/cc" }),
        f.percent("air_voids_pct", "Air voids %"),
        f.json("gradation_result", "Gradation"),
        f.select("result", "Result", ["pass", "fail"], { list: true }),
        f.photo("report_photo", "Report"),
      ],
    },
  ],
};
