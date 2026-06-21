import type { PropsWithChildren } from "react";
import { BarChart3, Clock3, Inbox, LayoutDashboard, Settings2 } from "lucide-react";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Separator } from "@/components/ui/separator";
import { cn } from "@/lib/utils";
import { NAV_LABELS } from "../../lib/labels";
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
    <div className="grid min-h-screen grid-cols-[236px_minmax(0,1fr)] bg-background max-lg:grid-cols-[84px_minmax(0,1fr)] max-md:grid-cols-1">
      <aside
        className="sticky top-0 flex h-screen flex-col gap-4 border-r bg-slate-950 px-4 py-5 text-slate-50 max-md:static max-md:h-auto"
        aria-label="주요 화면"
      >
        <div className="flex min-w-0 items-center gap-3 px-1">
          <span className="grid size-9 shrink-0 place-items-center rounded-lg bg-primary text-sm font-black text-primary-foreground shadow">
            F
          </span>
          <div className="min-w-0 max-lg:hidden max-md:block">
            <h1 className="m-0 text-base font-bold leading-tight tracking-normal">FlowPilot</h1>
            <p className="m-0 mt-1 text-xs font-semibold text-slate-400">로컬 활동 분석</p>
          </div>
        </div>

        <Separator className="bg-slate-800" />

        <nav className="grid gap-1">
          {NAV_ITEMS.map(({ icon: Icon, page }) => {
            const label = NAV_LABELS[page];
            const badge = page === "review" && reviewCount > 0 ? reviewCount : null;

            return (
              <Button
                aria-current={currentPage === page ? "page" : undefined}
                aria-label={badge ? `${label} ${badge}` : label}
                className={cn(
                  "relative h-10 justify-start gap-3 px-3 text-sm font-semibold text-slate-300 hover:bg-slate-800 hover:text-white max-lg:justify-center max-lg:px-0 max-md:justify-start max-md:px-3",
                  currentPage === page && "bg-primary text-primary-foreground shadow hover:bg-primary hover:text-primary-foreground",
                )}
                key={page}
                onClick={() => onPageChange(page)}
                type="button"
                variant="ghost"
              >
                <Icon aria-hidden="true" size={18} strokeWidth={2.2} />
                <span className="min-w-0 truncate max-lg:hidden max-md:inline">{label}</span>
                {badge ? (
                  <Badge className="ml-auto bg-white/15 text-white max-lg:absolute max-lg:right-1 max-lg:top-1 max-lg:px-1.5 max-lg:py-0 max-lg:text-[10px] max-md:static max-md:ml-auto">
                    {badge}
                  </Badge>
                ) : null}
              </Button>
            );
          })}
        </nav>

        <span
          className={cn(
            "mt-auto inline-flex min-h-9 items-center gap-2 rounded-full border border-slate-700 bg-slate-900 px-3 text-xs font-semibold text-slate-200 max-lg:justify-center max-lg:px-0 max-md:justify-start max-md:px-3",
          )}
        >
          <span
            aria-hidden="true"
            className={cn(
              "size-2.5 rounded-full bg-slate-500",
              status === "ready" && "bg-emerald-400 shadow-[0_0_0_4px_rgba(52,211,153,0.16)]",
              status === "error" && "bg-red-400 shadow-[0_0_0_4px_rgba(248,113,113,0.16)]",
            )}
          />
          <span className="max-lg:hidden max-md:inline">{statusLabel}</span>
        </span>
      </aside>
      <main className="min-w-0 p-6 max-md:p-4">{children}</main>
    </div>
  );
}
