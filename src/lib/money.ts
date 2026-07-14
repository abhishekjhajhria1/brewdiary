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
