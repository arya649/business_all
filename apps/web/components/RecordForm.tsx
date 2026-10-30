"use client";

import { useEffect, useMemo, useState } from "react";
import { useRouter } from "next/navigation";
import { ChevronDown, ChevronUp, History, Plus, Printer, ScanLine, Trash2 } from "lucide-react";
import type { Entity, Field, Row } from "@/lib/types";
import { display, dateTime, humanize } from "@/lib/format";
import { generatePayroll, getRecord, history as getHistory, projectHealth, saveRecord, setStatus } from "@/lib/erp";
import { FieldInput } from "./FieldInput";
import { useApp } from "./AppProvider";
import { StatusChip } from "./StatusChip";

const SYSTEM = new Set(["id", "tenant_id", "company_id", "location_id", "created_by", "created_at", "updated_by", "updated_at",
  "device_id", "geo", "submitted_at", "approved_at", "approval_request_id", "_can", "_pending"]);

export function RecordForm({ entity, id }: { entity: Entity; id: string | null }) {
  const app = useApp();
  const router = useRouter();
  const [rec, setRec] = useState<Row | null>(null);
  const [data, setData] = useState<Record<string, any>>({});
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [showAll, setShowAll] = useState(app.ctx?.ui_mode !== "simple");
  const [tab, setTab] = useState<"form" | "history">("form");

  useEffect(() => {
    if (!id) {
      const init: Record<string, any> = {};
      if (entity.dated) init.doc_date = new Date().toISOString().slice(0, 10);
      setData(init);
      setRec(null);
      return;
    }
    getRecord(entity.key, id).then((r) => { setRec(r); setData(r); }).catch((e) => setError(e.message));
  }, [entity.key, id]);

  const status: string | undefined = rec?.status;
  const editable = !entity.read_only && (!rec || (rec._can?.edit ?? false) || rec._pending);
  const needLocation = entity.scope === "location" && !app.location && !rec;

  const visibleFields = useMemo(() => {
    const quick = entity.fields.filter((f) => f.quick || (f.required && !f.computed));
    if (showAll || quick.length === 0) return entity.fields;
    return quick;
  }, [entity, showAll]);

  const sections = useMemo(() => {
    const m = new Map<string, Field[]>();
    for (const f of visibleFields) {
      const k = f.section ?? "";
      m.set(k, [...(m.get(k) ?? []), f]);
    }
    return [...m.entries()];
  }, [visibleFields]);

  const save = async (then?: "submit") => {
    if (needLocation) { setError("Choose a location at the top first."); return; }
    setBusy(true);
    setError(null);
    try {
      const payload: Record<string, any> = {};
      for (const [k, v] of Object.entries(data)) {
        if (SYSTEM.has(k) && k !== "id") continue;
        const f = entity.fields.find((x) => x.name === k);
        if (f?.computed) continue;
        if (entity.children.some((c) => c.name === k)) {
          payload[k] = (v as any[]).map((line) => {
            const child = entity.children.find((c) => c.name === k)!;
            const clean: Record<string, any> = {};
            for (const cf of child.fields) if (!cf.computed && line[cf.name] !== undefined) clean[cf.name] = line[cf.name];
            return clean;
          });
          continue;
        }
        if (["doc_no", "doc_date", "status"].includes(k) || f) payload[k] = v;
      }
      delete payload.status;
      if (!rec) {
        payload.company_id = app.company!.id;
        payload.location_id = app.location?.id ?? null;
      } else payload.id = rec.id;
      if (rec && status && status !== "draft" && status !== "sent_back") {
        const reason = prompt(app.t("reason") + "?");
        if (!reason) { setBusy(false); return; }
        payload._reason = reason;
      }
      const { record, queued } = await saveRecord(entity, payload);
      if (queued) {
        app.toast(app.t("saved_offline"));
        router.push(`/m?e=${entity.key}`);
        return;
      }
      let r = record;
      if (then === "submit") r = await setStatus(entity.key, record.id, "submit");
      app.toast(then === "submit" ? humanize(r.status) : app.t("saved"));
      setRec(r);
      setData(r);
      if (!id) router.replace(`/m?e=${entity.key}&id=${r.id}`);
    } catch (e: any) {
      setError(e.message);
    } finally {
      setBusy(false);
    }
  };

  const cancelDoc = async () => {
    const reason = prompt("Why cancel?");
    if (!reason || !rec) return;
    try {
      const r = await setStatus(entity.key, rec.id, "cancel", reason);
      setRec(r); setData(r);
    } catch (e: any) { setError(e.message); }
  };

  if (error && !rec && id) return <p className="text-red-600">{error}</p>;

  return (
    <div className="max-w-3xl">
      <div className="flex flex-wrap items-center gap-2 mb-3">
        {rec?.doc_no && <span className="font-mono text-sm rounded-lg bg-[var(--soft)] px-2 py-1">{rec.doc_no}</span>}
        {status && <StatusChip status={status} />}
        {rec?._pending && <StatusChip status="waiting" />}
        {rec && (
          <div className="ml-auto flex gap-1">
            <button className={`tab ${tab === "form" ? "tab-on" : ""}`} onClick={() => setTab("form")}>Details</button>
            <button className={`tab ${tab === "history" ? "tab-on" : ""}`} onClick={() => setTab("history")}>
              <History size={14} /> {app.t("history")}
            </button>
            <button className="tab" onClick={() => window.print()} aria-label="Print"><Printer size={14} /></button>
          </div>
        )}
      </div>

      {tab === "history" && rec ? <HistoryList entity={entity.key} id={rec.id} /> : (
        <form onSubmit={(e) => { e.preventDefault(); save(); }} className="space-y-5">
          {needLocation && <div className="rounded-xl bg-amber-50 dark:bg-amber-900/30 p-3 text-sm">Choose a location at the top first.</div>}
          {entity.key === "finance.purchase_invoice" && editable && <ScanBill onFill={(d) => setData({ ...data, ...d })} />}

          {entity.dated && (
            <Labeled label="Date" id="f-doc_date">
              <input id="f-doc_date" type="date" disabled={!editable} value={data.doc_date ?? ""} onChange={(e) => setData({ ...data, doc_date: e.target.value })}
                     className="w-full rounded-xl border border-[var(--line)] bg-[var(--card)] px-3 py-2.5" />
            </Labeled>
          )}

          {sections.map(([sec, fields]) => (
            <fieldset key={sec} className="space-y-4">
              {sec && <legend className="text-sm font-semibold text-[var(--muted)] mb-2">{sec}</legend>}
              <div className="grid gap-4 sm:grid-cols-2">
                {fields.map((f) => (
                  <div key={f.name} className={f.type === "longtext" || f.type === "photos" || f.type === "select" && (f.options?.length ?? 0) > 3 ? "sm:col-span-2" : ""}>
                    <Labeled label={f.label} required={f.required && !f.computed} help={f.help} id={`f-${f.name}`}>
                      <FieldInput id={`f-${f.name}`} field={f} value={data[f.name]} disabled={!editable}
                                  onChange={(v) => setData((d) => ({ ...d, [f.name]: v }))} />
                    </Labeled>
                  </div>
                ))}
              </div>
            </fieldset>
          ))}

          {entity.fields.some((f) => !f.quick && !(f.required && !f.computed)) && (
            <button type="button" onClick={() => setShowAll(!showAll)} className="flex items-center gap-1 text-sm text-[var(--brand)]">
              {showAll ? <ChevronUp size={16} /> : <ChevronDown size={16} />} {showAll ? app.t("fewer_fields") : app.t("all_fields")}
            </button>
          )}

          {entity.children.map((c) => (
            <LinesEditor key={c.name} label={c.label} fields={c.fields} disabled={!editable}
                         lines={data[c.name] ?? []} onChange={(lines) => setData((d) => ({ ...d, [c.name]: lines }))} />
          ))}

          {entity.key === "hr.payroll_run" && rec && editable && (
            <button type="button" className="btn" onClick={async () => {
              try { const r = await generatePayroll(rec.id); app.toast(`${r.employees} employees calculated, ${r.with_checks} need a look`);
                    const fresh = await getRecord(entity.key, rec.id); setRec(fresh); setData(fresh); }
              catch (e: any) { setError(e.message); }
            }}>Calculate payroll from attendance</button>
          )}
          {entity.key === "infra.project" && rec && <ProjectHealth id={rec.id} />}

          {error && <div role="alert" className="rounded-xl bg-red-50 dark:bg-red-900/30 text-red-700 dark:text-red-200 p-3 text-sm">{error}</div>}

          {editable && (
            <div className="sticky bottom-16 md:bottom-0 flex flex-wrap gap-2 bg-[var(--bg)] py-3">
              <button type="submit" disabled={busy || needLocation} className="btn btn-primary flex-1 sm:flex-none">{app.t("save")}</button>
              {entity.workflow && (!status || status === "draft" || status === "sent_back") && (
                <button type="button" disabled={busy || needLocation} onClick={() => save("submit")} className="btn flex-1 sm:flex-none">
                  {app.t("submit")}
                </button>
              )}
            </div>
          )}
          {rec?._can?.cancel && status !== "cancelled" && (
            <button type="button" onClick={cancelDoc} className="text-sm text-red-600 hover:underline">{app.t("cancel_doc")}…</button>
          )}
        </form>
      )}
    </div>
  );
}

