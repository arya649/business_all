"use client";

import { useEffect, useState } from "react";
import { Download, MessageCircle } from "lucide-react";
import { AppShell } from "@/components/AppShell";
import { useApp } from "@/components/AppProvider";
import { RefPicker } from "@/components/RefPicker";
import { billingRun, stockOnHand, trialBalance } from "@/lib/erp";
import { sb } from "@/lib/supabase";
import { date, humanize, money, num } from "@/lib/format";
import { downloadText } from "@/lib/download";

const TABS = [
  ["pl", "Profit & loss"], ["bs", "Balance sheet"], ["recv", "To collect"], ["pay", "To pay"], ["stmt", "Party statement"],
  ["day", "Day book"], ["tb", "Trial balance"], ["dsr", "Bunk DSR"], ["stock", "Stock"], ["billing", "Billing run"],
  ["gst", "GST files"], ["bank", "Bank statement"], ["tally", "Tally export"],
] as const;
type Tab = (typeof TABS)[number][0];

export default function Reports() {
  const app = useApp();
  const [tab, setTab] = useState<Tab>("pl");
  const [group, setGroup] = useState(false);
  const co = group ? null : app.company?.id ?? null;
  return (
    <AppShell title={app.t("reports")}>
      <div className="flex flex-wrap gap-1 mb-3">
        {TABS.map(([k, l]) => <button key={k} className={`tab ${tab === k ? "tab-on" : ""}`} onClick={() => setTab(k)}>{l}</button>)}
      </div>
      {["pl", "bs", "tb"].includes(tab) && (app.ctx?.companies.length ?? 0) > 1 && (
        <label className="flex items-center gap-2 text-sm mb-3">
          <input type="checkbox" checked={group} onChange={(e) => setGroup(e.target.checked)} />
          Whole group (sales and purchases between group companies removed)
        </label>
      )}
      {tab === "pl" && <Rpc fn="profit_and_loss" args={{ p_company: co }} cols={[["section", "", "text"], ["ledger_group", "Group", "group"], ["ledger_name", "Ledger", "text"], ["amount", "Amount", "money"]]} />}
      {tab === "bs" && <Rpc fn="balance_sheet" args={{ p_company: co }} cols={[["side", "", "text"], ["ledger_group", "Group", "group"], ["ledger_name", "Ledger", "text"], ["amount", "Amount", "money"]]} />}
      {tab === "tb" && <TB company={co} />}
      {tab === "recv" && <Ageing kind="receivable" />}
      {tab === "pay" && <Ageing kind="payable" />}
      {tab === "stmt" && <Statement />}
      {tab === "day" && <DayBook />}
      {tab === "dsr" && <Dsr />}
      {tab === "stock" && <Stock />}
      {tab === "billing" && <Billing />}
      {tab === "gst" && <Gst />}
      {tab === "bank" && <Bank />}
      {tab === "tally" && <Tally />}
    </AppShell>
  );
}

type Col = [key: string, label: string, kind: "text" | "money" | "num" | "date" | "group"];

function Table({ rows, cols, total }: { rows: any[]; cols: Col[]; total?: string[] }) {
  if (!rows.length) return <p className="text-[var(--muted)]">Nothing to show.</p>;
  const cell = (k: Col[2], v: any) => k === "money" ? money(v) : k === "num" ? num(v) : k === "date" ? date(v) : k === "group" ? humanize(v) : v ?? "";
  return (
    <div className="card overflow-x-auto">
      <table className="w-full text-sm">
        <thead className="text-left text-[var(--muted)] border-b border-[var(--line)]">
          <tr>{cols.map(([k, l, t]) => <th key={k} className={`px-3 py-2 font-medium ${["money", "num"].includes(t) ? "text-right" : ""}`}>{l}</th>)}</tr>
        </thead>
        <tbody>
          {rows.map((r, i) => (
            <tr key={i} className={`border-b border-[var(--line)] last:border-0 ${String(r.section ?? "").startsWith("Net") ? "font-semibold bg-[var(--soft)]" : ""}`}>
              {cols.map(([k, , t]) => <td key={k} className={`px-3 py-1.5 ${["money", "num"].includes(t) ? "text-right tabular-nums" : ""}`}>{cell(t, r[k])}</td>)}
            </tr>
          ))}
          {total && (
            <tr className="font-semibold">
              {cols.map(([k, , t], i) => <td key={k} className={`px-3 py-2 ${["money", "num"].includes(t) ? "text-right tabular-nums" : ""}`}>
                {i === 0 ? "Total" : total.includes(k) ? cell(t, rows.reduce((a, r) => a + Number(r[k] ?? 0), 0)) : ""}</td>)}
            </tr>
          )}
        </tbody>
      </table>
    </div>
  );
}

