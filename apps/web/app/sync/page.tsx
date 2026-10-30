"use client";

import { useEffect, useState } from "react";
import { AppShell } from "@/components/AppShell";
import { useApp } from "@/components/AppProvider";
import { dropOutboxItem, flushOutbox, onOutboxChange, outbox, retryOutboxItem, type OutboxItem } from "@/lib/offline";
import { dateTime } from "@/lib/format";

// Entries saved on this phone and not yet sent. Rejected ones show the reason so they can be fixed.
export default function Sync() {
  const app = useApp();
  const [items, setItems] = useState<OutboxItem[]>([]);
  useEffect(() => { const r = () => outbox().then(setItems); r(); return onOutboxChange(r); }, []);
  return (
    <AppShell title="Saved on this phone"
              actions={<button className="btn" disabled={!app.online} onClick={() => flushOutbox()}>Send now</button>}>
      {items.length === 0 ? <p className="text-[var(--muted)]">Everything is sent.</p> : (
        <ul className="space-y-2">
          {items.map((i) => (
            <li key={i.key} className="card p-3">
              <div className="flex gap-2"><b>{i.label}</b><span className="ml-auto text-sm text-[var(--muted)]">{dateTime(i.queued_at)}</span></div>
              {i.error ? (
                <div className="mt-2 space-y-2">
                  <p className="text-sm text-red-600">{i.error}</p>
                  <div className="flex gap-2">
                    <button className="btn" onClick={() => retryOutboxItem(i.key)}>Try again</button>
                    <button className="btn" onClick={() => confirm("Delete this entry from the phone?") && dropOutboxItem(i.key)}>Delete</button>
                  </div>
                </div>
              ) : <p className="text-sm text-[var(--muted)]">{app.t("waiting")}</p>}
            </li>
          ))}
        </ul>
      )}
    </AppShell>
  );
}
