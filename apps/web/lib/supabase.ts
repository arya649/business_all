"use client";

import { createBrowserClient } from "@supabase/ssr";
import type { SupabaseClient } from "@supabase/supabase-js";

let client: SupabaseClient | null = null;

export function deviceId(): string {
  if (typeof window === "undefined") return "server";
  try {
    let id = localStorage.getItem("erp.device_id");
    if (!id) {
      id = crypto.randomUUID();
      localStorage.setItem("erp.device_id", id);
    }
    return id;
  } catch {
    return "unknown";
  }
}

export function isMobileApp(): boolean {
  if (typeof window === "undefined") return false;
  return window.matchMedia("(display-mode: standalone)").matches || window.innerWidth < 768;
}

// Every request carries where it came from; the audit log records it with each change.
export function sb(): SupabaseClient {
  if (!client) {
    client = createBrowserClient(process.env.NEXT_PUBLIC_SUPABASE_URL!, process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!, {
      global: { headers: { "x-source": isMobileApp() ? "mobile" : "web", "x-device-id": deviceId() } },
    });
  }
  return client;
}