function useRpc(fn: string, args: Record<string, unknown>, ready = true) {
  const app = useApp();
  const [rows, setRows] = useState<any[] | null>(null);
  const key = JSON.stringify(args);
  useEffect(() => {
    if (!ready) return;
    setRows(null);
    sb().rpc(fn, args).then(({ data, error }) => { if (error) { app.toast(error.message, "error"); setRows([]); } else setRows(data ?? []); });
  }, [fn, key, ready]); // eslint-disable-line
  return rows;
}

function Rpc({ fn, args, cols, total }: { fn: string; args: Record<string, unknown>; cols: Col[]; total?: string[] }) {
  const rows = useRpc(fn, args);
  return rows === null ? <p className="text-[var(--muted)]">…</p> : <Table rows={rows} cols={cols} total={total} />;
}

function TB({ company }: { company: string | null }) {
  const rows = useRpc("trial_balance", { p_company: company });
  return rows === null ? <p>…</p> : <Table rows={rows} total={["debit", "credit"]}
    cols={[["company_code", "Company", "text"], ["ledger_name", "Ledger", "text"], ["ledger_group", "Group", "group"], ["debit", "Debit", "money"], ["credit", "Credit", "money"], ["balance", "Balance", "money"]]} />;
}

// Who owes us / whom we owe, by age; one tap sends a polite WhatsApp reminder.
function Ageing({ kind }: { kind: "receivable" | "payable" }) {
  const app = useApp();
  const rows = useRpc("ageing", { p_company: app.company?.id, p_kind: kind }, !!app.company);
  if (rows === null) return <p>…</p>;
  const remind = (r: any) => {
    const text = `Namaste ${r.party_name}, a gentle reminder from ${app.company?.name}: ₹${num(r.total)} is due` +
      `${r.oldest_days > 30 ? ` (oldest ${r.oldest_days} days)` : ""}. Kindly arrange payment. Thank you.`;
    window.open(`https://wa.me/${r.mobile ? "91" + String(r.mobile).replace(/\D/g, "").slice(-10) : ""}?text=${encodeURIComponent(text)}`, "_blank");
  };
  return (
    <div className="space-y-2">
      <Table rows={rows} total={["total", "d0_30", "d31_60", "d61_90", "over_90"]}
        cols={[["party_name", "Party", "text"], ["total", "Total", "money"], ["d0_30", "0–30 days", "money"], ["d31_60", "31–60", "money"], ["d61_90", "61–90", "money"], ["over_90", "Over 90", "money"]]} />
      {kind === "receivable" && rows.length > 0 && (
        <div className="flex flex-wrap gap-2">
          {rows.slice(0, 12).map((r) => (
            <button key={r.party_id} className="btn !min-h-0 !py-1.5 text-sm" onClick={() => remind(r)}>
              <MessageCircle size={14} /> Remind {r.party_name}
            </button>
          ))}
        </div>
      )}
    </div>
  );
}

function Statement() {
  const app = useApp();
  const [party, setParty] = useState<string | null>(null);
  const rows = useRpc("party_statement", { p_company: app.company?.id, p_party: party }, !!party && !!app.company);
  return (
    <div className="space-y-3">
      <div className="max-w-sm"><RefPicker refName="party" value={party} onChange={setParty} /></div>
      {party && (rows === null ? <p>…</p> : <Table rows={rows}
        cols={[["doc_date", "Date", "date"], ["doc_no", "No.", "text"], ["narration", "Details", "text"], ["debit", "Debit", "money"], ["credit", "Credit", "money"], ["balance", "Balance", "money"]]} />)}
    </div>
  );
}

function DayBook() {
  const app = useApp();
  const [d, setD] = useState(new Date().toISOString().slice(0, 10));
  return (
    <div className="space-y-3">
      <input type="date" aria-label="Date" value={d} onChange={(e) => setD(e.target.value)} className="rounded-lg border border-[var(--line)] bg-[var(--card)] px-2 py-1.5" />
      <Rpc fn="day_book" args={{ p_company: app.company?.id, p_date: d }} total={["debit", "credit"]}
        cols={[["doc_no", "No.", "text"], ["voucher_type", "Type", "group"], ["ledger_name", "Ledger", "text"], ["party_name", "Party", "text"], ["debit", "Debit", "money"], ["credit", "Credit", "money"]]} />
    </div>
  );
}

