import type { Metadata } from "next";
import { Circles } from "@/components/together/Circles";
import { RoomHeader } from "@/components/together/RoomHeader";

export const metadata: Metadata = { title: "Circles", description: "Private rooms for a few people." };

export default function Page() {
  return (
    <>
      <RoomHeader title="Circles" blurb="A few friends and one combined mosaic. You join with a code — there's no public discovery." />
      <Circles />
    </>
  );
}
