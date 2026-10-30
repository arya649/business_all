"use client";

import { useRef, useState } from "react";
import { Camera, MapPin, Mic, X } from "lucide-react";
import type { Field } from "@/lib/types";
import { display, humanize, toLocalInput } from "@/lib/format";
import { RefPicker } from "./RefPicker";
import { useApp } from "./AppProvider";
import { sb } from "@/lib/supabase";
import { option as trOption } from "@/lib/labels";

const SPEECH_LANG: Record<string, string> = { en: "en-IN", te: "te-IN", hi: "hi-IN", ta: "ta-IN", kn: "kn-IN" };

export function FieldInput({ field, value, onChange, disabled, id }: {
  field: Field; value: any; onChange: (v: any) => void; disabled?: boolean; id?: string;
}) {
  const app = useApp();
  const base = "w-full rounded-xl border border-[var(--line)] bg-[var(--card)] px-3 py-2.5 text-base text-[var(--ink)] disabled:opacity-60 focus:outline-2 focus:outline-[var(--brand)]";

  if (field.computed) {
    return <div className="rounded-xl bg-[var(--soft)] px-3 py-2.5 text-base min-h-[46px] tabular-nums">{display(field.type, value) || "—"}
      {field.unit && value != null && <span className="text-[var(--muted)] text-sm"> {field.unit}</span>}</div>;
  }

  switch (field.type) {
    case "longtext":
      return <VoiceText id={id} value={value} onChange={onChange} disabled={disabled} className={base} />;
    case "int": case "number": case "money": case "qty": case "percent":
      return (
        <div className="relative">
          {field.type === "money" && <span className="absolute left-3 top-1/2 -translate-y-1/2 text-[var(--muted)]">₹</span>}
          <input id={id} type="number" inputMode="decimal" step="any" disabled={disabled} value={value ?? ""}
                 onChange={(e) => onChange(e.target.value === "" ? null : Number(e.target.value))}
                 className={`${base} text-lg tabular-nums ${field.type === "money" ? "pl-7" : ""} ${field.unit || field.type === "percent" ? "pr-14" : ""}`} />
          {(field.unit || field.type === "percent") && (
            <span className="absolute right-3 top-1/2 -translate-y-1/2 text-sm text-[var(--muted)]">{field.unit ?? "%"}</span>
          )}
        </div>
      );
    case "date":
      return <input id={id} type="date" disabled={disabled} value={value ?? ""} onChange={(e) => onChange(e.target.value || null)} className={base} />;
    case "datetime":
      return (
        <div className="flex gap-2">
          <input id={id} type="datetime-local" disabled={disabled} value={toLocalInput(value)}
                 onChange={(e) => onChange(e.target.value ? new Date(e.target.value).toISOString() : null)} className={base} />
          {!disabled && <button type="button" onClick={() => onChange(new Date().toISOString())}
                                className="shrink-0 rounded-xl border border-[var(--line)] px-3 text-sm">Now</button>}
        </div>
      );
    case "time":
      return <input id={id} type="time" disabled={disabled} value={value ?? ""} onChange={(e) => onChange(e.target.value || null)} className={base} />;
    case "bool":
      return (
        <button id={id} type="button" role="switch" aria-checked={!!value} disabled={disabled} onClick={() => onChange(!value)}
                className={`relative h-8 w-14 rounded-full transition ${value ? "bg-[var(--brand)]" : "bg-slate-300 dark:bg-slate-600"}`}>
          <span className={`absolute top-1 size-6 rounded-full bg-white shadow transition-all ${value ? "left-7" : "left-1"}`} />
        </button>
      );
    case "select": {
      const opts = field.options ?? [];
      if (opts.length <= 6) {
        return (
          <div className="flex flex-wrap gap-2" role="radiogroup" aria-labelledby={id ? `${id}-label` : undefined}>
            {opts.map((o) => (
              <button key={o} type="button" role="radio" aria-checked={value === o} disabled={disabled} onClick={() => onChange(value === o && !field.required ? null : o)}
                      className={`rounded-xl border px-3 py-2 text-sm ${value === o ? "border-[var(--brand)] bg-[var(--brand-soft)] text-[var(--brand)] font-medium" : "border-[var(--line)] bg-[var(--card)]"}`}>
                {trOption(o, app.lang, humanize(o))}
              </button>
            ))}
          </div>
        );
      }
      return (
        <select id={id} disabled={disabled} value={value ?? ""} onChange={(e) => onChange(e.target.value || null)} className={base}>
          <option value="">—</option>
          {opts.map((o) => <option key={o} value={o}>{trOption(o, app.lang, humanize(o))}</option>)}
        </select>
      );
    }
    case "multiselect": {
      const cur: string[] = value ?? [];
      return (
        <div className="flex flex-wrap gap-2">
          {(field.options ?? []).map((o) => {
            const on = cur.includes(o);
            return (
              <button key={o} type="button" disabled={disabled} onClick={() => onChange(on ? cur.filter((x) => x !== o) : [...cur, o])}
                      className={`rounded-xl border px-3 py-2 text-sm ${on ? "border-[var(--brand)] bg-[var(--brand-soft)] text-[var(--brand)]" : "border-[var(--line)]"}`}>
                {trOption(o, app.lang, humanize(o))}
              </button>
            );
          })}
        </div>
      );
    }
    case "ref":
      return <RefPicker id={id} refName={field.ref!} value={value} onChange={onChange} disabled={disabled} />;
    case "photo":
      return <PhotoInput value={value ? [value] : []} onChange={(v) => onChange(v[0] ?? null)} disabled={disabled} label={app.t("take_photo")} />;
    case "photos":
      return <PhotoInput multiple value={value ?? []} onChange={onChange} disabled={disabled} label={app.t("take_photo")} />;
    case "file":
      return <PhotoInput accept="*/*" value={value ? [value] : []} onChange={(v) => onChange(v[0] ?? null)} disabled={disabled} label="Attach file" />;
    case "geo":
      return (
        <div className="flex gap-2 items-center">
          <input id={id} disabled={disabled} value={value ?? ""} onChange={(e) => onChange(e.target.value || null)} placeholder="lat,lng" className={base} />
          {!disabled && (
            <button type="button" className="shrink-0 rounded-xl border border-[var(--line)] px-3 py-2.5" aria-label="Use my location"
                    onClick={() => navigator.geolocation.getCurrentPosition(
                      (p) => onChange(`${p.coords.latitude.toFixed(6)},${p.coords.longitude.toFixed(6)}`),
                      () => app.toast("Could not get location. Turn on GPS.", "error"), { enableHighAccuracy: true, timeout: 15000 })}>
              <MapPin size={20} />
            </button>
          )}
        </div>
      );
    case "json":
      return (
        <textarea id={id} disabled={disabled} rows={3} className={`${base} font-mono text-sm`}
                  defaultValue={value == null ? "" : JSON.stringify(value)}
                  onBlur={(e) => { try { onChange(e.target.value ? JSON.parse(e.target.value) : null); } catch { app.toast("Not valid JSON", "error"); } }} />
      );
    case "phone":
      return <input id={id} type="tel" inputMode="tel" disabled={disabled} value={value ?? ""} onChange={(e) => onChange(e.target.value || null)} className={base} />;
    default:
      return <input id={id} disabled={disabled} value={value ?? ""} onChange={(e) => onChange(e.target.value || null)} className={base} />;
  }
}

