// The privacy policy. Required by GDPR (Arts. 12–14), India's DPDP Act 2023, and
// by both app stores — you cannot ship without one, and a generic template is
// worse than useless because it will describe an app we didn't build.
//
// This one is written from what the code ACTUALLY does. If you change what the app
// collects, change this page in the same commit. Every claim here is checkable
// against a file, and the ones that matter are enforced by the database, not by
// our good intentions.
//
// ⚠ It still needs a lawyer's eye before public launch — see internal/legal-and-compliance.md.
import type { Metadata } from "next";
import Link from "next/link";

export const metadata: Metadata = {
  title: "Privacy — brewdiary",
  description: "What brewdiary collects, why, and how to get rid of it.",
};

const UPDATED = "14 July 2026";

export default function PrivacyPage() {
  return (
    // age-exempt: readable without passing the age gate — see lib/age.ts.
    <main className="age-exempt mx-auto max-w-2xl px-5 py-12 sm:py-16">
      <Link href="/" className="text-sm text-faint transition-colors hover:text-ink">
        ← brewdiary
      </Link>

      <h1 className="mt-6 font-display text-4xl leading-tight tracking-tight text-ink">Privacy</h1>
      <p className="mt-2 text-sm text-faint">Last updated {UPDATED}</p>

      <p className="mt-6 text-[15px] leading-relaxed text-muted">
        brewdiary is a diary of what you drink. A diary only works if it&apos;s yours, so the short version is
        this: <strong className="text-ink">everything you log is private by default</strong>, every social or
        public feature is off until you switch it on, and you can take your data or destroy it at any time.
      </p>

      <Section title="What we hold">
        <P>
          <B>Your account.</B> An email address and password (handled by Supabase Auth — we never see the
          password), a handle, and a display name.
        </P>
        <P>
          <B>Your diary.</B> The drinks you log: the name, the day, and anything optional you add — a mood, a
          note, a photo, a place, who you were with. This is the heart of it, and it is private to you unless
          you deliberately share an entry.
        </P>
        <P>
          <B>Social, only if you use it.</B> Friendships, circles, parties, cheers and comments. Splitting a
          tab stores the amounts and who owed what.
        </P>
        <P>
          <B>Points and tabs, only in a venue&apos;s room.</B> Sparks and vibe are counts. A tab is a figure a
          bar recorded — <em>you cannot enter your own spend</em>, by design (the database gives the app no
          way to write it).
        </P>
        <P>
          <B>Not your date of birth.</B> The age check computes your age, compares it to the legal drinking age
          where you are, and discards the date. Only a yes/no stays, on your device.
        </P>
      </Section>

      <Section title="What stays on your device and never reaches us">
        <P>
          Your <B>goals</B> (a weekly limit, dry days), your <B>extras</B> toggles, your currency and country,
          and the age confirmation. A private intention shouldn&apos;t need a server.
        </P>
      </Section>

      <Section title="What is off until you turn it on">
        <P>
          Every loud feature is opt-in, defaults to off, and is independent of the others — turning one on
          never turns on another:
        </P>
        <ul className="mt-2 space-y-1.5 text-[15px] leading-relaxed text-muted">
          <Li>Sharing an entry with friends, a circle, or a party.</Li>
          <Li>
            Appearing on a bar&apos;s wall screen. This is granted <B>inside one room, for that night</B>, and it
            expires when the bar&apos;s board closes — there is deliberately no permanent &ldquo;always show me&rdquo;
            setting.
          </Li>
          <Li>Showing your tab beside your name on that screen. Needs the switch above as well; either alone shows nothing.</Li>
          <Li>The leaderboard in Together — and only friends who also opted in ever appear on it.</Li>
          <Li>A public profile at /u/your-handle (counts only — never your notes, spend, or where you were).</Li>
          <Li>Helping train Ninkasi, our AI bartender, with your chats.</Li>
          <Li>Counting your diary in anonymous taste trends (which only ever report a drink once at least three different people logged it).</Li>
        </ul>
      </Section>

      <Section title="What a bar can see about you">
        <P>
          If you join a venue&apos;s room, its staff see <B>your name in that room</B> — they need it to hand
          you a perk or record your tab. They also see your standing toward <em>their own</em> reward.
        </P>
        <P>
          Beyond that, a bar only ever gets <B>counts</B>: how many people came, how many were new, how many
          rewards are waiting. Never a list of who. And when too few people came for a count to be safe — fewer
          than five — we <B>hide it rather than round it</B>, because &ldquo;one new guest&rdquo; would be
          pointing at a person.
        </P>
        <P>
          A bar <B>never</B> learns what you do anywhere else — not at another bar, and not in your diary. We
          will not build a list of customers who stopped coming, and we will not let a venue push offers at
          you.
        </P>
      </Section>

      <Section title="What we never do">
        <P>
          We don&apos;t sell your data. We don&apos;t run advertising trackers. There is no field anywhere for a
          phone number or an address, so they cannot be shared even by accident. And there is no negative
          rating of anyone, ever — not of a guest, and not of a bartender: a bar can praise a customer but
          never mark one, and a customer can thank a bartender but never complain about one through us.
        </P>
      </Section>

      <Section title="The AI (Ninkasi)">
        <P>
          Your message goes to our server, which asks a model provider to answer. The model is a stateless text
          function — it has no access to any database. We only keep a conversation to improve Ninkasi if you
          left &ldquo;Help train Ninkasi&rdquo; on, and you can delete that at any time from You → settings.
        </P>
      </Section>

      <Section title="Your rights — and where the buttons are">
        <P>
          Wherever you live, you can <B>download everything we hold about you</B> and <B>delete your account</B>
          from <Link href="/you" className="text-accent underline-offset-4 hover:underline">You → Your data</Link>.
          Deletion is immediate and real: the account is destroyed, and the diary, photos, friendships and
          points go with it. We can&apos;t undo it, so take a copy first if you want one.
        </P>
        <P>
          If you&apos;re in the EU/UK you also have rights of access, rectification, restriction, objection and
          portability under the GDPR; in India, the DPDP Act 2023 gives you access, correction and erasure. The
          two buttons above cover access, portability and erasure directly. For anything else, write to us.
        </P>
      </Section>

      <Section title="Where it lives">
        <P>
          Data is stored with <B>Supabase</B> (Postgres and file storage) and the app is served by{" "}
          <B>Vercel</B>. Row-Level Security means the database itself refuses to hand over rows you aren&apos;t
          allowed to see — the protection is in the data layer, not just in our code.
        </P>
      </Section>

      <Section title="Children">
        <P>
          brewdiary is for people over the legal drinking age where they live — 21 in the United States and much
          of India, 20 in Japan, 19 in Korea and most of Canada, 18 across much of Europe. It is not for
          children, and we don&apos;t knowingly keep data from them.
        </P>
      </Section>

      <Section title="Contact">
        <P>
          Questions, or a request about your data:{" "}
          <a href="mailto:hello@bwdy.site" className="text-accent underline-offset-4 hover:underline">
            hello@bwdy.site
          </a>
          .
        </P>
      </Section>

      <p className="mt-10 border-t border-line pt-5 text-xs leading-relaxed text-faint">
        If we change what we collect, we&apos;ll change this page and move the date at the top.
      </p>
    </main>
  );
}

function Section({ title, children }: { title: string; children: React.ReactNode }) {
  return (
    <section className="mt-9">
      <h2 className="font-display text-xl text-ink">{title}</h2>
      <div className="mt-2 space-y-3">{children}</div>
    </section>
  );
}
const P = ({ children }: { children: React.ReactNode }) => (
  <p className="text-[15px] leading-relaxed text-muted">{children}</p>
);
const B = ({ children }: { children: React.ReactNode }) => (
  <strong className="font-medium text-ink">{children}</strong>
);
const Li = ({ children }: { children: React.ReactNode }) => (
  <li className="flex gap-2">
    <span className="text-faint">·</span>
    <span>{children}</span>
  </li>
);
