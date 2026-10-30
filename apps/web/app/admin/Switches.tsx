"use client";

import { useEffect, useMemo, useState } from "react";
import { ChevronRight } from "lucide-react";
import { sb } from "@/lib/supabase";
import { useApp } from "@/components/AppProvider";

type State = "on" | "read_only" | "hidden" | "off";
interface Feature { key: string; parent_key: string | null; label: string; sort: number }
interface Flag { id: string; feature_key: string; level: string; level_id: string; state: State | null; config: any }

const LEVELS = [["tenant", "Whole group"], ["company", "Company"], ["location", "Location"], ["role", "Role"], ["user", "One person"]] as const;
const STATE_STYLE: Record<State, string> = {
  on: "bg-emerald-600 text-white", read_only: "bg-sky-600 text-white", hidden: "bg-slate-500 text-white", off: "bg-red-600 text-white",
};
const STATE_LABEL: Record<State, string> = { on: "On", read_only: "View only", hidden: "Hidden", off: "Off" };

// A tree of every module and feature. Pick who it applies to, flip a switch, and the preview on the right
// shows what that person sees on their next tap.
export function Switches() {
  const app = useApp();
  const tenant = app.ctx!.tenant!.id;
  const [features, setFeatures] = useState<Feature[]>([]);
  const [flags, setFlags] = useState<Flag[]>([]);
  const [level, setLevel] = useState<(typeof LEVELS)[number][0]>("tenant");
  const [target, setTarget] = useState<string>(tenant);
  const [targets, setTargets] = useState<{ id: string; label: string }[]>([]);
  const [open, setOpen] = useState<Set<string>>(new Set());
  const [previewUser, setPreviewUser] = useState<string>("");
  const [users, setUsers] = useState<{ id: string; full_name: string }[]>([]);
  const [preview, setPreview] = useState<Record<string, State>>({});
  const [screens, setScreens] = useState<{ key: string; label: string; read_only: boolean; can_create: boolean; fields: number }[]>([]);

  const load = async () => {
    const [f, fl, u] = await Promise.all([
      sb().from("feature").select("key,parent_key,label,sort").order("sort"),
      sb().from("feature_flag").select("id,feature_key,level,level_id,state,config").eq("tenant_id", tenant),
      sb().from("app_user").select("id,full_name").eq("tenant_id", tenant).order("full_name"),
    ]);
    setFeatures(f.data ?? []); setFlags(fl.data ?? []); setUsers(u.data ?? []);
  };
  useEffect(() => { load(); }, []); // eslint-disable-line

  useEffect(() => {
    (async () => {
      if (level === "tenant") { setTargets([{ id: tenant, label: app.ctx!.tenant!.name }]); setTarget(tenant); return; }
      let rows: { id: string; label: string }[] = [];
      if (level === "company") rows = app.ctx!.companies.map((c) => ({ id: c.id, label: c.name }));
      if (level === "location") rows = app.ctx!.companies.flatMap((c) => c.locations.map((l) => ({ id: l.id, label: `${c.code} · ${l.name}` })));
      if (level === "role") rows = ((await sb().from("role").select("id,name").eq("tenant_id", tenant)).data ?? []).map((r: any) => ({ id: r.id, label: r.name }));
      if (level === "user") rows = users.map((u) => ({ id: u.id, label: u.full_name }));
      setTargets(rows);
      setTarget(rows[0]?.id ?? "");
    })();
  }, [level, users]); // eslint-disable-line

  const refreshPreview = async () => {
    if (!previewUser || !app.company) { setPreview({}); return; }
    const args = { p_user: previewUser, p_company: app.company.id, p_location: app.location?.id ?? null };
    const [{ data }, { data: sc }] = await Promise.all([sb().rpc("preview_features", args), sb().rpc("preview_screens", args)]);
    setPreview(Object.fromEntries((data ?? []).map((r: any) => [r.feature_key, r.state])));
    setScreens(sc ?? []);
  };
  useEffect(() => { refreshPreview(); }, [previewUser, flags, app.company, app.location]); // eslint-disable-line

  const children = useMemo(() => {
    const m = new Map<string | null, Feature[]>();
    for (const f of features) m.set(f.parent_key, [...(m.get(f.parent_key) ?? []), f]);
    return m;
  }, [features]);
  const flagFor = (key: string) => flags.find((f) => f.feature_key === key && f.level === level && f.level_id === target);

  const setState = async (key: string, state: State | null) => {
    const existing = flagFor(key);
    if (state === null && existing && !existing.config) {
      await sb().from("feature_flag").delete().eq("id", existing.id);
    } else {
      const { error } = await sb().from("feature_flag").upsert(
        { tenant_id: tenant, feature_key: key, level, level_id: target, state, config: existing?.config ?? null },
        { onConflict: "feature_key,level,level_id" });
      if (error) { app.toast(error.message, "error"); return; }
    }
    const fl = await sb().from("feature_flag").select("id,feature_key,level,level_id,state,config").eq("tenant_id", tenant);
    setFlags(fl.data ?? []);
  };

  const Node = ({ f, depth }: { f: Feature; depth: number }) => {
    const kids = children.get(f.key) ?? [];
    const flag = flagFor(f.key);
    const isOpen = open.has(f.key);
    return (
      <li>
        <div className="flex items-center gap-2 py-1.5 border-b border-[var(--line)]" style={{ paddingLeft: depth * 18 }}>
          {kids.length ? (
            <button aria-label="Expand" onClick={() => setOpen((s) => { const n = new Set(s); n.has(f.key) ? n.delete(f.key) : n.add(f.key); return n; })}
                    className={`transition ${isOpen ? "rotate-90" : ""}`}><ChevronRight size={16} /></button>
          ) : <span className="w-4" />}
          <span className={`text-sm ${depth === 0 ? "font-semibold" : ""}`}>{f.label}</span>
          {previewUser && preview[f.key] && preview[f.key] !== "on" && (
            <span className="text-[10px] rounded px-1.5 py-0.5 bg-[var(--soft)] text-[var(--muted)]">{STATE_LABEL[preview[f.key]]} for them</span>
          )}
          <div className="ml-auto flex rounded-lg border border-[var(--line)] overflow-hidden text-xs" role="radiogroup" aria-label={f.label}>
            <button role="radio" aria-checked={!flag?.state} onClick={() => setState(f.key, null)}
                    className={`px-2 py-1 ${!flag?.state ? "bg-[var(--soft)] font-medium" : ""}`}>Inherit</button>
            {(["on", "read_only", "hidden", "off"] as State[]).map((s) => (
              <button key={s} role="radio" aria-checked={flag?.state === s} onClick={() => setState(f.key, s)}
                      className={`px-2 py-1 border-l border-[var(--line)] ${flag?.state === s ? STATE_STYLE[s] : ""}`}>{STATE_LABEL[s]}</button>
            ))}
          </div>
        </div>
        {isOpen && kids.length > 0 && <ul>{kids.map((k) => <Node key={k.key} f={k} depth={depth + 1} />)}</ul>}
      </li>
    );
  };


  return (
    <div className="grid gap-4 lg:grid-cols-[1fr_320px]">
      <section className="card p-3">
        <div className="flex flex-wrap gap-2 mb-3">
          <select aria-label="Applies to" value={level} onChange={(e) => setLevel(e.target.value as any)} className="rounded-lg border border-[var(--line)] bg-[var(--card)] px-2 py-1.5 text-sm">
            {LEVELS.map(([k, l]) => <option key={k} value={k}>{l}</option>)}
          </select>
          {level !== "tenant" && (
            <select aria-label="Which" value={target} onChange={(e) => setTarget(e.target.value)} className="rounded-lg border border-[var(--line)] bg-[var(--card)] px-2 py-1.5 text-sm">
              {targets.map((t) => <option key={t.id} value={t.id}>{t.label}</option>)}
            </select>
          )}
          <p className="text-xs text-[var(--muted)] w-full">The most specific setting wins: person → role → location → company → group. A feature is never more open than its parent or your plan.</p>
        </div>
        <ul>{(children.get(null) ?? []).map((f) => <Node key={f.key} f={f} depth={0} />)}</ul>
      </section>

      <aside className="card p-3 h-fit lg:sticky lg:top-20">
        <h3 className="font-semibold mb-2">Preview as</h3>
        <select aria-label="Preview as user" value={previewUser} onChange={(e) => setPreviewUser(e.target.value)} className="w-full rounded-lg border border-[var(--line)] bg-[var(--card)] px-2 py-1.5 text-sm">
          <option value="">Choose a person…</option>
          {users.map((u) => <option key={u.id} value={u.id}>{u.full_name}</option>)}
        </select>
        {previewUser && (
          <>
            <p className="text-xs text-[var(--muted)] mt-2">In {app.company?.name}{app.location ? `, ${app.location.name}` : ""}, they see:</p>
            <ul className="mt-2 space-y-1 text-sm">
              {screens.map((e) => (
                <li key={e.key} className="rounded-lg bg-[var(--soft)] px-2 py-1 flex gap-2">
                  <span>{e.label}</span>
                  <span className="ml-auto text-xs text-[var(--muted)]">{e.read_only ? "view only" : e.can_create ? "can add" : "can view"} · {e.fields} fields</span>
                </li>
              ))}
              {screens.length === 0 && <li className="text-[var(--muted)]">Nothing here for them in this company or location.</li>}
            </ul>
          </>
        )}
      </aside>
    </div>
  );
}
