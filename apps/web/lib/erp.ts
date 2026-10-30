"use client";

// Every screen talks to the database through these calls. Reads fall back to the last copy cached on
// the device when there is no signal; saves go to the outbox and are sent later.
import { sb } from "./supabase";
import { cacheGet, cacheSet, enqueue, isNetworkError, takeOfflineNumber } from "./offline";
import type { AppContext, Entity, Row } from "./types";

export class UserError extends Error {}

async function rpc<T>(fn: string, args: Record<string, unknown>, cacheKey?: string): Promise<T> {
  try {
    const { data, error } = await sb().rpc(fn, args);
    if (error) {
      if (isNetworkError(error) && cacheKey) {
        const cached = await cacheGet<T>(cacheKey);
        if (cached !== undefined) return cached;
      }
      throw new UserError(error.message);
    }
    if (cacheKey) await cacheSet(cacheKey, data);
    return data as T;
  } catch (e) {
    if (cacheKey && isNetworkError(e)) {
      const cached = await cacheGet<T>(cacheKey);
      if (cached !== undefined) return cached;
    }
    throw e;
  }
}

export const getContext = () => rpc<AppContext>("my_context", {}, "ctx");

export const getCatalog = (company: string, location: string | null) =>
  rpc<Entity[]>("erp_catalog", { p_company: company, p_location: location }, `catalog:${company}:${location}`);

export interface ListResult { rows: Row[]; total: number; hidden: string[] }
export const listRecords = (entity: string, company: string, location: string | null, filters: Record<string, unknown> = {},
                            search = "", limit = 50, offset = 0) =>
  rpc<ListResult>("erp_list", { p_entity: entity, p_company: company, p_location: location, p_filters: filters,
                                p_search: search || null, p_limit: limit, p_offset: offset },
                  !search && offset === 0 ? `list:${entity}:${company}:${location}:${JSON.stringify(filters)}` : undefined);

export const getRecord = (entity: string, id: string) => rpc<Row>("erp_get", { p_entity: entity, p_id: id }, `rec:${entity}:${id}`);

export async function saveRecord(entity: Entity, data: Record<string, unknown>, opts: { offlineOk?: boolean } = {}):
  Promise<{ record: Row; queued: boolean }> {
  const payload: Record<string, any> = { ...data, id: (data.id as string) ?? crypto.randomUUID() };
  const isNew = !data.id;
  const queue = async () => {
    if (isNew && entity.numbering && !payload.doc_no && payload.location_id) {
      const n = await takeOfflineNumber(entity.key, payload.location_id as string);
      if (n) payload.doc_no = n;
    }
    await enqueue({ fn: "erp_save", args: { p_entity: entity.key, p_data: payload },
                    label: `${entity.label} ${payload.doc_no ?? ""}`.trim() });
    const record = { ...payload, _pending: true } as unknown as Row;
    await cacheSet(`rec:${entity.key}:${payload.id}`, record);
    return { record, queued: true };
  };
  if (opts.offlineOk !== false && typeof navigator !== "undefined" && !navigator.onLine) return queue();
  try {
    const record = await rpc<Row>("erp_save", { p_entity: entity.key, p_data: payload });
    await cacheSet(`rec:${entity.key}:${record.id}`, record);
    return { record, queued: false };
  } catch (e) {
    if (isNetworkError(e) && opts.offlineOk !== false) return queue();
    throw e;
  }
}

export const setStatus = (entity: string, id: string, action: "submit" | "cancel", reason?: string) =>
  rpc<Row>("erp_set_status", { p_entity: entity, p_id: id, p_action: action, p_reason: reason ?? null,
                               p_source: typeof window !== "undefined" && window.innerWidth < 768 ? "mobile" : "web" });

export const deleteRecord = (entity: string, id: string, reason: string) =>
  rpc<void>("erp_delete", { p_entity: entity, p_id: id, p_reason: reason });

export interface LookupRow { id: string; label: string; sub: string | null }
export const lookup = (ref: string, company: string, search = "", ids: string[] | null = null) =>
  rpc<LookupRow[]>("erp_lookup", { p_ref: ref, p_company: company, p_search: search || null, p_ids: ids, p_limit: 30 },
                   !search && !ids ? `lookup:${ref}:${company}` : undefined);

export const history = (entity: string, id: string) => rpc<any[]>("erp_history", { p_entity: entity, p_id: id });

export const approvalCards = () => rpc<any[]>("my_approval_cards", {}, "approvals");
export const actOnApproval = (id: string, action: "approve" | "reject" | "send_back", comment?: string) =>
  rpc<any>("act_on_approval", { p_request: id, p_action: action, p_comment: comment ?? null,
                                p_source: typeof window !== "undefined" && window.innerWidth < 768 ? "mobile" : "web" });

export const ownerDashboard = (from?: string, to?: string) =>
  rpc<any[]>("owner_dashboard", { ...(from ? { p_from: from } : {}), ...(to ? { p_to: to } : {}) }, from || to ? undefined : "dashboard");
export const leakageBoard = (company: string) => rpc<any[]>("leakage_board", { p_company: company }, `leakage:${company}`);
export const trialBalance = (company: string | null) => rpc<any[]>("trial_balance", { p_company: company }, `tb:${company}`);
export const stockOnHand = (company: string, location: string | null) =>
  rpc<any[]>("stock_on_hand", { p_company: company, p_location: location }, `stock:${company}:${location}`);
export const billingRun = (source: string, company: string, location: string) =>
  rpc<any[]>("billing_run", { p_source: source, p_company: company, p_location: location });
export const generatePayroll = (run: string) => rpc<any>("hr_generate_payroll", { p_run: run });
export const projectHealth = (project: string) => rpc<any>("project_health", { p_project: project });
