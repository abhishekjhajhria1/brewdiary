"use client";

import Link from "next/link";
import { usePathname } from "next/navigation";
import { useEffect, useState } from "react";
import clsx from "clsx";
import { useProfile } from "@/lib/profile";

const TABS = [
  { href: "/", label: "Calendar" },
  { href: "/together", label: "Together" },
  { href: "/bartender", label: "Ninkasi" },
  { href: "/you", label: "You" },
];

export function TabBar() {
  const pathname = usePathname();
  const profile = useProfile();
  const [mounted, setMounted] = useState(false);
  useEffect(() => setMounted(true), []);

  // Hidden during onboarding — no nav until there's an account.
  if (!mounted || !profile) return null;

  return (
    <nav aria-label="Primary" className="fixed inset-x-0 bottom-0 z-40 px-4 pt-2 pb-[max(1rem,env(safe-area-inset-bottom))]">
      <div className="glass mx-auto grid max-w-md grid-cols-4 overflow-hidden rounded-tile">
        {TABS.map((t) => {
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
