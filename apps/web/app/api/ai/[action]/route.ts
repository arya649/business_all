import { randomUUID } from "node:crypto";
import { NextResponse } from "next/server";
import { callerFrom, mintZentrixToken } from "@/lib/server/zentrix";

// Proxy to Zentrix ADK: the browser never holds the partner key. Scopes come from the database
// (plan ∩ switches ∩ role), so AI can never do more than the person could do by hand.
//   POST /api/ai/extract  {document_type, files, company_id}
//   POST /api/ai/agent    {agent, input, messages, company_id, location_id}
export async function POST(req: Request, { params }: { params: Promise<{ action: string }> }) {
  const { action } = await params;
  if (!process.env.ZENTRIX_URL) return NextResponse.json({ error: "AI is not set up yet (ZENTRIX_URL)." }, { status: 503 });
  const caller = await callerFrom(req);
  if (!caller) return NextResponse.json({ error: "Sign in again." }, { status: 401 });
  const body = await req.json();
  const { data: scopes, error } = await caller.db.rpc("ai_scopes", { p_company: body.company_id, p_location: body.location_id ?? null });
  if (error) return NextResponse.json({ error: error.message }, { status: 403 });

  const correlation = randomUUID();
  const token = mintZentrixToken(caller.ctx.tenant.id, caller.ctx.user.id, scopes as string[]);
  const headers = { "content-type": "application/json", authorization: `Bearer ${token}`, "x-correlation-id": correlation, "x-channel": "api" };

  let url: string;
  let payload: unknown;
  if (action === "extract") {
    if (!(scopes as string[]).includes("extract.*")) return NextResponse.json({ error: "Document reading is switched off for you." }, { status: 403 });
    url = `${process.env.ZENTRIX_URL}/v1/extract`;
    payload = { document_type: body.document_type, files: body.files };
  } else if (action === "agent") {
    if (!(scopes as string[]).includes(`agent.${body.agent}`)) return NextResponse.json({ error: "This assistant is switched off for you." }, { status: 403 });
    url = `${process.env.ZENTRIX_URL}/v1/agents/${encodeURIComponent(body.agent)}/run`;
    // the ERP tools inside Zentrix call back as this user; they get the company and location the user is working in
    payload = { input: body.input, messages: body.messages ?? [],
                context: { company_id: body.company_id, location_id: body.location_id ?? null, correlation_id: correlation } };
  } else {
    return NextResponse.json({ error: "unknown action" }, { status: 404 });
  }
  const r = await fetch(url, { method: "POST", headers, body: JSON.stringify(payload) });
  const text = await r.text();
  return new NextResponse(text, { status: r.status, headers: { "content-type": "application/json", "x-correlation-id": correlation } });
}
