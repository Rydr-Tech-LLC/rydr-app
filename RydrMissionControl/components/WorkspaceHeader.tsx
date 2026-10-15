"use client";
import Link from "next/link";
import { usePathname, useRouter } from "next/navigation";
import { useTransition } from "react";
import { ChevronRight, RefreshCw, Search } from "lucide-react";
export default function WorkspaceHeader({ role }: { role: string }) {
  const path = usePathname();
  const router = useRouter();
  const [pending, start] = useTransition();
  const parts = path.split("/").filter(Boolean);
  const names: Record<string, string> = {
    "campus-growth": "Campus Growth",
    "vehicle-library": "Vehicle Library",
    "payment-failures": "Payment Failures",
    "account-deletions": "Account Deletions",
    "beta-testers": "Beta Testers",
    all: "Directory",
    support: "Support Inbox",
    payouts: "Driver Payouts",
  };
  return (
    <header className="mc-topbar flex flex-wrap items-center justify-between gap-3 border-b border-line bg-white/90 px-4 py-4 sm:px-6 lg:px-10">
      <nav
        aria-label="Breadcrumb"
        className="flex min-w-0 items-center gap-2 text-xs text-muted"
      >
        <span className="hidden lg:inline">Workspace</span>
        {parts.map((part, i) => (
          <span key={i} className="flex min-w-0 items-center gap-2">
            <ChevronRight size={13} />
            <Link
              className="max-w-40 truncate capitalize hover:text-rydr-red"
              href={"/" + parts.slice(0, i + 1).join("/")}
              aria-current={i === parts.length - 1 ? "page" : undefined}
            >
              {names[part] ??
                (part.length > 24 ? "Profile" : part.replaceAll("-", " "))}
            </Link>
          </span>
        ))}
      </nav>
      <div className="flex items-center gap-2">
        {role !== "marketing" && (
          <Link
            href="/search"
            className="mc-search-link flex items-center gap-2 rounded-xl border border-line px-3 py-2 text-xs text-muted"
          >
            <Search size={15} />
            Search people, VIN, plates
          </Link>
        )}
        <button
          aria-label="Refresh page data"
          disabled={pending}
          onClick={() => start(() => router.refresh())}
          className="rounded-xl border border-line bg-white p-2 text-muted"
        >
          <RefreshCw size={16} className={pending ? "animate-spin" : ""} />
        </button>
      </div>
    </header>
  );
}
