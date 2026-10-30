#!/usr/bin/env node
// Site PC gateway: reads the weighbridge indicator and receives biometric punches, and sends both to the ERP.
// No extra packages. Settings in gateway.json (see README.md). Keeps a local queue when the internet is down.
import { createReadStream, existsSync, readFileSync, writeFileSync } from "node:fs";
import http from "node:http";
import net from "node:net";

const cfg = JSON.parse(readFileSync(new URL("./gateway.json", import.meta.url)));
const QUEUE = new URL("./queue.json", import.meta.url);
const queue = existsSync(QUEUE) ? JSON.parse(readFileSync(QUEUE)) : [];
const save = () => writeFileSync(QUEUE, JSON.stringify(queue));

async function send(device, payload) {
  queue.push({ device, payload, at: new Date().toISOString() });
  save();
  await flush();
}
async function flush() {
  while (queue.length) {
    const { device, payload } = queue[0];
    try {
      const r = await fetch(`${cfg.supabase_url}/rest/v1/rpc/device_ingest`, {
        method: "POST",
        headers: { apikey: cfg.anon_key, "content-type": "application/json" },
        body: JSON.stringify({ p_serial: device.serial, p_key: device.key, p_payload: payload }),
      });
      const text = await r.text();
      console.log(new Date().toLocaleTimeString(), device.serial, r.status, text.slice(0, 200));
      if (r.status >= 500) return;         // server trouble: try again later
    } catch {
      return;                              // no internet: keep the queue
    }
    queue.shift();
    save();
  }
}
setInterval(flush, 30_000);

// ---- weighbridge indicator ---------------------------------------------------------------------------
// Most Indian indicators stream lines like "+0014320" or "ST,GS,+  14320kg". A weight is taken when it has
// stayed the same for `stable_seconds` and is above `min_kg`. The operator types or ANPR fills the vehicle no.
if (cfg.weighbridge) {
  const w = cfg.weighbridge;
  let last = null, since = 0, sent = false, vehicle = "";
  const onLine = (line) => {
    const m = String(line).match(/([+-]?)\s*0*(\d{2,7})/);
    if (!m) return;
    const kg = Number(m[2]) * (m[1] === "-" ? -1 : 1);
    if (kg !== last) { last = kg; since = Date.now(); sent = false; return; }
    const stable = (Date.now() - since) / 1000;
    if (!sent && kg >= (w.min_kg ?? 1000) && stable >= (w.stable_seconds ?? 3) && vehicle) {
      sent = true;
      send(w, { weight_kg: kg, stable_seconds: stable, vehicle_no: vehicle });
      vehicle = "";
    }
  };
  const feed = (stream) => { let buf = ""; stream.on("data", (d) => { buf += d; const parts = buf.split(/[\r\n\x02\x03]+/); buf = parts.pop(); parts.forEach(onLine); }); };
  if (w.tcp) feed(net.connect(w.tcp.port, w.tcp.host));          // indicators with an Ethernet port
  else feed(createReadStream(w.serial_device ?? "/dev/ttyUSB0"));   // set the port first: stty -F /dev/ttyUSB0 2400 cs8 -cstopb -parenb raw
  // the operator (or an ANPR camera's HTTP push) sets the vehicle number: POST /vehicle {"vehicle_no": "AP16TX4521"}
  http.createServer((req, res) => {
    let b = ""; req.on("data", (d) => (b += d)); req.on("end", () => {
      if (req.url === "/vehicle") { vehicle = JSON.parse(b || "{}").vehicle_no ?? ""; res.end("ok"); }
      else { res.writeHead(200, { "content-type": "application/json" }); res.end(JSON.stringify({ weight_kg: last, vehicle })); }
    });
  }).listen(w.http_port ?? 8085);
}

// ---- biometric (ZKTeco / eSSL "ADMS" push) -------------------------------------------------------------
// Point the machine's Cloud Server setting to this PC's IP and port. Punches arrive as ATTLOG lines.
if (cfg.biometric) {
  const b = cfg.biometric;
  http.createServer((req, res) => {
    let body = ""; req.on("data", (d) => (body += d)); req.on("end", () => {
      const url = new URL(req.url, "http://x");
      if (url.pathname === "/iclock/cdata" && req.method === "POST" && url.searchParams.get("table") === "ATTLOG") {
        const records = body.split("\n").filter(Boolean).map((l) => l.split("\t"))
          .map(([pin, time]) => ({ emp_code: (b.code_prefix ?? "") + pin, time: time.replace(" ", "T") + "+05:30" }));
        if (records.length) send(b, { records });
        res.end(`OK: ${records.length}`);
      } else res.end("OK");
    });
  }).listen(b.port ?? 8081);
}
console.log("gateway running");
