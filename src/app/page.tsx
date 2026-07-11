// The gate, decided ON THE SERVER: the session lives in cookies (@supabase/ssr),
// so a returning diarist gets the calendar in the SSR HTML and a visitor gets the
// real landing — no client-side flash, no placeholder frame. (A stale cookie can
// briefly show the empty calendar shell; the client session then resolves it.)
import { cookies } from "next/headers";
import { CalendarHome } from "@/components/calendar/CalendarHome";
import { Landing } from "@/components/onboarding/Landing";

export default async function Page() {
  const store = await cookies();
  const authed = store.getAll().some((c) => /^sb-.+-auth-token/.test(c.name));
  return authed ? <CalendarHome /> : <Landing />;
}
