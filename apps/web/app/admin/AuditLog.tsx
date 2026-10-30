"use client";

import { useEffect, useState } from "react";
import { sb } from "@/lib/supabase";
import { useApp } from "@/components/AppProvider";
import { dateTime, humanize } from "@/lib/format";

// Who changed what: every insert, edit, delete, approval, print and AI action, newest first.
export function AuditLog() {
  const app = useApp();
  const [rows, setRows] = useState<any[]>([]);
  const [users, setUsers] = useState<any[]>([]);
  const [actor, setActor] = useState("");
  const [days, setDays] = useState(7);
  const [check, setCheck] = useState<string | null>(null);

  useEffect(() => { sb().from("app_user").select("id,full_name").eq("tenant_id", app.ctx!.tenant!.id).then(({ data }) => setUsers(data ?? [])); }, []); // eslint-disable-line
  useEffect(() => {
    sb().rpc("audit_search", { p_actor: actor || null, p_from: new Date(Date.now() - days * 864e5).toISOString() })
      .then(({ data, error }) => { if (error) app.toast(error.message, "error"); setRows(data ?? []); });
  }, [actor, days]); // eslint-disable-line

  const verify = async () => {
    const { data, error } = await sb().rpc("verify_audit_chain");
    if (error) setCheck(error.message);
    else setCheck(data.length === 0 ? "Intact: no record has been changed, removed or reordered." : `${data.length} problem(s): ${data.map((d: any) => `#${d.seq} ${d.problem}`).join("; ")}`);
  };

  return (
    <div className="space-y-3">
      <div className="flex flex-wrap gap-2 items-center">
        <select aria-label="Person" value={actor} onChange={(e) => setActor(e.target.value)} className="rounded-lg border border-[var(--line)] bg-[var(--card)] px-2 py-1.5 text-sm">
          <option value="">Everyone</option>{users.map((u) => <option key={u.id} value={u.id}>{u.full_name}</option>)}
        </select>
        <select aria-label="Period" value={days} onChange={(e) => setDays(Number(e.target.value))} className="rounded-lg border border-[var(--line)] bg-[var(--card)] px-2 py-1.5 text-sm">
          {[1, 7, 30, 90].map((d) => <option key={d} value={d}>Last {d} day{d > 1 ? "s" : ""}</option>)}
        </select>
        <button className="btn !min-h-0 !py-1.5 ml-auto" onClick={verify}>Check the log has not been tampered with</button>
      </div>
      {check && <p className="rounded-lg bg-[var(--soft)] p-2 text-sm">{check}</p>}
      <div className="card overflow-x-auto">
        <table className="w-full text-sm">
          <thead className="text-left text-[var(--muted)] border-b border-[var(--line)]">
            <tr><th className="px-3 py-2">When</th><th className="px-3 py-2">Who</th><th className="px-3 py-2">What</th><th className="px-3 py-2">Changed</th><th className="px-3 py-2">From</th><th className="px-3 py-2">Reason</th></tr>
          </thead>
          <tbody>
            {rows.map((r) => (
              <tr key={r.id} className="border-b border-[var(--line)] align-top">
                <td className="px-3 py-1.5 whitespace-nowrap">{dateTime(r.occurred_at)}</td>
                <td className="px-3 py-1.5">{r.actor_name ?? humanize(r.actor_type)}{r.actor_type === "ai_agent" && " (AI)"}</td>
                <td className="px-3 py-1.5">{r.action.toLowerCase()} {r.table_name.replace("public.", "").replace(/_/g, " ")}</td>
                <td className="px-3 py-1.5 text-xs">{(r.changed_fields ?? []).filter((f: string) => !["updated_at", "updated_by"].includes(f)).map((f: string) =>
                  <div key={f}>{humanize(f)}: {String(r.old_data?.[f] ?? "—")} → <b>{String(r.new_data?.[f] ?? "—")}</b></div>)}</td>
                <td className="px-3 py-1.5 text-xs">{r.source}{r.device_id ? ` · ${String(r.device_id).slice(0, 8)}` : ""}</td>
                <td className="px-3 py-1.5">{r.reason}</td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
    </div>
  );
}
