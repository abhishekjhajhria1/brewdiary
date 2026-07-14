// The terms of service. Both app stores require one, and so does taking money later.
//
// Written from what the code ACTUALLY does — same rule as /privacy. Every promise
// here is one the app keeps, and the ones that matter (a bar can't verify itself, a
// guest can't punch their own card, an unlawful perk can't be created) are enforced
// by the DATABASE, not by this page.
//
// Two audiences, and they need different things said to them:
//   • a PERSON keeping a diary — mostly needs to know it's theirs and we won't sell it,
//   • a VENUE running a loyalty card — needs to know THEY hold the licence, THEY are
//     liable, and we refuse to build them an illegal perk even if they ask for one.
//
// ⚠ Needs a lawyer's eye before public launch. This is a good-faith plain-English
//   draft, not advice — see internal/legal-and-compliance.md.
import type { Metadata } from "next";
import Link from "next/link";

export const metadata: Metadata = {
  title: "Terms", // bare — the root template brands it
  description: "The deal between you and brewdiary, in plain English.",
};

const UPDATED = "14 July 2026";

export default function TermsPage() {
  return (
    // age-exempt: readable without passing the age gate — see lib/age.ts.
    <main className="age-exempt mx-auto max-w-2xl px-5 py-12 sm:py-16">
      <Link href="/" className="text-sm text-faint transition-colors hover:text-ink">
        ← brewdiary
      </Link>

      <h1 className="mt-6 font-display text-4xl leading-tight tracking-tight text-ink">Terms</h1>
      <p className="mt-2 text-sm text-faint">Last updated {UPDATED}</p>

      <p className="mt-6 text-[15px] leading-relaxed text-muted">
        The deal, in one line: <strong className="text-ink">brewdiary is a diary you own.</strong> We keep it
        working and private; you keep it honest and lawful. Everything below is the long version, and it&apos;s
        written to be read — if a clause here needs a lawyer to decode, that&apos;s our failure, not yours.
      </p>

      <Section title="Who can use it">
        <P>
          You must be old enough to drink alcohol where you are. That&apos;s{" "}
          <B>18 in most of the world, 21 in India and the United States, 20 in Japan</B> — the app asks once and
          holds you to the local answer. If alcohol is prohibited where you are, the diary still works for coffee,
          tea and everything else; the bar features simply don&apos;t exist there.
        </P>
        <P>
          Don&apos;t lie about your age to get in. It&apos;s the one place in this app where the honest answer is
          the only thing protecting you.
        </P>
      </Section>

      <Section title="Your diary is yours">
        <P>
          <B>You own what you write.</B> Your entries, notes and photos are yours. We store them so you can get
          them back on another device, and that&apos;s the whole of our interest in them.
        </P>
        <P>
          <B>We don&apos;t sell it, and we don&apos;t advertise at you.</B> Not to brands, not to bars, not to
          anyone. There is no ad product here and there is not going to be one.
        </P>
        <P>
          <B>You can leave with everything, or leave nothing behind.</B> Export the lot as a file, or delete your
          account and every row of it goes. See <Link href="/privacy" className="text-ink underline underline-offset-2">privacy</Link>.
        </P>
      </Section>

      <Section title="What we ask of you">
        <P>Don&apos;t use brewdiary to:</P>
        <ul className="space-y-1.5 text-[15px] leading-relaxed text-muted">
          <Li>log or post on someone else&apos;s behalf without them knowing;</Li>
          <Li>harass anyone, or use a room, a comment or a public profile to get at someone;</Li>
          <Li>pretend to be a bar you don&apos;t work at, or a person you aren&apos;t;</Li>
          <Li>scrape it, resell it, or wire it into something that does.</Li>
        </ul>
        <P>
          If you do, we&apos;ll close the account. We&apos;d rather explain than ban, but we&apos;ll ban.
        </P>
      </Section>

      <Section title="Drinking is your business, not ours">
        <P>
          <B>brewdiary is a diary, not a health app and not a doctor.</B> Streaks, mosaics, weekly balance and
          gentle limits are a mirror — they describe what you did. They are not medical advice, and nothing here
          is a judgement about whether you should be drinking.
        </P>
        <P>
          <B>Nothing in this app rewards you for drinking more.</B> That&apos;s a design rule, not a slogan:
          sparks are earned for <em>variety</em> — a new place, a new drink, a dry day — and never for how often
          or how much you drink. A dry day keeps your streak alive. A bar&apos;s loyalty card counts{" "}
          <em>visits</em>, not drinks and not money.
        </P>
        <P>
          If your drinking is worrying you, please talk to someone real. We can&apos;t help with that and we
          won&apos;t pretend to.
        </P>
      </Section>

      <Section title="If you run a bar or a bottle shop">
        <P>
          The venue dashboard is a separate deal, and the important part is this:{" "}
          <B>you hold the licence, so you carry the liability.</B> We give you tools; we can&apos;t give you
          permission.
        </P>
        <P>
          <B>We will refuse to build you an illegal perk.</B> Alcohol promotion law is national and often
          sub-national, and we enforce it in the database rather than trusting a form. A bar in Ireland or the UK
          cannot set an alcoholic reward. A bar in Thailand, Norway or Poland gets no loyalty card at all. A bar
          in Northern Ireland gets none either — Article 57ZB reaches every licensed premises. An off-licence
          anywhere gets a <em>visits</em> card with a <em>non-alcoholic</em> reward, or nothing. If we
          haven&apos;t researched your jurisdiction, the answer is no until we have. Silence means no.
        </P>
        <P>
          <B>You verify; you don&apos;t self-verify.</B> A venue cannot mark itself verified — we check, by hand,
          and only a verified venue can hand out a reward or record anything against a guest.
        </P>
        <P>
          <B>You can&apos;t see your guests as individuals.</B> Insights are counts, suppressed below five people
          so a number can never identify one. Staff thanks arrive as a single total for the whole team — you
          cannot get a per-person league table out of this app, by design, and not even by asking us.
        </P>
        <P>
          <B>A tab is something you record, never something a guest claims.</B> Only your staff can put a spend or
          a visit on a guest&apos;s card. That&apos;s enforced server-side, so nobody can hand themselves a free
          drink on your dime.
        </P>
      </Section>

      <Section title="Ninkasi">
        <P>
          Ninkasi is a language model with a personality, not a sommelier and not a bartender who knows you. It
          will be confidently wrong sometimes. Don&apos;t take a recommendation from it as fact, and don&apos;t
          ask it anything you&apos;d be upset to see be wrong.
        </P>
        <P>It never sees your diary unless you paste something into it. It has no memory between conversations.</P>
      </Section>

      <Section title="The boring necessary part">
        <P>
          <B>The app is provided as it is.</B> We work hard to keep it up and correct, but we can&apos;t promise
          it will never lose a day, never go down, or never get something wrong. Keep an export if your diary
          matters to you — the button is right there in <Link href="/you" className="text-ink underline underline-offset-2">You</Link>.
        </P>
        <P>
          <B>To the extent the law allows,</B> we&apos;re not liable for indirect or consequential loss arising
          from using brewdiary. Nothing here limits liability we&apos;re not allowed to limit — including for
          death, personal injury, or fraud.
        </P>
        <P>
          <B>We can change these terms.</B> If we change something that matters, we&apos;ll say so in the app
          rather than quietly moving the date at the top.
        </P>
        <P>
          <B>You can stop any time</B>, and so can we — if we close your account for a reason other than one of
          the things listed above, you get your data out first.
        </P>
      </Section>

      <Section title="Reaching a human">
        <P>
          Questions, complaints, a bar with a jurisdiction we haven&apos;t researched, or a legal notice:{" "}
          <a href="mailto:hello@bwdy.site" className="text-ink underline underline-offset-2">
            hello@bwdy.site
          </a>
          . A person reads it.
        </P>
      </Section>

      <p className="mt-10 border-t border-line pt-5 text-xs leading-relaxed text-faint">
        Governed by the laws of India. If you&apos;re in the EU or the UK, this doesn&apos;t take away the
        consumer rights your own country gives you — those come first, whatever this page says.
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
