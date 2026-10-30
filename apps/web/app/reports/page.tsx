"use client";

import { useEffect, useState } from "react";
import { AppShell } from "@/components/AppShell";
import { useApp } from "@/components/AppProvider";
import { billingRun, stockOnHand, trialBalance } from "@/lib/erp";
import { humanize, money, num } from "@/lib/format";

export default function Reports() {
  const app = useApp();
  const [tab, setTab] = useState<"tb" | "group" | "stock" | "billing">("tb");
  return (
    <AppShell title={app.t("reports")}>
      <div className="flex flex-wrap gap-1 mb-4">
        {([["tb", "Trial balance"], ["group", "Group (inter-company removed)"], ["stock", "Stock"], ["billing", "Billing run"]] as const).map(([k, l]) => (
          <button key={k} className={`tab ${tab === k ? "tab-on" : ""}`} onClick={() => setTab(k)}>{l}</button>
        ))}
      </div>
      {tab === "tb" && <TB company={app.company?.id ?? null} />}
      {tab === "group" && <TB company={null} />}
      {tab === "stock" && <Stock />}
      {tab === "billing" && <Billing />}
    </AppShell>
  );
}

function TB({ company }: { company: string | null }) {
  const app = useApp();
  const [rows, setRows] = useState<any[]>([]);
  useEffect(() => { trialBalance(company).then(setRows).catch((e) => app.toast(e.message, "error")); }, [company]); // eslint-disable-line
  const dr = rows.reduce((a, r) => a + Number(r.debit), 0);
  const cr = rows.reduce((a, r) => a + Number(r.credit), 0);
  return (
    <div className="card overflow-x-auto">
      <table className="w-full text-sm">
        <thead className="text-left text-[var(--muted)] border-b border-[var(--line)]">
          <tr><th className="px-3 py-2">Company</th><th className="px-3 py-2">Ledger</th><th className="px-3 py-2">Group</th>
              <th className="px-3 py-2 text-right">Debit</th><th className="px-3 py-2 text-right">Credit</th><th className="px-3 py-2 text-right">Balance</th></tr>
        </thead>
        <tbody>
          {rows.map((r, i) => (
            <tr key={i} className="border-b border-[var(--line)]">
              <td className="px-3 py-1.5">{r.company_code}</td><td className="px-3 py-1.5">{r.ledger_name}</td><td className="px-3 py-1.5">{humanize(r.ledger_group)}</td>
              <td className="px-3 py-1.5 text-right tabular-nums">{money(r.debit)}</td><td className="px-3 py-1.5 text-right tabular-nums">{money(r.credit)}</td>
              <td className="px-3 py-1.5 text-right tabular-nums">{money(r.balance)}</td>
            </tr>
          ))}
          <tr className="font-semibold"><td className="px-3 py-2" colSpan={3}>Total</td>
            <td className="px-3 py-2 text-right">{money(dr)}</td><td className="px-3 py-2 text-right">{money(cr)}</td><td /></tr>
        </tbody>
      </table>
    </div>
  );
}

function Stock() {
  const app = useApp();
  const [rows, setRows] = useState<any[]>([]);
  useEffect(() => { if (app.company) stockOnHand(app.company.id, app.location?.id ?? null).then(setRows).catch((e) => app.toast(e.message, "error")); }, [app.company, app.location]); // eslint-disable-line
  return (
    <div className="card overflow-x-auto">
      <table className="w-full text-sm">
        <thead className="text-left text-[var(--muted)] border-b border-[var(--line)]">
          <tr><th className="px-3 py-2">Location</th><th className="px-3 py-2">Item</th><th className="px-3 py-2 text-right">Qty</th><th className="px-3 py-2 text-right">Value</th></tr>
        </thead>
        <tbody>
          {rows.map((r, i) => (
            <tr key={i} className={`border-b border-[var(--line)] ${r.below_reorder ? "bg-amber-50 dark:bg-amber-900/20" : ""}`}>
              <td className="px-3 py-1.5">{r.location_name}</td><td className="px-3 py-1.5">{r.item_name}</td>
              <td className="px-3 py-1.5 text-right tabular-nums">{num(r.qty)} {r.uom}</td><td className="px-3 py-1.5 text-right tabular-nums">{money(r.value)}</td>
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  );
}

function Billing() {
  const app = useApp();
  const [out, setOut] = useState<any[] | null>(null);
  const run = async (src: string) => {
    if (!app.company || !app.location) { app.toast("Choose the plant at the top first.", "error"); return; }
    try { setOut(await billingRun(src, app.company.id, app.location.id)); } catch (e: any) { app.toast(e.message, "error"); }
  };
  return (
    <div className="space-y-4">
      <p className="text-sm text-[var(--muted)]">Makes draft GST invoices for everything delivered and signed but not yet billed, one per customer.</p>
      <div className="flex flex-wrap gap-2">
        <button className="btn" onClick={() => run("rmc.challan")}>Bill RMC challans</button>
        <button className="btn" onClick={() => run("bitumen.dispatch")}>Bill hot-mix dispatches</button>
        <button className="btn" onClick={() => run("bricks.dispatch")}>Bill bricks dispatches</button>
      </div>
      {out && (out.length === 0 ? <p>Nothing to bill.</p> : (
        <ul className="space-y-2">{out.map((r) => (
          <li key={r.invoice_id} className="card p-3 flex"><a className="text-[var(--brand)]" href={`/m?e=finance.sales_invoice&id=${r.invoice_id}`}>Invoice draft · {r.lines} lines</a>
            <span className="ml-auto tabular-nums">{money(r.amount)}</span></li>))}</ul>
      ))}
    </div>
  );
}
