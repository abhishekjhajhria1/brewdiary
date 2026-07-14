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
  type Venue,
} from "@/lib/venues";
import { searchUsers, type SocialProfile } from "@/lib/friends";
import { useVenueRooms, createParty } from "@/lib/parties";
import {
  useVenuePerk,
  setVenuePerk,
  clearVenuePerk,
  perkPolicy,
  perkPolicyNote,
  type PerkKind,
} from "@/lib/perks";
import { KNOWN_COUNTRIES } from "@/lib/jurisdiction";
import { currencyForCountry, currencySymbol, formatMoney } from "@/lib/money";
import { useRoomGuests, staffAwardVibe, recordSpend, STAFF_VIBE_REASONS } from "@/lib/points";
import { todayKey } from "@/lib/date";

const SECTIONS: { name: string; blurb: string }[] = [
  { name: "Rooms", blurb: "Open a room for the night. Guests with the app join by a code on the table — the night becomes a shared board." },
  { name: "Sparks & vibe", blurb: "Sparks are for trying something new — a new place, a new drink. Coming back again isn't a score. You and the table hand out vibe, positive only, and nobody is ranked by what they spent." },
  { name: "House perks", blurb: "Loyalty is YOUR reward to give — a free pour on the next visit, a house special. Private between you and each guest, and it's what brings them back." },
  { name: "The kiosk screen", blurb: "Cast the room to a screen on the wall. Guests choose to appear for that night only, and everyone drops off when it ends." },
];

