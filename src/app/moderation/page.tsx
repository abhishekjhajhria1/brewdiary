import type { Metadata } from "next";
import { Moderation } from "@/components/moderation/Moderation";

export const metadata: Metadata = { title: "Moderation", description: "Review reports and keep the community safe." };

export default function Page() {
  return <Moderation />;
}
