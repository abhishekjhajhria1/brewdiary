import type { Metadata } from "next";
import Link from "next/link";
import { NightPage } from "@/components/together/nights/NightPage";

export const metadata: Metadata = { title: "A night", description: "The invitation, the room, and the recap." };

export default async function Page({ params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  return (
    <>
      <Link
        href="/together/nights"
        className="mb-2 inline-flex min-h-11 items-center gap-1.5 text-sm text-faint transition-colors hover:text-ink"
      >
        <span aria-hidden>←</span> Nights
      </Link>
      <NightPage nightId={id} />
    </>
  );
}
