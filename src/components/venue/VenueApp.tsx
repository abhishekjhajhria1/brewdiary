"use client";

// The venue/bar dashboard — served on bar.bwdy.site (middleware rewrites `bar.*`
// onto /venue). Option A auth: venue staff sign in ON this subdomain with a
// normal brewdiary account (its own-origin cookie); no cross-domain session.
//
// Three states: loading → skeleton; signed-out → the pitch + sign in/create;
// signed-in → your venues (claim one, manage the team). House style throughout.
import { useEffect, useState } from "react";
import clsx from "clsx";
import { useAuth, signIn, signUp, signOut, type Profile } from "@/lib/profile";
import {
  useMyVenues,
  useVenueStaff,
  useVenueInsights,
  useVerification,
  createVenue,
  updateVenue,
  removeStaff,
  enrolStaff,
  reissueStaffCode,
  revokeStaffEnrolment,
  approveStaff,
  declineStaff,
  lockStaff,
  unlockStaff,
  useOpenEnrolments,
  useStaffAccess,
  claimStaffCode,
  usePayroll,
  usePayRates,
  setStaffPay,
  type StaffCode,
  type VenueStaff,
  type StaffRole,
  deleteVenue,
  requestVerification,
  withdrawVerification,
  slugify,
  isValidSlug,
  type Venue,
} from "@/lib/venues";
import { searchUsers, type SocialProfile } from "@/lib/friends";
import { ROLE_LABEL, STAFF_ROLES, canGrant } from "@/lib/roles";
import { claimMessage, codeDigits, codeLifeLeft, enrolShareText, reportLine, roleWithArticle, validStaffEmail, validStaffPhone } from "@/lib/staffAccess";
import { useVenueRooms, createParty } from "@/lib/parties";
import { RoomQr } from "./RoomQr";
import { useMyKudos, useVenueKudosTotal, setThankable } from "@/lib/kudos";
import {
  useVenuePerks,
  addVenuePerk,
  removeVenuePerk,
  MAX_TIERS,
  perkPolicy,
  perkPolicyNote,
  usePerkTiers,
  redeemPerk,
  recordVisit,
  type PerkKind,
  type VenueKind,
} from "@/lib/perks";
import { KNOWN_COUNTRIES } from "@/lib/jurisdiction";
import { VENUE_KINDS, VENUE_KIND_LABEL, VENUE_KIND_BLURB, alcoholIsChoice, isCounter } from "@/lib/venueKinds";
import { currencyForCountry, currencySymbol, formatMoney } from "@/lib/money";
import {
  PAY_PERIODS,
  payPeriod,
  payrollCsv,
  payrollFileName,
  payrollFileText,
  payrollTotalCents,
  payrollTotals,
  minutesWords,
  todayIn,
  venueTimeZone,
  type PayPeriod,
} from "@/lib/payroll";
import { useRoomGuests, staffAwardVibe, recordSpend, STAFF_VIBE_REASONS } from "@/lib/points";
import { todayKey } from "@/lib/date";
import { peakDays, pctChange } from "@/lib/venueAdvisor";
import { requestLocationGeohash } from "@/lib/trends";
import { VENUE_PRECISION } from "@/lib/geohash";
import { VenueAdvisor } from "./VenueAdvisor";
import { GuestBook } from "./GuestBook";
import { VenueMenu } from "./VenueMenu";

// Written for a BAR OWNER, not for us. They care about three things: do people come
// back, does tonight feel good, and what does it cost me. Everything below answers
// one of those. No jargon, no "gamification", no promises we don't keep.
const SECTIONS: { name: string; blurb: string }[] = [
  {
    name: "They come back — and you decide why",
    blurb:
      "Set your own house perk: five visits, a free pour. A big tab, dessert on the house. It's private between you and that guest, it's your reward to give, and it's the whole reason regulars become regulars.",
  },
  {
    name: "Your staff can say thank you",
    blurb:
      "A bartender taps a guest's name and hands them a good word — \"kept it classy\", \"a pleasure to serve\". It's positive-only: you can praise a customer, you can never mark one. No ratings, no blacklist, not ever.",
  },
  {
    name: "A room for the night, and a screen on the wall",
    blurb:
      "Open a room, put the code on the table. Guests who join can appear on a board you cast to a TV — by choice, for that night only. Nobody's name lingers on your screen after closing.",
  },
  {
    name: "Numbers that tell you what to do",
    blurb:
      "Ninkasi reads your takings, your regulars, your quiet nights — the totals only, never a guest or a name — and tells you the one or two things worth doing next. A read of the books, not a file on your customers.",
  },
  {
    name: "Nobody is ranked by what they spent",
    blurb:
      "Points are for trying something new — a first visit, a drink they've never had. Not for drinking more. That's a deliberate line, and it's why we're a bar's friend rather than a liability.",
  },
  {
    name: "Free, and no till to touch",
    blurb:
      "No POS integration, no hardware, no fee. Your staff sign in on their own phones with an ordinary account. Set it up in ten minutes tonight.",
  },
];

// This dashboard is a TRADE tool, not the consumer app wearing a hat. It carries
// its own header (no Discover, no Calendar/Together/You nav — those are hidden by
// host, see lib/host.ts) and it says plainly whose product it is and who it's for.
function Header({ profile }: { profile?: Profile | null }) {
  return (
    <header className="mb-8 flex items-center justify-between border-b border-line pb-4">
      <span className="flex items-baseline gap-2">
        <span className="font-display text-lg italic text-muted">brewdiary</span>
        <span className="label text-accent">for bars</span>
      </span>
      <span className="flex items-center gap-3">
        {profile && (
          <>
            <span className="hidden text-xs text-faint sm:inline">@{profile.handle}</span>
            <button onClick={() => signOut()} className="text-sm text-faint transition-colors hover:text-ink">
              Sign out
            </button>
          </>
        )}
      </span>
    </header>
  );
}

export function VenueApp() {
  const auth = useAuth();

  if (auth.status === "loading") {
    return (
      <main className="flex-1" aria-hidden>
        <div className="mb-8 h-12 border-b border-line" />
        <div className="glass h-40 animate-pulse rounded-tile" />
      </main>
    );
  }

  return (
    <main className="flex-1">
      <Header profile={auth.profile} />
      {auth.profile ? <VenueHome me={auth.profile} /> : <VenueLanding />}
    </main>
  );
}

// ── signed-out: the pitch + sign in / create account ─────────────────────────
function VenueLanding() {
  return (
    <>
      <p className="label mb-2 text-faint">brewdiary for bars</p>
      <h1 className="font-display text-4xl leading-tight tracking-tight text-ink sm:text-5xl">
        Give your regulars a reason to be regulars.
      </h1>
      <p className="mt-3 max-w-prose text-[15px] leading-relaxed text-muted">
        brewdiary is a drink diary its people already carry. This is the side you run: a room for tonight, a
        reward that brings them back, and a way for your staff to thank the good ones. Free, and nothing to
        install.
      </p>

      <VenueAuth />

      <ul className="mt-10 space-y-3">
        {SECTIONS.map((s) => (
          <li key={s.name} className="glass rounded-tile p-5">
            <p className="font-display text-xl leading-tight text-ink">{s.name}</p>
            <p className="mt-1.5 max-w-prose text-[15px] leading-relaxed text-muted">{s.blurb}</p>
          </li>
        ))}
      </ul>

      <section className="mt-10">
        <h2 className="label mb-3 text-faint">How a night runs</h2>
        <ol className="glass divide-y divide-line rounded-tile px-5">
          {[
            "Open a room from your phone and put the code on the tables.",
            "Guests join. Your bartenders hand out a good word as they serve.",
            "Close a tab? Record it — only you can, so it counts toward their perk.",
            "Cast the board to a TV if you want the room to see it.",
            "They come back next week to claim what you promised them.",
          ].map((step, i) => (
            <li key={step} className="flex gap-3 py-3.5">
              <span className="tnum shrink-0 text-sm text-accent">{i + 1}</span>
              <span className="text-[15px] leading-relaxed text-muted">{step}</span>
            </li>
          ))}
        </ol>
        <p className="mt-3 text-xs leading-relaxed text-faint">
          One thing we ask: we verify a venue before it can hand out real-world rewards, so a guest always
          knows the perk on their screen is genuinely yours.
        </p>
      </section>
    </>
  );
}

// No `outline-none`: the global :focus-visible accent ring (globals.css) then
// shows on focus — keyboard users can see where they are.
const inputClass = "glass w-full rounded-ctl px-4 py-2.5 text-[15px] text-ink placeholder:text-faint";

function VenueAuth() {
  const [mode, setMode] = useState<"in" | "up">("in");
  const [name, setName] = useState("");
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [confirm, setConfirm] = useState(false);

  async function submit(e: React.FormEvent) {
    e.preventDefault();
    setBusy(true);
    setError(null);
    const res = mode === "up" ? await signUp(email, password, name) : await signIn(email, password);
    setBusy(false);
    if (!res.ok) {
      setError(res.error);
      return;
    }
    if ("needsConfirm" in res && res.needsConfirm) setConfirm(true);
    // on success the auth store flips and VenueApp re-renders to the dashboard
  }

  if (confirm) {
    return (
      <div className="glass mt-7 rounded-tile p-5">
        <p className="font-display text-xl text-ink">Check your inbox.</p>
        <p className="mt-1.5 text-sm text-muted">Confirm your email, then come back here and sign in to set up your venue.</p>
      </div>
    );
  }

  return (
    <form onSubmit={submit} className="glass mt-7 rounded-tile p-5">
      <p className="label mb-3 text-faint">{mode === "up" ? "Create an account" : "Sign in to your venue"}</p>
      <div className="space-y-2.5">
        {mode === "up" && (
          <div>
            <label htmlFor="v-name" className="sr-only">Your name</label>
            <input id="v-name" value={name} onChange={(e) => setName(e.target.value)} placeholder="Your name" className={inputClass} autoComplete="name" />
          </div>
        )}
        <div>
          <label htmlFor="v-email" className="sr-only">Email</label>
          <input id="v-email" type="email" required value={email} onChange={(e) => setEmail(e.target.value)} placeholder="Email" className={inputClass} autoComplete="email" />
        </div>
        <div>
          <label htmlFor="v-pass" className="sr-only">Password</label>
          <input id="v-pass" type="password" required value={password} onChange={(e) => setPassword(e.target.value)} placeholder="Password" className={inputClass} autoComplete={mode === "up" ? "new-password" : "current-password"} />
        </div>
      </div>

      {error && <p className="mt-2.5 text-sm text-accent">{error}</p>}

      <button
        type="submit"
        disabled={busy}
        className="mt-4 w-full rounded-ctl bg-ink px-4 py-2.5 text-sm font-medium text-paper transition-opacity hover:opacity-90 disabled:opacity-50"
      >
        {busy ? "One moment…" : mode === "up" ? "Create account" : "Sign in"}
      </button>

      <button
        type="button"
        onClick={() => { setMode((m) => (m === "in" ? "up" : "in")); setError(null); }}
        className="mt-3 text-sm text-faint transition-colors hover:text-ink"
      >
        {mode === "in" ? "New here? Create an account" : "Already have an account? Sign in"}
      </button>
    </form>
  );
}

