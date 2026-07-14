import type { Metadata } from "next";
import { You } from "@/components/you/You";

export const metadata: Metadata = { title: "You", description: "Your profile, goals, extras and settings." };

export default function Page() {
  return <You />;
}
