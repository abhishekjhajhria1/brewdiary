// The kiosk wall screen — bwdy.site/kiosk/<code>, a public (no-auth) route a
// venue casts to a TV. Server component unwraps the room code; the client
// KioskBoard polls the anon room_board rpc and renders full-screen.
import type { Metadata } from "next";
import { KioskBoard } from "@/components/kiosk/KioskBoard";

export const metadata: Metadata = {
  title: "brewdiary · the room",
  robots: { index: false },
};

export default async function KioskPage({ params }: { params: Promise<{ code: string }> }) {
  const { code } = await params;
  return <KioskBoard code={code} />;
}
