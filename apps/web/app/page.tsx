"use client";

import Link from "next/link";
import { useEffect, useState } from "react";
import { AppShell } from "@/components/AppShell";
import { useApp } from "@/components/AppProvider";
import { Icon } from "@/components/Icon";
import { approvalCards } from "@/lib/erp";
import { SpeakButton } from "@/components/Guided";

const MODULES: Record<string, string> = {
  bunk: "Petrol bunk", rmc: "RMC plant", weighbridge: "Weighbridge", bitumen: "Hot-mix plant", bricks: "Bricks", infra: "Projects",
  fleet: "Fleet & machines", purchase: "Purchase & stores", hr: "HR & payroll", crm: "Sales & leads", finance: "Accounts",
};

// Each business has its own colour so people find their tiles without reading.
const TILE_COLORS: Record<string, string> = {
  bunk: "bg-orange-100 text-orange-700 dark:bg-orange-900/40 dark:text-orange-200",
  rmc: "bg-slate-200 text-slate-800 dark:bg-slate-700 dark:text-slate-100",
  weighbridge: "bg-violet-100 text-violet-700 dark:bg-violet-900/40 dark:text-violet-200",
  bitumen: "bg-stone-300 text-stone-900 dark:bg-stone-700 dark:text-stone-100",
  bricks: "bg-red-100 text-red-700 dark:bg-red-900/40 dark:text-red-200",
  infra: "bg-amber-100 text-amber-800 dark:bg-amber-900/40 dark:text-amber-100",
  fleet: "bg-sky-100 text-sky-700 dark:bg-sky-900/40 dark:text-sky-200",
  purchase: "bg-lime-100 text-lime-800 dark:bg-lime-900/40 dark:text-lime-100",
  hr: "bg-pink-100 text-pink-700 dark:bg-pink-900/40 dark:text-pink-200",
  crm: "bg-indigo-100 text-indigo-700 dark:bg-indigo-900/40 dark:text-indigo-200",
  finance: "bg-emerald-100 text-emerald-700 dark:bg-emerald-900/40 dark:text-emerald-200",
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
              <div key={e.key} className="relative">
                <Link href={`/m?e=${e.key}&id=new`}
                      className="card flex flex-col items-start gap-3 p-4 hover:border-[var(--brand)] min-h-32">
                  <span className={`rounded-2xl p-3 ${TILE_COLORS[e.module] ?? "bg-[var(--brand-soft)] text-[var(--brand)]"}`}><Icon name={e.icon} size={32} /></span>
                  <span className="text-lg font-semibold leading-tight pr-8">{e.label}</span>
                </Link>
                <SpeakButton text={e.label} className="absolute top-3 right-3" />
              </div>
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
