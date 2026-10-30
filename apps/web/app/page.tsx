"use client";

import Link from "next/link";
import { useEffect, useState } from "react";
import { AppShell } from "@/components/AppShell";
import { useApp } from "@/components/AppProvider";
import { Icon } from "@/components/Icon";
import { approvalCards } from "@/lib/erp";

const MODULES: Record<string, string> = {
  bunk: "Petrol bunk", rmc: "RMC plant", weighbridge: "Weighbridge", bitumen: "Hot-mix plant", bricks: "Bricks", infra: "Projects",
  fleet: "Fleet & machines", purchase: "Purchase & stores", hr: "HR & payroll", crm: "Sales & leads", finance: "Accounts",
};

// Home is today's work as big tiles, not menus. Field users see only the entries they make;
// office users also see every register grouped by business.
export default function Home() {
  const app = useApp();
  const [approvals, setApprovals] = useState(0);
  useEffect(() => { if (app.ctx) approvalCards().then((a) => setApprovals(a.length)).catch(() => {}); }, [app.ctx]);

  const quick = app.catalog.filter((e) => e.mobile && e.can.create && !e.read_only);
  const byModule = new Map<string, typeof app.catalog>();
  for (const e of app.catalog) byModule.set(e.module, [...(byModule.get(e.module) ?? []), e]);

  return (
    <AppShell>
      {approvals > 0 && (
        <Link href="/approvals" className="mb-4 flex items-center justify-between rounded-2xl bg-amber-100 dark:bg-amber-900/40 px-4 py-3">
          <span className="font-medium">{approvals} waiting for your approval</span><span aria-hidden>→</span>
        </Link>
      )}
      {app.catalog.length === 0 && <p className="text-[var(--muted)]">{app.t("not_enabled")}</p>}

      {quick.length > 0 && (
        <section className="mb-6">
          <h2 className="text-sm font-semibold text-[var(--muted)] mb-2">{app.t("today_jobs")}</h2>
          <div className="grid grid-cols-2 sm:grid-cols-3 lg:grid-cols-4 gap-3">
            {quick.map((e) => (
              <Link key={e.key} href={`/m?e=${e.key}&id=new`}
                    className="card flex flex-col items-start gap-3 p-4 hover:border-[var(--brand)] min-h-28">
                <span className="rounded-xl bg-[var(--brand-soft)] text-[var(--brand)] p-2.5"><Icon name={e.icon} /></span>
                <span className="font-medium leading-tight">{e.label}</span>
              </Link>
            ))}
          </div>
        </section>
      )}

      {app.ctx?.ui_mode !== "simple" || quick.length === 0 ? (
        <div className="grid gap-4 sm:grid-cols-2 xl:grid-cols-3">
          {[...byModule.entries()].map(([m, list]) => (
            <section key={m} className="card p-4">
              <h2 className="font-semibold mb-2">{MODULES[m] ?? m}</h2>
              <ul className="space-y-1">
                {list.map((e) => (
                  <li key={e.key}>
                    <Link href={`/m?e=${e.key}`} className="flex items-center gap-2 rounded-lg px-2 py-1.5 hover:bg-[var(--soft)]">
                      <Icon name={e.icon} size={16} /> {e.label_plural}
                      {e.read_only && <span className="ml-auto text-xs text-[var(--muted)]">view only</span>}
                    </Link>
                  </li>
                ))}
              </ul>
            </section>
          ))}
        </div>
      ) : (
        <details className="card p-4">
          <summary className="cursor-pointer font-medium">{app.t("more")}</summary>
          <ul className="mt-2 space-y-1">
            {app.catalog.map((e) => <li key={e.key}><Link className="block py-1.5" href={`/m?e=${e.key}`}>{e.label_plural}</Link></li>)}
          </ul>
        </details>
      )}
    </AppShell>
  );
}
