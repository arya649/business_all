"use client";

import { useState } from "react";
import { useRouter } from "next/navigation";
import { sb } from "@/lib/supabase";
import { useApp } from "@/components/AppProvider";

// Field staff sign in with their mobile number and a one-time code; office staff can use email and password.
export default function Login() {
  const app = useApp();
  const router = useRouter();
  const [mode, setMode] = useState<"phone" | "email">("phone");
  const [phone, setPhone] = useState("");
  const [code, setCode] = useState("");
  const [sent, setSent] = useState(false);
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [error, setError] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);

  const done = async () => { await app.reload(); router.replace("/"); };
  const e164 = (p: string) => (p.startsWith("+") ? p : "+91" + p.replace(/\D/g, "").slice(-10));

  const run = async (fn: () => Promise<{ error: any }>, after?: () => void) => {
    setBusy(true); setError(null);
    const { error } = await fn();
    setBusy(false);
    if (error) setError(error.message); else after?.();
  };

  return (
    <main className="min-h-dvh grid place-items-center p-4 bg-[var(--bg)]">
      <div className="card w-full max-w-sm p-6 space-y-5">
        <div>
          <h1 className="text-2xl font-semibold">Sign in</h1>
          <p className="text-sm text-[var(--muted)]">Group ERP</p>
        </div>
        <div className="flex gap-1">
          <button className={`tab ${mode === "phone" ? "tab-on" : ""}`} onClick={() => setMode("phone")}>Mobile number</button>
          <button className={`tab ${mode === "email" ? "tab-on" : ""}`} onClick={() => setMode("email")}>Email</button>
        </div>
        {mode === "phone" ? (
          !sent ? (
            <form className="space-y-3" onSubmit={(e) => { e.preventDefault(); run(() => sb().auth.signInWithOtp({ phone: e164(phone) }), () => setSent(true)); }}>
              <label className="block text-sm font-medium">Mobile number
                <input type="tel" inputMode="numeric" autoComplete="tel" value={phone} onChange={(e) => setPhone(e.target.value)}
                       className="mt-1.5 w-full rounded-xl border border-[var(--line)] bg-[var(--card)] px-3 py-3 text-lg" placeholder="98765 43210" required />
              </label>
              <button disabled={busy} className="btn btn-primary w-full">Send code</button>
            </form>
          ) : (
            <form className="space-y-3" onSubmit={(e) => { e.preventDefault(); run(() => sb().auth.verifyOtp({ phone: e164(phone), token: code, type: "sms" }), done); }}>
              <label className="block text-sm font-medium">Code sent to {phone}
                <input inputMode="numeric" autoComplete="one-time-code" value={code} onChange={(e) => setCode(e.target.value)}
                       className="mt-1.5 w-full rounded-xl border border-[var(--line)] bg-[var(--card)] px-3 py-3 text-2xl tracking-[.4em] text-center" maxLength={6} required />
              </label>
              <button disabled={busy} className="btn btn-primary w-full">Sign in</button>
              <button type="button" className="text-sm text-[var(--muted)]" onClick={() => setSent(false)}>Change number</button>
            </form>
          )
        ) : (
          <form className="space-y-3" onSubmit={(e) => { e.preventDefault(); run(() => sb().auth.signInWithPassword({ email, password }), done); }}>
            <label className="block text-sm font-medium">Email
              <input type="email" autoComplete="email" value={email} onChange={(e) => setEmail(e.target.value)}
                     className="mt-1.5 w-full rounded-xl border border-[var(--line)] bg-[var(--card)] px-3 py-3" required />
            </label>
            <label className="block text-sm font-medium">Password
              <input type="password" autoComplete="current-password" value={password} onChange={(e) => setPassword(e.target.value)}
                     className="mt-1.5 w-full rounded-xl border border-[var(--line)] bg-[var(--card)] px-3 py-3" required />
            </label>
            <button disabled={busy} className="btn btn-primary w-full">Sign in</button>
          </form>
        )}
        {error && <p role="alert" className="text-sm text-red-600">{error}</p>}
      </div>
    </main>
  );
}
