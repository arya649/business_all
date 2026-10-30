"use client";

import { useEffect, useState } from "react";
import { Plus, Trash2 } from "lucide-react";
import { sb } from "@/lib/supabase";
import { useApp } from "@/components/AppProvider";

interface Cond { field: string; op: string; value: string }
interface Step { approver_type: string; approver_role_id: string; approver_user_id: string; mode: string; sla_hours: string }

export function ApprovalRules() {
  const app = useApp();
  const tenant = app.ctx!.tenant!.id;
  const [rules, setRules] = useState<any[]>([]);
  const [steps, setSteps] = useState<any[]>([]);
  const [entities, setEntities] = useState<any[]>([]);
  const [roles, setRoles] = useState<any[]>([]);
  const [users, setUsers] = useState<any[]>([]);
  const [draft, setDraft] = useState({ name: "", doc_type: "", company_id: "" });
  const [conds, setConds] = useState<Cond[]>([{ field: "amount", op: ">", value: "50000" }]);
  const [newSteps, setNewSteps] = useState<Step[]>([{ approver_type: "tenant_admin", approver_role_id: "", approver_user_id: "", mode: "any", sla_hours: "24" }]);

  const load = async () => {
    const [r, s, e, ro, u] = await Promise.all([
      sb().from("approval_rule").select("*").eq("tenant_id", tenant).order("doc_type"),
      sb().from("approval_rule_step").select("*").eq("tenant_id", tenant).order("step_no"),
      sb().from("erp_entity").select("key,label,workflow").eq("workflow", true).order("sort"),
      sb().from("role").select("id,name").eq("tenant_id", tenant),
      sb().from("app_user").select("id,full_name").eq("tenant_id", tenant),
    ]);
    setRules(r.data ?? []); setSteps(s.data ?? []); setEntities(e.data ?? []); setRoles(ro.data ?? []); setUsers(u.data ?? []);
  };
  useEffect(() => { load(); }, []); // eslint-disable-line

  const create = async (ev: React.FormEvent) => {
    ev.preventDefault();
    const conditions = conds.filter((c) => c.field).map((c) => ({
      field: c.field, op: c.op,
      value: c.op === "in" || c.op === "not_in" ? c.value.split(",").map((x) => x.trim()) : isNaN(Number(c.value)) ? c.value : Number(c.value),
    }));
    const { data, error } = await sb().from("approval_rule").insert({ tenant_id: tenant, name: draft.name, doc_type: draft.doc_type,
      company_id: draft.company_id || null, conditions }).select().single();
    if (error) { app.toast(error.message, "error"); return; }
    const { error: e2 } = await sb().from("approval_rule_step").insert(newSteps.map((s, i) => ({
      tenant_id: tenant, rule_id: data.id, step_no: i + 1, approver_type: s.approver_type,
      approver_role_id: s.approver_type === "role" ? s.approver_role_id : null,
      approver_user_id: s.approver_type === "user" ? s.approver_user_id : null, mode: s.mode, sla_hours: Number(s.sla_hours) || null })));
    if (e2) app.toast(e2.message, "error"); else { app.toast("Rule added"); load(); }
  };

  const describe = (s: any) => s.approver_type === "role" ? roles.find((r) => r.id === s.approver_role_id)?.name
    : s.approver_type === "user" ? users.find((u) => u.id === s.approver_user_id)?.full_name
    : s.approver_type === "location_head" ? "Location in-charge" : "Owner / admin";
  const sel = "rounded-lg border border-[var(--line)] bg-[var(--card)] px-2 py-1.5 text-sm";

  return (
    <div className="space-y-6">
      <ul className="space-y-2">
        {rules.map((r) => (
          <li key={r.id} className="card p-3">
            <div className="flex gap-2 items-center">
              <b>{r.name}</b><span className="text-sm text-[var(--muted)]">{entities.find((e) => e.key === r.doc_type)?.label ?? r.doc_type}</span>
              <label className="ml-auto text-sm flex items-center gap-1"><input type="checkbox" checked={r.is_active}
                onChange={async (e) => { await sb().from("approval_rule").update({ is_active: e.target.checked }).eq("id", r.id); load(); }} /> active</label>
            </div>
            <div className="text-sm mt-1">When {r.conditions.length ? r.conditions.map((c: any) => `${c.field} ${c.op} ${JSON.stringify(c.value)}`).join(" and ") : "always"}:
              {" "}{steps.filter((s) => s.rule_id === r.id).map((s) => `${s.step_no}. ${describe(s)}${s.sla_hours ? ` (${s.sla_hours} h)` : ""}`).join(" → ")}</div>
          </li>
        ))}
      </ul>

      <form onSubmit={create} className="card p-4 space-y-3">
        <h3 className="font-semibold">New approval rule</h3>
        <div className="flex flex-wrap gap-2">
          <input required placeholder="Rule name, e.g. Big POs" value={draft.name} onChange={(e) => setDraft({ ...draft, name: e.target.value })} className={sel} />
          <select required aria-label="Document" value={draft.doc_type} onChange={(e) => setDraft({ ...draft, doc_type: e.target.value })} className={sel}>
            <option value="">For…</option>{entities.map((e) => <option key={e.key} value={e.key}>{e.label}</option>)}
          </select>
          <select aria-label="Company" value={draft.company_id} onChange={(e) => setDraft({ ...draft, company_id: e.target.value })} className={sel}>
            <option value="">Every company</option>{app.ctx!.companies.map((c) => <option key={c.id} value={c.id}>{c.name}</option>)}
          </select>
        </div>
        <div className="space-y-2">
          <div className="text-sm font-medium">When</div>
          {conds.map((c, i) => (
            <div key={i} className="flex gap-2">
              <input aria-label="Field" value={c.field} onChange={(e) => setConds(conds.map((x, j) => j === i ? { ...x, field: e.target.value } : x))} className={sel} placeholder="amount" />
              <select aria-label="Operator" value={c.op} onChange={(e) => setConds(conds.map((x, j) => j === i ? { ...x, op: e.target.value } : x))} className={sel}>
                {[">", ">=", "<", "<=", "=", "!=", "in", "not_in"].map((o) => <option key={o}>{o}</option>)}
              </select>
              <input aria-label="Value" value={c.value} onChange={(e) => setConds(conds.map((x, j) => j === i ? { ...x, value: e.target.value } : x))} className={sel} />
              <button type="button" aria-label="Remove" onClick={() => setConds(conds.filter((_, j) => j !== i))}><Trash2 size={16} /></button>
            </div>
          ))}
          <button type="button" className="text-sm text-[var(--brand)] flex items-center gap-1" onClick={() => setConds([...conds, { field: "", op: "=", value: "" }])}><Plus size={14} /> condition</button>
        </div>
        <div className="space-y-2">
          <div className="text-sm font-medium">Then ask, in order</div>
          {newSteps.map((s, i) => (
            <div key={i} className="flex flex-wrap gap-2 items-center">
              <span className="text-sm">{i + 1}.</span>
              <select aria-label="Approver" value={s.approver_type} onChange={(e) => setNewSteps(newSteps.map((x, j) => j === i ? { ...x, approver_type: e.target.value } : x))} className={sel}>
                <option value="tenant_admin">Owner / admin</option><option value="role">Anyone with role</option><option value="user">A person</option><option value="location_head">Location in-charge</option>
              </select>
              {s.approver_type === "role" && <select aria-label="Role" value={s.approver_role_id} onChange={(e) => setNewSteps(newSteps.map((x, j) => j === i ? { ...x, approver_role_id: e.target.value } : x))} className={sel}>
                <option value="">Role…</option>{roles.map((r) => <option key={r.id} value={r.id}>{r.name}</option>)}</select>}
              {s.approver_type === "user" && <select aria-label="Person" value={s.approver_user_id} onChange={(e) => setNewSteps(newSteps.map((x, j) => j === i ? { ...x, approver_user_id: e.target.value } : x))} className={sel}>
                <option value="">Person…</option>{users.map((u) => <option key={u.id} value={u.id}>{u.full_name}</option>)}</select>}
              <input aria-label="Hours to act" value={s.sla_hours} onChange={(e) => setNewSteps(newSteps.map((x, j) => j === i ? { ...x, sla_hours: e.target.value } : x))} className={`${sel} w-20`} />
              <span className="text-xs text-[var(--muted)]">hours</span>
            </div>
          ))}
          <button type="button" className="text-sm text-[var(--brand)] flex items-center gap-1" onClick={() => setNewSteps([...newSteps, { approver_type: "tenant_admin", approver_role_id: "", approver_user_id: "", mode: "any", sla_hours: "24" }])}><Plus size={14} /> step</button>
        </div>
        <button className="btn btn-primary">Save rule</button>
      </form>
    </div>
  );
}
