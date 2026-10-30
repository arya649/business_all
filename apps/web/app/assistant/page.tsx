"use client";

import { useState } from "react";
import { Send } from "lucide-react";
import { AppShell } from "@/components/AppShell";
import { useApp } from "@/components/AppProvider";
import { saveRecord } from "@/lib/erp";
import { sb } from "@/lib/supabase";

const AGENTS = [
  ["owner_assistant", "Owner: ask about any business"], ["site_assistant", "Site engineer"], ["plant_assistant", "Plant"],
  ["bunk_assistant", "Petrol bunk"], ["fleet_assistant", "Fleet & diesel"], ["accounts_assistant", "Accounts"], ["admin_assistant", "Admin setup"],
] as const;

// Chat with an assistant. It reads data as you, and when it wants to make an entry it shows a card that
// you confirm; nothing is saved without your tap.
export default function Assistant() {
  const app = useApp();
  const [agent, setAgent] = useState<string>(app.ctx?.user?.is_tenant_admin ? "owner_assistant" : "site_assistant");
  const [messages, setMessages] = useState<any[]>([]);
  const [shown, setShown] = useState<{ role: string; text: string; proposal?: any }[]>([]);
  const [input, setInput] = useState("");
  const [busy, setBusy] = useState(false);

  const send = async () => {
    if (!input.trim()) return;
    const q = input;
    setInput("");
    setShown((s) => [...s, { role: "user", text: q }]);
    setBusy(true);
    try {
      const { data: s } = await sb().auth.getSession();
      const r = await fetch("/api/ai/agent", { method: "POST", headers: { "content-type": "application/json", authorization: `Bearer ${s.session?.access_token}` },
        body: JSON.stringify({ agent, input: q, messages, company_id: app.company?.id, location_id: app.location?.id }) });
      const j = await r.json();
      if (!r.ok) throw new Error(j.error ?? j.reason ?? "The assistant is not available");
      setMessages(j.messages ?? []);
      setShown((s) => [...s, { role: "assistant", text: j.output ?? j.reply ?? "", proposal: j.proposal }]);
    } catch (e: any) {
      setShown((s) => [...s, { role: "assistant", text: e.message }]);
    } finally { setBusy(false); }
  };

  const confirm = async (p: any) => {
    const ent = app.entity(p.entity);
    if (!ent) { app.toast(app.t("not_enabled"), "error"); return; }
    try {
      const { queued } = await saveRecord(ent, { ...p.data, company_id: app.company?.id, location_id: app.location?.id });
      app.toast(queued ? app.t("saved_offline") : app.t("saved"));
    } catch (e: any) { app.toast(e.message, "error"); }
  };

  return (
    <AppShell title={app.t("assistant")}>
      <div className="max-w-2xl flex flex-col gap-3">
        <select aria-label="Assistant" value={agent} onChange={(e) => { setAgent(e.target.value); setMessages([]); setShown([]); }}
                className="rounded-xl border border-[var(--line)] bg-[var(--card)] px-3 py-2">
          {AGENTS.map(([k, l]) => <option key={k} value={k}>{l}</option>)}
        </select>
        <ul className="space-y-2">
          {shown.map((m, i) => (
            <li key={i} className={`rounded-2xl px-4 py-3 max-w-[85%] whitespace-pre-wrap ${m.role === "user" ? "ml-auto bg-[var(--brand)] text-white" : "card"}`}>
              {m.text}
              {m.proposal && (
                <div className="mt-2 rounded-xl bg-[var(--soft)] p-3 text-sm text-[var(--ink)]">
                  <div className="font-medium">{app.entity(m.proposal.entity)?.label ?? m.proposal.entity}</div>
                  <pre className="text-xs overflow-auto">{JSON.stringify(m.proposal.data, null, 1)}</pre>
                  <button className="btn btn-primary mt-2" onClick={() => confirm(m.proposal)}>{app.t("save")}</button>
                </div>
              )}
            </li>
          ))}
        </ul>
        <form onSubmit={(e) => { e.preventDefault(); send(); }} className="flex gap-2 sticky bottom-16 md:bottom-2">
          <input value={input} onChange={(e) => setInput(e.target.value)} disabled={busy}
                 placeholder="e.g. Why is tank 2 short this week?" className="flex-1 rounded-xl border border-[var(--line)] bg-[var(--card)] px-3 py-3" />
          <button className="btn btn-primary" disabled={busy} aria-label="Send"><Send size={18} /></button>
        </form>
      </div>
    </AppShell>
  );
}
