"use client";

import { createContext, useCallback, useContext, useEffect, useMemo, useState, type ReactNode } from "react";
import { usePathname, useRouter } from "next/navigation";
import { sb } from "@/lib/supabase";
import { getCatalog, getContext, lookup } from "@/lib/erp";
import { flushOutbox, onOutboxChange, outbox, reserveBlocks } from "@/lib/offline";
import { t as tr, type Lang } from "@/lib/i18n";
import { label as trLabel } from "@/lib/labels";
import type { AppContext, Company, Entity, Location } from "@/lib/types";

interface AppState {
  ready: boolean;
  ctx: AppContext | null;
  company: Company | null;
  location: Location | null;
  catalog: Entity[];
  lang: Lang;
  online: boolean;
  pending: number;
  failed: number;
  setCompany: (id: string) => void;
  setLocation: (id: string | null) => void;
  setLang: (l: Lang) => void;
  t: (k: string) => string;
  entity: (key: string) => Entity | undefined;
  reload: () => Promise<void>;
  toast: (msg: string, kind?: "ok" | "error") => void;
}

const Ctx = createContext<AppState | null>(null);
export const useApp = () => useContext(Ctx)!;

const PUBLIC = ["/login"];

export function AppProvider({ children }: { children: ReactNode }) {
  const router = useRouter();
  const path = usePathname();
  const [ready, setReady] = useState(false);
  const [ctx, setCtx] = useState<AppContext | null>(null);
  const [companyId, setCompanyId] = useState<string | null>(null);
  const [locationId, setLocationId] = useState<string | null>(null);
  const [rawCatalog, setCatalog] = useState<Entity[]>([]);
  const [lang, setLangState] = useState<Lang>("en");
  const [online, setOnline] = useState(true);
  const [pending, setPending] = useState(0);
  const [failed, setFailed] = useState(0);
  const [toastMsg, setToast] = useState<{ msg: string; kind: "ok" | "error" } | null>(null);

  const load = useCallback(async () => {
    const { data } = await sb().auth.getSession();
    if (!data.session) {
      setReady(true);
      if (!PUBLIC.includes(path)) router.replace("/login");
      return;
    }
    try {
      const c = await getContext();
      setCtx(c);
      const savedCo = localStorage.getItem("erp.company");
      const co = c.companies.find((x) => x.id === savedCo) ?? c.companies[0] ?? null;
      setCompanyId(co?.id ?? null);
      const savedLoc = localStorage.getItem("erp.location");
      const loc = co?.locations.find((l) => l.id === savedLoc) ?? (co && co.locations.length === 1 ? co.locations[0] : null);
      setLocationId(loc?.id ?? null);
      setLangState(((localStorage.getItem("erp.lang") as Lang) || (c.user?.language as Lang) || "en"));
    } catch (e) {
      console.error(e);
    }
    setReady(true);
  }, [path, router]);

  useEffect(() => {
    load();
    const { data: sub } = sb().auth.onAuthStateChange((ev) => {
      if (ev === "SIGNED_OUT") router.replace("/login");
      if (ev === "SIGNED_IN") load();
    });
    return () => sub.subscription.unsubscribe();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  // screen and field names in the person's language
  const catalog = useMemo(() => rawCatalog.map((e) => ({
    ...e, label: trLabel(e.label, lang), label_plural: trLabel(e.label_plural, lang),
    fields: e.fields.map((f) => ({ ...f, label: trLabel(f.label, lang) })),
    children: e.children.map((c) => ({ ...c, label: trLabel(c.label, lang), fields: c.fields.map((f) => ({ ...f, label: trLabel(f.label, lang) })) })),
  })), [rawCatalog, lang]);

  const company = useMemo(() => ctx?.companies.find((c) => c.id === companyId) ?? null, [ctx, companyId]);
  const location = useMemo(() => company?.locations.find((l) => l.id === locationId) ?? null, [company, locationId]);

  useEffect(() => {
    if (!company) return;
    getCatalog(company.id, location?.id ?? null)
      .then((cat) => {
        setCatalog(cat);
        // reserve document numbers for offline use on this phone
        if (location) reserveBlocks(company.id, location.id, cat.filter((e) => e.mobile && e.numbering && e.can.create).map((e) => e.key)).catch(() => {});
        // keep the pick-lists field screens need on the phone, so entries can be made with no signal
        if (navigator.onLine) {
          const refs = new Set<string>();
          for (const e of cat.filter((x) => x.mobile && x.can.create)) {
            for (const f of [...e.fields, ...e.children.flatMap((c) => c.fields)]) if (f.type === "ref" && f.ref) refs.add(f.ref);
          }
          refs.forEach((r) => lookup(r, company.id).catch(() => {}));
        }
      })
      .catch(() => setCatalog([]));
  }, [company, location]);

  // connectivity and outbox
  useEffect(() => {
    const refresh = async () => {
      const items = await outbox();
      setPending(items.filter((i) => !i.error).length);
      setFailed(items.filter((i) => i.error).length);
    };
    const goOnline = async () => {
      setOnline(true);
      const r = await flushOutbox();
      if (r.sent) setToast({ msg: `${r.sent} saved entr${r.sent === 1 ? "y" : "ies"} sent`, kind: "ok" });
    };
    setOnline(navigator.onLine);
    refresh();
    const off = onOutboxChange(refresh);
    window.addEventListener("online", goOnline);
    window.addEventListener("offline", () => setOnline(false));
    const timer = setInterval(() => navigator.onLine && flushOutbox(), 60_000);
    if (navigator.onLine) flushOutbox();
    return () => {
      off();
      window.removeEventListener("online", goOnline);
      clearInterval(timer);
    };
  }, []);

  useEffect(() => {
    if (!toastMsg) return;
    const id = setTimeout(() => setToast(null), 4000);
    return () => clearTimeout(id);
  }, [toastMsg]);

  const value: AppState = {
    ready, ctx, company, location, catalog, lang, online, pending, failed,
    setCompany: (id) => {
      localStorage.setItem("erp.company", id);
      setCompanyId(id);
      const co = ctx?.companies.find((c) => c.id === id);
      const only = co && co.locations.length === 1 ? co.locations[0].id : null;
      setLocationId(only);
      if (only) localStorage.setItem("erp.location", only);
      else localStorage.removeItem("erp.location");
    },
    setLocation: (id) => {
      if (id) localStorage.setItem("erp.location", id);
      else localStorage.removeItem("erp.location");
      setLocationId(id);
    },
    setLang: (l) => {
      localStorage.setItem("erp.lang", l);
      setLangState(l);
    },
    t: (k) => tr(k, lang),
    entity: (key) => catalog.find((e) => e.key === key),
    reload: load,
    toast: (msg, kind = "ok") => setToast({ msg, kind }),
  };

  return (
    <Ctx.Provider value={value}>
      {children}
      {toastMsg && (
        <div role="status"
             className={`fixed bottom-20 md:bottom-6 left-1/2 -translate-x-1/2 z-50 rounded-xl px-4 py-3 text-sm shadow-lg max-w-[90vw] ${
               toastMsg.kind === "error" ? "bg-red-600 text-white" : "bg-slate-900 text-white"}`}>
          {toastMsg.msg}
        </div>
      )}
    </Ctx.Provider>
  );
}
