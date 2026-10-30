"use client";

import { useEffect, useMemo, useState } from "react";
import { sb } from "@/lib/supabase";
import { useApp } from "@/components/AppProvider";

const ACTIONS = ["view", "create", "edit", "delete", "approve", "export", "print", "see_rates", "see_cost"] as const;
interface Perm { role_id: string; feature_key: string; actions: string[]; masked_fields: string[]; edit_window_hours: number | null }

// navam-style permission table: for each feature, what the role can do and which fields it sees
// ("Fields 14/17"). Untick a field and it vanishes from that role's screens, lists, exports and AI answers.
export function Roles() {
  const app = useApp();
  const tenant = app.ctx!.tenant!.id;
  const [roles, setRoles] = useState<any[]>([]);
  const [role, setRole] = useState<string>("");
  const [perms, setPerms] = useState<Perm[]>([]);
  const [features, setFeatures] = useState<{ key: string; parent_key: string | null; label: string }[]>([]);
  const [fieldsFor, setFieldsFor] = useState<string | null>(null);
  const [fields, setFields] = useState<any[]>([]);
  const [newRole, setNewRole] = useState("");

  const loadRoles = async () => {
    const r = (await sb().from("role").select("*").eq("tenant_id", tenant).order("name")).data ?? [];
    setRoles(r);
    if (!role && r[0]) setRole(r[0].id);
  };
  useEffect(() => {
    loadRoles();
    sb().from("feature").select("key,parent_key,label").order("sort").then(({ data }) => setFeatures(data ?? []));
  }, []); // eslint-disable-line
  useEffect(() => {
    if (role) sb().from("role_permission").select("*").eq("role_id", role).then(({ data }) => setPerms(data ?? []));
  }, [role]);
  useEffect(() => {
    if (fieldsFor) sb().rpc("feature_fields", { p_feature: fieldsFor }).then(({ data }) => setFields(data ?? []));
  }, [fieldsFor]);

  // modules and their first level of features
  const rows = useMemo(() => features.filter((f) => !f.parent_key || features.find((p) => p.key === f.parent_key && !p.parent_key)), [features]);
  const perm = (k: string) => perms.find((p) => p.feature_key === k);

  const save = async (k: string, patch: Partial<Perm>) => {
    const cur = perm(k) ?? { role_id: role, feature_key: k, actions: [], masked_fields: [], edit_window_hours: null };
    const next = { ...cur, ...patch };
    if (next.actions.length === 0) await sb().from("role_permission").delete().eq("role_id", role).eq("feature_key", k);
    else {
      const { error } = await sb().from("role_permission").upsert(next, { onConflict: "role_id,feature_key" });
      if (error) { app.toast(error.message, "error"); return; }
    }
    const { data } = await sb().from("role_permission").select("*").eq("role_id", role);
    setPerms(data ?? []);
  };

  const fieldNames = [...new Set(fields.map((f) => f.name))];
  const masked = perm(fieldsFor ?? "")?.masked_fields ?? [];

  return (
    <div className="space-y-4">
      <div className="flex flex-wrap gap-2 items-center">
        <select aria-label="Role" value={role} onChange={(e) => setRole(e.target.value)} className="rounded-lg border border-[var(--line)] bg-[var(--card)] px-2 py-1.5">
          {roles.map((r) => <option key={r.id} value={r.id}>{r.name}</option>)}
        </select>
        {roles.find((r) => r.id === role) && (
          <select aria-label="Screen style" value={roles.find((r) => r.id === role).ui_mode}
                  onChange={async (e) => { await sb().from("role").update({ ui_mode: e.target.value }).eq("id", role); loadRoles(); }}
                  className="rounded-lg border border-[var(--line)] bg-[var(--card)] px-2 py-1.5 text-sm">
            <option value="simple">Simple screens (field staff)</option><option value="standard">Standard</option><option value="power">Power (accounts / admin)</option>
          </select>
        )}
        <form className="flex gap-2 ml-auto" onSubmit={async (e) => {
          e.preventDefault();
          if (!newRole) return;
          const { data, error } = await sb().from("role").insert({ tenant_id: tenant, name: newRole }).select().single();
          if (error) app.toast(error.message, "error"); else { setNewRole(""); await loadRoles(); setRole(data.id); }
        }}>
          <input value={newRole} onChange={(e) => setNewRole(e.target.value)} placeholder="New role name" className="rounded-lg border border-[var(--line)] bg-[var(--card)] px-2 py-1.5 text-sm" />
          <button className="btn !min-h-0 !py-1.5">Add role</button>
        </form>
      </div>

      <div className="grid gap-4 lg:grid-cols-[1fr_300px]">
        <div className="card overflow-x-auto">
          <table className="w-full text-sm">
            <thead className="text-left text-[var(--muted)] border-b border-[var(--line)]">
              <tr><th className="px-3 py-2">Feature</th>{ACTIONS.map((a) => <th key={a} className="px-1 py-2 text-center font-medium capitalize">{a.replace("_", " ")}</th>)}<th className="px-2 py-2">Fields</th></tr>
            </thead>
            <tbody>
              {rows.map((f) => {
                const p = perm(f.key);
                return (
                  <tr key={f.key} className="border-b border-[var(--line)]">
                    <td className={`px-3 py-1.5 ${f.parent_key ? "pl-7" : "font-semibold"}`}>{f.label}</td>
                    {ACTIONS.map((a) => (
                      <td key={a} className="text-center">
                        <input type="checkbox" aria-label={`${f.label} ${a}`} checked={!!p?.actions.includes(a)}
                               onChange={(e) => save(f.key, { actions: e.target.checked ? [...(p?.actions ?? []), a] : (p?.actions ?? []).filter((x) => x !== a) })} />
                      </td>
                    ))}
                    <td className="px-2">
                      {p && <button className="text-[var(--brand)] text-xs whitespace-nowrap" onClick={() => setFieldsFor(f.key)}>
                        {fieldsFor === f.key ? "▶ " : ""}hide…{p.masked_fields.length ? ` (${p.masked_fields.length})` : ""}</button>}
                    </td>
                  </tr>
                );
              })}
            </tbody>
          </table>
        </div>

        <aside className="card p-3 h-fit lg:sticky lg:top-20">
          {!fieldsFor ? <p className="text-sm text-[var(--muted)]">Tick “view” for a feature, then choose “hide…” to pick which fields this role sees.</p> : (
            <>
              <h3 className="font-semibold">{features.find((f) => f.key === fieldsFor)?.label}</h3>
              {fieldNames.length === 0 ? <p className="text-xs text-[var(--muted)]">This feature has no screens of its own; its parts below do.</p> :
              <p className="text-xs text-[var(--muted)] mb-2">Response fields {fieldNames.length - masked.length}/{fieldNames.length}</p>}
              <div className="flex gap-3 text-xs mb-2">
                <button className="text-[var(--brand)]" onClick={() => save(fieldsFor, { masked_fields: [] })}>all</button>
                <button className="text-[var(--brand)]" onClick={() => save(fieldsFor, { masked_fields: fieldNames })}>none</button>
              </div>
              <ul className="max-h-[60vh] overflow-auto space-y-1">
                {fieldNames.map((n) => {
                  const f = fields.find((x) => x.name === n);
                  const on = !masked.includes(n);
                  return (
                    <li key={n}>
                      <label className="flex items-center gap-2 text-sm">
                        <input type="checkbox" checked={on} onChange={() => save(fieldsFor, { masked_fields: on ? [...masked, n] : masked.filter((m) => m !== n) })} />
                        <span className={on ? "" : "line-through text-[var(--muted)]"}>{f.label}</span>
                        <span className="text-[10px] text-[var(--muted)] font-mono">{n}</span>
                      </label>
                    </li>
                  );
                })}
              </ul>
            </>
          )}
        </aside>
      </div>
    </div>
  );
}
