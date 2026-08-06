"use client";

// "Needs you" — the one place that tells you you're needed.
//
// Four queues used to live in four rooms (friend requests under Feed, join requests
// inside a plan, guests at the door inside a party, invites nowhere at all). Here
// they are one list you can clear without leaving the page: every row is a person, a
// plain sentence about what they want, and two buttons.
//
// Deliberately boring when empty — it renders NOTHING rather than an "all caught up!"
// trophy. An inbox that congratulates you for having no mail is an inbox that wants
// to be checked, and this one has no interest in being checked.
import { useState } from "react";
import Link from "next/link";
import { useInbox, acceptItem, dismissItem, INBOX_VERBS, inboxLine, type InboxItem } from "@/lib/inbox";

export function NeedsYou() {
  const { items, loading } = useInbox();
  if (loading || items.length === 0) return null;

  return (
    <section className="mt-6">
      <p className="label mb-2 text-faint">
        Needs you · <span className="tnum text-accent">{items.length}</span>
      </p>
      <ul className="space-y-2">
        {items.map((item) => (
          <li key={`${item.kind}-${item.refId}`}>
            <InboxRow item={item} />
          </li>
        ))}
      </ul>
    </section>
  );
}

function InboxRow({ item }: { item: InboxItem }) {
  const [busy, setBusy] = useState(false);
  const [err, setErr] = useState<string | null>(null);
  // Optimistic: the row goes the moment you decide. The refetch behind it will agree.
  const [gone, setGone] = useState(false);
  const verbs = INBOX_VERBS[item.kind];

  if (gone) return null;

  async function decide(yes: boolean) {
    if (busy) return;
    setBusy(true);
    const e = await (yes ? acceptItem(item) : dismissItem(item));
    if (e) {
      setBusy(false);
      setErr(e);
      return;
    }
    setGone(true);
  }

  const who = (
    <span className="min-w-0">
      <span className="block truncate text-[15px] text-ink">{item.actorName}</span>
      <span className="mt-0.5 block truncate text-xs text-faint">{inboxLine(item)}</span>
    </span>
  );

  return (
    <div className="glass rounded-tile px-4 py-3">
      <div className="flex items-center justify-between gap-3">
        {/* A night you're being asked about is worth a look before you answer. */}
        {item.subjectId && item.kind !== "room_request" ? (
          <Link href={`/together/night/${item.subjectId}`} className="min-w-0 flex-1">
            {who}
          </Link>
        ) : (
          <span className="min-w-0 flex-1">{who}</span>
        )}
        <span className="flex shrink-0 items-center gap-3 text-sm">
          <button
            onClick={() => decide(true)}
            disabled={busy}
            className="min-h-11 font-medium text-accent transition-opacity hover:opacity-80 disabled:opacity-50"
          >
            {verbs.yes}
          </button>
          <button
            onClick={() => decide(false)}
            disabled={busy}
            className="min-h-11 text-faint transition-colors hover:text-ink disabled:opacity-50"
          >
            {verbs.no}
          </button>
        </span>
      </div>
      {err && (
        <p role="alert" className="mt-1.5 text-sm text-accent">
          {err}
        </p>
      )}
    </div>
  );
}
