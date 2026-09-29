// A venue's menu — /m/<slug>. What an NFC tag or QR on the table opens when the
// app isn't installed (with the app, the phone opens the menu there instead).
// Public: the middleware guards only /together,/split,/party, and venue_menu()
// is anon-callable. Never linked from Discover — see supabase/042_menus.sql.
import type { Metadata } from "next";
import { MenuView } from "@/components/menu/MenuView";

export const metadata: Metadata = { title: "Menu" };

export default async function MenuPage({ params }: { params: Promise<{ slug: string }> }) {
  const { slug } = await params;
  return <MenuView slug={slug} />;
}
