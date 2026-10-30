"use client";

// Local-first saving: every save goes to an outbox first when there is no signal, and is sent in order
// when the connection comes back. Records get their id on the phone, so later edits and lines refer to
// the same record before it ever reached the server. Numbered documents (challans, shifts, tickets) take
// their number from a block the phone reserved while online, so printed numbers stay valid.
import { get, set, del, createStore } from "idb-keyval";
import { sb } from "./supabase";

const store = typeof window !== "undefined" ? createStore("group-erp", "kv") : (undefined as any);

export interface OutboxItem {
  key: string;
  fn: string;
  args: Record<string, unknown>;
  label: string;
  queued_at: string;
  error?: string;
}

type Listener = () => void;
const listeners = new Set<Listener>();
export function onOutboxChange(fn: Listener): () => void {
  listeners.add(fn);
  return () => { listeners.delete(fn); };
}
const notify = () => listeners.forEach((l) => l());

export async function cacheGet<T>(key: string): Promise<T | undefined> {
  try {
    return await get<T>(key, store);
  } catch {
    return undefined;
  }
}
export async function cacheSet(key: string, value: unknown) {
  try {
    await set(key, value, store);
  } catch {
    /* storage full or blocked: the app still works online */
  }
}

export async function outbox(): Promise<OutboxItem[]> {
  return (await cacheGet<OutboxItem[]>("outbox")) ?? [];
}

export async function enqueue(item: Omit<OutboxItem, "key" | "queued_at">) {
  const items = await outbox();
  items.push({ ...item, key: crypto.randomUUID(), queued_at: new Date().toISOString() });
  await cacheSet("outbox", items);
  notify();
}

export function isNetworkError(e: unknown): boolean {
  const msg = String((e as any)?.message ?? e);
  return (typeof navigator !== "undefined" && !navigator.onLine) || /Failed to fetch|NetworkError|Load failed|fetch failed/i.test(msg);
}

let flushing = false;
// Sends queued saves one by one. A save the server rejects (e.g. a missing field) is kept with its message
// so the user can fix it; a network failure stops the run until the next attempt.
export async function flushOutbox(): Promise<{ sent: number; failed: number }> {
  if (flushing) return { sent: 0, failed: 0 };
  flushing = true;
  let sent = 0;
  let failed = 0;
  try {
    let items = await outbox();
    for (const item of items) {
      if (item.error) {
        failed++;
        continue;
      }
      const { error } = await sb().rpc(item.fn, item.args);
      if (error && isNetworkError(error)) break;
      items = (await outbox()).map((i) => (i.key === item.key ? { ...i, error: error?.message } : i));
      if (!error) {
        items = items.filter((i) => i.key !== item.key);
        sent++;
      } else failed++;
      await cacheSet("outbox", items);
      notify();
    }
  } finally {
    flushing = false;
  }
  return { sent, failed };
}

export async function dropOutboxItem(key: string) {
  await cacheSet("outbox", (await outbox()).filter((i) => i.key !== key));
  notify();
}

export async function retryOutboxItem(key: string) {
  await cacheSet("outbox", (await outbox()).map((i) => (i.key === key ? { ...i, error: undefined } : i)));
  notify();
  return flushOutbox();
}

// ---- offline document numbers ----------------------------------------------------------------------

interface Block { pattern: string; company_code: string; location_code: string | null; fy: string; next: number; to: number }

export function formatDocNumber(pattern: string, co: string, loc: string | null, fy: string, seq: number) {
  return pattern
    .replace("{CO}", co)
    .replace("{LOC}", loc ?? "")
    .replace("{FY}", fy)
    .replace(/\{SEQ:(\d+)\}/, (_, n) => String(seq).padStart(Number(n), "0"))
    .replace("{SEQ}", String(seq));
}

export async function reserveBlocks(company: string, location: string, entities: string[], size = 30) {
  if (!navigator.onLine) return;
  for (const key of entities) {
    const k = `block:${key}:${location}`;
    const b = await cacheGet<Block>(k);
    if (b && b.to - b.next >= 5) continue;
    const { data, error } = await sb().rpc("reserve_number_block", {
      p_company: company, p_location: location, p_doc_type: key, p_device_id: localStorage.getItem("erp.device_id"), p_count: size,
    });
    if (!error && data?.[0]) {
      const r = data[0];
      await cacheSet(k, { pattern: r.pattern, company_code: r.company_code, location_code: r.location_code, fy: r.fy, next: r.from_value, to: r.to_value });
    }
  }
}

export async function takeOfflineNumber(entity: string, location: string): Promise<string | null> {
  const k = `block:${entity}:${location}`;
  const b = await cacheGet<Block>(k);
  if (!b || b.next > b.to) return null;
  await cacheSet(k, { ...b, next: b.next + 1 });
  return formatDocNumber(b.pattern, b.company_code, b.location_code, b.fy, b.next);
}

export { del as _del };
