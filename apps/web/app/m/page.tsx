"use client";

import Link from "next/link";
import { Suspense, useEffect, useState } from "react";
import { useSearchParams } from "next/navigation";
import { Plus, Search } from "lucide-react";
import { AppShell } from "@/components/AppShell";
import { useApp } from "@/components/AppProvider";
import { RecordForm } from "@/components/RecordForm";
import { StatusChip } from "@/components/StatusChip";
import { listRecords, lookup } from "@/lib/erp";
import { isNetworkError, onOutboxChange, outbox, type OutboxItem } from "@/lib/offline";
import { display, num } from "@/lib/format";
import type { Entity, Row } from "@/lib/types";

// One page for every module's registers: ?e=<record type> lists them, &id=<id|new> opens one.
export default function Page() {
  return <Suspense><Records /></Suspense>;
}

function Records() {
  const app = useApp();
  const sp = useSearchParams();
  const key = sp.get("e") ?? "";
  const id = sp.get("id");
  const entity = app.entity(key);

  if (!app.ready) return <AppShell>…</AppShell>;
  if (!entity) return <AppShell><p className="text-[var(--muted)]">{app.catalog.length ? app.t("not_enabled") : "…"}</p></AppShell>;

  if (id) {
    return (
      <AppShell title={id === "new" ? `${app.t("new")} ${entity.label.toLowerCase()}` : entity.label}>
        <RecordForm key={id} entity={entity} id={id === "new" ? null : id} />
      </AppShell>
    );
  }
  return (
    <AppShell title={entity.label_plural}
              actions={entity.can.create && !entity.read_only &&
                <Link href={`/m?e=${entity.key}&id=new`} className="btn btn-primary"><Plus size={18} /> {app.t("new")}</Link>}>
      <RecordList entity={entity} />
    </AppShell>
  );
}

