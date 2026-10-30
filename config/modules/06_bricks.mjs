import { f, party, item, vehicle, user } from "./_dsl.mjs";

export default {
  module: "bricks",
  label: "Bricks manufacturing",
  entities: [
    {
      key: "bricks.recipe", feature: "bricks.recipe", label: "Recipe", kind: "master", scope: "location", title: "product_id",
      fields: [
        item("product_id", "Product", { required: true, list: true }),
        f.int("per_units", "Quantities are per", { default: "1000", unit: "units" }),
        f.int("units_per_stroke", "Units per machine stroke", { default: "6" }),
        f.int("curing_days", "Curing days", { default: "14" }),
        f.money("cost_per_1000", "Cost per 1000", { sensitive: "cost", list: true }),
      ],
      children: [{
        name: "materials", label: "Materials", fields: [
          item("item_id", "Material", { required: true }),
          f.qty("qty", "Qty", { required: true }),
          f.text("uom", "Unit", { default: "KG" }),
        ],
      }],
    },
    {
      key: "bricks.production", feature: "bricks.daily_production", label: "Daily production", plural: "Daily production", kind: "transaction",
      scope: "location", numbering: "BP/{LOC}/{FY}/{SEQ:5}", dated: true, mobile: true, icon: "blocks", title: "doc_no",
      description: "One screen for the supervisor. Materials are taken from the recipe; good units go to the curing yard.",
      fields: [
        f.select("shift", "Shift", ["day", "night"], { default: "day", quick: true }),
        f.text("machine", "Machine", { quick: true }),
        item("product_id", "Product", { required: true, quick: true, list: true }),
        f.int("good_units", "Good units", { required: true, quick: true, list: true, check: "good_units >= 0" }),
        f.int("rejected_units", "Rejected at moulding", { default: "0", quick: true }),
        f.int("operators", "Operators"),
        f.number("power_units_kwh", "Power used", { unit: "kWh" }),
        f.number("downtime_minutes", "Downtime (min)", { default: "0" }),
        f.text("downtime_reason", "Downtime reason"),
        f.text("curing_block", "Curing block / yard", { quick: true }),
      ],
      children: [{
        name: "materials", label: "Materials used", fields: [
          item("item_id", "Material", { required: true }),
          f.qty("qty", "Qty", { required: true }),
        ],
      }],
      stock: [{ child: "materials", item: "item_id", qty: "qty", dir: "out" }],
    },
    {
      key: "bricks.curing_lot", feature: "bricks.curing", label: "Curing lot", kind: "transaction", scope: "location",
      numbering: "LOT/{LOC}/{SEQ:5}", dated: true, mobile: true, icon: "droplets", title: "doc_no",
      fields: [
        f.ref("production_id", "Production", "bricks.production", { required: true }),
        item("product_id", "Product", { required: true, list: true }),
        f.int("qty", "Units", { required: true, list: true }),
        f.text("curing_block", "Block / yard", { list: true }),
        f.date("ready_on", "Ready on", { list: true }),
        f.int("broken", "Broken in curing", { default: "0" }),
        f.int("dispatched", "Dispatched", { default: "0" }),
        f.calc("available", "Available", "int", "qty - coalesce(broken, 0) - coalesce(dispatched, 0)", { list: true }),
        f.select("lot_status", "Status", ["curing", "ready", "partly_dispatched", "finished"], { default: "curing", list: true }),
        f.date("last_watered", "Last watered"),
      ],
    },
    {
      key: "bricks.breakage", feature: "bricks.breakage", label: "Breakage", kind: "log", scope: "location", dated: true, mobile: true,
      icon: "trash", title: "stage",
      fields: [
        f.select("stage", "Where", ["curing", "stacking", "loading", "transit", "at_customer"], { required: true, quick: true, list: true }),
        item("product_id", "Product", { required: true, quick: true }),
        f.ref("lot_id", "Lot", "bricks.curing_lot"),
        f.int("qty", "Units broken", { required: true, quick: true, list: true }),
        f.text("reason", "Reason", { quick: true }),
        f.photo("photo", "Photo", { quick: true }),
      ],
    },
    {
      key: "bricks.dispatch", feature: "bricks.dispatch", label: "Bricks dispatch", plural: "Bricks dispatches", kind: "transaction",
      scope: "location", numbering: "BD/{LOC}/{FY}/{SEQ:5}", dated: true, mobile: true, icon: "truck", amount: "amount",
      fields: [
        party("party_id", "Customer", { required: true, quick: true, list: true }),
        item("product_id", "Product", { required: true, quick: true, list: true }),
        f.ref("lot_id", "From lot", "bricks.curing_lot", { quick: true }),
        f.int("qty", "Units", { required: true, quick: true, list: true, check: "qty > 0" }),
        f.text("vehicle_no", "Vehicle no", { quick: true }),
        f.int("loaders", "Loading labour (count)"),
        f.money("loading_rate_per_1000", "Loading rate / 1000", { sensitive: "rates" }),
        f.money("rate_per_1000", "Rate / 1000", { sensitive: "rates" }),
        f.calc("amount", "Amount", "money", "round(qty * coalesce(rate_per_1000, 0) / 1000, 2)", { sensitive: "rates", list: true }),
        f.select("billing_status", "Billing", ["unbilled", "billed", "cash_sale"], { default: "unbilled", list: true }),
      ],
    },
  ],
};