function VoiceText({ id, value, onChange, disabled, className }: { id?: string; value: any; onChange: (v: any) => void; disabled?: boolean; className: string }) {
  const app = useApp();
  const [listening, setListening] = useState(false);
  const SR = typeof window !== "undefined" ? ((window as any).SpeechRecognition || (window as any).webkitSpeechRecognition) : null;
  const listen = () => {
    const r = new SR();
    r.lang = SPEECH_LANG[app.lang] ?? "en-IN";
    r.interimResults = false;
    r.onresult = (e: any) => onChange(((value ? value + " " : "") + e.results[0][0].transcript).trim());
    r.onend = () => setListening(false);
    setListening(true);
    r.start();
  };
  return (
    <div className="relative">
      <textarea id={id} rows={3} disabled={disabled} value={value ?? ""} onChange={(e) => onChange(e.target.value || null)} className={`${className} pr-12`} />
      {SR && !disabled && (
        <button type="button" onClick={listen} aria-label={app.t("speak")}
                className={`absolute right-2 top-2 rounded-full p-2 ${listening ? "bg-red-500 text-white animate-pulse" : "bg-[var(--soft)]"}`}>
          <Mic size={18} />
        </button>
      )}
    </div>
  );
}

// Photos are shrunk on the phone, then uploaded. With no signal they are kept inside the record and
// uploaded when it is sent.
async function shrink(file: File): Promise<Blob> {
  if (!file.type.startsWith("image/")) return file;
  const img = await createImageBitmap(file);
  const scale = Math.min(1, 1280 / Math.max(img.width, img.height));
  const c = document.createElement("canvas");
  c.width = Math.round(img.width * scale);
  c.height = Math.round(img.height * scale);
  const ctx = c.getContext("2d")!;
  ctx.drawImage(img, 0, 0, c.width, c.height);
  ctx.fillStyle = "rgba(0,0,0,.55)";
  ctx.fillRect(0, c.height - 26, c.width, 26);
  ctx.fillStyle = "#fff";
  ctx.font = "14px sans-serif";
  ctx.fillText(new Date().toLocaleString("en-IN"), 8, c.height - 8);   // time stamp on every photo
  return await new Promise((res) => c.toBlob((b) => res(b!), "image/jpeg", 0.72));
}

