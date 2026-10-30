const inr = new Intl.NumberFormat("en-IN", { maximumFractionDigits: 2 });
const inrMoney = new Intl.NumberFormat("en-IN", { style: "currency", currency: "INR", maximumFractionDigits: 2 });

export function money(v: unknown): string {
  if (v === null || v === undefined || v === "") return "";
  return inrMoney.format(Number(v));
}

export function num(v: unknown): string {
  if (v === null || v === undefined || v === "") return "";
  return inr.format(Number(v));
}

// ₹2.3 Cr / ₹41 L style for dashboard tiles
export function short(v: unknown): string {
  const n = Number(v ?? 0);
  const a = Math.abs(n);
  if (a >= 1e7) return `₹${(n / 1e7).toFixed(2)} Cr`;
  if (a >= 1e5) return `₹${(n / 1e5).toFixed(1)} L`;
  return inrMoney.format(n);
}

export function date(v: unknown): string {
  if (!v) return "";
  const d = new Date(String(v));
  return isNaN(+d) ? String(v) : d.toLocaleDateString("en-IN", { day: "2-digit", month: "short", year: "numeric" });
}

export function dateTime(v: unknown): string {
  if (!v) return "";
  const d = new Date(String(v));
  return isNaN(+d) ? String(v) : d.toLocaleString("en-IN", { day: "2-digit", month: "short", hour: "2-digit", minute: "2-digit" });
}

export function humanize(s: string | null | undefined): string {
  if (!s) return "";
  return s.replace(/_/g, " ").replace(/^\w/, (c) => c.toUpperCase());
}

export function display(type: string, v: unknown): string {
  if (v === null || v === undefined || v === "") return "";
  switch (type) {
    case "money": return money(v);
    case "qty": case "number": case "int": case "percent": return num(v) + (type === "percent" ? "%" : "");
    case "date": return date(v);
    case "datetime": return dateTime(v);
    case "bool": return v ? "Yes" : "No";
    case "select": return humanize(String(v));
    case "multiselect": return (v as string[]).map(humanize).join(", ");
    default: return String(v);
  }
}

export function toLocalInput(v: unknown): string {
  if (!v) return "";
  const d = new Date(String(v));
  if (isNaN(+d)) return "";
  const p = (n: number) => String(n).padStart(2, "0");
  return `${d.getFullYear()}-${p(d.getMonth() + 1)}-${p(d.getDate())}T${p(d.getHours())}:${p(d.getMinutes())}`;
}
