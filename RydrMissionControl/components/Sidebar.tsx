"use client";

import Link from "next/link";
import { usePathname, useRouter } from "next/navigation";
import { signOut } from "firebase/auth";
import { useEffect, useState } from "react";
import { clientAuth } from "@/lib/firebaseClient";

const CAMPUS_GROWTH_ITEMS = [
  { href: "/campus-growth/discovery", label: "AI Discovery" },
  { href: "/campus-growth/outreach", label: "Outreach Inbox" },
  { href: "/campus-growth/organizations", label: "Organizations" },
  { href: "/campus-growth/events", label: "Events" },
  { href: "/campus-growth/ambassadors", label: "Ambassadors" },
  { href: "/campus-growth/campuses", label: "Campuses" }
];

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
  const [mobileOpen, setMobileOpen] = useState(false);

  useEffect(() => {
    setMobileOpen(false);
  }, [pathname]);

  useEffect(() => {
    if (!mobileOpen) return;
    const previousOverflow = document.body.style.overflow;
    const closeOnEscape = (event: KeyboardEvent) => {
      if (event.key === "Escape") setMobileOpen(false);
    };
    document.body.style.overflow = "hidden";
    window.addEventListener("keydown", closeOnEscape);
    return () => {
      document.body.style.overflow = previousOverflow;
      window.removeEventListener("keydown", closeOnEscape);
    };
  }, [mobileOpen]);

  async function handleSignOut() {
    await fetch("/api/session", { method: "DELETE" });
    await signOut(clientAuth).catch(() => {});
    router.push("/login");
    router.refresh();
  }

  const navigation = (
    <>
      <div className="flex items-center gap-2 px-5 py-5">
        <div className="flex h-7 w-7 items-center justify-center rounded-md bg-gradient-to-br from-rydr-red to-rydr-burgundy text-xs font-bold text-white">
          R
        </div>
        <div>
          <p className="text-sm font-semibold leading-none text-ink">Mission Control</p>
          <p className="text-[11px] leading-none text-muted">Rydr Internal</p>
        </div>
      </div>

      <nav className="min-h-0 flex-1 space-y-0.5 overflow-y-auto px-3 pb-3">
        {NAV_ITEMS.map((item) => {
          const active = pathname === item.href || (item.href !== "/dashboard" && pathname?.startsWith(item.href));
          return (
            <div key={item.href}>
              <Link
                href={item.href}
                className={`block rounded-md px-3 py-2 text-sm font-medium transition ${
                  active ? "bg-ink text-white" : "text-muted hover:bg-grouped hover:text-ink"
                }`}
              >
                {item.label}
              </Link>
              {item.href === "/campus-growth" && active && (
                <div className="mt-1 space-y-0.5 border-l border-line pl-3">
                  {CAMPUS_GROWTH_ITEMS.map((child) => {
                    const childActive = pathname === child.href;
                    return (
                      <Link
                        key={child.href}
                        href={child.href}
                        className={`block rounded-md px-3 py-1.5 text-xs font-medium transition ${
                          childActive ? "bg-red-50 text-rydr-red" : "text-muted hover:bg-grouped hover:text-ink"
                        }`}
                      >
                        {child.label}
                      </Link>
                    );
                  })}
                </div>
              )}
            </div>
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
    </>
  );

  return (
    <>
      <aside className="hidden h-screen w-56 flex-shrink-0 flex-col border-r border-line bg-white md:flex">
        {navigation}
      </aside>

      <header className="fixed inset-x-0 top-0 z-40 flex h-16 items-center justify-between border-b border-line bg-white/95 px-4 backdrop-blur md:hidden">
        <div className="flex min-w-0 items-center gap-2.5">
          <div className="flex h-8 w-8 flex-shrink-0 items-center justify-center rounded-md bg-gradient-to-br from-rydr-red to-rydr-burgundy text-xs font-bold text-white">
            R
          </div>
          <div className="min-w-0">
            <p className="truncate text-sm font-semibold leading-tight text-ink">Mission Control</p>
            <p className="truncate text-[11px] leading-tight text-muted">Rydr Internal</p>
          </div>
        </div>
        <button
          type="button"
          onClick={() => setMobileOpen(true)}
          className="flex h-11 w-11 flex-shrink-0 flex-col items-center justify-center gap-1.5 rounded-md border border-line bg-white"
          aria-label="Open navigation menu"
          aria-expanded={mobileOpen}
          aria-controls="mobile-navigation"
        >
          <span className="h-0.5 w-5 rounded-full bg-ink" />
          <span className="h-0.5 w-5 rounded-full bg-ink" />
          <span className="h-0.5 w-5 rounded-full bg-ink" />
        </button>
      </header>

      <button
        type="button"
        aria-label="Close navigation menu"
        onClick={() => setMobileOpen(false)}
        className={`fixed inset-0 z-40 bg-black/35 transition-opacity md:hidden ${
          mobileOpen ? "pointer-events-auto opacity-100" : "pointer-events-none opacity-0"
        }`}
      />
      <aside
        id="mobile-navigation"
        className={`fixed inset-y-0 left-0 z-50 flex w-[min(20rem,88vw)] flex-col border-r border-line bg-white shadow-lg transition-transform duration-200 md:hidden ${
          mobileOpen ? "translate-x-0" : "-translate-x-full"
        }`}
        aria-hidden={!mobileOpen}
      >
        <div className="absolute right-3 top-3 z-10">
          <button
            type="button"
            onClick={() => setMobileOpen(false)}
            className="relative flex h-10 w-10 items-center justify-center rounded-md border border-line bg-white"
            aria-label="Close navigation menu"
          >
            <span className="absolute h-0.5 w-5 rotate-45 rounded-full bg-ink" />
            <span className="absolute h-0.5 w-5 -rotate-45 rounded-full bg-ink" />
          </button>
        </div>
        {navigation}
      </aside>
    </>
  );
}
