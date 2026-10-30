"use client";

import { useState } from "react";
import { AppShell } from "@/components/AppShell";
import { useApp } from "@/components/AppProvider";
import { Switches } from "./Switches";
import { Roles } from "./Roles";
import { Users } from "./Users";
import { ApprovalRules } from "./ApprovalRules";
import { Companies } from "./Companies";
import { AuditLog } from "./AuditLog";
import { Devices } from "./Devices";

const TABS = [
  ["switches", "Switches"], ["roles", "Roles & fields"], ["users", "Users"], ["approvals", "Approval rules"],
  ["companies", "Companies & locations"], ["devices", "Devices"], ["audit", "Audit log"],
] as const;

// Everything complex lives here, so nobody else has to see it.
export default function Admin() {
  const app = useApp();
  const [tab, setTab] = useState<(typeof TABS)[number][0]>("switches");
  if (app.ready && !app.ctx?.user?.is_tenant_admin) return <AppShell><p>{app.t("not_enabled")}</p></AppShell>;
  return (
    <AppShell title={app.t("admin")}>
      <div className="flex flex-wrap gap-1 mb-4">
        {TABS.map(([k, l]) => <button key={k} className={`tab ${tab === k ? "tab-on" : ""}`} onClick={() => setTab(k)}>{l}</button>)}
      </div>
      {tab === "switches" && <Switches />}
      {tab === "roles" && <Roles />}
      {tab === "users" && <Users />}
      {tab === "approvals" && <ApprovalRules />}
      {tab === "companies" && <Companies />}
      {tab === "devices" && <Devices />}
      {tab === "audit" && <AuditLog />}
    </AppShell>
  );
}
