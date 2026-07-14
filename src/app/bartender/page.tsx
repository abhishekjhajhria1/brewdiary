import type { Metadata } from "next";
import { Bartender } from "@/components/bartender/Bartender";

export const metadata: Metadata = { title: "Ninkasi", description: "The house bartender. Ask it anything drinkable." };

export default function Page() {
  return <Bartender />;
}
