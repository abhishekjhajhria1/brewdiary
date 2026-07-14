// The invite link's metadata. /p/<code> is the ONE url people paste into a chat, so
// its preview matters more than any other page's — without this it unfurled as a
// bare "brewdiary" with no hint there's a party behind it. The page itself is a
// client component (it joins on tap), so the title lives here in the segment layout.
import type { Metadata } from "next";

export const metadata: Metadata = {
  title: "You're invited",
  description: "Someone saved you a seat. Open the invite to see tonight's room.",
};

export default function InviteLayout({ children }: { children: React.ReactNode }) {
  return children;
}
