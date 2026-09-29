"use client";

// Resolves a table's code to its venue and table, then shows the menu with the table
// layer on (051). A stale or unknown code says so plainly.
import Link from "next/link";
import { useEffect, useState } from "react";
import { fetchTable, type TableInfo } from "@/lib/tableOrder";
import { MenuView } from "./MenuView";

export function TableMenu({ code }: { code: string }) {
  const [table, setTable] = useState<TableInfo | null | "missing" | "error">(null);

  useEffect(() => {
    let active = true;
    fetchTable(code)
      .then((t) => active && setTable(t ?? "missing"))
      .catch(() => active && setTable("error"));
    return () => {
      active = false;
    };
  }, [code]);

  if (table === null) {
    return (
      <main className="flex-1" aria-hidden>
        <div className="glass mb-6 h-20 animate-pulse rounded-tile" />
        <div className="glass h-64 animate-pulse rounded-tile" />
      </main>
    );
  }
  if (table === "missing" || table === "error") {
    return (
      <main className="flex-1 text-center">
        <p className="mt-16 font-display text-2xl text-ink">{table === "error" ? "Couldn't reach brewdiary." : "This table's link isn't live."}</p>
        <p className="mt-2 text-sm text-muted">
          {table === "error" ? "Check your connection and try again." : "The tag may have been replaced — ask your server for the menu."}
        </p>
        <Link href="/" className="mt-6 inline-block text-sm font-medium text-accent hover:opacity-80">
          Go to brewdiary →
        </Link>
      </main>
    );
  }
  return <MenuView slug={table.venueSlug} table={table} />;
}
