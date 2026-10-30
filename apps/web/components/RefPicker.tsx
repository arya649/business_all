"use client";

import { useEffect, useRef, useState } from "react";
import { Search, X } from "lucide-react";
import { lookup, type LookupRow } from "@/lib/erp";
import { useApp } from "./AppProvider";

const labelCache = new Map<string, string>();

export function RefPicker({ id, refName, value, onChange, disabled }: {
  id?: string; refName: string; value: string | null; onChange: (v: string | null) => void; disabled?: boolean;
}) {
  const app = useApp();
  const [open, setOpen] = useState(false);
  const [q, setQ] = useState("");
  const [rows, setRows] = useState<LookupRow[]>([]);
  const [label, setLabel] = useState<string>(value ? labelCache.get(value) ?? "" : "");
  const box = useRef<HTMLDivElement>(null);
  const co = app.company?.id;

  useEffect(() => {
    if (!value || !co) { setLabel(""); return; }
    if (labelCache.has(value)) { setLabel(labelCache.get(value)!); return; }
    lookup(refName, co, "", [value]).then((r) => {
      if (r[0]) { labelCache.set(value, r[0].label); setLabel(r[0].label); }
    }).catch(() => setLabel(value.slice(0, 8)));
  }, [value, refName, co]);

  useEffect(() => {
    if (!open || !co) return;
    const id = setTimeout(() => lookup(refName, co, q).then(setRows).catch(() => setRows([])), 200);
    return () => clearTimeout(id);
  }, [q, open, refName, co]);

  useEffect(() => {
    const close = (e: MouseEvent) => { if (box.current && !box.current.contains(e.target as Node)) setOpen(false); };
    document.addEventListener("mousedown", close);
    return () => document.removeEventListener("mousedown", close);
  }, []);

  return (
    <div ref={box} className="relative">
      <button id={id} type="button" disabled={disabled} onClick={() => setOpen(!open)} aria-haspopup="listbox" aria-expanded={open}
              className="w-full text-left rounded-xl border border-[var(--line)] bg-[var(--card)] px-3 py-2.5 text-base min-h-[46px] disabled:opacity-60 flex items-center gap-2">
        <span className={`truncate ${label ? "" : "text-[var(--muted)]"}`}>{label || "Choose…"}</span>
        {value && !disabled && (
          <span role="button" aria-label="Clear" className="ml-auto text-[var(--muted)]"
                onClick={(e) => { e.stopPropagation(); onChange(null); }}><X size={16} /></span>
        )}
      </button>
      {open && (
        <div className="absolute z-40 mt-1 w-full rounded-xl border border-[var(--line)] bg-[var(--card)] shadow-xl">
          <div className="flex items-center gap-2 border-b border-[var(--line)] px-3">
            <Search size={16} className="text-[var(--muted)]" />
            <input autoFocus value={q} onChange={(e) => setQ(e.target.value)} placeholder={app.t("search")}
                   className="w-full bg-transparent py-2.5 outline-none" />
          </div>
          <ul className="max-h-72 overflow-auto">
            {rows.map((r) => (
              <li key={r.id}>
                <button type="button" className="w-full text-left px-3 py-2.5 hover:bg-[var(--soft)]"
                        onClick={() => { labelCache.set(r.id, r.label); setLabel(r.label); onChange(r.id); setOpen(false); }}>
                  <div>{r.label}</div>
                  {r.sub && <div className="text-xs text-[var(--muted)]">{r.sub}</div>}
                </button>
              </li>
            ))}
            {rows.length === 0 && <li className="px-3 py-3 text-sm text-[var(--muted)]">{app.t("nothing_yet")}</li>}
          </ul>
        </div>
      )}
    </div>
  );
}
