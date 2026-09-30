// Outside signals (049): public facts about places, cleaned before they land.
//
// Scrapers, feeds and spreadsheets produce messy records. This turns one into a row
// for public.area_signals — or refuses it — and it is the ONLY way in: the import
// route (/api/signals/import) and the CLI (scripts/import-signals.mjs) both use it,
// and the table's own guard refuses whatever still slips through.
//
// The rule: places and happenings, never people. A review arrives only as numbers on a
// venue (rating, count). Emails, phone numbers, @handles and links inside text are
// removed; a field that names a person is dropped; a record ABOUT a person is refused.
//
// Pure and import-free on purpose, so the CLI can load it with Node's type stripping.
// The one outside need, turning coordinates into a geohash, is passed in.

export const SIGNAL_KINDS = ["event", "opening", "closing", "holiday", "hours", "price", "venue", "trend", "weather", "news"] as const;
export type SignalKind = (typeof SIGNAL_KINDS)[number];

/** Words a scraper might use, folded into ours. */
const KIND_ALIASES: Record<string, SignalKind> = {
  festival: "event",
  concert: "event",
  gig: "event",
  match: "event",
  game: "event",
  launch: "opening",
  new: "opening",
  closed: "closing",
  "dry day": "holiday",
  dry_day: "holiday",
  menu_price: "price",
  place: "venue",
  business: "venue",
};

/** Records ABOUT a person are refused whole — there is no safe part to keep. */
const PERSON_KINDS = new Set(["review", "person", "profile", "post", "comment", "user", "customer", "reviewer", "author", "tweet", "story"]);

/** A fact key that names a person is dropped (the SQL guard refuses the same). */
const PERSONAL_KEY = /(^|_)(name|email|phone|mobile|user|author|handle|profile|reviewer|contact|owner|person|age|gender)s?(_|$)/i;

const GEOHASH = /^[0-9b-hjkmnp-z]+$/;
const DATE = /^(\d{4})-(\d{2})-(\d{2})/;

const EMAIL = /[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}/g;
const HANDLE = /(^|[^A-Za-z0-9])@[A-Za-z0-9_.]{2,}/g;
const LINK = /\b(?:https?:\/\/|www\.)\S+/gi;
const PHONE = /\+?\d[\d ().-]{8,}\d/g;
const ISO_DATE = /\d{4}-\d{2}-\d{2}/g;

export interface SignalRow {
  area: string;
  cell: string | null;
  kind: SignalKind;
  title: string;
  detail: string | null;
  starts_on: string | null;
  ends_on: string | null;
  facts: Record<string, string | number | boolean>;
  source: string;
  source_url: string | null;
  dedupe_key: string;
  expires_at: string;
}

export type Clean = { ok: true; row: SignalRow } | { ok: false; reason: string };
export type Encode = (lat: number, lon: number, precision: number) => string;

/** Take anything that looks like a person out of free text. */
export function redact(text: string): string {
  // Dates look like phone numbers to a regex; set them aside first.
  const dates: string[] = [];
  let t = text.replace(ISO_DATE, (d) => `\u0000${dates.push(d) - 1}\u0000`);
  t = t
    .replace(EMAIL, "[removed]")
    .replace(LINK, "")
    .replace(HANDLE, "$1[removed]")
    .replace(PHONE, "[removed]");
  t = t.replace(/\u0000(\d+)\u0000/g, (_, i) => dates[Number(i)]);
  return t.replace(/\s+/g, " ").trim();
}

function str(x: unknown): string {
  return typeof x === "string" ? x : typeof x === "number" && Number.isFinite(x) ? String(x) : "";
}

function day(x: unknown): string | null {
  const m = DATE.exec(str(x).trim());
  if (!m) return null;
  const d = new Date(`${m[1]}-${m[2]}-${m[3]}T00:00:00Z`);
  return Number.isNaN(d.getTime()) || d.toISOString().slice(0, 10) !== `${m[1]}-${m[2]}-${m[3]}` ? null : `${m[1]}-${m[2]}-${m[3]}`;
}

function addDays(isoDay: string, n: number): Date {
  const d = new Date(`${isoDay}T00:00:00Z`);
  d.setUTCDate(d.getUTCDate() + n);
  return d;
}

/** Only an https link, and never its query string (tracking ids, session tokens). */
function cleanUrl(x: unknown): string | null {
  const s = str(x).trim();
  if (!s) return null;
  try {
    const u = new URL(s);
    if (u.protocol !== "https:") return null;
    u.search = "";
    u.hash = "";
    const out = u.toString();
    return out.length <= 500 ? out : null;
  } catch {
    return null;
  }
}

