"use client";

import { useParams } from "next/navigation";
import { PartyRoom } from "@/components/together/PartyRoom";

export default function Page() {
  const { id } = useParams<{ id: string }>();
  return <PartyRoom partyId={id} />;
}
