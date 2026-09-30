// A table's own link — /t/<code>. What a table's QR or NFC tag opens: the venue's
// menu with the table known, and (if the venue switched it on) ordering and calling
// staff from the phone. Public: table_info() is anon-callable; asking needs sign-in.
import type { Metadata } from "next";
import { TableMenu } from "@/components/menu/TableMenu";

export const metadata: Metadata = { title: "Menu" };

export default async function TablePage({ params }: { params: Promise<{ code: string }> }) {
  const { code } = await params;
  return <TableMenu code={code} />;
}
