// Money. brewdiary was built in India and "₹" was hardcoded into eight files —
// which is fine until a bar in London sets a perk and the app tells its guests
// they need to spend "₹3000". Currency is a property of the PLACE, not of the app.
//
// A venue carries its own currency (venues.currency, migration 022, defaulted from
// its country). Split — which is between friends, not venues — uses a per-device
// preference, because a tab shared in Goa and a tab shared in Berlin are different
// tabs and only the person splitting them knows which.
//
// Formatting goes through Intl, so grouping and symbol placement are correct per
// locale: ₹1,23,456 in India (lakhs!), €1.234,56 in Germany, $1,234.56 in the US.
// Never concatenate a symbol by hand again.

/** ISO-4217 for the markets in jurisdiction.ts. */
export const CURRENCY_BY_COUNTRY: Record<string, string> = {
  IN: "INR",
  US: "USD",
  GB: "GBP",
  IE: "EUR",
  FR: "EUR",
  DE: "EUR",
  ES: "EUR",
  IT: "EUR",
  NL: "EUR",
  FI: "EUR",
  AU: "AUD",
  CA: "CAD",
  NZ: "NZD",
  SG: "SGD",
  JP: "JPY",
  KR: "KRW",
  TH: "THB",
  NO: "NOK",
  SE: "SEK",
  PL: "PLN",
  TR: "TRY",
  ZA: "ZAR",
  BR: "BRL",
  MX: "MXN",
  AE: "AED",
};

export const DEFAULT_CURRENCY = "INR";

export function currencyForCountry(country?: string | null): string {
  return CURRENCY_BY_COUNTRY[(country || "").toUpperCase()] ?? DEFAULT_CURRENCY;
}

/** Currencies that have no minor unit — a "50.00" yen doesn't exist. */
const ZERO_DECIMAL = new Set(["JPY", "KRW"]);

/**
 * Format an amount in a currency, correctly for that currency's own conventions.
 * Falls back to a bare number rather than throwing if a currency code is unknown.
 */
export function formatMoney(amount: number, currency: string = DEFAULT_CURRENCY, opts?: { round?: boolean }): string {
  const code = (currency || DEFAULT_CURRENCY).toUpperCase();
  const zero = ZERO_DECIMAL.has(code);
  const digits = zero || opts?.round ? 0 : Number.isInteger(amount) ? 0 : 2;
  try {
    return new Intl.NumberFormat(localeFor(code), {
      style: "currency",
      currency: code,
      minimumFractionDigits: digits,
      maximumFractionDigits: digits,
    }).format(amount);
  } catch {
    return `${amount}`;
  }
}

/** Just the symbol, for a tight spot like an input prefix. */
export function currencySymbol(currency: string = DEFAULT_CURRENCY): string {
  const code = (currency || DEFAULT_CURRENCY).toUpperCase();
  try {
    return (
      new Intl.NumberFormat(localeFor(code), { style: "currency", currency: code })
        .formatToParts(0)
        .find((p) => p.type === "currency")?.value ?? code
    );
  } catch {
    return code;
  }
}

// The locale drives grouping (Indian lakhs vs. Western thousands) and symbol
// placement. We key it off the currency, which is what we actually know.
function localeFor(code: string): string {
  switch (code) {
    case "INR":
      return "en-IN";
    case "USD":
      return "en-US";
    case "GBP":
      return "en-GB";
    case "EUR":
      return "de-DE";
    case "JPY":
      return "ja-JP";
    case "KRW":
      return "ko-KR";
    case "THB":
      return "th-TH";
    case "AUD":
      return "en-AU";
    case "CAD":
      return "en-CA";
    case "BRL":
      return "pt-BR";
    default:
      return "en-US";
  }
}

// ── flexing a tab: a BAND, never the figure ──────────────────────────────────
// A flexed tab goes on a screen on a wall, next to a person's name, in a room full
// of strangers with cameras. An exact number there is two bad things at once:
//
//   1. A precise financial fact about a named individual, published. "Anita ₹2,340"
//      is a receipt. Anyone can photograph it, and we can never un-publish it.
//   2. A spending race. If the board is exact, you beat the person above you by
//      buying one more drink — the app would be paying people to drink more, which
//      is the one thing this product exists to not do.
//
// A band keeps the flex (the point is "I bought the round", not "I bought ₹2,340 of
// round") and destroys both problems: it's not a receipt, and you cannot out-rank
// anyone by ₹1 — you'd have to double your tab, which nobody does for a wall screen.
//
// Bands are ×1, ×2, ×5, ×10, ×20 of a per-currency step, so they read naturally in
// the local money (₹500 / ₹1,000 / ₹2,500 in Mumbai; $25 / $50 / $125 in New York).
const BAND_STEP: Record<string, number> = {
  INR: 500,
  JPY: 3000,
  KRW: 30000,
  THB: 500,
  ZAR: 250,
  MXN: 250,
  BRL: 100,
  TRY: 500,
  NOK: 250,
  SEK: 250,
  PLN: 100,
  AED: 100,
};
const DEFAULT_STEP = 25; // USD/EUR/GBP/AUD/CAD/NZD/SGD — roughly "a round"

/**
 * The band a tab falls in, as a display string: "₹2,500+".
 *
 * NEVER show a flexed tab as an exact figure — use this. The precision is the harm,
 * not the amount.
 */
export function spendBand(amount: number, currency: string = DEFAULT_CURRENCY): string {
  const code = (currency || DEFAULT_CURRENCY).toUpperCase();
  const step = BAND_STEP[code] ?? DEFAULT_STEP;
  const bands = [1, 2, 5, 10, 20].map((m) => m * step);

  // Below the first band there is nothing to flex — say so, rather than printing a
  // small number that's really just "they bought one drink".
  if (!Number.isFinite(amount) || amount < bands[0]) {
    return `under ${formatMoney(bands[0], code, { round: true })}`;
  }
  const floor = bands.filter((b) => amount >= b).pop()!;
  return `${formatMoney(floor, code, { round: true })}+`;
}

// ── the person's own currency (Split, which has no venue) ────────────────────
const KEY = "brewdiary.currency.v1";

export function savedCurrency(): string {
  if (typeof window === "undefined") return DEFAULT_CURRENCY;
  try {
    return window.localStorage.getItem(KEY) || DEFAULT_CURRENCY;
  } catch {
    return DEFAULT_CURRENCY;
  }
}

export function saveCurrency(code: string) {
  try {
    window.localStorage.setItem(KEY, code.toUpperCase());
  } catch {
    /* private mode — the default stands */
  }
}
