#!/usr/bin/env node
// Local stand-in for the Supabase API gateway, for development and demos without a Supabase project.
//   /rest/v1/*     → PostgREST
//   /auth/v1/*     → email+password and phone OTP (code 123456) sign-in against auth.users, JWTs signed with JWT_SECRET
//   /storage/v1/*  → files kept in a local folder
// Never use this in production: the real app runs on Supabase.
import http from "node:http";
import { createHmac, randomUUID } from "node:crypto";
import { spawnSync } from "node:child_process";
import { mkdirSync, readFileSync, writeFileSync, existsSync } from "node:fs";
import { dirname, join } from "node:path";

const PORT = Number(process.env.GATEWAY_PORT ?? 54321);
const PGRST = process.env.PGRST_URL ?? "http://127.0.0.1:3001";
const SECRET = process.env.JWT_SECRET ?? "dev-jwt-secret-dev-jwt-secret-dev-jwt-secret!";
const FILES = process.env.FILES_DIR ?? "/tmp/erp-dev-files";
const PSQL = (process.env.PSQL ?? "psql").split(" ");
const refresh = new Map();

const b64 = (o) => Buffer.from(JSON.stringify(o)).toString("base64url");
function jwt(claims) {
  const body = `${b64({ alg: "HS256", typ: "JWT" })}.${b64(claims)}`;
  return `${body}.${createHmac("sha256", SECRET).update(body).digest("base64url")}`;
}
function verify(token) {
  const [h, p, s] = String(token).split(".");
  if (!s || createHmac("sha256", SECRET).update(`${h}.${p}`).digest("base64url") !== s) return null;
  const c = JSON.parse(Buffer.from(p, "base64url").toString());
  return c.exp > Date.now() / 1000 ? c : null;
}
function sql(query, ...args) {
  // variables are only substituted in scripts read from a file or stdin, not with -c
  const r = spawnSync(PSQL[0], [...PSQL.slice(1), "-XAtq", "-v", "ON_ERROR_STOP=1",
    ...args.flatMap((a, i) => ["-v", `a${i + 1}=${a ?? ""}`])], { encoding: "utf8", input: query + ";\n" });
  if (r.status !== 0) throw new Error(r.stderr);
  return r.stdout.trim();
}
function session(userId) {
  const row = JSON.parse(sql("select json_build_object('id', id, 'email', email, 'phone', phone) from auth.users where id = :'a1'", userId));
  const exp = Math.floor(Date.now() / 1000) + 3600;
  const access = jwt({ sub: row.id, role: "authenticated", aud: "authenticated", email: row.email, phone: row.phone, exp, iat: exp - 3600 });
  const rt = randomUUID();
  refresh.set(rt, row.id);
  return { access_token: access, token_type: "bearer", expires_in: 3600, expires_at: exp, refresh_token: rt,
           user: { ...row, aud: "authenticated", role: "authenticated", app_metadata: {}, user_metadata: {}, created_at: new Date().toISOString() } };
}
const cors = {
  "access-control-allow-origin": "*", "access-control-allow-headers": "*",
  "access-control-allow-methods": "GET,POST,PUT,PATCH,DELETE,OPTIONS", "access-control-expose-headers": "*",
};
const send = (res, code, obj, headers = {}) => {
  res.writeHead(code, { "content-type": "application/json", ...cors, ...headers });
  res.end(obj === undefined ? "" : JSON.stringify(obj));
};
const readBody = (req) => new Promise((ok) => { const c = []; req.on("data", (d) => c.push(d)); req.on("end", () => ok(Buffer.concat(c))); });

http.createServer(async (req, res) => {
  const url = new URL(req.url, "http://x");
  if (req.method === "OPTIONS") return send(res, 204);
  try {
    if (url.pathname.startsWith("/rest/v1")) {
      const body = ["GET", "HEAD"].includes(req.method) ? undefined : await readBody(req);
      const headers = Object.fromEntries(Object.entries(req.headers).filter(([k]) => !["host", "connection", "content-length"].includes(k)));
      // anon requests carry the anon key as a bearer; PostgREST should see them as anonymous
      if (headers.authorization && !verify(headers.authorization.replace(/^Bearer /, ""))) delete headers.authorization;
      const r = await fetch(PGRST + url.pathname.slice(8) + url.search, { method: req.method, headers, body });
      const buf = Buffer.from(await r.arrayBuffer());
      res.writeHead(r.status, { ...Object.fromEntries(r.headers), ...cors });
      return res.end(buf);
    }
    if (url.pathname === "/auth/v1/token") {
      const b = JSON.parse((await readBody(req)).toString() || "{}");
      if (url.searchParams.get("grant_type") === "password") {
        const id = sql("select id from auth.users where email = :'a1' and encrypted_password = extensions.crypt(:'a2', encrypted_password)", b.email, b.password);
        if (!id) return send(res, 400, { error: "invalid_grant", error_description: "Invalid login credentials", msg: "Invalid login credentials" });
        return send(res, 200, session(id));
      }
      if (url.searchParams.get("grant_type") === "refresh_token" && refresh.has(b.refresh_token)) return send(res, 200, session(refresh.get(b.refresh_token)));
      return send(res, 400, { error: "invalid_grant", msg: "Session expired" });
    }
    if (url.pathname === "/auth/v1/otp") return send(res, 200, {});
    if (url.pathname === "/auth/v1/verify") {
      const b = JSON.parse((await readBody(req)).toString() || "{}");
      const phone = String(b.phone ?? "").replace(/\D/g, "").slice(-10);
      const id = b.token === "123456" ? sql("select id from auth.users where right(phone, 10) = :'a1'", phone) : "";
      if (!id) return send(res, 400, { error: "invalid_otp", msg: "Wrong code. In the dev stack the code is 123456." });
      return send(res, 200, session(id));
    }
    if (url.pathname === "/auth/v1/user") {
      const c = verify((req.headers.authorization ?? "").replace(/^Bearer /, ""));
      if (!c) return send(res, 401, { msg: "not signed in" });
      return send(res, 200, session(c.sub).user);
    }
    if (url.pathname === "/auth/v1/logout") return send(res, 204);
    if (url.pathname.startsWith("/storage/v1/object/")) {
      const rel = url.pathname.replace(/^\/storage\/v1\/object\/(public\/)?/, "");
      const file = join(FILES, rel);
      if (req.method === "POST" || req.method === "PUT") {
        mkdirSync(dirname(file), { recursive: true });
        writeFileSync(file, await readBody(req));
        return send(res, 200, { Key: rel });
      }
      if (!existsSync(file)) return send(res, 404, { error: "not found" });
      res.writeHead(200, { "content-type": "image/jpeg", ...cors });
      return res.end(readFileSync(file));
    }
    send(res, 404, { error: "not found" });
  } catch (e) {
    send(res, 500, { error: String(e.message ?? e) });
  }
}).listen(PORT, () => console.log(`dev gateway on http://localhost:${PORT}`));
