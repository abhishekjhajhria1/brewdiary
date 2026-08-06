import type { Metadata } from "next";
import { Nights } from "@/components/together/nights/Nights";
import { RoomHeader } from "@/components/together/RoomHeader";

export const metadata: Metadata = { title: "Nights", description: "Tonight, what's coming up, and the recaps." };

export default function Page() {
  return (
    <>
      <RoomHeader title="Nights" blurb="Tonight, what's coming up, and everything you've already had." />
      <Nights />
    </>
  );
}
