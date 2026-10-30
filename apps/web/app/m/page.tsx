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
import { display } from "@/lib/format";
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
      <ul className="md:hidden space-y-2">
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
      <div className="hidden md:block card overflow-x-auto">
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