// ── signed-in: your venues ───────────────────────────────────────────────────
function VenueHome({ me }: { me: Profile }) {
  const { venues, loading } = useMyVenues();
  const [openId, setOpenId] = useState<string | null>(null);
  const [creating, setCreating] = useState(false);

  if (loading) {
    return <div className="glass h-32 animate-pulse rounded-tile" />;
  }

  if (venues.length === 0 && !creating) {
    return (
      <>
        <StaffAccessPanel />
        <p className="label mb-2 text-faint">Welcome, {me.name}</p>
        <h1 className="font-display text-3xl leading-tight tracking-tight text-ink">Claim your venue.</h1>
        <p className="mt-3 max-w-prose text-[15px] leading-relaxed text-muted">
          Set up your bar so you can open rooms, hand out vibe, and cast the kiosk screen. Verification comes after.
        </p>
        <button
          onClick={() => setCreating(true)}
          className="mt-6 rounded-ctl bg-ink px-4 py-2.5 text-sm font-medium text-paper transition-opacity hover:opacity-90"
        >
          Set up my venue
        </button>
      </>
    );
  }

  return (
    <>
      <StaffAccessPanel />
      <div className="mb-5 flex items-end justify-between">
        <p className="label text-faint">Your venues</p>
        {!creating && (
          <button onClick={() => setCreating(true)} className="text-sm font-medium text-accent transition-opacity hover:opacity-80">
            Add venue
          </button>
        )}
      </div>

      {creating && <CreateVenue meId={me.id} onDone={() => setCreating(false)} />}

      <ul className="space-y-3">
        {venues.map((v) => (
          <VenueCard key={v.id} venue={v} meId={me.id} open={openId === v.id} onToggle={() => setOpenId((cur) => (cur === v.id ? null : v.id))} />
        ))}
      </ul>
    </>
  );
}

function CreateVenue({ meId, onDone }: { meId: string; onDone: () => void }) {
  const [name, setName] = useState("");
  const [slug, setSlug] = useState("");
  const [city, setCity] = useState("");
  const [kind, setKind] = useState<VenueKind>("bar");
  const [servesAlcohol, setServesAlcohol] = useState(false);
  const [country, setCountry] = useState("IN");
  const [region, setRegion] = useState("");
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  // The address preview follows the name until the owner types their own slug.
  const effectiveSlug = slug.trim() || slugify(name);
  const slugValid = isValidSlug(effectiveSlug);

  // Say NOW whether a loyalty card is even possible here, rather than letting them
  // set the shop up and hit a wall at the perk screen.
  const policy = perkPolicy(country, region, kind, servesAlcohol);
  const policyNote = perkPolicyNote(country, region, kind, servesAlcohol);

  async function submit(e: React.FormEvent) {
    e.preventDefault();
    setBusy(true);
    setError(null);
    const res = await createVenue(meId, {
      name,
      slug: slug.trim() || undefined,
      city,
      kind,
      servesAlcohol,
      country,
      region: region.trim() || undefined,
    });
    setBusy(false);
    if ("error" in res) {
      setError(res.error);
      return;
    }
    onDone();
  }

  return (
    <form onSubmit={submit} className="glass mb-4 rounded-tile p-5">
      <p className="label mb-3 text-faint">New venue</p>
      <div className="space-y-2.5">
        <input value={name} onChange={(e) => setName(e.target.value)} placeholder="Venue name" className={inputClass} aria-label="Venue name" />
        <input value={slug} onChange={(e) => setSlug(e.target.value.toLowerCase())} placeholder="web address (optional)" className={inputClass} aria-label="Web address slug" />
        <input value={city} onChange={(e) => setCity(e.target.value)} placeholder="City (optional)" className={inputClass} aria-label="City" />

        {/* What kind of place. Not cosmetic: a counter (a liquor store, a sweet shop, a
            bakery, a shop) runs no rooms; a liquor store's card needs its own legal
            permission, because at a shop a visit is a sale; a place that sells no alcohol
            is outside alcohol-promotion law altogether (047). */}
        <div className="glass grid grid-cols-2 gap-1 rounded-ctl p-1" role="group" aria-label="Venue kind">
          {VENUE_KINDS.map((k) => (
            <button
              key={k}
              type="button"
              onClick={() => setKind(k)}
              aria-pressed={kind === k}
              className={clsx(
                "rounded-[7px] px-3 py-2 text-left transition-colors",
                kind === k ? "bg-ink text-paper" : "text-faint hover:text-ink",
              )}
            >
              <span className="block text-sm font-medium">{VENUE_KIND_LABEL[k]}</span>
              <span className={clsx("block text-[11px]", kind === k ? "opacity-70" : "text-faint")}>{VENUE_KIND_BLURB[k]}</span>
            </button>
          ))}
        </div>
        {alcoholIsChoice(kind) && (
          <label className="flex items-center gap-2 px-1 text-sm text-muted">
            <input type="checkbox" checked={servesAlcohol} onChange={(e) => setServesAlcohol(e.target.checked)} />
            We serve alcohol (licensed)
          </label>
        )}

        <select
          value={country}
          onChange={(e) => setCountry(e.target.value)}
          aria-label="Country"
          className={inputClass}
        >
          {KNOWN_COUNTRIES.map((c) => (
            <option key={c.code} value={c.code}>
              {c.label}
            </option>
          ))}
        </select>

        {/* Two countries split internally in ways that change what's legal: US states
            (drink deals), and the UK — Northern Ireland bans loyalty rewards in every
            licensed premises, Scotland bans a shop's card. Getting this wrong fines
            the LICENSEE, so we ask rather than guess. */}
        {country === "US" && (
          <input
            value={region}
            onChange={(e) => setRegion(e.target.value.toUpperCase().slice(0, 2))}
            placeholder="State code (e.g. NY, MA)"
            aria-label="State"
            className={inputClass}
          />
        )}
        {country === "GB" && (
          <select value={region} onChange={(e) => setRegion(e.target.value)} aria-label="UK nation" className={inputClass}>
            <option value="">England or Wales</option>
            <option value="SCT">Scotland</option>
            <option value="NIR">Northern Ireland</option>
          </select>
        )}
      </div>

      {/* Tell them the rule BEFORE they build on it, not after. */}
      <p className="mt-2.5 text-xs leading-relaxed text-faint">
        {policyNote ??
          (policy.allowPerks
            ? "You'll be able to run a loyalty card here once you're verified."
            : "Where you are decides what kind of loyalty reward is legal. We'll show you the rule when you set your card.")}
      </p>

      {slugValid ? (
        <p className="mt-2.5 text-xs text-faint">
          Address: <span className="text-muted">bar.bwdy.site/{effectiveSlug}</span>
        </p>
      ) : (
        name.trim() && (
          <p className="mt-2.5 text-xs text-accent">Pick a web address with letters or numbers — 2 to 40 characters.</p>
        )
      )}
      {error && <p className="mt-2.5 text-sm text-accent">{error}</p>}

      <div className="mt-4 flex items-center gap-3">
        <button
          type="submit"
          disabled={busy || !name.trim() || !slugValid}
          className="rounded-ctl bg-ink px-4 py-2.5 text-sm font-medium text-paper transition-opacity hover:opacity-90 disabled:opacity-50"
        >
          {busy ? "Creating…" : "Create venue"}
        </button>
        <button type="button" onClick={onDone} className="text-sm text-faint transition-colors hover:text-ink">
          Cancel
        </button>
      </div>
    </form>
  );
}

function VenueCard({ venue, meId, open, onToggle }: { venue: Venue; meId: string; open: boolean; onToggle: () => void }) {
  const canManage = venue.myRole === "owner" || venue.myRole === "manager";
  return (
    <li className="glass rounded-tile p-5">
      <button onClick={onToggle} aria-expanded={open} className="flex w-full items-center justify-between gap-3 text-left">
        <span className="min-w-0">
          <span className="font-display text-xl leading-tight text-ink">{venue.name}</span>
          <span className="mt-0.5 block truncate text-xs text-faint">
            bar.bwdy.site/{venue.slug}
            {venue.city && <> · {venue.city}</>} · {venue.myRole}
          </span>
        </span>
        <span className={clsx("shrink-0 text-xs", venue.verified ? "text-accent" : "text-faint")}>
          {venue.verified ? "Verified" : "Not verified"}
        </span>
      </button>

      {open && <VenueManage venue={venue} meId={meId} canManage={canManage} />}
    </li>
  );
}

// The dashboard is used STANDING UP, mid-service, usually by a bartender on a
// phone behind the bar. So it opens on TONIGHT — the room, the guest list, the tab
// and vibe controls — and everything administrative (perks, team, setup) is a tab
// away rather than a scroll away. A bartender should never have to walk past the
// "delete venue" button to record someone's tab.
type Section = "tonight" | "menu" | "perks" | "team" | "insights" | "guests" | "setup";

function VenueManage({ venue, meId, canManage }: { venue: Venue; meId: string; canManage: boolean }) {
  const { staff } = useVenueStaff(venue.id);
  const [confirmDelete, setConfirmDelete] = useState(false);
  const [section, setSection] = useState<Section>("tonight");

  // A shop's first tab is the TILL, not the room — it has no rooms at all (the DB
  // refuses to attach one), because a bottle shop isn't a place you sit and drink.
  const store = isCounter(venue.kind);

  // A bartender only ever needs Tonight — the rest is a manager's job, so we don't
  // show them doors they can't open.
  const sections: { id: Section; label: string }[] = canManage
    ? [
        { id: "tonight", label: store ? "Till" : "Tonight" },
        { id: "menu", label: store ? "Shelf" : "Menu" },
        { id: "perks", label: store ? "Card" : "Perks" },
        { id: "insights", label: "Insights" },
        { id: "guests", label: "Guests" },
        { id: "team", label: "Team" },
        { id: "setup", label: "Setup" },
      ]
    : [{ id: "tonight", label: store ? "Till" : "Tonight" }];

  return (
    <div className="mt-4 border-t border-line pt-4">
      {!venue.verified && !canManage && (
        <p className="mb-4 text-xs leading-relaxed text-faint">
          This venue isn&apos;t verified yet — rooms and vibe work, but real-world perks wait until it is.
        </p>
      )}

      {sections.length > 1 && (
        <div className="glass mb-4 grid grid-cols-4 gap-1 rounded-ctl p-1">
          {sections.map((s) => (
            <button
              key={s.id}
              onClick={() => setSection(s.id)}
              aria-pressed={section === s.id}
              className={clsx(
                "rounded-[7px] py-2.5 text-[11px] font-medium uppercase tracking-[0.12em] transition-colors",
                section === s.id ? "bg-ink text-paper" : "text-faint hover:text-ink",
              )}
            >
              {s.label}
            </button>
          ))}
        </div>
      )}

      {/* TONIGHT — what service actually needs: the room, its guests, tabs, vibe.
          For a shop there is no room and no service: just the till. */}
      {section === "tonight" && (
        <>
          {store ? <StoreCounter venue={venue} meId={meId} /> : <VenueRooms venue={venue} meId={meId} />}
          <MyKudos venue={venue} meId={meId} />
        </>
      )}

      {section === "perks" && canManage && (
        <>
          {!venue.verified && <VerificationPanel venue={venue} meId={meId} />}
          <VenuePerkEditor venue={venue} />
        </>
      )}

      {section === "menu" && canManage && <VenueMenu venue={venue} />}

      {section === "insights" && canManage && <Insights venue={venue} />}

      {section === "guests" && canManage && <GuestBook venue={venue} />}

      {section === "team" && canManage && (
        <>
          <TeamKudos venueId={venue.id} />
          <TeamPanel venue={venue} meId={meId} staff={staff} />
          <PayrollPanel venue={venue} meId={meId} />
        </>
      )}

      {section === "setup" && canManage && (
        <>
          {!venue.verified && <VerificationPanel venue={venue} meId={meId} />}
          <EditVenue venue={venue} />
          <VenueLocation venue={venue} />

          {venue.myRole === "owner" && (
            <div className="mt-6 border-t border-line pt-4 text-sm">
              {confirmDelete ? (
                <span className="flex items-center gap-3">
                  <span className="text-muted">Delete this venue?</span>
                  <button onClick={() => deleteVenue(venue.id)} className="font-medium text-accent hover:opacity-80">
                    Delete
                  </button>
                  <button onClick={() => setConfirmDelete(false)} className="text-faint hover:text-ink">
                    Keep
                  </button>
                </span>
              ) : (
                <button onClick={() => setConfirmDelete(true)} className="text-faint transition-colors hover:text-ink">
                  Delete venue
                </button>
              )}
            </div>
          )}
        </>
      )}
    </div>
  );
}

