"use client";

import Link from "next/link";
import { usePathname, useRouter } from "next/navigation";
import { signOut } from "firebase/auth";
import { clientAuth } from "@/lib/firebaseClient";

const NAV_ITEMS = [
  { href: "/dashboard", label: "Dashboard" },
  { href: "/drivers", label: "Driver Verification" },
  { href: "/drivers/all", label: "Drivers" },
  { href: "/riders", label: "Riders" },
  { href: "/promotions", label: "Promotions" },
  { href: "/campus-growth", label: "Campus Growth" },
  { href: "/reports", label: "Reports" },
  { href: "/analytics", label: "Analytics" },
  { href: "/payment-failures", label: "Payment Failures" },
  { href: "/support", label: "Support Inbox" },
  { href: "/account-deletions", label: "Account Deletions" },
  { href: "/vehicle-library", label: "Vehicle Library" },
  { href: "/waitlist", label: "Waitlist" },
  { href: "/beta-testers", label: "Beta Testers" },
  { href: "/search", label: "Search" },
  { href: "/settings", label: "Settings" }
];

export default function Sidebar({ email }: { email: string | null }) {
  const pathname = usePathname();
  const router = useRouter();

  async function handleSignOut() {
    await fetch("/api/session", { method: "DELETE" });
    await signOut(clientAuth).catch(() => {});
    router.push("/login");
    router.refresh();
  }

  return (
    <aside className="flex h-screen w-56 flex-shrink-0 flex-col border-r border-line bg-white">
      <div className="flex items-center gap-2 px-5 py-5">
        <div className="flex h-7 w-7 items-center justify-center rounded-md bg-gradient-to-br from-rydr-red to-rydr-burgundy text-xs font-bold text-white">
          R
        </div>
        <div>
          <p className="text-sm font-semibold leading-none text-ink">Mission Control</p>
          <p className="text-[11px] leading-none text-muted">Rydr Internal</p>
        </div>
      </div>

      <nav className="flex-1 space-y-0.5 px-3">
        {NAV_ITEMS.map((item) => {
          const active = pathname === item.href || (item.href !== "/dashboard" && pathname?.startsWith(item.href));
          return (
            <Link
              key={item.href}
              href={item.href}
              className={`block rounded-md px-3 py-2 text-sm font-medium transition ${
                active ? "bg-ink text-white" : "text-muted hover:bg-grouped hover:text-ink"
              }`}
            >
              {item.label}
            </Link>
          );
        })}
      </nav>

      <div className="border-t border-line px-3 py-3">
        <p className="truncate px-2 text-[11px] text-muted">{email}</p>
        <button
          onClick={handleSignOut}
          className="mt-1 w-full rounded-md px-2 py-1.5 text-left text-xs font-medium text-muted hover:bg-grouped hover:text-ink"
        >
          Sign out
        </button>
      </div>
    </aside>
  );
}