function Labeled({ label, required, help, id, children }: { label: string; required?: boolean; help?: string | null; id?: string; children: React.ReactNode }) {
  return (
    <div role="group" aria-labelledby={id ? `${id}-label` : undefined}>
      <label id={id ? `${id}-label` : undefined} htmlFor={id} className="block text-sm font-medium text-[var(--ink)] mb-1.5">
        {label}{required && <span className="text-red-600"> *</span>}
      </label>
      {children}
      {help && <span className="block text-xs text-[var(--muted)] mt-1">{help}</span>}
    </div>
  );
}

function LinesEditor({ label, fields, lines, onChange, disabled }: {
  label: string; fields: Field[]; lines: Record<string, any>[]; onChange: (l: Record<string, any>[]) => void; disabled: boolean;
}) {
  const app = useApp();
  const set = (i: number, k: string, v: any) => onChange(lines.map((l, j) => (j === i ? { ...l, [k]: v } : l)));
  return (
    <section>
      <h2 className="text-base font-semibold mb-2">{label}</h2>
      <div className="space-y-3">
        {lines.map((line, i) => (
          <div key={i} className="rounded-2xl border border-[var(--line)] bg-[var(--card)] p-3">
            <div className="flex items-center mb-2">
              <span className="text-xs text-[var(--muted)]">#{i + 1}</span>
              {!disabled && (
                <button type="button" aria-label="Remove line" className="ml-auto text-red-600" onClick={() => onChange(lines.filter((_, j) => j !== i))}>
                  <Trash2 size={16} />
                </button>
              )}
            </div>
            <div className="grid gap-3 sm:grid-cols-3">
              {fields.map((f) => (
                <Labeled key={f.name} label={f.label} required={f.required && !f.computed} id={`f-${label}-${i}-${f.name}`}>
                  <FieldInput id={`f-${label}-${i}-${f.name}`} field={f} value={line[f.name]} disabled={disabled} onChange={(v) => set(i, f.name, v)} />
                </Labeled>
              ))}
            </div>
          </div>
        ))}
      </div>
      {!disabled && (
        <button type="button" onClick={() => onChange([...lines, {}])} className="mt-2 flex items-center gap-1 text-sm text-[var(--brand)]">
          <Plus size={16} /> {app.t("add_line")}
        </button>
      )}
    </section>
  );
}

