import type { PropsWithChildren } from "react";
import { BarChart3, Clock3, Inbox, LayoutDashboard, Settings2 } from "lucide-react";
import { Badge } from "../ui/badge";
import { Button } from "../ui/button";
import { NAV_LABELS } from "../../lib/labels";
import { cn } from "../../lib/utils";
import type { AppPage } from "../../types/navigation";

interface AppShellProps extends PropsWithChildren {
  currentPage: AppPage;
  onPageChange: (page: AppPage) => void;
  reviewCount: number;
  status: "loading" | "ready" | "error";
  statusLabel: string;
}

const NAV_ITEMS: Array<{ icon: typeof LayoutDashboard; page: AppPage }> = [
  { page: "today", icon: LayoutDashboard },
  { page: "timeline", icon: Clock3 },
  { page: "weekly", icon: BarChart3 },
  { page: "review", icon: Inbox },
  { page: "rules", icon: Settings2 },
];

export function AppShell({ children, currentPage, onPageChange, reviewCount, status, statusLabel }: AppShellProps) {
  return (
    <div className="grid min-h-screen grid-cols-[232px_minmax(0,1fr)] bg-background max-[760px]:grid-cols-1">
      <aside
        className="sticky top-0 flex h-screen flex-col gap-5 border-r bg-slate-950 px-4 py-5 text-slate-50 max-[760px]:static max-[760px]:h-auto"
        aria-label="주요 화면"
      >
        <div className="flex min-w-0 items-center gap-3">
          <span className="grid size-8 shrink-0 place-items-center rounded-md bg-primary text-sm font-black text-primary-foreground">
            F
          </span>
          <div>
            <h1 className="m-0 text-lg font-semibold leading-none tracking-normal">FlowPilot</h1>
            <p className="m-0 mt-1 text-xs font-semibold text-slate-400">로컬 활동 분석</p>
          </div>
        </div>

        <nav className="grid gap-1.5">
          {NAV_ITEMS.map(({ icon: Icon, page }) => {
            const label = NAV_LABELS[page];
            const badge = page === "review" && reviewCount > 0 ? reviewCount : null;

            return (
              <Button
                aria-current={currentPage === page ? "page" : undefined}
                aria-label={badge ? `${label} ${badge}` : label}
                className={cn(
                  "grid h-10 grid-cols-[20px_minmax(0,1fr)_auto] justify-start gap-2.5 px-2.5 text-left text-sm font-semibold text-slate-300 hover:bg-slate-800 hover:text-white",
                  currentPage === page && "bg-primary text-primary-foreground hover:bg-primary hover:text-primary-foreground",
                )}
                key={page}
                onClick={() => onPageChange(page)}
                type="button"
                variant="ghost"
              >
                <Icon aria-hidden="true" size={18} strokeWidth={2.2} />
                <span className="min-w-0 overflow-hidden text-ellipsis whitespace-nowrap">{label}</span>
                {badge ? (
                  <Badge className="min-w-6 justify-center bg-white/15 px-1.5 text-[0.72rem] text-white hover:bg-white/15">
                    {badge}
                  </Badge>
                ) : null}
              </Button>
            );
          })}
        </nav>

        <span className="mt-auto inline-flex min-h-9 items-center gap-2 rounded-full border border-slate-700 bg-slate-900 px-3 text-xs font-semibold text-slate-200">
          <span
            aria-hidden="true"
            className={cn(
              "size-2.5 rounded-full bg-slate-400",
              status === "ready" && "bg-emerald-400 shadow-[0_0_0_4px_rgba(52,211,153,0.16)]",
              status === "error" && "bg-destructive shadow-[0_0_0_4px_rgba(239,68,68,0.16)]",
            )}
          />
          {statusLabel}
        </span>
      </aside>
      <main className="min-w-0 p-5">{children}</main>
    </div>
  );
}