function RecordList({ entity }: { entity: Entity }) {
  const app = useApp();
  const boardable = entity.key === "crm.lead" || entity.key === "rmc.order";
  const [view, setView] = useState<"list" | "board">(boardable ? "board" : "list");
  const [rows, setRows] = useState<Row[]>([]);
  const [total, setTotal] = useState(0);
  const [q, setQ] = useState("");
  const [status, setStatus] = useState<string>("");
  const [error, setError] = useState<string | null>(null);
  const [loading, setLoading] = useState(true);
  const [labels, setLabels] = useState<Record<string, string>>({});
  const [waiting, setWaiting] = useState<OutboxItem[]>([]);
  useEffect(() => {
    const r = () => outbox().then((items) => setWaiting(items.filter((i) => (i.args as any).p_entity === entity.key)));
    r();
    return onOutboxChange(r);
  }, [entity.key]);

  const load = async (offset = 0) => {
    if (!app.company) return;
    setLoading(true);
    try {
      const r = await listRecords(entity.key, app.company.id, app.location?.id ?? null, status ? { status } : {}, q, 50, offset);
      const all = offset ? [...rows, ...r.rows] : r.rows;
      setRows(all);
      // names for linked records (customer, vehicle, tank...) instead of ids
      const refs = entity.fields.filter((f) => f.in_list && f.type === "ref");
      const got: Record<string, string> = {};
      await Promise.all(refs.map(async (f) => {
        const ids = [...new Set(all.map((x) => x[f.name]).filter(Boolean))] as string[];
        if (!ids.length) return;
        try { for (const l of await lookup(f.ref!, app.company!.id, "", ids)) got[l.id] = l.label; } catch { /* offline */ }
      }));
      setLabels((old) => ({ ...old, ...got }));
      setTotal(r.total);
      setError(null);
    } catch (e: any) { setError(isNetworkError(e) ? app.t("offline") : e.message); }
    setLoading(false);
  };
  // eslint-disable-next-line react-hooks/exhaustive-deps
  useEffect(() => { const t = setTimeout(() => load(0), 250); return () => clearTimeout(t); }, [entity.key, app.company?.id, app.location?.id, q, status]);

  const cols = entity.fields.filter((f) => f.in_list).slice(0, 6);
  const cell = (c: (typeof cols)[number], r: Row) => (c.type === "ref" ? labels[r[c.name]] ?? "" : display(c.type, r[c.name]));
  const title = (r: Row) => r.doc_no ?? (entity.title_field ? display("text", r[entity.title_field]) : "") ?? r.id.slice(0, 8);

  return (
    <div className="space-y-3">
      <div className="flex flex-wrap gap-2">
        <label className="flex items-center gap-2 rounded-xl border border-[var(--line)] bg-[var(--card)] px-3 flex-1 min-w-48">
          <Search size={16} className="text-[var(--muted)]" />
          <input value={q} onChange={(e) => setQ(e.target.value)} placeholder={app.t("search")} className="w-full bg-transparent py-2.5 outline-none" />
        </label>
        {entity.workflow && (
          <select value={status} onChange={(e) => setStatus(e.target.value)} aria-label="Status"
                  className="rounded-xl border border-[var(--line)] bg-[var(--card)] px-3">
            <option value="">All</option>
            {["draft", "submitted", "approved", "rejected", "sent_back", "cancelled"].map((s) => <option key={s} value={s}>{s.replace("_", " ")}</option>)}
          </select>
        )}
      </div>
      {boardable && (
        <div className="flex gap-1">
          <button className={`tab ${view === "board" ? "tab-on" : ""}`} onClick={() => setView("board")}>{entity.key === "crm.lead" ? "Pipeline" : "Pour schedule"}</button>
          <button className={`tab ${view === "list" ? "tab-on" : ""}`} onClick={() => setView("list")}>List</button>
        </div>
      )}
      {boardable && view === "board" && <Board entity={entity} rows={rows} labels={labels} onMoved={() => load(0)} />}
      {error && <p className={`text-sm ${app.online ? "text-red-600" : "text-amber-700 dark:text-amber-300"}`}>{error}</p>}
      {waiting.length > 0 && (
        <ul className="space-y-2">
          {waiting.map((w) => (
            <li key={w.key} className="card p-3 flex items-center gap-2 border-dashed">
              <span className="font-medium">{w.label}</span>
              <span className={`ml-auto text-xs ${w.error ? "text-red-600" : "text-[var(--muted)]"}`}>{w.error ?? app.t("waiting")}</span>
            </li>
          ))}
        </ul>
      )}

      {/* phones: cards */}
      <ul className={`md:hidden space-y-2 ${boardable && view === "board" ? "hidden" : ""}`}>
        {rows.map((r) => (
          <li key={r.id}>
            <Link href={`/m?e=${entity.key}&id=${r.id}`} className="card block p-3">
              <div className="flex items-center gap-2">
                <span className="font-medium truncate">{title(r)}</span>
                {r.status && <span className="ml-auto"><StatusChip status={r.status} /></span>}
              </div>
              <div className="mt-1 grid grid-cols-2 gap-x-3 text-sm text-[var(--muted)]">
                {cols.slice(0, 4).map((c) => <span key={c.name} className="truncate">{cell(c, r)}</span>)}
              </div>
            </Link>
          </li>
        ))}
      </ul>

      {/* desktop: table */}
      <div className={`hidden ${boardable && view === "board" ? "" : "md:block"} card overflow-x-auto`}>
        <table className="w-full text-sm">
          <thead className="text-left text-[var(--muted)] border-b border-[var(--line)]">
            <tr>
              <th className="px-3 py-2 font-medium">{entity.numbering ? "No." : "Name"}</th>
              {entity.dated && <th className="px-3 py-2 font-medium">Date</th>}
              {cols.map((c) => <th key={c.name} className="px-3 py-2 font-medium">{c.label}</th>)}
              {entity.workflow && <th className="px-3 py-2 font-medium">Status</th>}
            </tr>
          </thead>
          <tbody>
            {rows.map((r) => (
              <tr key={r.id} className="border-b border-[var(--line)] last:border-0 hover:bg-[var(--soft)]">
                <td className="px-3 py-2"><Link className="text-[var(--brand)] font-medium" href={`/m?e=${entity.key}&id=${r.id}`}>{title(r)}</Link></td>
                {entity.dated && <td className="px-3 py-2 whitespace-nowrap">{display("date", r.doc_date)}</td>}
                {cols.map((c) => <td key={c.name} className={`px-3 py-2 ${["money", "qty", "number", "int"].includes(c.type) ? "text-right tabular-nums" : ""}`}>{cell(c, r)}</td>)}
                {entity.workflow && <td className="px-3 py-2"><StatusChip status={r.status} /></td>}
              </tr>
            ))}
          </tbody>
        </table>
      </div>

      {!loading && rows.length === 0 && waiting.length === 0 && <p className="text-[var(--muted)] py-6 text-center">{app.t("nothing_yet")}</p>}
      {rows.length < total && <button className="btn w-full" onClick={() => load(rows.length)}>{app.t("more")}</button>}
    </div>
  );
}