function HistoryList({ entity, id }: { entity: string; id: string }) {
  const [rows, setRows] = useState<any[] | null>(null);
  useEffect(() => { getHistory(entity, id).then(setRows).catch(() => setRows([])); }, [entity, id]);
  if (!rows) return <p className="text-[var(--muted)]">Loading…</p>;
  return (
    <ol className="space-y-3">
      {rows.map((h) => (
        <li key={h.id} className="rounded-xl border border-[var(--line)] bg-[var(--card)] p-3 text-sm">
          <div className="flex flex-wrap gap-x-2">
            <b>{h.actor_name ?? (h.actor_type === "system" ? "System" : "Unknown")}</b>
            <span>{h.action === "INSERT" ? "created" : h.action === "UPDATE" ? "changed" : h.action === "DELETE" ? "deleted" : h.action}</span>
            <span className="text-[var(--muted)]">{h.table_name.replace("public.", "").replace(/_/g, " ")}</span>
            <span className="ml-auto text-[var(--muted)]">{dateTime(h.occurred_at)}</span>
          </div>
          <div className="text-xs text-[var(--muted)] mt-0.5">
            {[h.source, h.device_id && `device ${String(h.device_id).slice(0, 8)}`, h.actor_type === "ai_agent" && "by AI assistant"].filter(Boolean).join(" · ")}
          </div>
          {h.reason && <div className="mt-1">Reason: {h.reason}</div>}
          {h.action === "UPDATE" && h.changed_fields && (
            <ul className="mt-1 space-y-0.5">
              {h.changed_fields.filter((f: string) => !["updated_at", "updated_by"].includes(f)).map((f: string) => (
                <li key={f}><span className="text-[var(--muted)]">{humanize(f)}:</span> {fmt(h.old_data?.[f])} → <b>{fmt(h.new_data?.[f])}</b></li>
              ))}
            </ul>
          )}
        </li>
      ))}
    </ol>
  );
}
const fmt = (v: any) => (v === null || v === undefined ? "—" : typeof v === "object" ? JSON.stringify(v) : String(v));

