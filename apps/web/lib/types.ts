export type FieldType =
  | "text" | "longtext" | "phone" | "int" | "number" | "money" | "qty" | "percent" | "date" | "datetime" | "time"
  | "bool" | "select" | "multiselect" | "ref" | "photo" | "photos" | "file" | "geo" | "json";

export interface Field {
  name: string;
  label: string;
  type: FieldType;
  required: boolean;
  options: string[] | null;
  ref: string | null;
  computed: boolean;
  quick: boolean;
  in_list: boolean;
  unit: string | null;
  help: string | null;
  section: string | null;
  default: string | null;
}

export interface Entity {
  key: string;
  module: string;
  feature: string;
  label: string;
  label_plural: string;
  kind: "master" | "transaction" | "log";
  scope: "company" | "location";
  numbering: boolean;
  workflow: boolean;
  dated: boolean;
  title_field: string | null;
  amount_field: string | null;
  mobile: boolean;
  icon: string | null;
  description: string | null;
  read_only: boolean;
  can: { create: boolean; approve: boolean };
  fields: Field[];
  children: { key: string; name: string; label: string; fields: Field[] }[];
}

export interface Location { id: string; name: string; code: string; type: string }
export interface Company { id: string; name: string; code: string; locations: Location[] }

export interface AppContext {
  user: { id: string; name: string; mobile: string | null; language: string; is_tenant_admin: boolean; is_platform_admin: boolean } | null;
  tenant: { id: string; name: string; logo: string | null } | null;
  ui_mode: "simple" | "standard" | "power";
  companies: Company[];
}

export type Row = Record<string, any> & { id: string };
