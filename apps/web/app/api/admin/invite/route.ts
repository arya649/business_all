import { NextResponse } from "next/server";
import { createClient } from "@supabase/supabase-js";
import { callerFrom } from "@/lib/server/zentrix";

// Super Admin adds a person: a Supabase login by mobile number (OTP) plus their app_user row in this group.
export async function POST(req: Request) {
  const caller = await callerFrom(req);
  if (!caller?.ctx.user.is_tenant_admin) return NextResponse.json({ error: "Only admins can add people." }, { status: 403 });
  if (!process.env.SUPABASE_SERVICE_ROLE_KEY) return NextResponse.json({ error: "SUPABASE_SERVICE_ROLE_KEY is not set on the server." }, { status: 503 });
  const { full_name, mobile, email } = await req.json();
  const digits = String(mobile ?? "").replace(/\D/g, "").slice(-10);
  if (!full_name || digits.length !== 10) return NextResponse.json({ error: "Name and a 10-digit mobile number are needed." }, { status: 400 });

  const admin = createClient(process.env.NEXT_PUBLIC_SUPABASE_URL!, process.env.SUPABASE_SERVICE_ROLE_KEY, { auth: { persistSession: false } });
  const { data, error } = await admin.auth.admin.createUser({ phone: `+91${digits}`, phone_confirm: true, email: email || undefined, email_confirm: !!email });
  if (error) return NextResponse.json({ error: error.message }, { status: 400 });
  // inserted as the admin (not the service role), so RLS checks they may add people to this group
  const { error: e2 } = await caller.db.from("app_user").insert({ id: data.user.id, tenant_id: caller.ctx.tenant.id, full_name, mobile: digits, email: email || null });
  if (e2) {
    await admin.auth.admin.deleteUser(data.user.id);
    return NextResponse.json({ error: e2.message }, { status: 400 });
  }
  return NextResponse.json({ id: data.user.id });
}
