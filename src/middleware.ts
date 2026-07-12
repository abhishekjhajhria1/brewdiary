// Route guards — the server-side half of auth. Only the SOCIAL interior (Together,
// Split, parties) needs a session; signed-out visits there bounce to the landing.
// Public by design: "/" (landing), /you + /bartender (they run fully on the local
// diary — experience first, register at the moment of value), /p/<code> (party
// invites for non-users), /discover (a shop window).
import { createServerClient } from "@supabase/ssr";
import { NextResponse, type NextRequest } from "next/server";

export async function middleware(req: NextRequest) {
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
  matcher: ["/together", "/split", "/party/:path*"],
};