function cleanFacts(x: unknown): Record<string, string | number | boolean> {
  if (typeof x !== "object" || x === null || Array.isArray(x)) return {};
  const out: Record<string, string | number | boolean> = {};
  for (const [k, v] of Object.entries(x as Record<string, unknown>)) {
    if (Object.keys(out).length >= 12) break;
    const key = k.trim().toLowerCase();
    if (!/^[a-z][a-z0-9_]{0,31}$/.test(key) || PERSONAL_KEY.test(key)) continue;
    if (typeof v === "number" && Number.isFinite(v)) out[key] = v;
    else if (typeof v === "boolean") out[key] = v;
    else if (typeof v === "string") {
      const s = redact(v).slice(0, 60);
      if (s) out[key] = s;
    }
  }
  return out;
}

/** Where the thing is: a geohash, or coordinates turned into one here (~1 km).
 *  Raw coordinates are never kept. */
function place(raw: Record<string, unknown>, encode?: Encode): { area: string; cell: string | null } | null {
  let gh = str(raw.geohash ?? raw.cell ?? raw.area).trim().toLowerCase();
  const lat = Number(raw.lat ?? raw.latitude);
  const lon = Number(raw.lon ?? raw.lng ?? raw.longitude);
  if (!gh && encode && Number.isFinite(lat) && Number.isFinite(lon) && Math.abs(lat) <= 90 && Math.abs(lon) <= 180) {
    gh = encode(lat, lon, 6);
  }
  if (gh.length < 4 || !GEOHASH.test(gh)) return null;
  return { area: gh.slice(0, 4), cell: gh.length >= 5 ? gh.slice(0, 7) : null };
}

const LONG_LIVED: SignalKind[] = ["price", "venue", "hours", "trend"];
const SHORT_LIVED: SignalKind[] = ["news", "weather"];

/** One messy record in, one clean row (or a reason) out. */
export function cleanSignal(input: unknown, encode?: Encode, now: Date = new Date()): Clean {
  if (typeof input !== "object" || input === null || Array.isArray(input)) return { ok: false, reason: "not a record" };
  const raw = input as Record<string, unknown>;

  const kindIn = str(raw.kind ?? raw.type).trim().toLowerCase();
  if (PERSON_KINDS.has(kindIn)) return { ok: false, reason: "about a person, not a place" };
  const kind = (SIGNAL_KINDS as readonly string[]).includes(kindIn) ? (kindIn as SignalKind) : KIND_ALIASES[kindIn];
  if (!kind) return { ok: false, reason: `unknown kind "${kindIn || "(none)"}"` };

  const where = place(raw, encode);
  if (!where) return { ok: false, reason: "no place (a geohash, or lat and lon)" };

  const title = redact(str(raw.title ?? raw.name)).slice(0, 140).trim();
  if (title.replace(/\[removed\]/g, "").trim().length < 3) return { ok: false, reason: "no usable title" };
  const detailRaw = redact(str(raw.detail ?? raw.description)).slice(0, 600).trim();

  const source = str(raw.source).trim().slice(0, 80);
  if (source.length < 2) return { ok: false, reason: "no source (say where it came from)" };

  let starts = day(raw.starts_on ?? raw.start ?? raw.date);
  let ends = day(raw.ends_on ?? raw.end);
  if (starts && ends && ends < starts) [starts, ends] = [ends, starts];

  const horizon = new Date(now.getTime() + 3 * 365 * 86_400_000);
  if ((starts && addDays(starts, 0) > horizon) || (ends && addDays(ends, 0) > horizon)) return { ok: false, reason: "a date more than 3 years ahead" };
  const expires =
    ends ? addDays(ends, 1) : starts ? addDays(starts, 1) : new Date(now.getTime() + (LONG_LIVED.includes(kind) ? 90 : SHORT_LIVED.includes(kind) ? 3 : 30) * 86_400_000);
  if (expires <= now) return { ok: false, reason: "already over" };

  const ext = str(raw.external_id ?? raw.id).trim();
  const key = (ext ? `${source}:${ext}` : `${source}:${kind}:${where.area}:${title.toLowerCase()}:${starts ?? ""}`).toLowerCase().slice(0, 300);

  return {
    ok: true,
    row: {
      area: where.area,
      cell: where.cell,
      kind,
      title,
      detail: detailRaw || null,
      starts_on: starts,
      ends_on: ends,
      facts: cleanFacts(raw.facts),
      source,
      source_url: cleanUrl(raw.source_url ?? raw.url),
      dedupe_key: key,
      expires_at: expires.toISOString(),
    },
  };
}

/** A batch: clean each record, keep the last of any duplicates, report every refusal. */
export function cleanBatch(
  records: unknown[],
  encode?: Encode,
  now: Date = new Date(),
): { rows: SignalRow[]; refused: { index: number; reason: string }[] } {
  const byKey = new Map<string, SignalRow>();
  const refused: { index: number; reason: string }[] = [];
  records.forEach((r, index) => {
    const c = cleanSignal(r, encode, now);
    if (c.ok) byKey.set(c.row.dedupe_key, c.row);
    else refused.push({ index, reason: c.reason });
  });
  return { rows: [...byKey.values()], refused };
}
