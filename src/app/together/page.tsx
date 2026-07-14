import type { Metadata } from "next";
import { Together } from "@/components/together/Together";

export const metadata: Metadata = { title: "Together", description: "Friends, circles and tonight's rooms." };

export default function Page() {
  return <Together />;
}
