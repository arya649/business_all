"use client";

import { useEffect, useState } from "react";
import { sb } from "@/lib/supabase";
import { useApp } from "@/components/AppProvider";
import { dateTime } from "@/lib/format";

// Weighbridge scales, biometric machines and GPS units. Each gets a serial and a secret key, shown once,
// that goes into scripts/gateway on the site PC (or the GPS vendor's webhook).
export function Devices() {
  const app = useApp();
  const [rows, setRows] = useState<any[]>([]);
  const [form, setForm] = useState({ kind: "weighbridge", name: "", company: app.company?.id ?? "", location: "" });
  const [created, setCreated] = useState<any>(null);
  const load = () => sb().from("device").select("*").order("created_at").then(({ data }) => setRows(data ?? []));
  useEffect(() => { load(); }, []);
  const inp = "rounded-lg border border-[var(--line)] bg-[var(--card)] px-2 py-2 text-sm";
  return (
    <div className="space-y-4">
      <div className="card overflow-x-auto">
        <table className="w-full text-sm">
          <thead className="text-left text-[var(--muted)] border-b border-[var(--line)]"><tr><th className="px-3 py-2">Device</th><th className="px-3 py-2">Type</th><th className="px-3 py-2">Serial</th><th className="px-3 py-2">Last heard</th><th className="px-3 py-2">On</th></tr></thead>
          <tbody>{rows.map((d) => (
            <tr key={d.id} className="border-b border-[var(--line)]">
              <td className="px-3 py-2">{d.name}</td><td className="px-3 py-2">{d.kind}</td><td className="px-3 py-2 font-mono">{d.serial}</td>
              <td className="px-3 py-2">{d.last_seen_at ? dateTime(d.last_seen_at) : "never"}</td>
              <td className="px-3 py-2"><input type="checkbox" aria-label="Active" checked={d.is_active} onChange={async (e) => { await sb().from("device").update({ is_active: e.target.checked }).eq("id", d.id); load(); }} /></td>
            </tr>))}</tbody>
        </table>
      </div>
      <form className="card p-3 flex flex-wrap gap-2" onSubmit={async (e) => {
        e.preventDefault();
        const { data, error } = await sb().rpc("device_register", { p_company: form.company, p_location: form.location || null, p_kind: form.kind, p_name: form.name });
        if (error) app.toast(error.message, "error"); else { setCreated(data); load(); }
      }}>
        <h3 className="w-full font-semibold">Add a device</h3>
        <select aria-label="Type" value={form.kind} onChange={(e) => setForm({ ...form, kind: e.target.value })} className={inp}>
          <option value="weighbridge">Weighbridge scale</option><option value="biometric">Biometric machine</option><option value="gps">GPS / fuel sensor feed</option>
        </select>
        <input required placeholder="Name, e.g. Plant weighbridge" value={form.name} onChange={(e) => setForm({ ...form, name: e.target.value })} className={inp} />
        <select required aria-label="Company" value={form.company} onChange={(e) => setForm({ ...form, company: e.target.value, location: "" })} className={inp}>
          <option value="">Company…</option>{app.ctx!.companies.map((c) => <option key={c.id} value={c.id}>{c.name}</option>)}
        </select>
        <select aria-label="Location" value={form.location} onChange={(e) => setForm({ ...form, location: e.target.value })} className={inp}>
          <option value="">Location…</option>{app.ctx!.companies.find((c) => c.id === form.company)?.locations.map((l) => <option key={l.id} value={l.id}>{l.name}</option>)}
        </select>
        <button className="btn btn-primary">Add</button>
      </form>
      {created && (
        <div className="card p-4 border-amber-500 space-y-1">
          <b>Copy these now; the key is not shown again.</b>
          <div>Serial: <code>{created.serial}</code></div>
          <div>Key: <code className="break-all">{created.key}</code></div>
          <div className="text-sm text-[var(--muted)]">Put them in the site PC's gateway (scripts/gateway/README.md).</div>
        </div>
      )}
    </div>
  );
}