function Header({ profile }: { profile?: Profile | null }) {
  return (
    <header className="mb-8 flex items-center justify-between border-b border-line pb-4">
      <span className="font-display text-lg italic text-muted">brewdiary</span>
      <span className="flex items-center gap-3">
        <span className="label text-faint">for venues</span>
        {profile && (
          <button onClick={() => signOut()} className="text-sm text-faint transition-colors hover:text-ink">
            Sign out
          </button>
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
      <p className="label mb-2 text-faint">The dashboard</p>
      <h1 className="font-display text-4xl leading-tight tracking-tight text-ink sm:text-5xl">Your bar, on the board.</h1>
      <p className="mt-3 max-w-prose text-[15px] leading-relaxed text-muted">
        Turn an ordinary night into a room your guests play in — good vibes and coming back, not who spent the most.
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
  const [country, setCountry] = useState("IN");
  const [region, setRegion] = useState("");
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  // The address preview follows the name until the owner types their own slug.
  const effectiveSlug = slug.trim() || slugify(name);
  const slugValid = isValidSlug(effectiveSlug);

  async function submit(e: React.FormEvent) {
    e.preventDefault();
    setBusy(true);
    setError(null);
    const res = await createVenue(meId, {
      name,
      slug: slug.trim() || undefined,
      city,
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

        {/* Only the US needs a state from us — that's where drink-deal rules split. */}
        {country === "US" && (
          <input
            value={region}
            onChange={(e) => setRegion(e.target.value.toUpperCase().slice(0, 2))}
            placeholder="State code (e.g. NY, MA)"
            aria-label="State"
            className={inputClass}
          />
        )}
      </div>

      <p className="mt-2.5 text-xs leading-relaxed text-faint">
        Where you are decides what kind of loyalty reward is legal — some countries don&apos;t allow a free
        drink to be earned by buying drinks. We&apos;ll show you the rule when you set your perk.
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

function VenueManage({ venue, meId, canManage }: { venue: Venue; meId: string; canManage: boolean }) {
  const { staff } = useVenueStaff(venue.id);
  const [confirmDelete, setConfirmDelete] = useState(false);

  return (
    <div className="mt-4 border-t border-line pt-4">
      {!venue.verified &&
        (canManage ? (
          <VerificationPanel venue={venue} meId={meId} />
        ) : (
          <p className="mb-4 text-xs leading-relaxed text-faint">
            This venue isn&apos;t verified yet — rooms and vibe work, but real-world perks wait until it is.
          </p>
        ))}

      <VenueRooms venue={venue} meId={meId} />

      {canManage && <VenuePerkEditor venue={venue} />}

      <p className="label mb-2 text-faint">The team</p>
      <ul className="mb-3 divide-y divide-line border-y border-line">
        {staff.map((s) => (
          <li key={s.id} className="flex items-center justify-between gap-3 py-2.5">
            <span className="min-w-0 truncate text-[15px] text-ink">
              {s.id === meId ? "you" : s.name} <span className="text-faint">@{s.handle}</span>
            </span>
            <span className="flex shrink-0 items-center gap-3 text-sm">
              <span className="text-xs text-faint">{s.role}</span>
              {canManage && s.role !== "owner" && s.id !== meId && (
                <button onClick={() => removeStaff(venue.id, s.id)} className="text-faint transition-colors hover:text-ink">
                  Remove
                </button>
              )}
            </span>
          </li>
        ))}
      </ul>

      {canManage && <AddStaff venueId={venue.id} meId={meId} />}

      {canManage && <EditVenue venue={venue} />}

      {venue.myRole === "owner" && (
        <div className="mt-4 text-sm">
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
    </div>
  );
}

function VenueRooms({ venue, meId }: { venue: Venue; meId: string }) {
  const { rooms, loading } = useVenueRooms(venue.id);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [copied, setCopied] = useState<string | null>(null);
  const [openRoom, setOpenRoom] = useState<string | null>(null);
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
                <RoomGuestList partyId={r.id} verified={venue.verified} currency={currencyForCountry(venue.country)} />
              )}
            </li>
          ))}
        </ul>
      )}
    </div>
  );
}

// The bar's people hand out vibe. Staff aren't party members, so the guest list
// and the award both go through definer rpcs. Positive-only — there is no way to
// dock anyone here, and a guest is never publicly rated.
function RoomGuestList({
  partyId,
  verified,
  currency,
}: {
  partyId: string;
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
              <span className="min-w-0 truncate text-[15px] text-ink">{g.name}</span>
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

function VenuePerkEditor({ venue }: { venue: Venue }) {
  const { perk, loading } = useVenuePerk(venue.id);
  const [kind, setKind] = useState<PerkKind>("visits");
  const [threshold, setThreshold] = useState(5);
  const [reward, setReward] = useState("");
  const [rewardAlcoholic, setRewardAlcoholic] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [saved, setSaved] = useState(false);

  // What this venue may lawfully offer, decided by WHERE IT IS. The database has
  // the final say (020_perk_policy.sql); this is so the bar sees the rule rather
  // than bumping into an error.
  const policy = perkPolicy(venue.country, venue.region);
  const note = perkPolicyNote(venue.country, venue.region);

  useEffect(() => {
    if (perk) {
      setKind(perk.kind);
      setThreshold(perk.threshold);
      setReward(perk.reward);
      setRewardAlcoholic(perk.rewardAlcoholic);
    }
  }, [perk]);

  // Never leave the editor sitting on an option the venue can't actually use.
  useEffect(() => {
    if (!policy.allowSpendPerk && kind === "spend") setKind("visits");
    if (!policy.allowAlcoholReward && rewardAlcoholic) setRewardAlcoholic(false);
  }, [policy.allowSpendPerk, policy.allowAlcoholReward, kind, rewardAlcoholic]);

  if (!venue.verified) {
    return (
      <div className="mb-5">
        <p className="label mb-2 text-faint">House perk</p>
        <p className="text-sm text-faint">Get verified to offer a perk — a reward that brings guests back.</p>
      </div>
    );
  }

  // Some places forbid a loyalty perk on alcohol entirely (Thailand, Norway…), and
  // anywhere we haven't researched is treated the same way — deny by default. Say
  // so honestly instead of showing an editor that will only ever fail.
  if (!policy.allowPerks) {
    return (
      <div className="mb-5">
        <p className="label mb-2 text-faint">House perk</p>
        <p className="max-w-prose text-sm leading-relaxed text-faint">
          {note ?? "Loyalty perks aren't available for a venue here."}
        </p>
      </div>
    );
  }

  async function save() {
    setError(null);
    const err = await setVenuePerk(venue.id, kind, threshold, reward, rewardAlcoholic);
    if (err) {
      setError(err);
      return;
    }
    setSaved(true);
    setTimeout(() => setSaved(false), 1600);
  }

  const spend = kind === "spend";

  return (
    <div className="mb-5">
      <p className="label mb-2 text-faint">House perk</p>
      {loading ? (
        <div className="glass h-14 animate-pulse rounded-ctl" />
      ) : (
        <>
          {/* Where the bar is decides what it may offer. We say so plainly — a
              licensee needs to know the rule, not just be blocked by it. */}
          {note && (
            <p className="glass mb-2.5 rounded-ctl px-3.5 py-2.5 text-xs leading-relaxed text-muted">{note}</p>
          )}

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
              ? "Reward a guest once their tab at your place passes this. Only your staff can record a tab — a guest can never enter their own."
              : "Reward a guest after this many visits — a check-in at one of your rooms counts as a visit."}
          </p>

          <div className="flex items-center gap-2">
            <input
              type="number"
              min={1}
              max={spend ? 1000000 : 100}
              value={threshold}
              onChange={(e) => setThreshold(Number(e.target.value))}
              aria-label={spend ? "Rupees to spend" : "Visits needed"}
              className="tnum glass w-24 rounded-ctl px-3 py-2.5 text-[15px] text-ink"
            />
            <input
              value={reward}
              onChange={(e) => setReward(e.target.value)}
              placeholder={spend ? "e.g. a free drink next visit" : "e.g. a free pour"}
              aria-label="Reward"
              className="glass w-full rounded-ctl px-4 py-2.5 text-[15px] text-ink placeholder:text-faint"
            />
          </div>
          <p className="mt-1.5 text-xs text-faint">
            {spend
              ? `Reward at ${formatMoney(threshold || 0, currencyForCountry(venue.country), { round: true })}`
              : `Reward after ${threshold || 0} visits`}
          </p>

          {/* The reward's NATURE is the whole legal question. A loyalty scheme
              whose prize isn't alcohol isn't an alcohol loyalty scheme — which is
              why this feature can exist outside India at all. */}
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
          <div className="mt-3 flex items-center gap-3">
            <button
              onClick={save}
              disabled={!reward.trim()}
              className="rounded-ctl bg-ink px-4 py-2 text-sm font-medium text-paper transition-opacity hover:opacity-90 disabled:opacity-50"
            >
              {saved ? "Saved" : perk ? "Update perk" : "Set perk"}
            </button>
            {perk && (
              <button onClick={() => clearVenuePerk(venue.id)} className="text-sm text-faint transition-colors hover:text-ink">
                Remove
              </button>
            )}
          </div>
        </>
      )}
    </div>
  );
}

function AddStaff({ venueId, meId }: { venueId: string; meId: string }) {
  const [query, setQuery] = useState("");
  const [results, setResults] = useState<SocialProfile[]>([]);
  const [added, setAdded] = useState<Set<string>>(new Set());

  useEffect(() => {
    if (query.trim().length < 2) {
      setResults([]);
      return;
    }
    const t = setTimeout(async () => setResults(await searchUsers(query, meId)), 300);
    return () => clearTimeout(t);
  }, [query, meId]);

  async function add(id: string) {
    setAdded((s) => new Set(s).add(id));
    const err = await addStaff(venueId, id, "bartender");
    if (err) setAdded((s) => { const n = new Set(s); n.delete(id); return n; });
  }

  return (
    <div className="mb-4">
      <label htmlFor={`add-staff-${venueId}`} className="label mb-2 block text-faint">Add to the team</label>
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
