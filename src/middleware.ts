// Two jobs, in order:
//
// 1) SUBDOMAIN ROUTING. The venue/bar dashboard is served from the `bar.`
//    subdomain (bar.bwdy.site in prod, bar.localhost:3000 in dev). We REWRITE
//    those requests onto the /venue route tree so the whole thing lives in this
//    same Next app + same Supabase project — the browser URL stays on bar.*.
//    This branch only fires for `bar.` hosts, so the main domain and localhost
//    behave EXACTLY as before.
//
// 2) ROUTE GUARDS (main domain). Only the SOCIAL interior (Together, Split,
//    parties) needs a session; signed-out visits there bounce to the landing.
//    Public by design: "/" (landing), /you + /bartender (they run fully on the
//    local diary), /p/<code> (party invites for non-users), /discover, /venue.
//    The protected set is an explicit list so broadening the matcher (needed for
//    the subdomain rewrite) can never accidentally guard a new route.
import { createServerClient } from "@supabase/ssr";
import { NextResponse, type NextRequest } from "next/server";

const PROTECTED = ["/together", "/split", "/party"];

function needsAuth(pathname: string): boolean {
  return PROTECTED.some((p) => pathname === p || pathname.startsWith(`${p}/`));
}

export async function middleware(req: NextRequest) {
  // ── 1) bar.* subdomain → /venue/* (rewrite; URL stays on the subdomain) ──
  const host = req.headers.get("host") ?? "";
  if (host.startsWith("bar.")) {
    const to = req.nextUrl.clone();
    if (!to.pathname.startsWith("/venue")) {
      to.pathname = to.pathname === "/" ? "/venue" : `/venue${to.pathname}`;
      return NextResponse.rewrite(to);
    }
    return NextResponse.next();
  }

  // ── 2) main domain: only the protected social routes run the auth check ──
  if (!needsAuth(req.nextUrl.pathname)) return NextResponse.next();

  const url = process.env.NEXT_PUBLIC_SUPABASE_URL;
  const anon = process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY;
  if (!url || !anon) return NextResponse.next(); // unconfigured env → local-only mode, no guards

  let res = NextResponse.next({ request: req });
  const supabase = createServerClient(url, anon, {
    cookies: {
      getAll: () => req.cookies.getAll(),
      setAll: (cookiesToSet) => {
        // keep refreshed tokens flowing to both the request and the response
        cookiesToSet.forEach(({ name, value }) => req.cookies.set(name, value));
        res = NextResponse.next({ request: req });
        cookiesToSet.forEach(({ name, value, options }) => res.cookies.set(name, value, options));
      },
    },
  });

  const {
    data: { user },
  } = await supabase.auth.getUser();

  if (!user) {
    const to = req.nextUrl.clone();
    to.pathname = "/";
    to.search = "";
    return NextResponse.redirect(to);
  }
  return res;
}

export const config = {
  // Run on all PAGE routes so the subdomain rewrite works; skip API + static
  // assets (anything under _next, or a path containing a dot like sw.js/icons).
  matcher: ["/((?!api|_next/static|_next/image|favicon.ico|.*\\..*).*)"],
};
