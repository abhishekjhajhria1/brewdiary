import type { Metadata } from "next";
import { Cups } from "@/components/together/Cups";
import { RoomHeader } from "@/components/together/RoomHeader";

export const metadata: Metadata = { title: "Cups", description: "Small exploration contests with friends." };

export default function Page() {
  return (
    <>
      <RoomHeader title="Cups" blurb="A small contest you make yourself — name it, pick what it scores on, set a window." />
      <Cups />
    </>
  );
}
