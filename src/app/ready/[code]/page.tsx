// The ready board — bwdy.site/ready/<code>, opened on a TV's browser or a tablet by the
// counter (059). Pickup numbers being made and ready, never a name or an order. Public:
// pickup_board() is anon-callable and takes one of the venue's pickup-point codes.
import type { Metadata } from "next";
import { ReadyBoard } from "@/components/ready/ReadyBoard";

export const metadata: Metadata = {
  title: { absolute: "Ready to collect" },
  robots: { index: false },
};

export default async function ReadyPage({ params }: { params: Promise<{ code: string }> }) {
  const { code } = await params;
  return <ReadyBoard code={code} />;
}
