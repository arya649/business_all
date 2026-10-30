"use client";

// Step-by-step entry for people who find forms hard: one question per screen, read aloud in their
// language, big picture buttons, a big green Next, and a clear tick when it is saved.
import { useEffect, useMemo, useState } from "react";
import { ArrowLeft, ArrowRight, Check, Volume2 } from "lucide-react";
import type { Entity, Field, Row } from "@/lib/types";
import { useApp } from "./AppProvider";
import { FieldInput } from "./FieldInput";
import { Icon } from "./Icon";
import { lookup } from "@/lib/erp";
import { display, humanize } from "@/lib/format";
import { option as trOption } from "@/lib/labels";

const VOICE: Record<string, string> = { en: "en-IN", te: "te-IN", hi: "hi-IN", ta: "ta-IN", kn: "kn-IN" };

export function speak(text: string, lang: string) {
  if (typeof window === "undefined" || !("speechSynthesis" in window)) return;
  window.speechSynthesis.cancel();
  const u = new SpeechSynthesisUtterance(text);
  u.lang = VOICE[lang] ?? "en-IN";
  const voice = window.speechSynthesis.getVoices().find((v) => v.lang === u.lang);
  if (voice) u.voice = voice;
  u.rate = 0.9;
  window.speechSynthesis.speak(u);
}

export function SpeakButton({ text, className = "" }: { text: string; className?: string }) {
  const app = useApp();
  return (
    <button type="button" aria-label={`Read aloud: ${text}`} onClick={(e) => { e.preventDefault(); e.stopPropagation(); speak(text, app.lang); }}
            className={`rounded-full p-2 bg-[var(--soft)] text-[var(--brand)] ${className}`}>
      <Volume2 size={20} />
    </button>
  );
}

interface Step { key: string; field: Field; line?: { child: string; index: number; title: string } }

function isEmpty(v: unknown) {
  return v === null || v === undefined || v === "" || (Array.isArray(v) && v.length === 0);
}

