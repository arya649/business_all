// Small helpers for describing module records. Every field takes (name, label, options).
// Options: required, quick (on the simple mobile form), list (column in lists), unit, help, section,
//          default (SQL literal text), sensitive ('rates' | 'cost'), check (SQL boolean on this row), expr (computed).

const field = (type) => (name, label, o = {}) => ({ name, label, type, ...o });

export const f = {
  text: field("text"),
  longtext: field("longtext"),
  int: field("int"),
  number: field("number"),
  money: field("money"),
  qty: field("qty"),
  percent: field("percent"),
  date: field("date"),
  datetime: field("datetime"),
  time: field("time"),
  bool: field("bool"),
  photo: field("photo"),
  photos: field("photos"),
  file: field("file"),
  geo: field("geo"),
  json: field("json"),
  phone: (name, label, o = {}) => ({ name, label, type: "phone", check: `${name} is null or ${name} ~ '^\\+?[0-9]{10,15}$'`, ...o }),
  select: (name, label, options, o = {}) => ({ name, label, type: "select", options, ...o }),
  multi: (name, label, options, o = {}) => ({ name, label, type: "multiselect", options, ...o }),
  ref: (name, label, ref, o = {}) => ({ name, label, type: "ref", ref, ...o }),
  // computed from other columns of the same row, e.g. calc("net_kg", "Net", "number", "gross_kg - tare_kg")
  calc: (name, label, type, expr, o = {}) => ({ name, label, type, expr, ...o }),
};

// Party / item / vehicle shortcuts used everywhere.
export const party = (name = "party_id", label = "Party", o = {}) => f.ref(name, label, "party", o);
export const item = (name = "item_id", label = "Item", o = {}) => f.ref(name, label, "item", o);
export const vehicle = (name = "vehicle_id", label = "Vehicle", o = {}) => f.ref(name, label, "vehicle", o);
export const user = (name, label, o = {}) => f.ref(name, label, "app_user", o);

// Standard GST invoice-style lines with amounts computed per line.
export const taxLines = (extra = []) => ({
  name: "lines",
  label: "Items",
  fields: [
    item("item_id", "Item", { required: true }),
    f.text("description", "Description"),
    f.text("hsn_sac", "HSN/SAC"),
    f.qty("qty", "Qty", { required: true, check: "qty > 0" }),
    f.text("uom", "Unit"),
    f.money("rate", "Rate", { required: true, sensitive: "rates" }),
    f.percent("discount_pct", "Discount %", { default: "0" }),
    f.percent("gst_rate", "GST %", { default: "18" }),
    f.calc("taxable_value", "Taxable", "money", "round(qty * rate * (1 - coalesce(discount_pct, 0) / 100), 2)", { sensitive: "rates" }),
    f.calc("gst_amount", "GST", "money", "round(qty * rate * (1 - coalesce(discount_pct, 0) / 100) * coalesce(gst_rate, 0) / 100, 2)", { sensitive: "rates" }),
    f.calc("line_total", "Total", "money", "round(qty * rate * (1 - coalesce(discount_pct, 0) / 100) * (1 + coalesce(gst_rate, 0) / 100), 2)", { sensitive: "rates" }),
    ...extra,
  ],
});

export const taxRollups = [
  { field: "taxable_value", child: "lines", expr: "coalesce(sum(taxable_value), 0)" },
  { field: "gst_amount", child: "lines", expr: "coalesce(sum(gst_amount), 0)" },
];
