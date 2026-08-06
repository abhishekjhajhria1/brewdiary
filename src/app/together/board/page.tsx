import type { Metadata } from "next";
import { FriendsBoard } from "@/components/together/FriendsBoard";
import { RoomHeader } from "@/components/together/RoomHeader";

export const metadata: Metadata = { title: "Board", description: "You and the friends who opted in." };

export default function Page() {
  return (
    <>
      <RoomHeader title="Board" blurb="Sparks come from variety — a new place, a new drink, a dry day. Never from drinking more, and never from what anyone spent." />
      <FriendsBoard />
    </>
  );
}
