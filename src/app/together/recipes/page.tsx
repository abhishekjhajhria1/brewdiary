import type { Metadata } from "next";
import { Recipes } from "@/components/together/Recipes";
import { RoomHeader } from "@/components/together/RoomHeader";

export const metadata: Metadata = { title: "Recipes", description: "Drinks your friends invented, and yours." };

export default function Page() {
  return (
    <>
      <RoomHeader title="Recipes" blurb="Drinks your friends invented, and yours." />
      <Recipes />
    </>
  );
}