function VenueRooms({ venue, meId }: { venue: Venue; meId: string }) {
  const { rooms, loading } = useVenueRooms(venue.id);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [copied, setCopied] = useState<string | null>(null);
  const [openRoom, setOpenRoom] = useState<string | null>(null);
  const [qrRoom, setQrRoom] = useState<string | null>(null);
  // How long your wall board stays live. Guests' consent to be on it expires with
  // it — nobody's name lingers on a screen after the night is over.
  const [boardHours, setBoardHours] = useState(6);

  // The room's public invite lives on the MAIN app (/p/<code>), not this
  // subdomain — derive it by dropping the leading "bar." from the host.
  const mainOrigin =
    typeof window !== "undefined" ? `${location.protocol}//${location.host.replace(/^bar\./, "")}` : "https://bwdy.site";

  async function open() {
    setBusy(true);
    setError(null);
    const res = await createParty(meId, {
      name: `${venue.name} · tonight`,
      date: todayKey(),
      venueId: venue.id,
      boardHours, // when this runs out, every guest drops off the wall screen
    });
    setBusy(false);
    if ("error" in res) setError("Couldn't open the room — try again.");
  }

  async function copyLink(code: string) {
    try {
      await navigator.clipboard.writeText(`${mainOrigin}/p/${code}`);
      setCopied(code);
      setTimeout(() => setCopied(null), 1600);
    } catch {}
  }

  return (
    <div className="mb-5">
      <div className="mb-2 flex items-center justify-between">
        <p className="label text-faint">Rooms</p>
        <button
          onClick={open}
          disabled={busy}
          className="text-sm font-medium text-accent transition-opacity hover:opacity-80 disabled:opacity-50"
        >
          {busy ? "Opening…" : "Open a room"}
        </button>
      </div>

      {/* The bar sets how long its screen runs. Guest consent expires with it. */}
      <div className="mb-3 flex flex-wrap items-center gap-2">
        <span className="text-xs text-faint">Screen runs for</span>
        {[4, 6, 8].map((h) => (
          <button
            key={h}
            onClick={() => setBoardHours(h)}
            aria-pressed={boardHours === h}
            className={clsx(
              "rounded-ctl px-3 py-1.5 text-xs transition-colors",
              boardHours === h ? "bg-ink font-medium text-paper" : "glass glass-press text-muted hover:text-ink",
            )}
          >
            {h}h
          </button>
        ))}
        <span className="text-xs text-faint">— then everyone drops off it.</span>
      </div>

      {error && <p className="mb-2 text-sm text-accent">{error}</p>}
      {loading ? (
        <div className="glass h-14 animate-pulse rounded-ctl" />
      ) : rooms.length === 0 ? (
        <p className="text-sm text-faint">No rooms yet. Open one and put the code on the table.</p>
      ) : (
        <ul className="divide-y divide-line border-y border-line">
          {rooms.map((r) => (
            <li key={r.id} className="py-2.5">
              <div className="flex items-center justify-between gap-3">
                <span className="min-w-0">
                  <span className="block truncate text-[15px] text-ink">{r.name}</span>
                  <span className="tnum text-xs text-faint">code {r.inviteCode}</span>
                </span>
                <span className="flex shrink-0 items-center gap-3 text-sm">
                  <button
                    onClick={() => setOpenRoom((cur) => (cur === r.id ? null : r.id))}
                    aria-expanded={openRoom === r.id}
                    className={clsx("transition-colors", openRoom === r.id ? "text-accent" : "text-faint hover:text-ink")}
                  >
                    Guests
                  </button>
                  <button
                    onClick={() => setQrRoom(r.inviteCode)}
                    className="text-faint transition-colors hover:text-ink"
                  >
                    QR
                  </button>
                  <a
                    href={`${mainOrigin}/kiosk/${r.inviteCode}`}
                    target="_blank"
                    rel="noopener noreferrer"
                    className="text-faint transition-colors hover:text-ink"
                  >
                    Kiosk
                  </a>
                  <button
                    onClick={() => copyLink(r.inviteCode)}
                    className={clsx("transition-colors", copied === r.inviteCode ? "font-medium text-accent" : "text-faint hover:text-ink")}
                  >
                    {copied === r.inviteCode ? "Copied" : "Copy link"}
                  </button>
                </span>
              </div>

              {openRoom === r.id && (
                <RoomGuestList
                  partyId={r.id}
                  venueId={venue.id}
                  verified={venue.verified}
                  currency={currencyForCountry(venue.country)}
                />
              )}
            </li>
          ))}
        </ul>
      )}

      {qrRoom && (
        <RoomQr url={`${mainOrigin}/p/${qrRoom}`} code={qrRoom} onClose={() => setQrRoom(null)} />
      )}
    </div>
  );
}

// ── insights: numbers a bar can act on, and a profile of nobody ──────────────
// A manager already sees who is in their own room. So counts over that same group
// aren't new personal data. What WOULD be: a small-group split ("1 new guest" =
// that named person has never been here before), a profile built over time, or
// anything at all about another venue. So splits are hidden below 5 people, there
// are no per-guest rows anywhere, and every number is scoped to this venue.
//
// A hidden number renders as "—", NEVER as 0. "Nobody was new" and "we're not
// telling you" are different facts, and showing 0 for both leaks the first.
function Insights({ venue }: { venue: Venue }) {
  const [days, setDays] = useState(30);
  const { data, loading } = useVenueInsights(venue.id, days);
  const money = (n: number) => formatMoney(n, currencyForCountry(venue.country), { round: true });

  if (loading) return <div className="glass h-40 animate-pulse rounded-tile" />;
  if (!data) return <p className="text-sm text-faint">Nothing to show yet.</p>;

  const hidden = data.newGuests === null;

  return (
    <div>
      <div className="mb-3 flex items-center justify-between gap-3">
        <p className="label text-faint">Last {days} days</p>
        <div className="flex gap-1.5">
          {[7, 30, 90].map((d) => (
            <button
              key={d}
              onClick={() => setDays(d)}
              aria-pressed={days === d}
              className={clsx(
                "rounded-ctl px-2.5 py-1 text-xs transition-colors",
                days === d ? "bg-ink font-medium text-paper" : "glass glass-press text-muted hover:text-ink",
              )}
            >
              {d}d
            </button>
          ))}
        </div>
      </div>

      <div className="glass grid grid-cols-2 gap-4 rounded-tile p-5 sm:grid-cols-3">
        <Stat label="nights open" value={String(data.rooms)} />
        <Stat label="guests" value={String(data.guests)} />
        <Stat label="new" value={data.newGuests === null ? "—" : String(data.newGuests)} />
        <Stat label="regulars" value={data.returningGuests === null ? "—" : String(data.returningGuests)} />
        <Stat label="perks waiting" value={data.perksEarned === null ? "—" : String(data.perksEarned)} accent />
        <Stat label="perks given" value={String(data.perksClaimed)} />
        <Stat label="tabs" value={String(data.tabs)} />
        <Stat label="takings" value={money(data.takings)} />
        <Stat
          label="came back"
          value={data.returningGuests === null ? "—" : `${Math.round((data.returningGuests / data.guests) * 100)}%`}
        />
        {/* Average tab is HIDDEN below k tabs — over 1–4 it would be one guest's spend. */}
        <Stat label="avg tab" value={data.tabs >= 5 ? money(data.takings / data.tabs) : "—"} />
        <Stat label="team thanked" value={String(data.kudos)} />
      </div>

      {/* Growth vs the previous equal-length window — the "are we up?" glance. */}
      {(data.prevGuests > 0 || data.prevTakings > 0) && (
        <p className="mt-3 flex flex-wrap items-center gap-x-4 gap-y-1 text-xs text-faint">
          <span>vs the previous {days} days:</span>
          <TrendChip label="guests" cur={data.guests} prev={data.prevGuests} />
          <TrendChip label="takings" cur={data.takings} prev={data.prevTakings} />
        </p>
      )}

      {/* Busiest / deadest night — the read that feeds the quiet-night lever. */}
      <WeekdayVisits visits={data.visitsByDow} quietNights={venue.quietNights ?? []} />

      {(data.quietVisits > 0 || venue.quietNights.length > 0) && (
        <p className="mt-3 text-xs leading-relaxed text-faint">
          <span className="text-ink">{data.quietVisits}</span> of those visits landed on a night you called
          quiet ({data.otherVisits} on the others).
        </p>
      )}

      {hidden && (
        <p className="mt-3 text-xs leading-relaxed text-faint">
          Some numbers show &ldquo;—&rdquo; because too few people came for us to split them without pointing
          at somebody. With five or more guests they&apos;ll appear.
        </p>
      )}

      {/* The AI reads the SAME aggregates above — never an individual — and says what
          to do next. Lives here, under the numbers it's grounded in. */}
      <VenueAdvisor venue={venue} insights={data} days={days} />

      <p className="mt-4 border-t border-line pt-3 text-xs leading-relaxed text-faint">
        These are counts, for this venue only. Your <span className="text-ink">guest book</span> keeps notes on
        the regulars you serve — first-party, only ever your own guests, and they can see and erase it. What we
        never hand over, anywhere, is a churn list of strangers, or what a guest does at another bar or in their
        private diary.
      </p>
    </div>
  );
}

function Stat({ label, value, accent }: { label: string; value: string; accent?: boolean }) {
  return (
    <div>
      <p className={clsx("tnum font-display text-2xl leading-none", accent ? "text-accent" : "text-ink")}>{value}</p>
      <p className="mt-1 text-xs text-faint">{label}</p>
    </div>
  );
}

