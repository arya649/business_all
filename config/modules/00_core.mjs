import { f, party, vehicle } from "./_dsl.mjs";

export default {
  module: "core",
  label: "Documents",
  entities: [
    {
      key: "core.document", feature: "core.documents.register", label: "Licence / document", plural: "Licences & documents",
      kind: "master", scope: "company", title: "title", mobile: false, icon: "file-check",
      description: "Every licence, certificate, tender, work order and drawing, with expiry reminders.",
      fields: [
        f.select("category", "Type", ["peso_licence", "weights_measures", "pollution_consent", "factory_licence", "labour_licence",
          "trade_licence", "fire_noc", "gst_certificate", "msme", "calibration", "insurance", "tender", "work_order", "drawing",
          "agreement", "bank_guarantee", "other"], { required: true, list: true }),
        f.text("title", "Title", { required: true, list: true }),
        f.text("doc_number", "Number", { list: true }),
        f.text("issued_by", "Issued by"),
        f.date("issued_on", "Issued on"),
        f.date("expires_on", "Valid till", { list: true }),
        f.int("remind_days", "Remind before (days)", { default: "30" }),
        f.ref("location_ref_id", "For location", "location"),
        vehicle("vehicle_id", "For vehicle"),
        party("party_id", "With party"),
        f.money("amount", "Amount / fee"),
        f.photos("files", "Scans / photos"),
        f.longtext("notes", "Notes"),
      ],
    },
  ],
};
