#!/usr/bin/env node
// Generates the module tables and the erp_entity / erp_field catalogue from config/modules/*.mjs.
// Run after editing a module:  node scripts/gen-modules.mjs
import { readFileSync, readdirSync, writeFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";

const root = join(dirname(fileURLToPath(import.meta.url)), "..");
const out = join(root, "supabase/migrations/20261030000100_modules_generated.sql");
const catalogOut = join(root, "config/modules.generated.json");

// ---- feature keys from the registry ---------------------------------------------------------
const registry = JSON.parse(readFileSync(join(root, "config/feature-registry.json"), "utf8"));
const featureKeys = new Set();
(function walk(node, parent) {
  for (const [k, v] of Object.entries(node)) {
    if (k.startsWith("$") || k === "config") continue;
    const key = parent ? `${parent}.${k}` : k;
    featureKeys.add(key);
    walk(v, key);
  }
})(registry, null);

// ---- load modules ---------------------------------------------------------------------------
const dir = join(root, "config/modules");
const files = readdirSync(dir).filter((f) => f.endsWith(".mjs") && !f.startsWith("_")).sort();
const modules = [];
for (const file of files) modules.push((await import(pathToFileURL(join(dir, file)))).default);

const CORE_REFS = { party: "party", item: "item", vehicle: "vehicle", app_user: "app_user", location: "location", company: "company" };
const SQL_TYPES = {
  text: "text", longtext: "text", phone: "text", int: "integer", number: "numeric(18,4)", money: "numeric(14,2)",
  qty: "numeric(14,3)", percent: "numeric(7,3)", date: "date", datetime: "timestamptz", time: "time", bool: "boolean",
  select: "text", multiselect: "text[]", ref: "uuid", photo: "text", photos: "text[]", file: "text", geo: "text", json: "jsonb",
};
const RESERVED = new Set(["id", "tenant_id", "company_id", "location_id", "doc_no", "doc_date", "status", "created_by",
  "created_at", "updated_by", "updated_at", "device_id", "geo", "parent_id", "line_no", "submitted_at", "approved_at",
  "approval_request_id"]);

const q = (s) => (s === null || s === undefined ? "null" : `'${String(s).replaceAll("'", "''")}'`);
const tableOf = (key) => key.replaceAll(".", "_");
const errors = [];
const entities = new Map();

for (const m of modules) {
  for (const e of m.entities) {
    e.module = m.module;
    e.table = tableOf(e.key);
    e.kind ??= "transaction";
    e.scope ??= "location";
    e.plural ??= e.label + "s";
    if (!featureKeys.has(e.feature)) errors.push(`${e.key}: feature ${e.feature} is not in feature-registry.json`);
    if (entities.has(e.key)) errors.push(`${e.key}: defined twice`);
    entities.set(e.key, e);
    for (const c of e.children ?? []) {
      c.key = `${e.key}.${c.name}`;
      c.table = tableOf(c.key);
      c.parent = e;
    }
  }
}
for (const e of entities.values()) {
  for (const fl of [...e.fields, ...(e.children ?? []).flatMap((c) => c.fields)]) {
    if (RESERVED.has(fl.name)) errors.push(`${e.key}.${fl.name}: reserved column name`);
    if (!SQL_TYPES[fl.type]) errors.push(`${e.key}.${fl.name}: unknown type ${fl.type}`);
    if (fl.type === "ref" && !CORE_REFS[fl.ref] && !entities.has(fl.ref)) errors.push(`${e.key}.${fl.name}: unknown ref ${fl.ref}`);
  }
}
if (errors.length) {
  console.error(errors.join("\n"));
  process.exit(1);
}

// ---- SQL ------------------------------------------------------------------------------------
const sql = [];
const fks = [];
const catalog = [];
let sort = 0;

function columnSql(table, fl) {
  const t = SQL_TYPES[fl.type];
  if (fl.expr) return `  ${fl.name} ${t} generated always as (${fl.expr}) stored`;
  let s = `  ${fl.name} ${t}`;
  if (fl.type === "bool") s += ` not null default ${fl.default ?? "false"}`;
  else if (fl.default !== undefined) s += ` default ${/^[0-9.-]+$/.test(fl.default) || /^(current_date|now\(\)|true|false)$/.test(fl.default) ? fl.default : q(fl.default)}`;
  if (fl.type === "select") s += ` check (${fl.name} in (${fl.options.map(q).join(", ")}))`;
  if (fl.type === "multiselect") s += ` check (${fl.name} <@ array[${fl.options.map(q).join(", ")}])`;
  if (fl.check) s += ` check (${fl.check})`;
  if (fl.type === "ref") fks.push(`alter table public.${table} add foreign key (${fl.name}) references public.${CORE_REFS[fl.ref] ?? entities.get(fl.ref).table};`);
  return s;
}

function catalogRows(entityKey, fields) {
  return fields.map((fl, i) => `(${[
    q(entityKey), q(fl.name), q(fl.label), q(fl.type), fl.required ? "true" : "false",
    fl.options ? q(JSON.stringify(fl.options)) + "::jsonb" : "null", q(fl.ref ?? null), fl.expr ? "true" : "false",
    q(fl.sensitive ?? null), fl.quick ? "true" : "false", fl.list ? "true" : "false", q(fl.unit ?? null), q(fl.help ?? null),
    q(fl.section ?? null), fl.type === "bool" || fl.expr ? "null" : q(fl.default ?? null), i,
  ].join(", ")})`);
}

for (const e of entities.values()) {
  const cols = [
    "  id uuid primary key default gen_random_uuid()",
    "  tenant_id uuid not null references public.tenant",
    "  company_id uuid not null references public.company",
    `  location_id uuid references public.location`,
  ];
  if (e.numbering) cols.push("  doc_no text not null");
  if (e.dated) cols.push("  doc_date date not null default current_date");
  if (e.workflow) cols.push(
    "  status text not null default 'draft' check (status in ('draft', 'submitted', 'approved', 'rejected', 'sent_back', 'cancelled'))",
    "  submitted_at timestamptz", "  approved_at timestamptz", "  approval_request_id uuid references public.approval_request");
  for (const fl of e.fields) cols.push(columnSql(e.table, fl));
  cols.push("  device_id text", "  geo text", "  created_by uuid default auth.uid()", "  created_at timestamptz not null default now()",
            "  updated_by uuid", "  updated_at timestamptz not null default now()");
  if (e.numbering) cols.push("  unique (company_id, doc_no)");
  for (const u of e.unique ?? []) cols.push(`  unique (${u.join(", ")})`);
  if (e.scope === "location") cols.push("  check (location_id is not null)");

  sql.push(`-- ${e.label} (${e.key})${e.description ? `\n-- ${e.description}` : ""}
create table public.${e.table} (
${cols.join(",\n")}
);
create index on public.${e.table} (company_id, location_id${e.dated ? ", doc_date" : ""});
alter table public.${e.table} enable row level security;
create policy admin_read on public.${e.table} for select using (public.is_tenant_admin(tenant_id));
create trigger erp_touch before update on public.${e.table} for each row execute function public.erp_touch();
select audit.track('public.${e.table}');`);

  for (const c of e.children ?? []) {
    const ccols = [
      "  id uuid primary key default gen_random_uuid()",
      "  tenant_id uuid not null references public.tenant",
      `  parent_id uuid not null references public.${e.table} on delete cascade`,
      "  line_no integer not null",
      ...c.fields.map((fl) => columnSql(c.table, fl)),
      "  unique (parent_id, line_no)",
    ];
    sql.push(`create table public.${c.table} (
${ccols.join(",\n")}
);
create index on public.${c.table} (parent_id);
alter table public.${c.table} enable row level security;
create policy admin_read on public.${c.table} for select using (public.is_tenant_admin(tenant_id));
select audit.track('public.${c.table}');`);
  }

  if (e.rollups?.length) {
    const sets = e.rollups.map((r) => {
      const child = e.children.find((c) => c.name === r.child);
      return `  new.${r.field} := (select ${r.expr} from public.${child.table} where parent_id = new.id);`;
    });
    sql.push(`create function public.${e.table}_rollup() returns trigger language plpgsql as $$
begin
${sets.join("\n")}
  return new;
end $$;
create trigger erp_rollup before insert or update on public.${e.table} for each row execute function public.${e.table}_rollup();`);
  }

  const children = e.children ?? [];
  catalog.push({ ...e, parent: undefined, children: children.map((c) => ({ ...c, parent: undefined })) });
  sql.push(`insert into public.erp_entity (key, module, feature_key, table_name, label, label_plural, kind, scope, numbering, workflow,
  dated, title_field, amount_field, mobile, icon, description, stock_rules, posting, sort) values
(${[q(e.key), q(e.module), q(e.feature), q(e.table), q(e.label), q(e.plural), q(e.kind), q(e.scope), q(e.numbering ?? null),
    e.workflow ? "true" : "false", e.dated ? "true" : "false", q(e.title ?? null), q(e.amount ?? null), e.mobile ? "true" : "false",
    q(e.icon ?? null), q(e.description ?? null),
    e.stock ? q(JSON.stringify(e.stock)) + "::jsonb" : "null", e.posting ? q(JSON.stringify(e.posting)) + "::jsonb" : "null",
    sort++].join(", ")});`);
  for (const c of children) {
    sql.push(`insert into public.erp_entity (key, module, feature_key, table_name, parent_key, child_name, label, label_plural, kind, scope, sort) values
(${[q(c.key), q(e.module), q(e.feature), q(c.table), q(e.key), q(c.name), q(c.label), q(c.label), "'child'", q(e.scope), sort++].join(", ")});`);
  }
  const rows = [...catalogRows(e.key, e.fields), ...children.flatMap((c) => catalogRows(c.key, c.fields))];
  if (rows.length) sql.push(`insert into public.erp_field (entity_key, name, label, type, required, options, ref, computed, sensitive,
  quick, in_list, unit, help, section, default_value, sort) values
${rows.join(",\n")};`);
}

writeFileSync(out, `-- GENERATED by scripts/gen-modules.mjs from config/modules/*.mjs. Do not edit by hand.
-- Module tables: group admins may read them directly (reports); everyone else goes through the erp_* functions,
-- which apply permissions and field visibility.

${sql.join("\n\n")}

-- references between tables
${fks.join("\n")}
`);
writeFileSync(catalogOut, JSON.stringify(catalog, null, 1));
const n = [...entities.values()];
console.log(`${modules.length} modules, ${n.length} records, ${n.reduce((a, e) => a + (e.children?.length ?? 0), 0)} line tables, ` +
  `${n.reduce((a, e) => a + e.fields.length + (e.children ?? []).reduce((b, c) => b + c.fields.length, 0), 0)} fields`);