// A single up/down delta vs the previous window. Renders nothing when there's no
// prior period to compare against (a first month has no honest trend to show).
function TrendChip({ label, cur, prev }: { label: string; cur: number; prev: number }) {
  const pct = pctChange(cur, prev);
  if (pct === null) return null;
  const up = pct >= 0;
  return (
    <span className="inline-flex items-baseline gap-1">
      <span className="text-muted">{label}</span>
      <span className={clsx("tnum font-medium", up ? "text-accent" : "text-ink")}>
        {up ? "↑" : "↓"} {Math.abs(pct)}%
      </span>
    </span>
  );
}

// Visit volume by weekday — one tall bright bar is your big night, and the caption
// names the quietest so the owner can point the quiet-night boost straight at it.
const DOW_LETTERS = ["S", "M", "T", "W", "T", "F", "S"];
const DOW_FULL = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"];

function WeekdayVisits({ visits, quietNights }: { visits: number[]; quietNights: number[] }) {
  if (!visits || visits.length < 7) return null;
  const total = visits.reduce((a, b) => a + b, 0);
  if (total === 0) return null;
  const max = Math.max(...visits);
  const { busiest, deadest } = peakDays(visits);
  const deadMarked = deadest !== null && quietNights.includes(deadest);

  return (
    <div className="glass mt-3 rounded-tile p-4">
      <p className="label mb-3 text-faint">By night</p>
      <div className="flex h-20 items-end gap-1.5">
        {visits.map((v, i) => (
          <div key={i} className="flex h-full flex-1 flex-col items-center justify-end gap-1.5">
            <div
              className="w-full rounded-t-sm bg-accent transition-[height] duration-300"
              style={{ height: `${Math.max(6, (v / max) * 100)}%`, opacity: i === busiest ? 1 : 0.3 }}
              title={`${DOW_FULL[i]}: ${v} ${v === 1 ? "visit" : "visits"}`}
            />
            <span className={clsx("text-[10px]", i === busiest || i === deadest ? "text-muted" : "text-faint")}>
              {DOW_LETTERS[i]}
            </span>
          </div>
        ))}
      </div>
      <p className="mt-2.5 text-xs leading-relaxed text-faint">
        Busiest <span className="text-ink">{busiest !== null ? DOW_FULL[busiest] : "—"}</span>
        {deadest !== null && deadest !== busiest && (
          <>
            {" · "}quietest <span className="text-ink">{DOW_FULL[deadest]}</span>
            {!deadMarked && (
              <>
                {" — "}
                <span className="text-accent">worth marking a quiet night</span>, so a visit then counts double toward
                the perk.
              </>
            )}
          </>
        )}
      </p>
    </div>
  );
}

// ── what a STAFF MEMBER sees: their own thanks ───────────────────────────────
// This is who the feature is for. People don't quit because they lost a
// leaderboard; they quit because nobody ever noticed.
function MyKudos({ venue, meId }: { venue: Venue; meId: string }) {
  const rows = useMyKudos(venue.id);
  const [off, setOff] = useState(false);
  const total = rows.reduce((n, r) => n + r.n, 0);

  function toggle() {
    const next = !off;
    setOff(next);
    setThankable(venue.id, meId, !next);
  }

  return (
    <div className="mt-6 border-t border-line pt-4">
      <div className="mb-2 flex items-center justify-between gap-3">
        <p className="label text-faint">Your thanks</p>
        <button onClick={toggle} className="text-xs text-faint transition-colors hover:text-ink">
          {off ? "Turn thanks back on" : "Don't thank me"}
        </button>
      </div>

      {total === 0 ? (
        <p className="text-sm text-faint">
          Nothing yet. When a guest thanks you, it lands here — and only you see it.
        </p>
      ) : (
        <>
          <p className="font-display text-3xl text-ink">
            {total} <span className="text-base text-faint">{total === 1 ? "thank you" : "thank yous"}</span>
          </p>
          <ul className="mt-2 flex flex-wrap gap-1.5">
            {rows.map((r) => (
              <li key={r.reason} className="glass rounded-ctl px-3 py-1.5 text-xs text-muted">
                {r.reason} <span className="tnum text-accent">{r.n}</span>
              </li>
            ))}
          </ul>
          <p className="mt-2 text-xs text-faint">Yours alone. Your manager never sees who was thanked.</p>
        </>
      )}
    </div>
  );
}

// ── what a MANAGER sees: ONE NUMBER ─────────────────────────────────────────
// Deliberately NOT a per-person league table. That line is the difference between
// a thank-you box and an employee-monitoring tool — the latter needs a DPIA and
// works-council consultation in seven EU states, and it turns a kindness into a
// performance metric. A bar WILL ask for the ranking. The answer is no.
function TeamKudos({ venueId }: { venueId: string }) {
  const total = useVenueKudosTotal(venueId, 30);

  return (
    <div className="mb-5">
      <p className="label mb-1.5 text-faint">Your team, thanked</p>
      <p className="font-display text-3xl text-ink">
        {total} <span className="text-base text-faint">in the last 30 days</span>
      </p>
      <p className="mt-1.5 max-w-prose text-xs leading-relaxed text-faint">
        Guests can thank whoever looked after them. We show you the team&apos;s total and nothing else — never
        who was thanked, or how often. Your people can see their own, and there is no way for a guest to
        complain about anyone here. That&apos;s deliberate: it&apos;s a thank-you box, not a scoreboard.
      </p>
    </div>
  );
}

// ── one guest's standing toward this venue's perk, + the claim ───────────────
// The bartender sees the same number the guest sees (one server function, no two
// versions of the truth). "Give it" records the claim, and the guest's progress
// restarts from zero — so a perk can be earned again, but never claimed twice for
// the same earn, and two bartenders can't both honour it.
function RoomGuestList({
  partyId,
  venueId,
  verified,
  currency,
}: {
  partyId: string;
  venueId: string;
  verified: boolean;
  currency: string;
}) {
  const { guests, loading } = useRoomGuests(partyId);
  const [openVibe, setOpenVibe] = useState<string | null>(null);
  const [openTab, setOpenTab] = useState<string | null>(null);
  const [amount, setAmount] = useState("");
  const [given, setGiven] = useState<Set<string>>(new Set());
  const [saved, setSaved] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);

  async function give(subjectId: string, reason: string) {
    const key = `${subjectId}:${reason}`;
    setGiven((s) => new Set(s).add(key));
    setOpenVibe(null);
    setError(null);
    const err = await staffAwardVibe(partyId, subjectId, reason);
    if (err) {
      setError(err);
      setGiven((s) => {
        const n = new Set(s);
        n.delete(key);
        return n;
      });
    }
  }

  async function saveTab(subjectId: string) {
    setError(null);
    const err = await recordSpend(partyId, subjectId, Number(amount));
    if (err) {
      setError(err);
      return;
    }
    setOpenTab(null);
    setAmount("");
    setSaved(subjectId);
    setTimeout(() => setSaved(null), 1600);
  }

  if (loading) return <div className="glass mt-2.5 h-12 animate-pulse rounded-ctl" />;
  if (guests.length === 0) return <p className="mt-2.5 text-sm text-faint">No one has joined this room yet.</p>;

  return (
    <div className="mt-2.5">
      {!verified && (
        <p className="mb-2 text-xs text-faint">
          Get verified to hand out vibe and record tabs — you can still see who&apos;s in.
        </p>
      )}
      {error && <p className="mb-2 text-sm text-accent">{error}</p>}

      <ul className="space-y-1.5">
        {guests.map((g) => (
          <li key={g.id}>
            <div className="flex items-center justify-between gap-3">
              <span className="min-w-0 truncate text-[15px] text-ink">
                {g.name}
                {/* Their standing on YOUR perks — and the button that hands one over. */}
                {verified && <GuestPerk venueId={venueId} guestId={g.id} />}
              </span>
              {verified && (
                <span className="flex shrink-0 items-center gap-3 text-sm">
                  <button
                    onClick={() => {
                      setOpenTab((cur) => (cur === g.id ? null : g.id));
                      setOpenVibe(null);
                      setAmount("");
                    }}
                    aria-expanded={openTab === g.id}
                    className={clsx(
                      "transition-colors",
                      saved === g.id ? "font-medium text-accent" : openTab === g.id ? "text-accent" : "text-faint hover:text-ink",
                    )}
                  >
                    {saved === g.id ? "Recorded" : "Tab"}
                  </button>
                  <button
                    onClick={() => {
                      setOpenVibe((cur) => (cur === g.id ? null : g.id));
                      setOpenTab(null);
                    }}
                    aria-expanded={openVibe === g.id}
                    className={clsx("transition-colors", openVibe === g.id ? "text-accent" : "text-faint hover:text-ink")}
                  >
                    Give vibe
                  </button>
                </span>
              )}
            </div>

            {/* the bar records the tab — a guest can never write this themselves */}
            {openTab === g.id && (
              <div className="mt-1.5 flex items-center gap-2">
                <input
                  type="number"
                  min={1}
                  inputMode="decimal"
                  value={amount}
                  onChange={(e) => setAmount(e.target.value)}
                  placeholder={`${currencySymbol(currency)} amount`}
                  aria-label={`Tab for ${g.name}`}
                  className="tnum glass w-32 rounded-ctl px-3 py-2 text-[15px] text-ink placeholder:text-faint"
                />
                <button
                  onClick={() => saveTab(g.id)}
                  disabled={!amount || Number(amount) <= 0}
                  className="rounded-ctl bg-ink px-3.5 py-2 text-sm font-medium text-paper transition-opacity hover:opacity-90 disabled:opacity-50"
                >
                  Record
                </button>
              </div>
            )}

            {openVibe === g.id && (
              <div className="mt-1.5 flex flex-wrap gap-1.5">
                {STAFF_VIBE_REASONS.map((reason) => {
                  const isGiven = given.has(`${g.id}:${reason}`);
                  return (
                    <button
                      key={reason}
                      disabled={isGiven}
                      onClick={() => give(g.id, reason)}
                      className={clsx(
                        "glass glass-press rounded-ctl px-3 py-2 text-xs transition-colors",
                        isGiven ? "text-faint" : "text-muted hover:text-accent",
                      )}
                    >
                      {reason}
                      {isGiven && " ✓"}
                    </button>
                  );
                })}
              </div>
            )}
          </li>
        ))}
      </ul>
    </div>
  );
}

