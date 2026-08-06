import type { Metadata } from "next";
import { ToTryRoom } from "@/components/together/ToTry";
import { RoomHeader } from "@/components/together/RoomHeader";

export const metadata: Metadata = { title: "To try", description: "Drinks you mean to get to." };

export default function Page() {
  return (
    <>
      <RoomHeader title="To try" blurb="What friends poured that you haven't, and the list you keep yourself. Tap one to write it into your diary." />
      <ToTryRoom />
    </>
  );
}