const STAGES = ["new", "contacted", "site_visit", "quote_sent", "trial", "negotiation", "won", "lost"];

// Leads as a pipeline (move a card with one tap), RMC orders as a pour schedule by day and time.
function Board({ entity, rows, labels, onMoved }: { entity: Entity; rows: Row[]; labels: Record<string, string>; onMoved: () => void }) {
  const app = useApp();
  if (entity.key === "crm.lead") {
    const move = async (r: Row, dir: 1 | -1) => {
      const next = STAGES[Math.min(Math.max(STAGES.indexOf(r.stage ?? "new") + dir, 0), STAGES.length - 1)];
      try { await (await import("@/lib/erp")).saveRecord(entity, { id: r.id, stage: next }); onMoved(); } catch (e: any) { app.toast(e.message, "error"); }
    };
    return (
      <div className="flex gap-3 overflow-x-auto pb-2">
        {STAGES.map((s) => {
          const list = rows.filter((r) => (r.stage ?? "new") === s);
          return (
            <section key={s} className="min-w-60 w-60 shrink-0 rounded-2xl bg-[var(--soft)] p-2">
              <h3 className="px-1 py-1 text-sm font-semibold flex">{s.replace("_", " ")}<span className="ml-auto text-[var(--muted)]">{list.length}</span></h3>
              <ul className="space-y-2">
                {list.map((r) => (
                  <li key={r.id} className="card p-2 text-sm">
                    <Link href={`/m?e=${entity.key}&id=${r.id}`} className="font-medium text-[var(--brand)]">{r.contact_name}</Link>
                    <div className="text-[var(--muted)]">{r.business_line?.replace("_", " ")} · {r.expected_value ? display("money", r.expected_value) : ""}</div>
                    {r.next_follow_up_at && <div className="text-xs">Call: {display("datetime", r.next_follow_up_at)}</div>}
                    <div className="mt-1 flex gap-1">
                      {r.mobile && <a className="tab !px-2" href={`tel:${r.mobile}`}>Call</a>}
                      {r.mobile && <a className="tab !px-2" target="_blank" href={`https://wa.me/91${String(r.mobile).slice(-10)}`}>WhatsApp</a>}
                      <button className="tab !px-2 ml-auto" aria-label="Move back" onClick={() => move(r, -1)}>←</button>
                      <button className="tab !px-2" aria-label="Move forward" onClick={() => move(r, 1)}>→</button>
                    </div>
                  </li>
                ))}
              </ul>
            </section>
          );
        })}
      </div>
    );
  }
  // RMC: orders by pour day, in time order, with trucks needed for the pour rate
  const byDay = new Map<string, Row[]>();
  for (const r of [...rows].sort((a, b) => String(a.pour_start).localeCompare(String(b.pour_start)))) {
    const d = String(r.pour_start ?? r.doc_date).slice(0, 10);
    byDay.set(d, [...(byDay.get(d) ?? []), r]);
  }
  return (
    <div className="space-y-4">
      {[...byDay.entries()].map(([d, list]) => (
        <section key={d}>
          <h3 className="font-semibold mb-2">{display("date", d)} · {num(list.reduce((a, r) => a + Number(r.qty_m3 ?? 0), 0))} m³</h3>
          <ul className="grid gap-2 sm:grid-cols-2 lg:grid-cols-3">
            {list.map((r) => {
              const trucks = Math.ceil(Number(r.pour_rate_m3_hr ?? 15) / 7 * 1.5);
              return (
                <li key={r.id} className="card p-3 text-sm">
                  <div className="flex gap-2">
                    <span className="font-mono">{new Date(r.pour_start).toLocaleTimeString("en-IN", { hour: "2-digit", minute: "2-digit" })}</span>
                    <Link href={`/m?e=${entity.key}&id=${r.id}`} className="font-medium text-[var(--brand)] truncate">{labels[r.party_id] ?? r.site_name}</Link>
                    <span className="ml-auto">{r.grade}</span>
                  </div>
                  <div className="text-[var(--muted)]">{r.site_name} · {num(r.qty_m3)} m³ · delivered {num(r.delivered_m3 ?? 0)}</div>
                  <div className="text-xs mt-1">{r.pump !== "none" ? `${r.pump} pump · ` : ""}≈ {trucks} transit mixers at {num(r.pour_rate_m3_hr ?? 15)} m³/hr
                    {r.credit_check === "over_limit" && <span className="ml-1 text-red-600">· over credit limit</span>}</div>
                </li>
              );
            })}
          </ul>
        </section>
      ))}
    </div>
  );
}