function Dsr() {
  const app = useApp();
  const [d, setD] = useState(new Date(Date.now() - 864e5).toISOString().slice(0, 10));
  if (!app.location) return <p>Choose the bunk at the top.</p>;
  return (
    <div className="space-y-3">
      <div className="flex gap-2 items-center">
        <input type="date" aria-label="Date" value={d} onChange={(e) => setD(e.target.value)} className="rounded-lg border border-[var(--line)] bg-[var(--card)] px-2 py-1.5" />
        <button className="btn !min-h-0 !py-1.5" onClick={() => window.print()}>Print DSR</button>
      </div>
      <Rpc fn="bunk_dsr" args={{ p_company: app.company?.id, p_location: app.location.id, p_date: d }} total={["sales", "sale_value"]}
        cols={[["tank", "Tank", "text"], ["product", "Product", "text"], ["opening_dip", "Opening (dip)", "num"], ["receipts", "Receipts", "num"], ["sales", "Sales", "num"],
               ["testing", "Testing", "num"], ["book_closing", "Book closing", "num"], ["closing_dip", "Closing dip", "num"], ["variance", "Variance", "num"],
               ["variance_pct", "%", "num"], ["rate", "Rate", "money"], ["sale_value", "Value", "money"]]} />
    </div>
  );
}