function PhotoInput({ value, onChange, disabled, multiple, label, accept = "image/*" }: {
  value: string[]; onChange: (v: string[]) => void; disabled?: boolean; multiple?: boolean; label: string; accept?: string;
}) {
  const app = useApp();
  const ref = useRef<HTMLInputElement>(null);
  const [busy, setBusy] = useState(false);
  const pick = async (files: FileList | null) => {
    if (!files?.length) return;
    setBusy(true);
    const out: string[] = [];
    for (const f of Array.from(files)) {
      const blob = await shrink(f);
      const path = `${app.ctx?.tenant?.id}/${new Date().toISOString().slice(0, 10)}/${crypto.randomUUID()}.${f.type.startsWith("image/") ? "jpg" : f.name.split(".").pop()}`;
      try {
        const { error } = await sb().storage.from("erp-files").upload(path, blob, { contentType: blob.type });
        if (error) throw error;
        out.push(`storage:${path}`);
      } catch {
        out.push(await new Promise<string>((res) => { const r = new FileReader(); r.onload = () => res(String(r.result)); r.readAsDataURL(blob); }));
      }
    }
    onChange(multiple ? [...value, ...out] : out.slice(0, 1));
    setBusy(false);
  };
  return (
    <div className="flex flex-wrap gap-2 items-center">
      {value.map((v, i) => (
        <div key={i} className="relative">
          <StoredImage src={v} className="size-20 rounded-lg object-cover border border-[var(--line)]" />
          {!disabled && (
            <button type="button" aria-label="Remove" onClick={() => onChange(value.filter((_, j) => j !== i))}
                    className="absolute -top-2 -right-2 rounded-full bg-red-600 text-white p-0.5"><X size={14} /></button>
          )}
        </div>
      ))}
      {!disabled && (multiple || value.length === 0) && (
        <>
          <button type="button" onClick={() => ref.current?.click()} disabled={busy}
                  className="flex items-center gap-2 rounded-xl border border-dashed border-[var(--line)] px-4 py-3 text-sm">
            <Camera size={20} /> {busy ? "…" : label}
          </button>
          <input ref={ref} hidden type="file" accept={accept} capture={accept === "image/*" ? "environment" : undefined}
                 multiple={multiple} onChange={(e) => pick(e.target.files)} />
        </>
      )}
    </div>
  );
}

export function StoredImage({ src, className }: { src: string; className?: string }) {
  const url = src.startsWith("storage:")
    ? sb().storage.from("erp-files").getPublicUrl(src.slice(8)).data.publicUrl
    : src;
  // eslint-disable-next-line @next/next/no-img-element
  return <img src={url} alt="" className={className} />;
}