// Verification: the venue asks; only WE can approve (scripts/verify-venue.mjs,
// service role). RLS forces status='pending' — they can never self-verify.
function VerificationPanel({ venue, meId }: { venue: Venue; meId: string }) {
  const { request, loading } = useVerification(venue.id);
  const [contact, setContact] = useState("");
  const [note, setNote] = useState("");
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  if (loading) return <div className="glass mb-4 h-16 animate-pulse rounded-tile" />;

  async function submit(e: React.FormEvent) {
    e.preventDefault();
    setBusy(true);
    setError(null);
    // venue_id is the primary key, so a rejected row must go before we resubmit.
    if (request?.status === "rejected") await withdrawVerification(venue.id);
    const err = await requestVerification(venue.id, meId, contact, note);
    setBusy(false);
    if (err) setError(err);
  }

  if (request?.status === "pending") {
    return (
      <div className="glass mb-4 rounded-tile p-4">
        <p className="text-[15px] text-ink">Verification requested.</p>
        <p className="mt-1 text-xs leading-relaxed text-faint">
          We&apos;ll reach you at {request.contact}. Rooms and vibe work meanwhile — perks unlock once you&apos;re verified.
        </p>
        <button
          onClick={() => withdrawVerification(venue.id)}
          className="mt-2 text-sm text-faint transition-colors hover:text-ink"
        >
          Withdraw
        </button>
      </div>
    );
  }

  const rejected = request?.status === "rejected";

  return (
    <form onSubmit={submit} className="glass mb-4 rounded-tile p-4">
      <p className="text-[15px] text-ink">{rejected ? "Not verified." : "Get verified."}</p>
      <p className="mb-3 mt-1 text-xs leading-relaxed text-faint">
        {rejected
          ? "We couldn't verify this one. Fix anything that looks off and send it again."
          : "Rooms and vibe already work. Verification is what unlocks real-world perks — tell us how to reach you."}
      </p>
      <div className="space-y-2.5">
        <input
          value={contact}
          onChange={(e) => setContact(e.target.value)}
          placeholder="Phone or email we can reach you on"
          aria-label="Contact"
          className={inputClass}
        />
        <input
          value={note}
          onChange={(e) => setNote(e.target.value)}
          placeholder="Anything that helps us verify you (optional)"
          aria-label="Note"
          className={inputClass}
        />
      </div>
      {error && <p className="mt-2 text-sm text-accent">{error}</p>}
      <button
        type="submit"
        disabled={busy || contact.trim().length < 3}
        className="mt-3 rounded-ctl bg-ink px-4 py-2 text-sm font-medium text-paper transition-opacity hover:opacity-90 disabled:opacity-50"
      >
        {busy ? "Sending…" : rejected ? "Request again" : "Request verification"}
      </button>
    </form>
  );
}

function GuestPerk({ venueId, guestId }: { venueId: string; guestId: string }) {
  const { tiers, loading } = usePerkTiers(venueId, guestId);
  const [busy, setBusy] = useState<string | null>(null);
  const [done, setDone] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);

  if (loading || tiers.length === 0) return null;

  async function give(perkId: string) {
    setBusy(perkId);
    setError(null);
    const err = await redeemPerk(perkId, guestId);
    setBusy(null);
    if (err) {
      setError(err);
      return;
    }
    setDone(perkId);
    setTimeout(() => setDone(null), 2000);
  }

  return (
    <span className="mt-0.5 block space-y-1 text-xs">
      {tiers.map((t) => {
        const spend = t.kind === "spend";
        const fmt = (n: number) => (spend ? formatMoney(n, t.currency, { round: true }) : `${n}`);

        return (
          <span key={t.id} className="block">
            {done === t.id ? (
              <span className="text-accent">Given · that one starts again</span>
            ) : t.earned ? (
              <button
                onClick={() => give(t.id)}
                disabled={busy === t.id}
                className="rounded-ctl bg-accent px-2.5 py-1 text-xs font-medium text-accent-contrast transition-opacity hover:opacity-90 disabled:opacity-50"
              >
                {busy === t.id ? "…" : `Give ${t.reward}`}
              </button>
            ) : (
              <span className="text-faint">
                <span className="tnum">{fmt(t.progress)}</span>/<span className="tnum">{fmt(t.threshold)}</span>{" "}
                toward {t.reward}
              </span>
            )}
          </span>
        );
      })}
      {error && <span className="text-accent">{error}</span>}
    </span>
  );
}

// ── the shop counter: how an off-licence punches a card ─────────────────────
// A bar records a visit implicitly — you joined the room, so you were there. A shop
// has no room, so a member of staff has to do it at the till. Which means the same
// rule as a tab: THE GUEST CAN NEVER RECORD THEIR OWN. And the server clamps it to
// one punch per person per day, so a shop can't punch your card ten times because
// you bought ten bottles — that would quietly turn a visits card back into a volume
// card, which is the thing we refused to build.
function StoreCounter({ venue, meId }: { venue: Venue; meId: string }) {
  const [query, setQuery] = useState("");
  const [results, setResults] = useState<SocialProfile[]>([]);
  const [guest, setGuest] = useState<SocialProfile | null>(null);
  const [busy, setBusy] = useState(false);
  const [note, setNote] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    if (guest || query.trim().length < 2) {
      setResults([]);
      return;
    }
    const t = setTimeout(async () => setResults(await searchUsers(query)), 300);
    return () => clearTimeout(t);
  }, [query, meId, guest]);

  async function punch(p: SocialProfile) {
    setGuest(p);
    setQuery("");
    setBusy(true);
    setError(null);
    setNote(null);
    const err = await recordVisit(venue.id, p.id);
    setBusy(false);
    if (err) {
      setError(err);
      return;
    }
    setNote(`${p.name}'s card is punched for today.`);
  }

  if (!venue.verified) {
    return (
      <p className="text-sm leading-relaxed text-faint">
        Cards start once you&apos;re verified — until then nothing you punch would count, so we don&apos;t
        pretend. Ask for verification under Setup.
      </p>
    );
  }

  return (
    <div>
      <p className="label mb-1.5 text-faint">At the till</p>
      <p className="mb-3 text-xs leading-relaxed text-faint">
        Find the customer and punch their card. Once a day, per person — buying more doesn&apos;t earn more.
      </p>

      {guest ? (
        <div className="glass rounded-tile p-4">
          <p className="text-[15px] text-ink">
            {guest.name} <span className="text-faint">@{guest.handle}</span>
          </p>
          {busy && <p className="mt-1 text-xs text-faint">Punching…</p>}
          {note && <p className="mt-1 text-xs text-accent">{note}</p>}
          {error && <p className="mt-1 text-xs text-accent">{error}</p>}
          {!busy && !error && <GuestPerk venueId={venue.id} guestId={guest.id} />}
          <button
            onClick={() => {
              setGuest(null);
              setNote(null);
              setError(null);
            }}
            className="mt-3 text-sm text-faint transition-colors hover:text-ink"
          >
            Next customer
          </button>
        </div>
      ) : (
        <>
          <label htmlFor={`punch-${venue.id}`} className="sr-only">
            Find a customer
          </label>
          <input
            id={`punch-${venue.id}`}
            value={query}
            onChange={(e) => setQuery(e.target.value)}
            placeholder="Find a customer by name or @handle"
            className={inputClass}
          />
          {query.trim().length >= 2 && (
            <ul className="mt-2 space-y-2">
              {results.length === 0 && <li className="px-1 text-sm text-faint">No one by that name or handle.</li>}
              {results.map((p) => (
                <li key={p.id} className="flex items-center justify-between gap-3 px-1">
                  <span className="min-w-0 truncate text-[15px] text-ink">
                    {p.name} <span className="text-faint">@{p.handle}</span>
                  </span>
                  <button
                    onClick={() => punch(p)}
                    className="shrink-0 text-sm font-medium text-accent transition-opacity hover:opacity-80"
                  >
                    Punch card
                  </button>
                </li>
              ))}
            </ul>
          )}
        </>
      )}
    </div>
  );
}

// ── quiet nights: the dead-Tuesday fix, without rewarding drinking ───────────
// The obvious fix is illegal (discount the drinks). The next-most-obvious breaks
// our own rule (a spark for turning up = a reward for FREQUENCY, which 019 removed
// on purpose). So the boost lands on the PRIVATE perk instead: a visit on a quiet
// night counts double toward the house reward. The bar fills its Tuesday; the
// public board stays clean; no drink is discounted, so it isn't an irresponsible
// promotion anywhere.
const WEEKDAYS = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"];

