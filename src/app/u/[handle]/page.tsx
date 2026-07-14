// A public profile page — /u/<handle>. Public (no auth): the middleware guards
// only /together,/split,/party, so this is open, and public_profile() is anon-
// callable. Server component unwraps the handle; the client PublicProfile renders.
import type { Metadata } from "next";
import { PublicProfile } from "@/components/profile/PublicProfile";

export async function generateMetadata({ params }: { params: Promise<{ handle: string }> }): Promise<Metadata> {
  const { handle } = await params;
  return { title: `@${handle} · brewdiary` };
}

export default async function ProfilePage({ params }: { params: Promise<{ handle: string }> }) {
  const { handle } = await params;
  return <PublicProfile handle={handle} />;
}