function Stock() {
  const app = useApp();
  const [rows, setRows] = useState<any[]>([]);
  useEffect(() => { if (app.company) stockOnHand(app.company.id, app.location?.id ?? null).then(setRows).catch((e) => app.toast(e.message, "error")); }, [app.company, app.location]); // eslint-disable-line
  return <Table rows={rows} total={["value"]} cols={[["location_name", "Location", "text"], ["item_name", "Item", "text"], ["qty", "Qty", "num"], ["uom", "Unit", "text"], ["value", "Value", "money"]]} />;
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

function Gst() {
  const app = useApp();
  const [gstins, setGstins] = useState<any[]>([]);
  const [g, setG] = useState("");
  const [month, setMonth] = useState(new Date(Date.now() - 15 * 864e5).toISOString().slice(0, 7));
  useEffect(() => {
    if (app.company) sb().from("company_gstin").select("id,gstin").eq("company_id", app.company.id).then(({ data }) => { setGstins(data ?? []); setG(data?.[0]?.id ?? ""); });
  }, [app.company]);
  const get = async () => {
    const { data, error } = await sb().rpc("gstr1_json", { p_gstin: g, p_month: month });
    if (error) return app.toast(error.message, "error");
    downloadText(`GSTR1_${gstins.find((x) => x.id === g)?.gstin}_${month}.json`, JSON.stringify(data, null, 1));
  };
  return (
    <div className="space-y-3 max-w-xl">
      <p className="text-sm text-[var(--muted)]">GSTR-1 in the format the GST offline tool and portal accept (B2B, B2C small, HSN summary). e-Invoice and e-way bill files are on each sales invoice.
        Direct upload to IRP / e-way bill portal needs a GSP account; until then upload these files on the portals.</p>
      <div className="flex flex-wrap gap-2 items-center">
        <select aria-label="GSTIN" value={g} onChange={(e) => setG(e.target.value)} className="rounded-lg border border-[var(--line)] bg-[var(--card)] px-2 py-1.5">
          {gstins.map((x) => <option key={x.id} value={x.id}>{x.gstin}</option>)}
        </select>
        <input type="month" aria-label="Month" value={month} onChange={(e) => setMonth(e.target.value)} className="rounded-lg border border-[var(--line)] bg-[var(--card)] px-2 py-1.5" />
        <button className="btn" disabled={!g} onClick={get}><Download size={16} /> GSTR-1 JSON</button>
      </div>
    </div>
  );
}

// Upload the bank's CSV/Excel export (saved as CSV); lines are matched to receipts and payments automatically.
function Bank() {
  const app = useApp();
  const [banks, setBanks] = useState<any[]>([]);
  const [bank, setBank] = useState("");
  const [result, setResult] = useState<string | null>(null);
  const rows = useRpc("erp_list", { p_entity: "finance.bank_txn", p_company: app.company?.id, p_limit: 200 }, !!app.company);
  useEffect(() => {
    if (app.company) sb().rpc("erp_list", { p_entity: "finance.ledger", p_company: app.company.id, p_filters: { is_bank: "true" }, p_limit: 50 })
      .then(({ data }) => { setBanks(data?.rows ?? []); setBank(data?.rows?.[0]?.id ?? ""); });
  }, [app.company]);
  const parse = (text: string) => {
    const lines = text.split(/\r?\n/).filter((l) => l.trim());
    const head = lines[0].toLowerCase().split(",").map((h) => h.replace(/"/g, "").trim());
    const find = (...names: string[]) => head.findIndex((h) => names.some((n) => h.includes(n)));
    const iDate = find("date"), iNar = find("narration", "description", "particular", "remark"), iRef = find("ref", "chq", "cheque", "utr");
    const iDr = find("withdrawal", "debit", "dr"), iCr = find("deposit", "credit", "cr"), iBal = find("balance");
    const toDate = (s: string) => { const m = s.match(/(\d{1,2})[\/\-.](\d{1,2})[\/\-.](\d{2,4})/); return m ? `${m[3].length === 2 ? "20" + m[3] : m[3]}-${m[2].padStart(2, "0")}-${m[1].padStart(2, "0")}` : s; };
    const n = (s?: string) => Number(String(s ?? "").replace(/[^0-9.\-]/g, "")) || 0;
    return lines.slice(1).map((l) => l.match(/("([^"]|"")*"|[^,]*)(,|$)/g)!.map((c) => c.replace(/,$/, "").replace(/^"|"$/g, "").trim()))
      .filter((c) => c[iDate]).map((c) => ({ date: toDate(c[iDate]), narration: c[iNar], reference: iRef >= 0 ? c[iRef] : null,
        debit: iDr >= 0 ? n(c[iDr]) : 0, credit: iCr >= 0 ? n(c[iCr]) : 0, balance: iBal >= 0 ? n(c[iBal]) : null }));
  };
  return (
    <div className="space-y-3">
      <div className="flex flex-wrap gap-2 items-center">
        <select aria-label="Bank account" value={bank} onChange={(e) => setBank(e.target.value)} className="rounded-lg border border-[var(--line)] bg-[var(--card)] px-2 py-1.5">
          {banks.length === 0 && <option value="">Add a bank ledger first (Ledgers → Bank account)</option>}
          {banks.map((b) => <option key={b.id} value={b.id}>{b.name}</option>)}
        </select>
        <label className="btn !min-h-0 !py-1.5 cursor-pointer">Upload statement (CSV)
          <input hidden type="file" accept=".csv,text/csv" onChange={async (e) => {
            const f = e.target.files?.[0];
            if (!f || !bank) return;
            const { data, error } = await sb().rpc("bank_import", { p_company: app.company!.id, p_bank_ledger: bank, p_rows: parse(await f.text()) });
            if (error) app.toast(error.message, "error");
            else setResult(`${data.imported} lines added, ${data.duplicates} already there, ${data.matched} matched automatically.`);
          }} />
        </label>
      </div>
      {result && <p className="rounded-lg bg-[var(--soft)] p-2 text-sm">{result}</p>}
      {rows === null ? <p>…</p> : <Table rows={(rows as any).rows ?? []}
        cols={[["doc_date", "Date", "date"], ["narration", "Narration", "text"], ["debit", "Withdrawal", "money"], ["credit", "Deposit", "money"], ["match_status", "Match", "group"], ["match_confidence", "Sure %", "num"]]} />}
    </div>
  );
}

function Tally() {
  const app = useApp();
  const [from, setFrom] = useState(new Date(Date.now() - 30 * 864e5).toISOString().slice(0, 10));
  const [to, setTo] = useState(new Date().toISOString().slice(0, 10));
  return (
    <div className="space-y-3 max-w-xl">
      <p className="text-sm text-[var(--muted)]">All posted vouchers as Tally XML. In Tally: Gateway → Import → Vouchers, choose this file.
        Ledgers with the same names must exist in Tally (party names are used as ledger names).</p>
      <div className="flex flex-wrap gap-2 items-center">
        <input type="date" aria-label="From" value={from} onChange={(e) => setFrom(e.target.value)} className="rounded-lg border border-[var(--line)] bg-[var(--card)] px-2 py-1.5" />
        <input type="date" aria-label="To" value={to} onChange={(e) => setTo(e.target.value)} className="rounded-lg border border-[var(--line)] bg-[var(--card)] px-2 py-1.5" />
        <button className="btn" onClick={async () => {
          const { data, error } = await sb().rpc("tally_export", { p_company: app.company!.id, p_from: from, p_to: to });
          if (error) app.toast(error.message, "error"); else downloadText(`tally_${app.company?.code}_${from}_${to}.xml`, data, "application/xml");
        }}><Download size={16} /> Tally XML</button>
      </div>
    </div>
  );
}