// ── the house perks: up to three TIERS, each its own punch-card ─────────────
// "3 visits: a coffee. 10 visits: a free pour." Tiered programmes beat single-tier
// by ~22% on engagement, and it's how a bar already thinks. Each tier keeps its own
// clock: claiming the coffee doesn't wipe progress toward the pour.
//
// What a tier may BE is decided by WHERE THE VENUE IS. The database has the final
// say (perk_policy — 021, fixed in 028); this UI exists so a licensee sees the rule
// rather than bumping into an error.
function VenuePerkEditor({ venue }: { venue: Venue }) {
  const { perks, loading } = useVenuePerks(venue.id);
  const [kind, setKind] = useState<PerkKind>("visits");
  const [threshold, setThreshold] = useState(5);
  const [reward, setReward] = useState("");
  const [rewardAlcoholic, setRewardAlcoholic] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);

  // A SHOP is judged by the shop's rules, not the bar's: its own jurisdiction
  // permission, visits only, and never an alcoholic reward — see perkPolicy(). Pass
  // the kind or a bottle shop inherits a pub's freedoms.
  const policy = perkPolicy(venue.country, venue.region, venue.kind, venue.servesAlcohol);
  const note = perkPolicyNote(venue.country, venue.region, venue.kind, venue.servesAlcohol);
  const currency = currencyForCountry(venue.country);

  // Never leave the editor sitting on an option the venue can't lawfully use.
  useEffect(() => {
    if (!policy.allowSpendPerk && kind === "spend") setKind("visits");
    if (!policy.allowAlcoholReward && rewardAlcoholic) setRewardAlcoholic(false);
  }, [policy.allowSpendPerk, policy.allowAlcoholReward, kind, rewardAlcoholic]);

  async function add() {
    setBusy(true);
    setError(null);
    const err = await addVenuePerk(venue.id, kind, threshold, reward, rewardAlcoholic);
    setBusy(false);
    if (err) {
      setError(err);
      return;
    }
    setReward("");
  }

  if (!venue.verified) {
    return (
      <div className="mb-5">
        <p className="label mb-2 text-faint">House perks</p>
        <p className="text-sm text-faint">Get verified to offer a perk — a reward that brings guests back.</p>
      </div>
    );
  }

  // Some places forbid a loyalty perk on alcohol entirely (Thailand, Norway…), and
  // anywhere we haven't researched is treated the same way — deny by default.
  if (!policy.allowPerks) {
    return (
      <div className="mb-5">
        <p className="label mb-2 text-faint">House perks</p>
        <p className="max-w-prose text-sm leading-relaxed text-faint">
          {note ?? "Loyalty perks aren't available for a venue here."}
        </p>
      </div>
    );
  }

  const spend = kind === "spend";
  const full = perks.length >= MAX_TIERS;
  const fmt = (n: number, k: PerkKind) => (k === "spend" ? formatMoney(n, currency, { round: true }) : `${n} visits`);

  return (
    <div className="mb-5">
      <p className="label mb-2 text-faint">House perks</p>

      {note && <p className="glass mb-2.5 rounded-ctl px-3.5 py-2.5 text-xs leading-relaxed text-muted">{note}</p>}

      {loading ? (
        <div className="glass h-14 animate-pulse rounded-ctl" />
      ) : (
        <>
          {perks.length > 0 && (
            <ul className="mb-4 divide-y divide-line border-y border-line">
              {perks.map((t) => (
                <li key={t.id} className="flex items-center justify-between gap-3 py-2.5">
                  <span className="min-w-0">
                    <span className="block truncate text-[15px] text-ink">{t.reward}</span>
                    <span className="text-xs text-faint">
                      at {fmt(t.threshold, t.kind)}
                      {t.rewardAlcoholic && " · an alcoholic drink"}
                    </span>
                  </span>
                  <button
                    onClick={() => removeVenuePerk(t.id)}
                    className="shrink-0 text-sm text-faint transition-colors hover:text-ink"
                  >
                    Remove
                  </button>
                </li>
              ))}
            </ul>
          )}

          {full ? (
            <p className="text-xs leading-relaxed text-faint">
              Three is the limit. A reward nobody can remember is a reward nobody chases — and the research is
              blunt that confusing schemes are the main reason people abandon them.
            </p>
          ) : (
            <>
              <p className="label mb-2 text-faint">{perks.length === 0 ? "Set a perk" : "Add another"}</p>

              <div className="mb-2 flex gap-2">
                {(["visits", "spend"] as PerkKind[]).map((k) => {
                  const blocked = k === "spend" && !policy.allowSpendPerk;
                  return (
                    <button
                      key={k}
                      onClick={() => {
                        if (blocked) return;
                        setKind(k);
                        setThreshold(k === "spend" ? 2000 : 5);
                      }}
                      disabled={blocked}
                      aria-pressed={kind === k}
                      title={blocked ? "Not permitted where this venue is" : undefined}
                      className={clsx(
                        "rounded-ctl px-3.5 py-1.5 text-sm transition-colors",
                        blocked
                          ? "cursor-not-allowed border border-line text-faint"
                          : kind === k
                            ? "bg-ink font-medium text-paper"
                            : "glass glass-press text-muted hover:text-ink",
                      )}
                    >
                      {k === "visits" ? "By visits" : "By spend"}
                    </button>
                  );
                })}
              </div>

              <p className="mb-2 text-xs leading-relaxed text-faint">
                {spend
                  ? "Reward a guest once their tab passes this. Only your staff can record a tab — a guest can never enter their own."
                  : "Reward a guest after this many visits. A visit on one of your quiet nights counts double."}
              </p>

              <div className="flex items-center gap-2">
                <input
                  type="number"
                  min={1}
                  max={spend ? 1000000 : 100}
                  value={threshold}
                  onChange={(e) => setThreshold(Number(e.target.value))}
                  aria-label={spend ? "Amount to spend" : "Visits needed"}
                  className="tnum glass w-24 rounded-ctl px-3 py-2.5 text-[15px] text-ink"
                />
                <input
                  value={reward}
                  onChange={(e) => setReward(e.target.value)}
                  placeholder={spend ? "e.g. dessert on the house" : "e.g. a free coffee"}
                  aria-label="Reward"
                  className="glass w-full rounded-ctl px-4 py-2.5 text-[15px] text-ink placeholder:text-faint"
                />
              </div>

              <div className="mt-3">
                <p className="mb-1.5 text-xs text-muted">The reward is…</p>
                <div className="flex gap-2">
                  <button
                    onClick={() => setRewardAlcoholic(false)}
                    aria-pressed={!rewardAlcoholic}
                    className={clsx(
                      "rounded-ctl px-3.5 py-1.5 text-sm transition-colors",
                      !rewardAlcoholic ? "bg-ink font-medium text-paper" : "glass glass-press text-muted hover:text-ink",
                    )}
                  >
                    Not a drink
                  </button>
                  <button
                    onClick={() => policy.allowAlcoholReward && setRewardAlcoholic(true)}
                    disabled={!policy.allowAlcoholReward}
                    aria-pressed={rewardAlcoholic}
                    title={!policy.allowAlcoholReward ? "Not permitted where this venue is" : undefined}
                    className={clsx(
                      "rounded-ctl px-3.5 py-1.5 text-sm transition-colors",
                      !policy.allowAlcoholReward
                        ? "cursor-not-allowed border border-line text-faint"
                        : rewardAlcoholic
                          ? "bg-ink font-medium text-paper"
                          : "glass glass-press text-muted hover:text-ink",
                    )}
                  >
                    An alcoholic drink
                  </button>
                </div>
                <p className="mt-1.5 text-xs leading-relaxed text-faint">
                  {rewardAlcoholic
                    ? "Permitted here — but a coffee, a dessert or priority entry brings a regular back just as well, without rewarding drinking."
                    : "A coffee, a dessert, priority entry, something from the kitchen. Legal everywhere we operate."}
                </p>
              </div>

              {error && <p className="mt-2 text-sm text-accent">{error}</p>}

              <button
                onClick={add}
                disabled={!reward.trim() || busy}
                className="mt-3 rounded-ctl bg-ink px-4 py-2 text-sm font-medium text-paper transition-opacity hover:opacity-90 disabled:opacity-50"
              >
                {busy ? "Saving…" : perks.length === 0 ? "Set perk" : "Add tier"}
              </button>
            </>
          )}

          {/* Only a VISITS perk can be doubled — money is never doubled, because
              doubling money is rewarding the spend, which is the thing we don't do. */}
          {perks.some((t) => t.kind === "visits") && <QuietNights venue={venue} />}
        </>
      )}
    </div>
  );
}

function QuietNights({ venue }: { venue: Venue }) {
  const [nights, setNights] = useState<number[]>(venue.quietNights ?? []);
  const [saved, setSaved] = useState(false);

  async function toggle(day: number) {
    const next = nights.includes(day) ? nights.filter((d) => d !== day) : [...nights, day].sort();
    setNights(next);
    await updateVenue(venue.id, { quietNights: next });
    setSaved(true);
    setTimeout(() => setSaved(false), 1400);
  }

  return (
    <div className="mt-6 border-t border-line pt-4">
      <p className="text-sm text-ink">Quiet nights</p>
      <p className="mb-2.5 text-xs leading-relaxed text-faint">
        Your dead nights. A visit on one of these counts <span className="text-ink">double</span> toward the
        perk — so people have a reason to come on a Tuesday. Nothing is discounted and nobody is asked to
        drink more; they just have to turn up.
      </p>

      <div className="flex flex-wrap gap-1.5">
        {WEEKDAYS.map((label, day) => {
          const on = nights.includes(day);
          return (
            <button
              key={label}
              onClick={() => toggle(day)}
              aria-pressed={on}
              className={clsx(
                "rounded-ctl px-3 py-1.5 text-xs transition-colors",
                on ? "bg-accent font-medium text-accent-contrast" : "glass glass-press text-muted hover:text-ink",
              )}
            >
              {label}
            </button>
          );
        })}
      </div>

      {saved && <p className="mt-2 text-xs text-accent">Saved.</p>}
    </div>
  );
}

// ── staff access (053) ───────────────────────────────────────────────────────
// Where I stand beyond the venues I work: a code a venue's owner gave me to type (they
// added my email), and where I'm waiting for a yes or paused — with why and who to see.
function StaffAccessPanel() {
  const { codes, access } = useStaffAccess();
  if (codes.length === 0 && access.length === 0) return null;
  return (
    <div className="mb-8 space-y-3">
      {codes.map((c) => (
        <ClaimCode key={c.id} code={c} />
      ))}
      {access.map((a) => (
        <div key={a.venueId} className="glass rounded-tile p-5">
          <p className="label mb-1.5 text-faint">{a.status === "locked" ? "Paused" : "Waiting for a yes"}</p>
          <p className="font-display text-xl leading-tight text-ink">{a.venueName}</p>
          {a.status === "locked" ? (
            <>
              <p className="mt-2 text-[15px] text-ink">{reportLine(a.reportTo, a.reportToRole)}</p>
              {a.lockReason && <p className="mt-1.5 font-display text-lg italic text-muted">&ldquo;{a.lockReason}&rdquo;</p>}
              <p className="mt-2 text-xs leading-relaxed text-faint">
                Your access here is paused, so the venue&apos;s screens are closed to you. Nothing you recorded is lost.
              </p>
            </>
          ) : (
            <p className="mt-1.5 text-sm text-muted">
              You asked to join as {roleWithArticle(ROLE_LABEL[a.role] ?? a.role)} — an owner or manager says yes first.
            </p>
          )}
        </div>
      ))}
    </div>
  );
}

function ClaimCode({ code }: { code: { id: string; venueName: string; role: StaffRole; addedBy?: string; expiresAt: string; triesLeft: number } }) {
  const [typed, setTyped] = useState("");
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [left, setLeft] = useState(code.triesLeft);

  async function join(e: React.FormEvent) {
    e.preventDefault();
    const digits = codeDigits(typed);
    if (digits.length !== 6) {
      setError("The code is 6 digits.");
      return;
    }
    setBusy(true);
    setError(null);
    const r = await claimStaffCode(code.id, digits);
    setBusy(false);
    if (r.ok) return; // the venue list refreshes with the venue in it
    if (r.left != null) setLeft(r.left);
    setError(r.message ?? claimMessage(r.error, r.left, code.addedBy));
  }

  return (
    <form onSubmit={join} className="glass rounded-tile p-5">
      <p className="label mb-1.5 text-faint">A code to type</p>
      <p className="font-display text-xl leading-tight text-ink">{code.venueName}</p>
      <p className="mt-1.5 text-sm text-muted">
        {code.addedBy ?? "A manager"} added you as {roleWithArticle(ROLE_LABEL[code.role] ?? code.role)}. Type the 6-digit code they gave you.
      </p>
      <label htmlFor={`claim-${code.id}`} className="sr-only">The owner&apos;s code</label>
      <input
        id={`claim-${code.id}`}
        value={typed}
        onChange={(e) => setTyped(e.target.value)}
        inputMode="numeric"
        autoComplete="one-time-code"
        placeholder="6 digits"
        maxLength={7}
        className={clsx(inputClass, "mt-3 text-center font-display text-2xl tracking-[0.3em]")}
      />
      {error && <p className="mt-2 text-sm text-accent">{error}</p>}
      <button type="submit" disabled={busy} className="mt-3 w-full rounded-ctl bg-ink px-4 py-2.5 text-sm font-medium text-paper transition-opacity hover:opacity-90 disabled:opacity-50">
        {busy ? "One moment…" : `Join ${code.venueName}`}
      </button>
      <p className="mt-2 text-xs text-faint">
        {left === 1 ? "1 try" : `${left} tries`} left · the code {codeLifeLeft(new Date(code.expiresAt), new Date())} · it only works for the email you&apos;re signed in with.
      </p>
    </form>
  );
}

