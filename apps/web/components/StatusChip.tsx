import { humanize } from "@/lib/format";

const COLORS: Record<string, string> = {
  draft: "bg-slate-100 text-slate-700 dark:bg-slate-800 dark:text-slate-200",
  submitted: "bg-sky-100 text-sky-800 dark:bg-sky-900/50 dark:text-sky-100",
  approved: "bg-emerald-100 text-emerald-800 dark:bg-emerald-900/50 dark:text-emerald-100",
  rejected: "bg-red-100 text-red-800 dark:bg-red-900/50 dark:text-red-100",
  sent_back: "bg-amber-100 text-amber-900 dark:bg-amber-900/50 dark:text-amber-100",
  cancelled: "bg-slate-200 text-slate-500 line-through dark:bg-slate-700",
  waiting: "bg-sky-100 text-sky-800 dark:bg-sky-900/50 dark:text-sky-100",
};

export function StatusChip({ status }: { status: string }) {
  return (
    <span className={`inline-flex items-center rounded-full px-2.5 py-0.5 text-xs font-medium ${COLORS[status] ?? COLORS.draft}`}>
      {status === "waiting" ? "Waiting to send" : humanize(status)}
    </span>
  );
}
