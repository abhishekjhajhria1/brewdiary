"use client";

import Link from "next/link";
import { usePathname } from "next/navigation";
import { useEffect, useState } from "react";
import clsx from "clsx";
import { useAuth } from "@/lib/profile";

const TABS = [
  { href: "/", label: "Calendar" },
  { href: "/together", label: "Together", authed: true }, // social is sign-in-only
  { href: "/bartender", label: "Ninkasi" },
  { href: "/you", label: "You" },
];

export function TabBar() {
  const pathname = usePathname();
  const auth = useAuth();
  const [mounted, setMounted] = useState(false);
  useEffect(() => setMounted(true), []);

  // Wait for the session to resolve so the bar doesn't flash between layouts.
  // The venue dashboard (/venue) and the kiosk wall (/kiosk) carry no app chrome.
  if (!mounted || auth.status === "loading" || pathname.startsWith("/venue") || pathname.startsWith("/kiosk")) return null;

  // Guests still get the local diary — only the social tab needs an account.
  const tabs = TABS.filter((t) => !t.authed || auth.profile);

  return (
    <nav aria-label="Primary" className="fixed inset-x-0 bottom-0 z-40 px-4 pt-2 pb-[max(1rem,env(safe-area-inset-bottom))]">
      <div
        className={clsx(
          "glass mx-auto grid max-w-md overflow-hidden rounded-tile",
          tabs.length === 4 ? "grid-cols-4" : "grid-cols-3",
        )}
      >
        {tabs.map((t) => {
          const active = t.href === "/" ? pathname === "/" : pathname.startsWith(t.href);
          return (
            <Link
              key={t.href}
              href={t.href}
              aria-current={active ? "page" : undefined}
              className="relative flex flex-col items-center justify-center py-3.5"
            >
              {active && (
                <span aria-hidden className="absolute top-1 h-1 w-8 rounded-full bg-accent" />
              )}
              <span
                className={clsx(
                  "text-[11px] uppercase tracking-[0.14em] transition-colors",
                  active ? "font-medium text-ink" : "text-faint",
                )}
              >
                {t.label}
              </span>
            </Link>
          );
        })}
      </div>
    </nav>
  );
}
