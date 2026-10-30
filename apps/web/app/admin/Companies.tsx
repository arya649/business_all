"use client";

import { useEffect, useState } from "react";
import { sb } from "@/lib/supabase";
import { useApp } from "@/components/AppProvider";

const TYPES = ["branch", "office", "plant", "site", "bunk", "weighbridge", "yard", "warehouse"];

export function Companies() {
  const app = useApp();
  const tenant = app.ctx!.tenant!.id;
  const [cos, setCos] = useState<any[]>([]);
  const [locs, setLocs] = useState<any[]>([]);
  const [gstins, setGstins] = useState<any[]>([]);
  const [co, setCo] = useState({ legal_name: "", short_code: "", pan: "" });
  const [loc, setLoc] = useState({ company_id: "", name: "", short_code: "", type: "plant", gstin_id: "" });
  const [gst, setGst] = useState({ company_id: "", gstin: "" });
  const [locks, setLocks] = useState<any[]>([]);

  const load = async () => {
    const [c, l, g] = await Promise.all([
      sb().from("company").select("*").eq("tenant_id", tenant).order("legal_name"),
      sb().from("location").select("*").eq("tenant_id", tenant).order("name"),
      sb().from("company_gstin").select("*").eq("tenant_id", tenant),
    ]);
    setCos(c.data ?? []); setLocs(l.data ?? []); setGstins(g.data ?? []);
    setLocks((await sb().from("period_lock").select("*").eq("tenant_id", tenant)).data ?? []);
  };
  useEffect(() => { load(); }, []); // eslint-disable-line
  const done = async (p: PromiseLike<{ error: any }>) => { const { error } = await p; if (error) app.toast(error.message, "error"); else { await load(); await app.reload(); } };
  const inp = "rounded-lg border border-[var(--line)] bg-[var(--card)] px-2 py-2 text-sm";

  return (
    <div className="space-y-6">
      {cos.map((c) => (
        <section key={c.id} className="card p-4">
          <h3 className="font-semibold">{c.legal_name} <span className="text-sm text-[var(--muted)]">{c.short_code}{c.pan ? ` · PAN ${c.pan}` : ""}</span></h3>
          <div className="text-sm text-[var(--muted)]">GSTIN: {gstins.filter((g) => g.company_id === c.id).map((g) => g.gstin).join(", ") || "none"}</div>
          <label className="mt-2 flex flex-wrap items-center gap-2 text-sm">
            Entries locked up to (after GST filing):
            <input type="date" aria-label="Locked up to" defaultValue={locks.find((x) => x.company_id === c.id)?.locked_upto ?? ""}
                   className="rounded-lg border border-[var(--line)] bg-[var(--card)] px-2 py-1"
                   onChange={(e) => done(e.target.value
                     ? sb().from("period_lock").upsert({ company_id: c.id, tenant_id: tenant, locked_upto: e.target.value, reason: "GST filed" })
                     : sb().from("period_lock").delete().eq("company_id", c.id))} />
          </label>
          <ul className="mt-2 text-sm grid sm:grid-cols-2 gap-1">
            {locs.filter((l) => l.company_id === c.id).map((l) => <li key={l.id}>• {l.name} <span className="text-[var(--muted)]">({l.type}, {l.short_code})</span></li>)}
          </ul>
        </section>
      ))}
      <form className="card p-3 flex flex-wrap gap-2" onSubmit={(e) => { e.preventDefault(); done(sb().from("company").insert({ tenant_id: tenant, ...co, pan: co.pan || null })); }}>
        <h3 className="w-full font-semibold">Add company</h3>
        <input required placeholder="Legal name" value={co.legal_name} onChange={(e) => setCo({ ...co, legal_name: e.target.value })} className={inp} />
        <input required placeholder="Short code (e.g. SRMC)" value={co.short_code} onChange={(e) => setCo({ ...co, short_code: e.target.value.toUpperCase() })} className={inp} />
        <input placeholder="PAN" value={co.pan} onChange={(e) => setCo({ ...co, pan: e.target.value.toUpperCase() })} className={inp} />
        <button className="btn btn-primary">Add</button>
      </form>
      <form className="card p-3 flex flex-wrap gap-2" onSubmit={(e) => { e.preventDefault(); done(sb().from("company_gstin").insert({ tenant_id: tenant, ...gst })); }}>
        <h3 className="w-full font-semibold">Add GSTIN</h3>
        <select required aria-label="Company" value={gst.company_id} onChange={(e) => setGst({ ...gst, company_id: e.target.value })} className={inp}>
          <option value="">Company…</option>{cos.map((c) => <option key={c.id} value={c.id}>{c.legal_name}</option>)}
        </select>
        <input required placeholder="GSTIN" value={gst.gstin} onChange={(e) => setGst({ ...gst, gstin: e.target.value.toUpperCase() })} className={inp} />
        <button className="btn btn-primary">Add</button>
      </form>
      <form className="card p-3 flex flex-wrap gap-2" onSubmit={(e) => { e.preventDefault(); done(sb().from("location").insert({ tenant_id: tenant, ...loc, gstin_id: loc.gstin_id || null })); }}>
        <h3 className="w-full font-semibold">Add plant / site / bunk</h3>
        <select required aria-label="Company" value={loc.company_id} onChange={(e) => setLoc({ ...loc, company_id: e.target.value })} className={inp}>
          <option value="">Company…</option>{cos.map((c) => <option key={c.id} value={c.id}>{c.legal_name}</option>)}
        </select>
        <select aria-label="Type" value={loc.type} onChange={(e) => setLoc({ ...loc, type: e.target.value })} className={inp}>{TYPES.map((t) => <option key={t}>{t}</option>)}</select>
        <input required placeholder="Name" value={loc.name} onChange={(e) => setLoc({ ...loc, name: e.target.value })} className={inp} />
        <input required placeholder="Code (used in numbers)" value={loc.short_code} onChange={(e) => setLoc({ ...loc, short_code: e.target.value.toUpperCase() })} className={inp} />
        <select aria-label="GSTIN" value={loc.gstin_id} onChange={(e) => setLoc({ ...loc, gstin_id: e.target.value })} className={inp}>
          <option value="">GSTIN…</option>{gstins.filter((g) => g.company_id === loc.company_id).map((g) => <option key={g.id} value={g.id}>{g.gstin}</option>)}
        </select>
        <button className="btn btn-primary">Add</button>
      </form>
    </div>
  );
}