// The team, for an owner or manager: add an employee (their code, shown once), say yes
// to someone who used a shared invite, pause someone's access with a reason and who to
// report to, give it back, remove. The database decides each (venue_can, can_grant_role).
function TeamPanel({ venue, meId, staff }: { venue: Venue; meId: string; staff: VenueStaff[] }) {
  const codes = useOpenEnrolments(venue.id, true);
  const [msg, setMsg] = useState<string | null>(null);
  const [pausing, setPausing] = useState<string | null>(null);
  const [shown, setShown] = useState<{ name: string; email: string; role: StaffRole; code: StaffCode } | null>(null);
  const mine = venue.myRole;
  const run = async (p: Promise<string | null>, done: string) => setMsg((await p) ?? done);
  const waiting = staff.filter((s) => s.status === "pending");
  const on = staff.filter((s) => s.status === "active");
  const paused = staff.filter((s) => s.status === "locked");
  const bosses = on.filter((s) => s.role === "owner" || s.role === "manager");

  const row = (s: VenueStaff, actions: React.ReactNode) => (
    <li key={s.id} className="py-2.5">
      <div className="flex items-center justify-between gap-3">
        <span className="min-w-0 truncate text-[15px] text-ink">
          {s.id === meId ? "you" : s.name} <span className="text-faint">@{s.handle}</span>
        </span>
        <span className="flex shrink-0 items-center gap-3 text-sm">
          <span className="text-xs text-faint">
            {ROLE_LABEL[s.role] ?? s.role}
            {s.onShiftSince && s.status === "active" ? " · on shift" : ""}
          </span>
          {s.role !== "owner" && s.id !== meId && canGrant(mine, s.role) && actions}
        </span>
      </div>
      {s.status === "locked" && (
        <p className="mt-1 text-xs text-faint">
          {reportLine(s.reportTo, null)}
          {s.lockReason ? ` “${s.lockReason}”` : ""}
        </p>
      )}
      {pausing === s.id && (
        <PauseForm
          name={s.name}
          bosses={bosses}
          meId={meId}
          onCancel={() => setPausing(null)}
          onPause={async (reason, reportTo) => {
            setPausing(null);
            await run(lockStaff(venue.id, s.id, reason, reportTo), `${s.name} is paused.`);
          }}
        />
      )}
    </li>
  );
  const btn = (label: string, onClick: () => void, strong = false) => (
    <button onClick={onClick} className={clsx("transition-colors", strong ? "font-medium text-accent hover:opacity-80" : "text-faint hover:text-ink")}>
      {label}
    </button>
  );

  return (
    <>
      <AddEmployee venue={venue} onMade={(m) => setShown(m)} />
      {shown && <CodeShown venue={venue} {...shown} onDone={() => setShown(null)} />}
      {msg && <p className="mb-3 text-xs text-accent" role="status">{msg}</p>}

      {waiting.length > 0 && (
        <>
          <p className="label mb-1.5 text-faint">Waiting for your yes</p>
          <p className="mb-2 text-xs leading-relaxed text-faint">They used a shared invite code. Say yes only if you know who this is.</p>
          <ul className="mb-5 divide-y divide-line border-y border-line">
            {waiting.map((s) =>
              row(
                s,
                <>
                  {btn("Say no", () => run(declineStaff(venue.id, s.id), `Said no to ${s.name}.`))}
                  {btn("Approve", () => run(approveStaff(venue.id, s.id), `${s.name} is on the team.`), true)}
                </>,
              ),
            )}
          </ul>
        </>
      )}

      {codes.length > 0 && (
        <>
          <p className="label mb-1.5 text-faint">Added, not in yet</p>
          <ul className="mb-5 divide-y divide-line border-y border-line">
            {codes.map((c) => {
              const dead = c.attempts >= 5 || new Date(c.expiresAt) <= new Date();
              return (
                <li key={c.id} className="flex items-center justify-between gap-3 py-2.5">
                  <span className="min-w-0 truncate text-[15px] text-ink">
                    {c.name} <span className="text-faint">{c.email}</span>
                  </span>
                  <span className="flex shrink-0 items-center gap-3 text-sm">
                    <span className="text-xs text-faint">
                      {ROLE_LABEL[c.role]} · {c.attempts >= 5 ? "5 wrong tries" : `code ${codeLifeLeft(new Date(c.expiresAt), new Date())}`}
                    </span>
                    {btn("Cancel", () => run(revokeStaffEnrolment(c.id), `${c.name}'s code is cancelled.`))}
                    {btn(
                      "New code",
                      async () => {
                        const r = await reissueStaffCode(c.id);
                        if (r.code) setShown({ name: c.name, email: c.email, role: c.role, code: r.code });
                        else setMsg(r.error ?? "Couldn't make a new code.");
                      },
                      dead,
                    )}
                  </span>
                </li>
              );
            })}
          </ul>
        </>
      )}

      <p className="label mb-1.5 text-faint">The team</p>
      <ul className="mb-5 divide-y divide-line border-y border-line">
        {on.map((s) =>
          row(
            s,
            <>
              {btn("Pause", () => setPausing(s.id))}
              {btn("Remove", () => run(removeStaff(venue.id, s.id).then(() => null), `${s.name} is off the team.`))}
            </>,
          ),
        )}
      </ul>

      {paused.length > 0 && (
        <>
          <p className="label mb-1.5 text-faint">Paused</p>
          <ul className="mb-5 divide-y divide-line border-y border-line">
            {paused.map((s) =>
              row(
                s,
                <>
                  {btn("Remove", () => run(removeStaff(venue.id, s.id).then(() => null), `${s.name} is off the team.`))}
                  {btn("Give access again", () => run(unlockStaff(venue.id, s.id), `${s.name} can use the app again.`), true)}
                </>,
              ),
            )}
          </ul>
        </>
      )}
    </>
  );
}

// ── payroll (054): hours and pay by person, and the file an accountant opens ────
// In NAME order — for pay, never a ranking. A day is the VENUE's (its time zone), and a
// shift counts on the day it started. The CSV is byte for byte the one the venue app
// shares (payroll.ts and payroll.dart are held to one fixture). brewdiary reports hours
// and rates; overtime, tax and deductions stay with the payroll provider.
function PayrollPanel({ venue, meId }: { venue: Venue; meId: string }) {
  const tz = venueTimeZone(venue.country, venue.region);
  const [period, setPeriod] = useState<PayPeriod>("lastWeek");
  const [from, to] = payPeriod(period, todayIn(tz));
  const { rows, loading, error } = usePayroll(venue.id, from, to, tz);
  const rates = usePayRates(venue.id);
  const [editing, setEditing] = useState<string | null>(null);
  const [msg, setMsg] = useState<string | null>(null);
  const currency = currencyForCountry(venue.country);
  const money = (n: number) => formatMoney(n, currency, { round: false });
  const people = payrollTotals(rows);
  const worked = people.reduce((n, p) => n + p.workedMinutes, 0);
  const noRate = people.filter((p) => p.missingRate && p.role !== "owner").map((p) => p.name);

  function download() {
    const csv = payrollCsv({ venue: venue.name, currency, from, to, rows });
    const url = URL.createObjectURL(new Blob([payrollFileText(csv)], { type: "text/csv;charset=utf-8" }));
    const a = document.createElement("a");
    a.href = url;
    a.download = payrollFileName(venue.name, from, to);
    document.body.appendChild(a);
    a.click();
    a.remove();
    setTimeout(() => URL.revokeObjectURL(url), 1000);
  }

  return (
    <div className="mt-8 border-t border-line pt-5">
      <div className="mb-3 flex flex-wrap items-center justify-between gap-3">
        <p className="label text-faint">Payroll</p>
        <div className="flex flex-wrap gap-1.5">
          {PAY_PERIODS.map((p) => (
            <button
              key={p.id}
              onClick={() => setPeriod(p.id)}
              aria-pressed={period === p.id}
              className={clsx(
                "rounded-ctl px-2.5 py-1 text-xs transition-colors",
                period === p.id ? "bg-ink font-medium text-paper" : "glass glass-press text-muted hover:text-ink",
              )}
            >
              {p.label}
            </button>
          ))}
        </div>
      </div>
      <p className="mb-3 text-xs text-faint">
        {from === to ? from : `${from} to ${to}`} · days in {tz}
      </p>

      {loading && rows.length === 0 ? (
        <div className="glass h-32 animate-pulse rounded-tile" />
      ) : error ? (
        <p className="text-sm text-faint" role="status">{error}</p>
      ) : (
        <>
          <div className="glass grid grid-cols-2 gap-4 rounded-tile p-5">
            <Stat label="hours worked" value={minutesWords(worked)} />
            <Stat label="pay" value={money(payrollTotalCents(people) / 100)} accent />
          </div>

          {noRate.length > 0 && (
            <p className="mt-3 text-xs leading-relaxed text-accent" role="status">
              No rate for {noRate.join(", ")} — their hours are in the file without pay. Set one with “Pay” below.
            </p>
          )}
          {msg && <p className="mt-3 text-xs text-accent" role="status">{msg}</p>}

          {people.length === 0 ? (
            <p className="mt-4 text-sm text-faint">No hours in this period.</p>
          ) : (
            <ul className="mt-4 divide-y divide-line border-y border-line">
              {people.map((p) => {
                const canPay = p.userId !== meId && p.role !== "owner" && p.role !== "left" && canGrant(venue.myRole, p.role as StaffRole);
                const rate = rates[p.userId] ?? null;
                return (
                  <li key={p.userId} className="py-2.5">
                    <div className="flex items-center justify-between gap-3">
                      <span className="min-w-0 truncate text-[15px] text-ink">
                        {p.userId === meId ? "you" : p.name}{" "}
                        <span className="text-xs text-faint">
                          {p.role === "left" ? "left the team" : (ROLE_LABEL[p.role as StaffRole] ?? p.role)} · {p.daysWorked}{" "}
                          {p.daysWorked === 1 ? "day" : "days"} · {minutesWords(p.workedMinutes)}
                          {p.plannedMinutes > 0 ? ` of ${minutesWords(p.plannedMinutes)} planned` : ""}
                        </span>
                      </span>
                      <span className="flex shrink-0 items-center gap-3 text-sm">
                        <span className="tnum text-ink">{p.payCents === null ? (p.workedMinutes > 0 && p.role !== "owner" ? "no rate" : "") : money(p.payCents / 100)}</span>
                        {canPay && (
                          <button onClick={() => setEditing(editing === p.userId ? null : p.userId)} className="text-faint transition-colors hover:text-ink">
                            Pay
                          </button>
                        )}
                      </span>
                    </div>
                    {editing === p.userId && (
                      <PayRateForm
                        name={p.name}
                        currency={currency}
                        rate={rate}
                        onCancel={() => setEditing(null)}
                        onSave={async (r) => {
                          setEditing(null);
                          const err = await setStaffPay(venue.id, p.userId, r);
                          setMsg(err ?? (r === null ? `${p.name}'s rate is cleared.` : `${p.name}'s rate is saved.`));
                        }}
                      />
                    )}
                  </li>
                );
              })}
            </ul>
          )}

          <button
            onClick={download}
            disabled={rows.length === 0}
            className="glass glass-press mt-4 w-full rounded-ctl py-3 text-sm font-medium text-ink transition-opacity disabled:opacity-40"
          >
            Download CSV
          </button>
          <p className="mt-3 max-w-prose text-xs leading-relaxed text-faint">
            By name, for pay — never a ranking. Unpaid breaks come off the hours; a shift keeps the rate it started
            at. The file opens in any spreadsheet: one line per person per day, then the totals. Overtime, tax and
            deductions are your payroll provider&apos;s — brewdiary reports hours and rates. Corrections and missed
            shifts are made in the venue app, always with a reason.
          </p>
        </>
      )}
    </div>
  );
}

