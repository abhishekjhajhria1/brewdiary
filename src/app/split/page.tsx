import type { Metadata } from "next";
import { Split } from "@/components/split/Split";

export const metadata: Metadata = { title: "Split", description: "Who owes whom — settle the night fairly." };

export default function Page() {
  return <Split />;
}
