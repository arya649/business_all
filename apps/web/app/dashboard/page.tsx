"use client";

import Link from "next/link";
import { useEffect, useState } from "react";
import { AlertTriangle } from "lucide-react";
import { AppShell } from "@/components/AppShell";
import { useApp } from "@/components/AppProvider";
import { leakageBoard, ownerDashboard } from "@/lib/erp";
import { date, num, short } from "@/lib/format";

// Owner view: group → company → record. Every number leads to its source.
export default function Dashboard() {
  const app = useApp();
  const [rows, setRows] = useState<any[] | null>(null);
  const [leaks, setLeaks] = useState<any[]>([]);
  // eslint-disable-next-line react-hooks/exhaustive-deps
  useEffect(() => { if (app.ctx) ownerDashboard().then(setRows).catch((e) => { setRows([]); app.toast(e.message, "error"); }); }, [app.ctx]);
  useEffect(() => { if (app.company) leakageBoard(app.company.id).then(setLeaks).catch(() => setLeaks([])); }, [app.company]);

  const sum = (k: string) => (rows ?? []).reduce((a, r) => a + Number(r[k] ?? 0), 0);
  const group = rows && rows.length > 1;
  const tiles: [string, string, string?][] = [
    ["Sales this month", short(sum("sales") - (group ? sum("intercompany_sales") : 0)), group ? "excludes sales between group companies" : undefined],
    ["Sales today", short(sum("sales_today"))],
    ["Cash & bank", short(sum("cash_bank"))],
    ["To collect", short(sum("receivables"))],
    ["To pay", short(sum("payables"))],
    ["Diesel used", `${num(sum("diesel_litres"))} L`],
    ["RMC delivered", `${num(sum("rmc_m3"))} m³`],
    ["Fuel sold", `${num(sum("fuel_litres_sold"))} L`],
    ["Hot-mix", `${num(sum("hotmix_mt"))} MT`],
    ["Bricks made", num(sum("bricks_units"))],
    ["Waiting approval", String(sum("pending_approvals"))],
    ["Alerts", String(sum("alerts"))],
  ];

  return (
    <AppShell title={app.t("dashboard")}>
      {rows === null ? <p className="text-[var(--muted)]">…</p> : (
        <div className="space-y-6">
          <section className="grid grid-cols-2 sm:grid-cols-3 lg:grid-cols-4 gap-3">
            {tiles.map(([k, v, note]) => (
              <div key={k} className="card p-4">
                <div className="text-sm text-[var(--muted)]">{k}</div>
                <div className="text-2xl font-semibold tabular-nums mt-1">{v}</div>
                {note && <div className="text-xs text-[var(--muted)] mt-1">{note}</div>}
              </div>
            ))}
          </section>

          {group && (
            <section className="card overflow-x-auto">
              <table className="w-full text-sm">
                <thead className="text-left text-[var(--muted)] border-b border-[var(--line)]">
                  <tr>{["Company", "Sales", "Today", "Cash & bank", "To collect", "To pay", "Alerts"].map((h) => <th key={h} className="px-3 py-2 font-medium">{h}</th>)}</tr>
                </thead>
                <tbody>
                  {rows.map((r) => (
                    <tr key={r.company_id} className="border-b border-[var(--line)] last:border-0">
                      <td className="px-3 py-2"><button className="text-[var(--brand)] font-medium" onClick={() => app.setCompany(r.company_id)}>{r.company_name}</button></td>
                      {["sales", "sales_today", "cash_bank", "receivables", "payables"].map((k) => <td key={k} className="px-3 py-2 tabular-nums">{short(r[k])}</td>)}
                      <td className="px-3 py-2">{r.alerts}</td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </section>
          )}

          <section>
            <h2 className="font-semibold mb-2 flex items-center gap-2"><AlertTriangle size={18} className="text-amber-600" /> Where money is leaking — {app.company?.name}</h2>
            {leaks.length === 0 ? <p className="text-[var(--muted)]">No leaks found.</p> : (
              <ul className="space-y-2">
                {leaks.map((l, i) => (
                  <li key={i} className="card p-3 flex gap-3 items-start">
                    <span className={`mt-1 size-2.5 shrink-0 rounded-full ${l.severity === "high" ? "bg-red-500" : "bg-amber-500"}`} />
                    <div className="min-w-0">
                      {l.entity ? <Link className="font-medium text-[var(--brand)]" href={`/m?e=${l.entity}&id=${l.record_id}`}>{l.title}</Link>
                                : <span className="font-medium">{l.title}</span>}
                      <div className="text-sm text-[var(--muted)]">{l.detail}</div>
                    </div>
                    <div className="ml-auto text-sm text-[var(--muted)] whitespace-nowrap">{date(l.doc_date)}</div>
                  </li>
                ))}
              </ul>
            )}
          </section>
        </div>
      )}
    </AppShell>
  );
}
