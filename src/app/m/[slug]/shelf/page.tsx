// A counter's shelf — /m/<slug>/shelf (059). What's in stock at a liquor store, sweet
// shop, bakery or shop, at its price — never how many are left. A list made here is
// shown as a QR at the till, where the staff scan it. Public: store_shelf() is
// anon-callable and only serves verified counters.
import type { Metadata } from "next";
import { ShelfView } from "@/components/menu/ShelfView";

export const metadata: Metadata = { title: "The shelf" };

export default async function ShelfPage({ params }: { params: Promise<{ slug: string }> }) {
  const { slug } = await params;
  return <ShelfView slug={slug} />;
}
