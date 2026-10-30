"use client";

import Link from "next/link";
import { useEffect, useState } from "react";
import { AppShell } from "@/components/AppShell";
import { useApp } from "@/components/AppProvider";
import { actOnApproval, approvalCards } from "@/lib/erp";
import { dateTime, money } from "@/lib/format";

// The approver sees only what they need: what, how much, who asked, which step — and two big buttons.
export default function Approvals() {
  const app = useApp();
  const [cards, setCards] = useState<any[] | null>(null);
  const load = () => approvalCards().then(setCards).catch((e) => { setCards([]); app.toast(e.message, "error"); });
  // eslint-disable-next-line react-hooks/exhaustive-deps
  useEffect(() => { if (app.ctx) load(); }, [app.ctx]);

  const act = async (id: string, action: "approve" | "reject" | "send_back") => {
    let comment: string | undefined;
    if (action !== "approve") {
      comment = prompt(action === "reject" ? "Why reject?" : "What should be corrected?") ?? undefined;
      if (!comment) return;
    }
    try {
      await actOnApproval(id, action, comment);
      app.toast(action === "approve" ? "Approved" : action === "reject" ? "Rejected" : "Sent back");
      load();
    } catch (e: any) { app.toast(e.message, "error"); }
  };

  return (
    <AppShell title={app.t("approvals")}>
      {cards === null ? <p className="text-[var(--muted)]">…</p> : cards.length === 0 ? <p className="text-[var(--muted)]">Nothing waiting for you.</p> : (
        <ul className="grid gap-3 md:grid-cols-2">
          {cards.map((c) => (
            <li key={c.id} className="card p-4 space-y-3">
              <div className="flex items-start gap-2">
                <div className="min-w-0">
                  <Link href={`/m?e=${c.doc_type}&id=${c.doc_id}`} className="font-semibold text-[var(--brand)]">{c.title}</Link>
                  <div className="text-sm text-[var(--muted)]">{c.company}{c.location ? ` · ${c.location}` : ""} · {c.requested_by} · {dateTime(c.requested_at)}</div>
                </div>
                {c.amount != null && <div className="ml-auto text-xl font-semibold tabular-nums">{money(c.amount)}</div>}
              </div>
              <div className="text-xs text-[var(--muted)]">{c.rule} · step {c.step} of {c.steps}</div>
              <div className="grid grid-cols-3 gap-2">
                <button className="btn btn-primary col-span-2" onClick={() => act(c.id, "approve")}>{app.t("approve")}</button>
                <button className="btn" onClick={() => act(c.id, "reject")}>{app.t("reject")}</button>
              </div>
              <button className="text-sm text-[var(--muted)] hover:underline" onClick={() => act(c.id, "send_back")}>Send back for correction</button>
            </li>
          ))}
        </ul>
      )}
    </AppShell>
  );
}
