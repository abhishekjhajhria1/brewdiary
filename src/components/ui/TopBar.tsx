"use client";

import Link from "next/link";
import { usePathname } from "next/navigation";
import { useEffect, useState } from "react";
import clsx from "clsx";
import { useProfile } from "@/lib/profile";
import { ThemeToggle } from "./ThemeToggle";

export function TopBar() {
  const pathname = usePathname();
  const profile = useProfile();
  const [mounted, setMounted] = useState(false);
  useEffect(() => setMounted(true), []);
  const onDiscover = pathname.startsWith("/discover");

  // Hidden during onboarding (logged out) — the landing carries its own header.
  if (!mounted || !profile) return null;

  return (
    <div className="glass mb-6 flex items-center justify-between rounded-tile px-4 py-2.5">
      <Link href="/" className="font-display text-lg italic text-muted transition-colors hover:text-ink">
        brewdiary
      </Link>

      <div className="flex items-center gap-1.5">
        <Link
          href={onDiscover ? "/" : "/discover"}
          aria-label={onDiscover ? "Close Discover" : "Open Discover"}
          className={clsx(
            "rounded-full px-4 py-1.5 text-xs font-medium uppercase tracking-[0.14em] transition-all duration-200 ease-out",
            onDiscover
              ? "glass glass-press text-muted hover:text-ink"
              : "bg-accent text-accent-contrast shadow-[0_3px_18px_-5px_var(--accent),inset_0_1px_0_rgba(255,255,255,0.28)] hover:-translate-y-px hover:shadow-[0_6px_24px_-5px_var(--accent),inset_0_1px_0_rgba(255,255,255,0.28)] active:translate-y-0",
          )}
        >
          {onDiscover ? "Close" : "Discover"}
        </Link>
        <ThemeToggle />
      </div>
    </div>
  );
}
