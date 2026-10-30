import { createHmac, randomUUID } from "node:crypto";
import { createClient, type SupabaseClient } from "@supabase/supabase-js";

const b64url = (b: Buffer | string) => Buffer.from(b).toString("base64url");

// A short-lived HS256 token for Zentrix ADK, signed with this product's partner key (never sent to browsers).
// cid = the client business group (Zentrix "customer"), sub = the signed-in user, scope = what they may use.
export function mintZentrixToken(tenantId: string, userId: string, scopes: string[], ttl = 300): string {
  const now = Math.floor(Date.now() / 1000);
  const header = { alg: "HS256", typ: "JWT", kid: process.env.ZENTRIX_KID };
  const claims = {
    iss: process.env.ZENTRIX_PARTNER_ID, aud: "zentrix-adk", cid: tenantId, sub: userId, typ: "user",
    scope: scopes.join(" "), iat: now, nbf: now, exp: now + Math.min(ttl, 900), jti: randomUUID(),
  };
  const body = `${b64url(JSON.stringify(header))}.${b64url(JSON.stringify(claims))}`;
  const sig = createHmac("sha256", process.env.ZENTRIX_SIGNING_KEY ?? "").update(body).digest("base64url");
  return `${body}.${sig}`;
}

// Supabase client acting as the caller (their own token), so RLS applies.
export function userClient(token: string): SupabaseClient {
  return createClient(process.env.NEXT_PUBLIC_SUPABASE_URL!, process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!, {
    global: { headers: { Authorization: `Bearer ${token}` } },
    auth: { persistSession: false },
  });
}

export async function callerFrom(req: Request) {
  const token = req.headers.get("authorization")?.replace(/^Bearer /, "");
  if (!token) return null;
  const db = userClient(token);
  const { data, error } = await db.rpc("my_context");
  if (error || !data?.user) return null;
  return { token, db, ctx: data as { user: { id: string; is_tenant_admin: boolean }; tenant: { id: string } } };
}
