"use client";

import Link from "next/link";
import { usePathname } from "next/navigation";
import type { ReactNode } from "react";
import { BarChart3, Bot, CheckCircle2, Home, Settings, ShieldCheck, Wifi, WifiOff } from "lucide-react";
import { useApp } from "./AppProvider";
import { LANGS, type Lang } from "@/lib/i18n";
import { sb } from "@/lib/supabase";

export function AppShell({ children, title, actions }: { children: ReactNode; title?: string; actions?: ReactNode }) {
  const app = useApp();
  const path = usePathname();
  const admin = !!app.ctx?.user?.is_tenant_admin;
  const aiOn = app.catalog.length > 0; // assistant shows only when the AI switch is on (checked on its page)

  const nav = [
    { href: "/", label: app.t("home"), icon: Home },
    { href: "/approvals", label: app.t("approvals"), icon: CheckCircle2 },
    ...(admin || app.ctx?.ui_mode !== "simple" ? [{ href: "/dashboard", label: app.t("dashboard"), icon: BarChart3 }] : []),
    ...(app.ctx?.ui_mode !== "simple" ? [{ href: "/reports", label: app.t("reports"), icon: ShieldCheck }] : []),
    ...(aiOn ? [{ href: "/assistant", label: app.t("assistant"), icon: Bot }] : []),
    ...(admin ? [{ href: "/admin", label: app.t("admin"), icon: Settings }] : []),
  ];

  if (!app.ready) {
    return <div className="min-h-dvh grid place-items-center text-slate-500">Loading…</div>;
  }

  return (
    <div className="min-h-dvh md:grid md:grid-cols-[220px_1fr] bg-[var(--bg)]">
      <aside className="hidden md:flex flex-col gap-1 border-r border-[var(--line)] p-3 sticky top-0 h-dvh">
        <div className="px-2 py-3 font-semibold text-[var(--ink)] truncate">{app.ctx?.tenant?.name ?? "Group ERP"}</div>
        {nav.map((n) => (
          <Link key={n.href} href={n.href}
                className={`flex items-center gap-2 rounded-lg px-3 py-2 text-sm ${path === n.href ? "bg-[var(--brand-soft)] text-[var(--brand)] font-medium" : "text-[var(--muted)] hover:bg-[var(--soft)]"}`}>
            <n.icon size={18} /> {n.label}
          </Link>
        ))}
        <div className="mt-auto text-xs text-[var(--muted)] px-2">{app.ctx?.user?.name}</div>
        <button className="text-left text-xs px-2 py-1 text-[var(--muted)] hover:underline" onClick={() => sb().auth.signOut()}>
          {app.t("sign_out")}
        </button>
      </aside>

      <div className="flex flex-col min-w-0">
        <header className="sticky top-0 z-30 bg-[var(--bg)]/95 backdrop-blur border-b border-[var(--line)]">
          <div className="flex flex-wrap items-center gap-2 px-4 py-2">
            <ContextPicker />
            <div className="ml-auto flex items-center gap-2">
              <SyncDot />
              <select aria-label="Language" value={app.lang} onChange={(e) => app.setLang(e.target.value as Lang)}
                      className="rounded-lg border border-[var(--line)] bg-[var(--card)] px-2 py-1 text-sm">
                {Object.entries(LANGS).map(([k, v]) => <option key={k} value={k}>{v}</option>)}
              </select>
            </div>
          </div>
          {!app.online && (
            <div className="bg-amber-100 text-amber-900 dark:bg-amber-900/40 dark:text-amber-100 text-sm px-4 py-1.5">{app.t("offline")}</div>
          )}
        </header>

        {(title || actions) && (
          <div className="flex items-center gap-2 px-4 pt-4">
            {title && <h1 className="text-xl font-semibold text-[var(--ink)] truncate">{title}</h1>}
            <div className="ml-auto flex gap-2">{actions}</div>
          </div>
        )}
        <main className="flex-1 p-4 pb-24 md:pb-6 min-w-0">{children}</main>

        <nav className="md:hidden fixed bottom-0 inset-x-0 z-30 grid border-t border-[var(--line)] bg-[var(--card)]"
             style={{ gridTemplateColumns: `repeat(${Math.min(nav.length, 5)}, 1fr)` }}>
          {nav.slice(0, 5).map((n) => (
            <Link key={n.href} href={n.href}
                  className={`flex flex-col items-center gap-0.5 py-2 text-[11px] ${path === n.href ? "text-[var(--brand)]" : "text-[var(--muted)]"}`}>
              <n.icon size={22} /> {n.label}
            </Link>
          ))}
        </nav>
      </div>
    </div>
  );
}

function ContextPicker() {
  const app = useApp();
  if (!app.ctx) return null;
  const cos = app.ctx.companies;
  return (
    <div className="flex flex-wrap items-center gap-2 min-w-0">
      {cos.length > 1 ? (
        <select aria-label={app.t("company")} value={app.company?.id ?? ""} onChange={(e) => app.setCompany(e.target.value)}
                className="rounded-lg border border-[var(--line)] bg-[var(--card)] px-2 py-1.5 text-sm max-w-[48vw]">
          {cos.map((c) => <option key={c.id} value={c.id}>{c.name}</option>)}
        </select>
      ) : (
        <span className="text-sm font-medium">{app.company?.name}</span>
      )}
      {app.company && app.company.locations.length > 1 && (
        <select aria-label={app.t("location")} value={app.location?.id ?? ""} onChange={(e) => app.setLocation(e.target.value || null)}
                className="rounded-lg border border-[var(--line)] bg-[var(--card)] px-2 py-1.5 text-sm max-w-[40vw]">
          <option value="">All locations</option>
          {app.company.locations.map((l) => <option key={l.id} value={l.id}>{l.name}</option>)}
        </select>
      )}
      {app.company && app.company.locations.length === 1 && <span className="text-sm text-[var(--muted)]">· {app.location?.name}</span>}
    </div>
  );
}

function SyncDot() {
  const app = useApp();
  const color = !app.online ? "bg-amber-500" : app.failed ? "bg-red-500" : app.pending ? "bg-sky-500" : "bg-emerald-500";
  return (
    <Link href="/sync" className="flex items-center gap-1.5 text-xs text-[var(--muted)]" title="Sync status">
      {app.online ? <Wifi size={16} /> : <WifiOff size={16} />}
      <span className={`inline-block size-2.5 rounded-full ${color}`} />
      {(app.pending > 0 || app.failed > 0) && <span>{app.pending + app.failed} {app.t("waiting")}</span>}
    </Link>
  );
}
