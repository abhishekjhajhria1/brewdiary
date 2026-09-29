// App links: the two files that let a tap on a bwdy.site link open the app instead of
// the browser — Android's /.well-known/assetlinks.json and Apple's
// /.well-known/apple-app-site-association. next.config rewrites both paths to
// /api/app-links/<platform>, which asks this module what to say for the host.
//
// One site, two apps: bwdy.site belongs to the guest app (test_m_app), bar.bwdy.site to
// the venue app (mobile-bar). The signing fingerprints and Apple team id come from
// server env, so rotating a key is a settings change, not a code change. With nothing
// set the file is simply absent (404) and the links open in the browser, as today.

export interface AppLinkEnv {
  /** Comma-separated SHA-256 signing-certificate fingerprints ("AB:CD:…"). */
  ANDROID_CERT_SHA256_GUEST?: string;
  ANDROID_CERT_SHA256_BAR?: string;
  /** The 10-character Apple Developer team id. */
  APPLE_TEAM_ID?: string;
}

interface App {
  id: string; // Android package / iOS bundle id
  paths: string[]; // URL paths the app opens
  androidCerts: keyof AppLinkEnv;
}

const GUEST: App = { id: "site.bwdy.brewdiary", paths: ["/p/*", "/u/*", "/party/*", "/m/*"], androidCerts: "ANDROID_CERT_SHA256_GUEST" };
const BAR: App = { id: "site.bwdy.bar", paths: ["/join/*"], androidCerts: "ANDROID_CERT_SHA256_BAR" };

export function appForHost(host: string): App {
  return host.toLowerCase().startsWith("bar.") ? BAR : GUEST;
}

const FINGERPRINT = /^([0-9A-F]{2}:){31}[0-9A-F]{2}$/;

function certs(raw: string | undefined): string[] {
  return (raw ?? "")
    .split(",")
    .map((s) => s.trim().toUpperCase())
    .filter((s) => FINGERPRINT.test(s));
}

/** Android Digital Asset Links, or null when no valid fingerprint is configured. */
export function assetLinks(host: string, env: AppLinkEnv): unknown[] | null {
  const app = appForHost(host);
  const sha = certs(env[app.androidCerts]);
  if (!sha.length) return null;
  return [
    {
      relation: ["delegate_permission/common.handle_all_urls"],
      target: { namespace: "android_app", package_name: app.id, sha256_cert_fingerprints: sha },
    },
  ];
}

/** Apple's app-site-association, or null without a valid team id. */
export function appleAssociation(host: string, env: AppLinkEnv): object | null {
  const team = (env.APPLE_TEAM_ID ?? "").trim().toUpperCase();
  if (!/^[A-Z0-9]{10}$/.test(team)) return null;
  const app = appForHost(host);
  return {
    applinks: {
      details: [{ appIDs: [`${team}.${app.id}`], components: app.paths.map((p) => ({ "/": p })) }],
    },
  };
}
