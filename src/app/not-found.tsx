// The 404. Without this file a mistyped URL gets Next's unstyled default — a white
// page with a black bar that looks like the app fell over. A wrong address isn't an
// emergency; this page should feel like the rest of the house: quiet, typographic,
// and pointing home.
import type { Metadata } from "next";
import Link from "next/link";

export const metadata: Metadata = { title: "Not found" }; // root template brands it

export default function NotFound() {
  return (
    // age-exempt: an error page must be readable without passing the age gate.
    <main className="age-exempt mx-auto flex min-h-[70dvh] max-w-md flex-col items-start justify-center px-6">
      <p className="label text-faint">404</p>
      <h1 className="mt-3 font-display text-3xl leading-tight tracking-tight text-ink">
        Nothing lives at this address.
      </h1>
      <p className="mt-3 text-[15px] leading-relaxed text-muted">
        The link may be old, or the letters may have wandered. Your diary is safe and exactly where you
        left it.
      </p>
      <Link
        href="/"
        className="mt-7 rounded-ctl bg-ink px-4 py-2.5 text-sm font-medium text-paper transition-opacity hover:opacity-90"
      >
        Back to the calendar
      </Link>
    </main>
  );
}
