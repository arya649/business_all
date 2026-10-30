"use client";

import { useEffect, useState } from "react";
import { sb } from "@/lib/supabase";
import { useApp } from "@/components/AppProvider";

export function Users() {
  const app = useApp();
  const tenant = app.ctx!.tenant!.id;
  const [users, setUsers] = useState<any[]>([]);
  const [roles, setRoles] = useState<any[]>([]);
  const [assignments, setAssignments] = useState<any[]>([]);
  const [form, setForm] = useState({ full_name: "", mobile: "", email: "" });
  const [assign, setAssign] = useState<{ user_id: string; company_id: string; location_id: string; role_id: string }>({ user_id: "", company_id: "", location_id: "", role_id: "" });

  const load = async () => {
    const [u, r, a] = await Promise.all([
      sb().from("app_user").select("*").eq("tenant_id", tenant).order("full_name"),
      sb().from("role").select("id,name").eq("tenant_id", tenant).order("name"),
      sb().from("user_assignment").select("*").eq("tenant_id", tenant),
    ]);
    setUsers(u.data ?? []); setRoles(r.data ?? []); setAssignments(a.data ?? []);
  };
  useEffect(() => { load(); }, []); // eslint-disable-line

  const coName = (id: string) => app.ctx!.companies.find((c) => c.id === id)?.name ?? "";
  const locName = (id: string | null) => (id ? app.ctx!.companies.flatMap((c) => c.locations).find((l) => l.id === id)?.name : "all locations");

  const invite = async (e: React.FormEvent) => {
    e.preventDefault();
    const { data: s } = await sb().auth.getSession();
    const r = await fetch("/api/admin/invite", { method: "POST", headers: { "content-type": "application/json", authorization: `Bearer ${s.session?.access_token}` },
                                                 body: JSON.stringify(form) });
    const j = await r.json();
    if (!r.ok) app.toast(j.error, "error"); else { app.toast(`${form.full_name} added. They can sign in with their mobile number.`); setForm({ full_name: "", mobile: "", email: "" }); load(); }
  };

  return (
    <div className="space-y-6">
      <form onSubmit={invite} className="card p-3 flex flex-wrap gap-2 items-end">
        <h3 className="w-full font-semibold">Add a person</h3>
        <input required placeholder="Name" value={form.full_name} onChange={(e) => setForm({ ...form, full_name: e.target.value })} className="rounded-lg border border-[var(--line)] bg-[var(--card)] px-2 py-2" />
        <input required placeholder="Mobile" inputMode="tel" value={form.mobile} onChange={(e) => setForm({ ...form, mobile: e.target.value })} className="rounded-lg border border-[var(--line)] bg-[var(--card)] px-2 py-2" />
        <input placeholder="Email (optional)" type="email" value={form.email} onChange={(e) => setForm({ ...form, email: e.target.value })} className="rounded-lg border border-[var(--line)] bg-[var(--card)] px-2 py-2" />
        <button className="btn btn-primary">Add</button>
      </form>

      <div className="card overflow-x-auto">
        <table className="w-full text-sm">
          <thead className="text-left text-[var(--muted)] border-b border-[var(--line)]"><tr><th className="px-3 py-2">Person</th><th className="px-3 py-2">Mobile</th><th className="px-3 py-2">Works as</th><th className="px-3 py-2">Active</th></tr></thead>
          <tbody>
            {users.map((u) => (
              <tr key={u.id} className="border-b border-[var(--line)] align-top">
                <td className="px-3 py-2 font-medium">{u.full_name}{u.is_tenant_admin && <span className="ml-1 text-xs text-[var(--brand)]">admin</span>}</td>
                <td className="px-3 py-2">{u.mobile}</td>
                <td className="px-3 py-2">
                  <ul className="space-y-0.5">
                    {assignments.filter((a) => a.user_id === u.id).map((a) => (
                      <li key={a.id} className="flex gap-2">
                        <span>{roles.find((r) => r.id === a.role_id)?.name} · {coName(a.company_id)} · {locName(a.location_id)}</span>
                        <button className="text-red-600 text-xs" onClick={async () => { await sb().from("user_assignment").delete().eq("id", a.id); load(); }}>remove</button>
                      </li>
                    ))}
                  </ul>
                </td>
                <td className="px-3 py-2">
                  <input type="checkbox" aria-label="Active" checked={u.is_active} onChange={async (e) => { await sb().from("app_user").update({ is_active: e.target.checked }).eq("id", u.id); load(); }} />
                </td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>

      <form className="card p-3 flex flex-wrap gap-2 items-end" onSubmit={async (e) => {
        e.preventDefault();
        const { error } = await sb().from("user_assignment").insert({ tenant_id: tenant, ...assign, location_id: assign.location_id || null });
        if (error) app.toast(error.message, "error"); else load();
      }}>
        <h3 className="w-full font-semibold">Give someone a role</h3>
        <select required aria-label="Person" value={assign.user_id} onChange={(e) => setAssign({ ...assign, user_id: e.target.value })} className="rounded-lg border border-[var(--line)] bg-[var(--card)] px-2 py-2">
          <option value="">Person…</option>{users.map((u) => <option key={u.id} value={u.id}>{u.full_name}</option>)}
        </select>
        <select required aria-label="Role" value={assign.role_id} onChange={(e) => setAssign({ ...assign, role_id: e.target.value })} className="rounded-lg border border-[var(--line)] bg-[var(--card)] px-2 py-2">
          <option value="">Role…</option>{roles.map((r) => <option key={r.id} value={r.id}>{r.name}</option>)}
        </select>
        <select required aria-label="Company" value={assign.company_id} onChange={(e) => setAssign({ ...assign, company_id: e.target.value, location_id: "" })} className="rounded-lg border border-[var(--line)] bg-[var(--card)] px-2 py-2">
          <option value="">Company…</option>{app.ctx!.companies.map((c) => <option key={c.id} value={c.id}>{c.name}</option>)}
        </select>
        <select aria-label="Location" value={assign.location_id} onChange={(e) => setAssign({ ...assign, location_id: e.target.value })} className="rounded-lg border border-[var(--line)] bg-[var(--card)] px-2 py-2">
          <option value="">All locations</option>
          {app.ctx!.companies.find((c) => c.id === assign.company_id)?.locations.map((l) => <option key={l.id} value={l.id}>{l.name}</option>)}
        </select>
        <button className="btn btn-primary">Assign</button>
      </form>
    </div>
  );
}