function ProjectHealth({ id }: { id: string }) {
  const [h, setH] = useState<any>(null);
  useEffect(() => { projectHealth(id).then(setH).catch(() => {}); }, [id]);
  if (!h) return null;
  const items: [string, string][] = [
    ["Physical progress", `${h.physical_pct ?? 0}%`], ["Time gone", `${h.time_elapsed_pct ?? 0}%`],
    ["Financial progress", `${h.financial_pct ?? 0}%`], ["Billed", display("money", h.billed)],
    ["Certified", display("money", h.certified)], ["Received", display("money", h.received)],
    ["Work done, not billed", display("money", h.unbilled_work)], ["Hindrance days", String(h.hindrance_days)],
  ];
  return (
    <section className="rounded-2xl border border-[var(--line)] p-4">
      <h2 className="font-semibold mb-3">Project health</h2>
      <dl className="grid grid-cols-2 sm:grid-cols-4 gap-3">
        {items.map(([k, v]) => <div key={k}><dt className="text-xs text-[var(--muted)]">{k}</dt><dd className="text-lg font-semibold tabular-nums">{v}</dd></div>)}
      </dl>
    </section>
  );
}

// Photo of a vendor bill → fields filled by the AI document reader (Zentrix /v1/extract, gst_invoice).
function ScanBill({ onFill }: { onFill: (d: Record<string, any>) => void }) {
  const app = useApp();
  const [busy, setBusy] = useState(false);
  return (
    <label className="flex items-center gap-2 rounded-xl border border-dashed border-[var(--brand)] p-3 text-sm text-[var(--brand)] cursor-pointer">
      <ScanLine size={18} /> {busy ? "Reading the bill…" : "Scan the bill — AI fills the form"}
      <input hidden type="file" accept="image/*,application/pdf" capture="environment" onChange={async (e) => {
        const f = e.target.files?.[0];
        if (!f) return;
        setBusy(true);
        try {
          const b64 = await new Promise<string>((res) => { const r = new FileReader(); r.onload = () => res(String(r.result)); r.readAsDataURL(f); });
          const { data: s } = await (await import("@/lib/supabase")).sb().auth.getSession();
          const resp = await fetch("/api/ai/extract", { method: "POST", headers: { "content-type": "application/json", authorization: `Bearer ${s.session?.access_token}` },
                                                         body: JSON.stringify({ document_type: "gst_invoice", files: [b64], company_id: app.company?.id }) });
          const r = await resp.json();
          if (r.status !== "extracted") throw new Error(r.error ?? r.status ?? "Could not read the bill");
          onFill({
            vendor_invoice_no: r.data.invoice_number, vendor_invoice_date: r.data.invoice_date,
            place_of_supply: r.data.place_of_supply_state_code,
            lines: (r.data.lines ?? []).map((l: any) => ({ description: l.description, hsn_sac: l.hsn, qty: l.qty, uom: l.uom, rate: l.rate, gst_rate: l.gst_rate })),
          });
          if (r.uncertain_fields?.length) app.toast(`Please check: ${r.uncertain_fields.join(", ")}`);
        } catch (err: any) {
          app.toast(err.message, "error");
        } finally { setBusy(false); }
      }} />
    </label>
  );
}