export function GuidedForm({ entity, data, setData, onSave, busy, saved, onFullForm }: {
  entity: Entity; data: Record<string, any>; setData: (fn: (d: Record<string, any>) => Record<string, any>) => void;
  onSave: (submit: boolean) => void; busy: boolean; saved: Row | null; onFullForm: () => void;
}) {
  const app = useApp();
  const [i, setI] = useState(0);
  const [lineTitles, setLineTitles] = useState<Record<string, string>>({});

  // Questions: the main fields first, then each existing line's empty numbers and photos (e.g. closing readings).
  const steps: Step[] = useMemo(() => {
    const main = entity.fields.filter((f) => !f.computed && (f.quick || f.required) && !["json", "multiselect"].includes(f.type));
    const out: Step[] = main.map((f) => ({ key: f.name, field: f }));
    for (const c of entity.children) {
      const lines: any[] = data[c.name] ?? [];
      lines.forEach((line, index) => {
        const titleField = c.fields.find((f) => f.type === "ref" || f.type === "text");
        const title = titleField ? (lineTitles[line[titleField.name]] ?? String(line[titleField.name] ?? `#${index + 1}`)) : `#${index + 1}`;
        for (const f of c.fields) {
          if (f.computed || !["qty", "number", "money", "int", "photo"].includes(f.type)) continue;
          if (isEmpty(line[f.name]) || f.name === "closing") out.push({ key: `${c.name}.${index}.${f.name}`, field: f, line: { child: c.name, index, title } });
        }
      });
    }
    return out;
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [entity, (Object.keys(data).filter((k) => entity.children.some((c) => c.name === k)).map((k) => (data[k] ?? []).length)).join(","), lineTitles]);

  // names for line titles (nozzle names, items)
  useEffect(() => {
    if (!app.company) return;
    for (const c of entity.children) {
      const tf = c.fields.find((f) => f.type === "ref");
      const ids = (data[c.name] ?? []).map((l: any) => l[tf?.name ?? ""]).filter(Boolean);
      if (tf && ids.length) lookup(tf.ref!, app.company.id, "", ids).then((rows) =>
        setLineTitles((t) => ({ ...t, ...Object.fromEntries(rows.map((r) => [r.id, r.label])) }))).catch(() => {});
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [entity.key, app.company]);

  // reopening a record (e.g. closing a shift) starts at the first question still unanswered
  const [started, setStarted] = useState(false);
  useEffect(() => {
    if (started || !steps.length || !data.id) return;
    const first = steps.findIndex((st) => isEmpty(st.line ? data[st.line.child]?.[st.line.index]?.[st.field.name] : data[st.field.name]));
    if (first > 0) setI(first);
    setStarted(true);
  }, [steps, data, started]);

  const atReview = i >= steps.length;
  const step = steps[i];
  const question = step ? (step.line ? `${step.line.title}: ${step.field.label}` : step.field.label) : "";

  useEffect(() => {
    if (localStorage.getItem("erp.voice") !== "off") speak(atReview ? app.t("check_and_save") : question, app.lang);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [i, atReview]);

  useEffect(() => {
    if (saved) speak(app.t("saved"), app.lang);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [saved]);

  const value = step ? (step.line ? data[step.line.child]?.[step.line.index]?.[step.field.name] : data[step.field.name]) : null;
  const setValue = (v: any) => {
    if (!step) return;
    if (step.line) {
      const { child, index } = step.line;
      setData((d) => ({ ...d, [child]: (d[child] ?? []).map((l: any, j: number) => (j === index ? { ...l, [step.field.name]: v } : l)) }));
    } else setData((d) => ({ ...d, [step.field.name]: v }));
    // choices move on by themselves
    if (["select", "ref", "bool"].includes(step.field.type) && v !== null) setTimeout(() => setI((n) => n + 1), 250);
  };
  const missingRequired = step && step.field.required && isEmpty(value);

  if (saved) {
    return (
      <div className="flex flex-col items-center justify-center gap-6 py-16 text-center">
        <div className="rounded-full bg-emerald-600 text-white p-6 animate-[pulse_1s_ease-in-out_2]"><Check size={72} strokeWidth={3} /></div>
        <div className="text-3xl font-semibold">{app.t("saved")}</div>
        {saved.doc_no && <div className="font-mono text-xl">{saved.doc_no}</div>}
        <div className="grid gap-3 w-full max-w-sm">
          <a href={`/m?e=${entity.key}&id=new`} className="btn btn-primary text-lg !min-h-16">{app.t("new")} {entity.label}</a>
          <a href="/" className="btn text-lg !min-h-14">{app.t("home")}</a>
        </div>
      </div>
    );
  }

  return (
    <div className="max-w-lg mx-auto flex flex-col gap-5 min-h-[70dvh]">
      {/* progress */}
      <div className="flex items-center gap-3">
        <span className="rounded-xl bg-[var(--brand-soft)] text-[var(--brand)] p-2"><Icon name={entity.icon} size={28} /></span>
        <div className="flex-1 h-3 rounded-full bg-[var(--soft)] overflow-hidden" role="progressbar" aria-valuemin={0} aria-valuemax={steps.length} aria-valuenow={i}>
          <div className="h-full bg-[var(--brand)] transition-all" style={{ width: `${(Math.min(i, steps.length) / Math.max(steps.length, 1)) * 100}%` }} />
        </div>
        <span className="text-sm tabular-nums text-[var(--muted)]">{Math.min(i + 1, steps.length)}/{steps.length}</span>
      </div>

      {!atReview && step ? (
        <section className="flex-1 flex flex-col gap-5">
          <div className="flex items-start gap-3">
            <h2 className="text-2xl sm:text-3xl font-semibold leading-snug flex-1">
              {question}{step.field.required && <span className="text-red-600"> *</span>}
            </h2>
            <SpeakButton text={question} />
          </div>
          {step.field.unit && <div className="text-lg text-[var(--muted)]">({step.field.unit})</div>}
          <div className="guided-input">
            {step.field.type === "ref" ? <BigChoice refName={step.field.ref!} value={value} onChange={setValue} />
              : <FieldInput id={`g-${step.key}`} field={step.field} value={value} onChange={setValue} />}
          </div>
          {step.field.help && <p className="text-[var(--muted)]">{step.field.help}</p>}
        </section>
      ) : (
        <section className="flex-1 space-y-3">
          <div className="flex items-center gap-3">
            <h2 className="text-2xl font-semibold flex-1">{app.t("check_and_save")}</h2>
            <SpeakButton text={app.t("check_and_save")} />
          </div>
          <ul className="space-y-2">
            {steps.map((s, n) => {
              const v = s.line ? data[s.line.child]?.[s.line.index]?.[s.field.name] : data[s.field.name];
              return (
                <li key={s.key}>
                  <button type="button" onClick={() => setI(n)} className="card w-full text-left p-3 flex gap-3 items-center">
                    <span className="text-[var(--muted)] flex-1">{s.line ? `${s.line.title}: ` : ""}{s.field.label}</span>
                    <span className="font-semibold">{s.field.type === "ref" ? (isEmpty(v) ? "—" : "✓") :
                      ["photo", "photos"].includes(s.field.type) ? (isEmpty(v) ? "—" : "📷 ✓") :
                      s.field.type === "select" && v ? trOption(String(v), app.lang, humanize(String(v))) : display(s.field.type, v) || "—"}</span>
                  </button>
                </li>
              );
            })}
          </ul>
        </section>
      )}

      <div className="sticky bottom-16 md:bottom-2 grid grid-cols-[auto_1fr] gap-3 bg-[var(--bg)] py-2">
        <button type="button" disabled={i === 0} onClick={() => setI(i - 1)} aria-label="Back" className="btn !min-h-16 !px-6">
          <ArrowLeft size={28} />
        </button>
        {!atReview ? (
          <button type="button" disabled={!!missingRequired} onClick={() => setI(i + 1)}
                  className="btn btn-primary !min-h-16 text-xl gap-2">{app.t("next")} <ArrowRight size={28} /></button>
        ) : (
          <button type="button" disabled={busy} onClick={() => onSave(entity.workflow)}
                  className="btn !min-h-16 text-xl gap-2 !bg-emerald-600 !border-emerald-600 !text-white"><Check size={28} /> {app.t("save")}</button>
        )}
      </div>
      <button type="button" onClick={onFullForm} className="text-sm text-[var(--muted)] underline self-center">{app.t("full_form")}</button>
    </div>
  );
}

// Big buttons instead of a search box: tanks, nozzles, vehicles, customers, projects…
function BigChoice({ refName, value, onChange }: { refName: string; value: string | null; onChange: (v: string | null) => void }) {
  const app = useApp();
  const [rows, setRows] = useState<{ id: string; label: string; sub: string | null }[]>([]);
  const [q, setQ] = useState("");
  useEffect(() => {
    if (!app.company) return;
    const t = setTimeout(() => lookup(refName, app.company!.id, q).then(setRows).catch(() => setRows([])), 150);
    return () => clearTimeout(t);
  }, [refName, q, app.company]);
  return (
    <div className="space-y-3">
      {(rows.length > 8 || q) && (
        <input value={q} onChange={(e) => setQ(e.target.value)} placeholder={app.t("search")} aria-label={app.t("search")}
               className="w-full rounded-xl border border-[var(--line)] bg-[var(--card)] px-4 py-3 text-lg" />
      )}
      <div className="grid grid-cols-2 gap-3">
        {rows.slice(0, 12).map((r) => (
          <button key={r.id} type="button" onClick={() => onChange(r.id)}
                  className={`rounded-2xl border-2 p-4 text-left min-h-20 ${value === r.id ? "border-[var(--brand)] bg-[var(--brand-soft)]" : "border-[var(--line)] bg-[var(--card)]"}`}>
            <div className="text-lg font-semibold leading-tight">{r.label}</div>
            {r.sub && <div className="text-sm text-[var(--muted)]">{r.sub}</div>}
          </button>
        ))}
      </div>
    </div>
  );
}
