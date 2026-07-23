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
  addStaff,
  removeStaff,
  deleteVenue,
  requestVerification,
  withdrawVerification,
  slugify,
  isValidSlug,
  ROLE_LABEL,
  ASSIGNABLE_ROLES,
  type Venue,
  type StaffRole,
} from "@/lib/venues";
import { searchUsers, type SocialProfile } from "@/lib/friends";
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
import {
  useVenueOffers,
  useVenueReservations,
  addDiningOffer,
  toggleDiningOffer,
  removeDiningOffer,
  setReservationStatus,
  MAX_OFFERS,
  type OfferKind,
  type ReservationStatus,
} from "@/lib/reservations";
import { KNOWN_COUNTRIES } from "@/lib/jurisdiction";
import { currencyForCountry, currencySymbol, formatMoney } from "@/lib/money";
import { useRoomGuests, staffAwardVibe, recordSpend, STAFF_VIBE_REASONS } from "@/lib/points";
import { todayKey } from "@/lib/date";
import { peakDays, pctChange } from "@/lib/venueAdvisor";
import { requestLocationGeohash } from "@/lib/trends";
import { VenueAdvisor } from "./VenueAdvisor";
import { GuestBook } from "./GuestBook";

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
        <span className="label text-accent">for the trade</span>
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
      <p className="label mb-2 text-faint">brewdiary for bars · bottle shops · restaurants</p>
      <h1 className="font-display text-4xl leading-tight tracking-tight text-ink sm:text-5xl">
        Give your regulars a reason to be regulars.
      </h1>
      <p className="mt-3 max-w-prose text-[15px] leading-relaxed text-muted">
        brewdiary is a drink diary its people already carry. This is the side you run: a room for tonight
        (or a punch-card at the till, if you&apos;re a shop), a reward that brings them back, staff thanks for
        the good ones, and Ninkasi reading your numbers. Free, and nothing to install.
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
  const [country, setCountry] = useState("IN");
  const [region, setRegion] = useState("");
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  // The address preview follows the name until the owner types their own slug.
  const effectiveSlug = slug.trim() || slugify(name);
  const slugValid = isValidSlug(effectiveSlug);

  // Say NOW whether a loyalty card is even possible here, rather than letting them
  // set the shop up and hit a wall at the perk screen.
  const policy = perkPolicy(country, region, kind);
  const policyNote = perkPolicyNote(country, region, kind);

  async function submit(e: React.FormEvent) {
    e.preventDefault();
    setBusy(true);
    setError(null);
    const res = await createVenue(meId, {
      name,
      slug: slug.trim() || undefined,
      city,
      kind,
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

        {/* Bar or bottle shop. Not cosmetic: a shop runs no rooms, and its loyalty
            card needs its own legal permission, because at a shop a visit is a sale. */}
        <div className="glass grid grid-cols-2 gap-1 rounded-ctl p-1" role="group" aria-label="Venue kind">
          {([
            { id: "bar", label: "Bar", blurb: "People drink here" },
            { id: "store", label: "Shop", blurb: "People carry out" },
          ] as const).map((k) => (
            <button
              key={k.id}
              type="button"
              onClick={() => setKind(k.id)}
              aria-pressed={kind === k.id}
              className={clsx(
                "rounded-[7px] px-3 py-2 text-left transition-colors",
                kind === k.id ? "bg-ink text-paper" : "text-faint hover:text-ink",
              )}
            >
              <span className="block text-sm font-medium">{k.label}</span>
              <span className={clsx("block text-[11px]", kind === k.id ? "opacity-70" : "text-faint")}>{k.blurb}</span>
            </button>
          ))}
        </div>

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
type Section = "tonight" | "perks" | "offers" | "bookings" | "team" | "insights" | "guests" | "setup";

function VenueManage({ venue, meId, canManage }: { venue: Venue; meId: string; canManage: boolean }) {
  const { staff } = useVenueStaff(venue.id);
  const [confirmDelete, setConfirmDelete] = useState(false);
  // Kitchen's first (and only) door is Insights; everyone else opens on service.
  const [section, setSection] = useState<Section>(
    venue.myRole === "kitchen" ? "insights" : "tonight",
  );

  // A shop's first tab is the TILL, not the room — it has no rooms at all (the DB
  // refuses to attach one), because a bottle shop isn't a place you sit and drink.
  const store = venue.kind === "store";

  // Doors follow the ladder (049): managers get everything; front-of-house service
  // (bartender, waiter) gets Tonight + Insights (Ninkasi included — money nulled by
  // the DB below manager rank); kitchen is read-focused, so Insights only. Nobody
  // is shown a door they can't open.
  const service = venue.myRole === "bartender" || venue.myRole === "waiter";
  const sections: { id: Section; label: string }[] = canManage
    ? [
        { id: "tonight", label: store ? "Till" : "Tonight" },
        { id: "perks", label: store ? "Card" : "Perks" },
        // Dining offers + table bookings are a sit-down-venue thing — a bottle shop
        // has neither (the DB refuses both), so a store never sees these doors.
        ...(store ? [] : ([{ id: "offers", label: "Offers" }, { id: "bookings", label: "Tables" }] as { id: Section; label: string }[])),
        { id: "insights", label: "Insights" },
        { id: "guests", label: "Guests" },
        { id: "team", label: "Team" },
        { id: "setup", label: "Setup" },
      ]
    : service
      ? [
          { id: "tonight", label: store ? "Till" : "Tonight" },
          // Front-of-house handles the floor, so service staff see incoming bookings.
          ...(store ? [] : ([{ id: "bookings", label: "Tables" }] as { id: Section; label: string }[])),
          { id: "insights", label: "Insights" },
        ]
      : [{ id: "insights", label: "Insights" }];

  return (
    <div className="mt-4 border-t border-line pt-4">
      {!venue.verified && !canManage && (
        <p className="mb-4 text-xs leading-relaxed text-faint">
          This venue isn&apos;t verified yet — rooms and vibe work, but real-world perks wait until it is.
        </p>
      )}

      {sections.length > 1 && (
        <div className={clsx("glass mb-4 grid gap-1 rounded-ctl p-1", sections.length === 2 ? "grid-cols-2" : "grid-cols-3")}>
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

      {section === "offers" && canManage && (
        <>
          {!venue.verified && <VerificationPanel venue={venue} meId={meId} />}
          <VenueOfferEditor venue={venue} meId={meId} />
        </>
      )}

      {section === "bookings" && <VenueBookings venue={venue} />}

      {/* Insights (with Ninkasi's read) is for EVERY rung now — the DB nulls the
          money below manager rank, so a waiter sees pattern, never the till. */}
      {section === "insights" && <Insights venue={venue} />}

      {section === "guests" && canManage && <GuestBook venue={venue} />}

      {section === "team" && canManage && (
        <>
          <TeamKudos venueId={venue.id} />

          <p className="label mb-1.5 text-faint">The team</p>
          <p className="mb-3 text-xs leading-relaxed text-faint">
            Bartenders and waiters run service — open a room, record a tab, hand out vibe. Kitchen sees
            Insights and Ninkasi&apos;s read (no money). Managers also set the perk, add staff, and see
            takings. Everyone gets Ninkasi.
          </p>
          <ul className="mb-3 divide-y divide-line border-y border-line">
            {staff.map((s) => (
              <li key={s.id} className="flex items-center justify-between gap-3 py-2.5">
                <span className="min-w-0 truncate text-[15px] text-ink">
                  {s.id === meId ? "you" : s.name} <span className="text-faint">@{s.handle}</span>
                </span>
                <span className="flex shrink-0 items-center gap-3 text-sm">
                  <span className="text-xs text-faint">{s.role}</span>
                  {s.role !== "owner" && s.id !== meId && (
                    <button
                      onClick={() => removeStaff(venue.id, s.id)}
                      className="text-faint transition-colors hover:text-ink"
                    >
                      Remove
                    </button>
                  )}
                </span>
              </li>
            ))}
          </ul>
          <AddStaff venueId={venue.id} meId={meId} />
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
        {/* money is manager-only (049) — below that rung the DB hands back null */}
        <Stat label="takings" value={data.takings === null ? "—" : money(data.takings)} />
        <Stat
          label="came back"
          value={data.returningGuests === null ? "—" : `${Math.round((data.returningGuests / data.guests) * 100)}%`}
        />
        {/* Average tab is HIDDEN below k tabs — over 1–4 it would be one guest's spend. */}
        <Stat label="avg tab" value={data.takings !== null && data.tabs >= 5 ? money(data.takings / data.tabs) : "—"} />
        <Stat label="team thanked" value={String(data.kudos)} />
      </div>

      {/* Growth vs the previous equal-length window — the "are we up?" glance. */}
      {(data.prevGuests > 0 || (data.prevTakings ?? 0) > 0) && (
        <p className="mt-3 flex flex-wrap items-center gap-x-4 gap-y-1 text-xs text-faint">
          <span>vs the previous {days} days:</span>
          <TrendChip label="guests" cur={data.guests} prev={data.prevGuests} />
          {data.takings !== null && data.prevTakings !== null && (
            <TrendChip label="takings" cur={data.takings} prev={data.prevTakings} />
          )}
        </p>
      )}

      {/* Ninkasi's read sits right under the numbers it's grounded in — the same
          aggregates, never an individual — high on the page: for most owners the
          "what should I do next" line IS the product, the tiles are the evidence. */}
      <VenueAdvisor venue={venue} insights={data} days={days} />

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
  const policy = perkPolicy(venue.country, venue.region, venue.kind);
  const note = perkPolicyNote(venue.country, venue.region, venue.kind);
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

// ── dining offers: a PUBLIC, advertisable deal — a table deal, never a drink deal ──
// The Dineout surface's venue side. Only a verified bar can run one, only where the
// bar layer is lawful, and there is deliberately no "free drink" option — an alcohol
// reward lives in Perks (private), never here (public). The DB enforces all of it (050).
const OFFER_KINDS: { id: OfferKind; label: string; placeholder: string; hint: string }[] = [
  { id: "percent_off", label: "% off the bill", placeholder: "e.g. Flat 20% off the total bill", hint: "A percentage off the whole table's bill." },
  { id: "flat_deal", label: "A deal", placeholder: "e.g. A free starter with two mains", hint: "A fixed table deal — a starter, a dessert, an add-on." },
  { id: "set_menu", label: "Set menu", placeholder: "e.g. Chef's 5-course tasting menu", hint: "A fixed menu at a fixed price." },
  { id: "experience", label: "Experience", placeholder: "e.g. A guided coffee cupping", hint: "Something to come for — a tasting, a class, live music." },
];

function VenueOfferEditor({ venue, meId }: { venue: Venue; meId: string }) {
  const { offers, loading } = useVenueOffers(venue.id);
  const [kind, setKind] = useState<OfferKind>("percent_off");
  const [title, setTitle] = useState("");
  const [detail, setDetail] = useState("");
  const [percent, setPercent] = useState(20);
  const [error, setError] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);

  // A dining offer follows the SAME jurisdiction gate as a bar perk (allow_perks) —
  // it's only shown where the bar layer is lawful at all. Judged as a bar, never a shop.
  const policy = perkPolicy(venue.country, venue.region, "bar");
  const note = perkPolicyNote(venue.country, venue.region, "bar");

  async function add() {
    setBusy(true);
    setError(null);
    const err = await addDiningOffer(venue.id, meId, {
      title,
      detail: detail || undefined,
      kind,
      percentOff: kind === "percent_off" ? percent : undefined,
    });
    setBusy(false);
    if (err) {
      setError(err);
      return;
    }
    setTitle("");
    setDetail("");
  }

  if (!venue.verified) {
    return (
      <div className="mb-5">
        <p className="label mb-2 text-faint">Dining offers</p>
        <p className="text-sm text-faint">Get verified to publish a dining offer — a table deal guests can find and book.</p>
      </div>
    );
  }

  if (!policy.allowPerks) {
    return (
      <div className="mb-5">
        <p className="label mb-2 text-faint">Dining offers</p>
        <p className="max-w-prose text-sm leading-relaxed text-faint">
          {note ?? "Dining offers aren't available for a venue here."}
        </p>
      </div>
    );
  }

  const full = offers.length >= MAX_OFFERS;

  return (
    <div className="mb-5">
      <p className="label mb-2 text-faint">Dining offers</p>
      <p className="mb-3 max-w-prose text-xs leading-relaxed text-faint">
        A <span className="text-ink">dining</span> deal shown to guests in Discover — a bill discount, a set
        menu, an experience. Never a drink offer: a free or discounted drink is a loyalty perk (private),
        not an advert. Guests can book a table against it.
      </p>

      {loading ? (
        <div className="glass h-14 animate-pulse rounded-ctl" />
      ) : (
        <>
          {offers.length > 0 && (
            <ul className="mb-4 divide-y divide-line border-y border-line">
              {offers.map((o) => (
                <li key={o.id} className="flex items-center justify-between gap-3 py-2.5">
                  <span className="min-w-0">
                    <span className="block truncate text-[15px] text-ink">{o.title}</span>
                    {o.detail && <span className="block truncate text-xs text-faint">{o.detail}</span>}
                    {!o.active && <span className="text-xs text-faint">paused</span>}
                  </span>
                  <span className="flex shrink-0 items-center gap-3 text-sm">
                    <button
                      onClick={() => toggleDiningOffer(o.id, !o.active)}
                      className="text-faint transition-colors hover:text-ink"
                    >
                      {o.active ? "Pause" : "Show"}
                    </button>
                    <button onClick={() => removeDiningOffer(o.id)} className="text-faint transition-colors hover:text-ink">
                      Remove
                    </button>
                  </span>
                </li>
              ))}
            </ul>
          )}

          {full ? (
            <p className="text-xs leading-relaxed text-faint">
              Four offers is plenty — a short, legible menu is one a guest can actually read.
            </p>
          ) : (
            <>
              <p className="label mb-2 text-faint">{offers.length === 0 ? "Add an offer" : "Add another"}</p>

              <div className="mb-2 flex flex-wrap gap-1.5">
                {OFFER_KINDS.map((k) => (
                  <button
                    key={k.id}
                    onClick={() => setKind(k.id)}
                    aria-pressed={kind === k.id}
                    className={clsx(
                      "rounded-ctl px-3.5 py-1.5 text-sm transition-colors",
                      kind === k.id ? "bg-ink font-medium text-paper" : "glass glass-press text-muted hover:text-ink",
                    )}
                  >
                    {k.label}
                  </button>
                ))}
              </div>

              <p className="mb-2 text-xs leading-relaxed text-faint">{OFFER_KINDS.find((k) => k.id === kind)?.hint}</p>

              <div className="space-y-2">
                {kind === "percent_off" && (
                  <div className="flex items-center gap-2">
                    <input
                      type="number"
                      min={1}
                      max={100}
                      value={percent}
                      onChange={(e) => setPercent(Number(e.target.value))}
                      aria-label="Percent off"
                      className="tnum glass w-20 rounded-ctl px-3 py-2.5 text-[15px] text-ink"
                    />
                    <span className="text-sm text-faint">% off the bill</span>
                  </div>
                )}
                <input
                  value={title}
                  onChange={(e) => setTitle(e.target.value)}
                  placeholder={OFFER_KINDS.find((k) => k.id === kind)?.placeholder}
                  aria-label="Offer title"
                  className="glass w-full rounded-ctl px-4 py-2.5 text-[15px] text-ink placeholder:text-faint"
                />
                <input
                  value={detail}
                  onChange={(e) => setDetail(e.target.value)}
                  placeholder="Fine print — e.g. Mon–Thu, dine-in, table of 2+ (optional)"
                  aria-label="Offer detail"
                  className="glass w-full rounded-ctl px-4 py-2.5 text-[15px] text-ink placeholder:text-faint"
                />
              </div>

              {error && <p className="mt-2 text-sm text-accent">{error}</p>}

              <button
                onClick={add}
                disabled={!title.trim() || busy}
                className="mt-3 rounded-ctl bg-ink px-4 py-2 text-sm font-medium text-paper transition-opacity hover:opacity-90 disabled:opacity-50"
              >
                {busy ? "Saving…" : offers.length === 0 ? "Add offer" : "Add another"}
              </button>
            </>
          )}
        </>
      )}
    </div>
  );
}

// ── table bookings: the venue's incoming reservations, confirmed by staff ────
const RES_STATUS_LABEL: Record<ReservationStatus, string> = {
  requested: "asked",
  confirmed: "confirmed",
  declined: "declined",
  cancelled: "cancelled",
  seated: "seated",
  no_show: "no-show",
};

function prettyResDate(key: string): string {
  const d = new Date(`${key}T00:00:00`);
  if (Number.isNaN(d.getTime())) return key;
  return d.toLocaleDateString(undefined, { weekday: "short", day: "numeric", month: "short" });
}

function VenueBookings({ venue }: { venue: Venue }) {
  const { reservations, loading } = useVenueReservations(venue.id);
  const today = todayKey();
  // The floor cares about what's still coming — past/closed bookings drop to the bottom.
  const live = reservations.filter((r) => r.date >= today && (r.status === "requested" || r.status === "confirmed"));
  const rest = reservations.filter((r) => !(r.date >= today && (r.status === "requested" || r.status === "confirmed")));

  if (loading) return <div className="glass h-24 animate-pulse rounded-tile" />;

  if (reservations.length === 0) {
    return (
      <div>
        <p className="label mb-2 text-faint">Table bookings</p>
        <p className="text-sm leading-relaxed text-faint">
          No bookings yet. When a guest books a table against one of your dining offers, it lands here for you
          to confirm.
        </p>
      </div>
    );
  }

  return (
    <div>
      <p className="label mb-2 text-faint">Table bookings</p>
      {live.length > 0 && (
        <ul className="mb-4 space-y-2">
          {live.map((r) => (
            <BookingRow key={r.id} r={r} />
          ))}
        </ul>
      )}
      {rest.length > 0 && (
        <>
          <p className="label mb-2 mt-4 text-faint">Earlier</p>
          <ul className="space-y-2 opacity-70">
            {rest.map((r) => (
              <BookingRow key={r.id} r={r} />
            ))}
          </ul>
        </>
      )}
    </div>
  );
}

function BookingRow({ r }: { r: import("@/lib/reservations").VenueReservation }) {
  const requested = r.status === "requested";
  const confirmed = r.status === "confirmed";
  return (
    <li className="glass rounded-tile p-4">
      <div className="flex items-start justify-between gap-3">
        <div className="min-w-0">
          <p className="truncate text-[15px] text-ink">
            {r.guestName} {r.guestHandle && <span className="text-xs text-faint">@{r.guestHandle}</span>}
          </p>
          <p className="mt-0.5 text-xs text-faint">
            {prettyResDate(r.date)}
            {r.time && <> · {r.time.slice(0, 5)}</>} · party of {r.partySize}
            {" · "}
            <span className={clsx(requested ? "text-accent" : confirmed ? "text-ink" : "text-faint")}>
              {RES_STATUS_LABEL[r.status]}
            </span>
          </p>
          {r.offerTitle && <p className="mt-1 text-xs text-muted">on: {r.offerTitle}</p>}
          {r.note && <p className="mt-1 text-sm text-muted">“{r.note}”</p>}
        </div>
      </div>
      <div className="mt-3 flex flex-wrap items-center gap-x-4 gap-y-2 border-t border-line pt-3 text-sm">
        {requested && (
          <>
            <button onClick={() => setReservationStatus(r.id, "confirmed")} className="font-medium text-accent transition-opacity hover:opacity-80">
              Confirm
            </button>
            <button onClick={() => setReservationStatus(r.id, "declined")} className="text-faint transition-colors hover:text-ink">
              Decline
            </button>
          </>
        )}
        {confirmed && (
          <>
            <button onClick={() => setReservationStatus(r.id, "seated")} className="font-medium text-accent transition-opacity hover:opacity-80">
              Seated
            </button>
            <button onClick={() => setReservationStatus(r.id, "no_show")} className="text-faint transition-colors hover:text-ink">
              No-show
            </button>
            <button onClick={() => setReservationStatus(r.id, "cancelled")} className="text-faint transition-colors hover:text-ink">
              Cancel
            </button>
          </>
        )}
      </div>
    </li>
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

function AddStaff({ venueId, meId }: { venueId: string; meId: string }) {
  const [query, setQuery] = useState("");
  const [results, setResults] = useState<SocialProfile[]>([]);
  const [added, setAdded] = useState<Set<string>>(new Set());
  const [role, setRole] = useState<StaffRole>("bartender");

  useEffect(() => {
    if (query.trim().length < 2) {
      setResults([]);
      return;
    }
    const t = setTimeout(async () => setResults(await searchUsers(query)), 300);
    return () => clearTimeout(t);
  }, [query, meId]);

  async function add(id: string) {
    setAdded((s) => new Set(s).add(id));
    const err = await addStaff(venueId, id, role);
    if (err) setAdded((s) => { const n = new Set(s); n.delete(id); return n; });
  }

  return (
    <div className="mb-4">
      <label htmlFor={`add-staff-${venueId}`} className="label mb-2 block text-faint">Add to the team</label>
      {/* the rung they join at — service by default; a cook gets the read-only view */}
      <div className="mb-2 flex flex-wrap gap-1.5">
        {ASSIGNABLE_ROLES.map((r) => (
          <button
            key={r}
            type="button"
            onClick={() => setRole(r)}
            aria-pressed={role === r}
            className={clsx(
              "rounded-ctl border px-3 py-1.5 text-xs transition-colors",
              role === r ? "border-transparent bg-accent/10 font-medium text-ink" : "border-line text-muted hover:text-ink",
            )}
          >
            {ROLE_LABEL[r]}
          </button>
        ))}
      </div>
      <input
        id={`add-staff-${venueId}`}
        value={query}
        onChange={(e) => setQuery(e.target.value)}
        placeholder="Find a person by name or @handle"
        className={inputClass}
      />
      {query.trim().length >= 2 && (
        <ul className="mt-2 space-y-2">
          {results.length === 0 && <li className="px-1 text-sm text-faint">No one by that name or handle.</li>}
          {results.map((p) => {
            const isAdded = added.has(p.id);
            return (
              <li key={p.id} className="flex items-center justify-between gap-3 px-1">
                <span className="min-w-0 truncate text-[15px] text-ink">
                  {p.name} <span className="text-faint">@{p.handle}</span>
                </span>
                <button
                  disabled={isAdded}
                  onClick={() => add(p.id)}
                  className={clsx("shrink-0 text-sm transition-colors", isAdded ? "cursor-default text-faint" : "font-medium text-accent hover:opacity-80")}
                >
                  {isAdded ? "Added" : "Add"}
                </button>
              </li>
            );
          })}
        </ul>
      )}
    </div>
  );
}

// The owner sets the venue's coarse location once — standing in the bar. We keep only
// a ~40 km geohash cell (never a pin), which is what area taste trends match on so
// Ninkasi can read the neighbourhood. updateVenue bumps the version, so the label here
// flips to "set" on its own once the venue reloads.
function VenueLocation({ venue }: { venue: Venue }) {
  const [busy, setBusy] = useState(false);
  const [msg, setMsg] = useState<string | null>(null);

  async function setLoc() {
    setBusy(true);
    setMsg(null);
    const { geohash, error } = await requestLocationGeohash();
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
        Stand in your venue and set its location once. We keep only a rough ~40&nbsp;km cell — never a pin — so
        Ninkasi can read what your neighbourhood is drinking. {venue.geohash ? "It's set." : "Not set yet."}
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