function PayRateForm({
  name,
  currency,
  rate,
  onSave,
  onCancel,
}: {
  name: string;
  currency: string;
  rate: number | null;
  onSave: (rate: number | null) => void;
  onCancel: () => void;
}) {
  const [text, setText] = useState(rate === null ? "" : String(rate));
  const [err, setErr] = useState<string | null>(null);
  function submit(e: React.FormEvent) {
    e.preventDefault();
    const r = Number(text.trim().replace(/,/g, ""));
    if (!text.trim() || !Number.isFinite(r) || r < 0 || r > 100000) {
      setErr("A number from 0 to 1,00,000.");
      return;
    }
    onSave(Math.round(r * 100) / 100);
  }
  return (
    <form onSubmit={submit} className="mt-2 flex flex-wrap items-center gap-2 text-sm">
      <label className="sr-only" htmlFor={`rate-${name}`}>
        {name}&apos;s hourly rate
      </label>
      <span className="text-faint">{currencySymbol(currency)}</span>
      <input
        id={`rate-${name}`}
        inputMode="decimal"
        value={text}
        onChange={(e) => setText(e.target.value)}
        placeholder="per hour"
        className="glass w-28 rounded-ctl px-3 py-1.5 text-ink outline-none"
        autoFocus
      />
      <button type="submit" className="font-medium text-accent hover:opacity-80">
        Save
      </button>
      {rate !== null && (
        <button type="button" onClick={() => onSave(null)} className="text-faint hover:text-ink">
          Clear
        </button>
      )}
      <button type="button" onClick={onCancel} className="text-faint hover:text-ink">
        Cancel
      </button>
      {err && <span className="w-full text-xs text-accent">{err}</span>}
      <span className="w-full text-xs text-faint">Before tax. The team&apos;s history notes that it changed — never the amount.</span>
    </form>
  );
}

function PauseForm({
  name,
  bosses,
  meId,
  onPause,
  onCancel,
}: {
  name: string;
  bosses: VenueStaff[];
  meId: string;
  onPause: (reason: string, reportTo: string | null) => void;
  onCancel: () => void;
}) {
  const [reason, setReason] = useState("");
  const [to, setTo] = useState<string | null>(bosses.find((b) => b.id === meId)?.id ?? bosses[0]?.id ?? null);
  return (
    <div className="glass mt-2 rounded-ctl p-3">
      <p className="text-xs leading-relaxed text-faint">
        Everything here stops for {name} at once, and they&apos;re clocked out. They see your message and who to report to.
      </p>
      <label htmlFor="pause-why" className="sr-only">Why (they&apos;ll see this)</label>
      <input
        id="pause-why"
        value={reason}
        onChange={(e) => setReason(e.target.value)}
        maxLength={200}
        placeholder="Why (they'll see this)"
        className={clsx(inputClass, "mt-2")}
      />
      <div className="mt-2 flex flex-wrap gap-1.5">
        {bosses.map((b) => (
          <button
            key={b.id}
            onClick={() => setTo(b.id)}
            aria-pressed={to === b.id}
            className={clsx("rounded-ctl px-3 py-1.5 text-xs transition-colors", to === b.id ? "bg-ink text-paper" : "glass text-muted hover:text-ink")}
          >
            Report to {b.id === meId ? "me" : b.name}
          </button>
        ))}
      </div>
      <div className="mt-3 flex items-center gap-3 text-sm">
        <button onClick={() => onPause(reason, to)} className="font-medium text-accent hover:opacity-80">
          Pause access
        </button>
        <button onClick={onCancel} className="text-faint hover:text-ink">
          Cancel
        </button>
      </div>
    </div>
  );
}

// Add an employee: their details and the role. brewdiary makes a 6-digit code, shown once;
// they sign in to brewdiary bar with that email and type it.
function AddEmployee({ venue, onMade }: { venue: Venue; onMade: (m: { name: string; email: string; role: StaffRole; code: StaffCode }) => void }) {
  const roles = STAFF_ROLES.filter((r) => canGrant(venue.myRole, r));
  const [name, setName] = useState("");
  const [email, setEmail] = useState("");
  const [phone, setPhone] = useState("");
  const [role, setRole] = useState<StaffRole>(roles.includes("server") ? "server" : roles[roles.length - 1] ?? "server");
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  async function submit(e: React.FormEvent) {
    e.preventDefault();
    if (!name.trim()) return setError("Add their name.");
    if (!validStaffEmail(email)) return setError("That email doesn't look right.");
    if (phone.trim() && !validStaffPhone(phone)) return setError("That phone number doesn't look right.");
    setBusy(true);
    setError(null);
    const r = await enrolStaff(venue.id, { name, email, phone, role });
    setBusy(false);
    if (!r.code) return setError(r.error ?? "Couldn't add them.");
    onMade({ name: name.trim(), email: email.trim().toLowerCase(), role, code: r.code });
    setName("");
    setEmail("");
    setPhone("");
  }

  return (
    <form onSubmit={submit} className="mb-6">
      <p className="label mb-1.5 text-faint">Add an employee</p>
      <p className="mb-2.5 text-xs leading-relaxed text-faint">
        They sign in to brewdiary bar with this email and type the code you get here. Only then are they on the team, as the role you pick.
      </p>
      <div className="grid gap-2 sm:grid-cols-2">
        <input aria-label="Their name" value={name} onChange={(e) => setName(e.target.value)} placeholder="Their name" maxLength={60} className={inputClass} />
        <input aria-label="Their email" type="email" value={email} onChange={(e) => setEmail(e.target.value)} placeholder="Their email" className={inputClass} />
        <input aria-label="Phone (optional)" value={phone} onChange={(e) => setPhone(e.target.value)} placeholder="Phone (optional)" className={inputClass} />
        <select aria-label="Role" value={role} onChange={(e) => setRole(e.target.value as StaffRole)} className={inputClass}>
          {roles.map((r) => (
            <option key={r} value={r}>
              {ROLE_LABEL[r]}
            </option>
          ))}
        </select>
      </div>
      {error && <p className="mt-2 text-sm text-accent">{error}</p>}
      <button type="submit" disabled={busy} className="mt-2.5 rounded-ctl bg-ink px-4 py-2 text-sm font-medium text-paper transition-opacity hover:opacity-90 disabled:opacity-50">
        {busy ? "One moment…" : "Make their code"}
      </button>
    </form>
  );
}

function CodeShown({ venue, name, email, role, code, onDone }: { venue: Venue; name: string; email: string; role: StaffRole; code: StaffCode; onDone: () => void }) {
  const spaced = code.code.length === 6 ? `${code.code.slice(0, 3)} ${code.code.slice(3)}` : code.code;
  const text = enrolShareText({ venue: venue.name, roleWord: ROLE_LABEL[role], email, code: code.code });
  const [copied, setCopied] = useState(false);
  return (
    <div className="glass mb-6 rounded-tile p-5 text-center" role="status">
      <p className="text-sm text-muted">{name}&apos;s code</p>
      <p className="mt-2 font-display text-5xl tracking-[0.2em] text-ink tabular-nums">{spaced}</p>
      <p className="mx-auto mt-3 max-w-prose text-xs leading-relaxed text-faint">
        Shown once — share it now, or tell them in person. It works only for {email}, for 48 hours, with 5 tries.
      </p>
      <div className="mt-4 flex items-center justify-center gap-4 text-sm">
        <button
          onClick={async () => {
            try {
              await navigator.clipboard.writeText(text);
              setCopied(true);
            } catch {
              /* no clipboard — the code is on screen */
            }
          }}
          className="font-medium text-accent hover:opacity-80"
        >
          {copied ? "Copied" : "Copy the message"}
        </button>
        <button onClick={onDone} className="text-faint hover:text-ink">
          Done
        </button>
      </div>
    </div>
  );
}

// The owner sets the venue's location once — standing in the venue. We keep a ~1 km
// geohash cell (a venue's address is public anyway): its first 4 characters are what
// area taste trends match on, its first 5 place it on the area heat map (048).
// updateVenue bumps the version, so the label flips to "set" once the venue reloads.
function VenueLocation({ venue }: { venue: Venue }) {
  const [busy, setBusy] = useState(false);
  const [msg, setMsg] = useState<string | null>(null);

  async function setLoc() {
    setBusy(true);
    setMsg(null);
    const { geohash, error } = await requestLocationGeohash(VENUE_PRECISION);
    if (error || !geohash) {
      setBusy(false);
      setMsg(error ?? "Couldn't read a location.");
      return;
    }
    const err = await updateVenue(venue.id, { geohash });
    setBusy(false);
    setMsg(err ? "Couldn't save — try again." : "Location set.");
  }

  return (
    <div className="mt-6 border-t border-line pt-4">
      <p className="text-sm text-ink">Venue location</p>
      <p className="mb-2.5 text-xs leading-relaxed text-faint">
        Stand in your venue and set its location once. We keep a ~1&nbsp;km cell — never a pin — so Ninkasi can
        read what your area is drinking and the area map can place you. {venue.geohash ? "It's set." : "Not set yet."}
      </p>
      <div className="flex items-center gap-3">
        <button
          onClick={setLoc}
          disabled={busy}
          className="rounded-ctl bg-ink px-4 py-2 text-sm font-medium text-paper transition-opacity hover:opacity-90 disabled:opacity-50"
        >
          {busy ? "Locating…" : venue.geohash ? "Update location" : "Use my location"}
        </button>
        {venue.geohash && (
          <button
            onClick={() => updateVenue(venue.id, { geohash: null })}
            className="text-sm text-faint transition-colors hover:text-ink"
          >
            Clear
          </button>
        )}
      </div>
      {msg && <p className="mt-2 text-xs text-accent">{msg}</p>}
      <label className="mt-4 flex items-start gap-3 text-sm text-ink">
        <input
          type="checkbox"
          className="mt-1"
          checked={venue.areaShare}
          onChange={(e) => updateVenue(venue.id, { areaShare: e.target.checked })}
        />
        <span>
          Share our totals with the area map
          <span className="block text-xs leading-relaxed text-faint">
            Counts and bands only, from guests who said yes, in groups of 5+ people across 3+ venues. Venues that
            share see the typical night&apos;s spend around them; venues that don&apos;t, don&apos;t.
          </span>
        </span>
      </label>
    </div>
  );
}

function EditVenue({ venue }: { venue: Venue }) {
  const [editing, setEditing] = useState(false);
  const [name, setName] = useState(venue.name);
  const [city, setCity] = useState(venue.city ?? "");
  const [busy, setBusy] = useState(false);

  if (!editing) {
    return (
      <button onClick={() => setEditing(true)} className="mb-1 text-sm text-faint transition-colors hover:text-ink">
        Edit name or city
      </button>
    );
  }

  async function save() {
    setBusy(true);
    await updateVenue(venue.id, { name, city });
    setBusy(false);
    setEditing(false);
  }

  return (
    <div className="mb-4 space-y-2.5">
      <input value={name} onChange={(e) => setName(e.target.value)} className={inputClass} aria-label="Venue name" />
      <input value={city} onChange={(e) => setCity(e.target.value)} placeholder="City" className={inputClass} aria-label="City" />
      <div className="flex items-center gap-3">
        <button
          onClick={save}
          disabled={busy || !name.trim()}
          className="rounded-ctl bg-ink px-4 py-2 text-sm font-medium text-paper transition-opacity hover:opacity-90 disabled:opacity-50"
        >
          {busy ? "Saving…" : "Save"}
        </button>
        <button onClick={() => setEditing(false)} className="text-sm text-faint transition-colors hover:text-ink">
          Cancel
        </button>
      </div>
    </div>
  );
}
