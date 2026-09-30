import { appleAssociation, assetLinks } from "@/lib/appLinks";

export const dynamic = "force-dynamic";

// Served at /.well-known/assetlinks.json and /.well-known/apple-app-site-association
// (rewrites in next.config.mjs). Both must be plain JSON over HTTPS with no redirect.
export async function GET(req: Request, { params }: { params: Promise<{ platform: string }> }) {
  const { platform } = await params;
  const host = req.headers.get("host") ?? "";
  const env = {
    ANDROID_CERT_SHA256_GUEST: process.env.ANDROID_CERT_SHA256_GUEST,
    ANDROID_CERT_SHA256_BAR: process.env.ANDROID_CERT_SHA256_BAR,
    APPLE_TEAM_ID: process.env.APPLE_TEAM_ID,
  };
  const body = platform === "android" ? assetLinks(host, env) : platform === "apple" ? appleAssociation(host, env) : null;
  if (!body) return new Response("Not found", { status: 404 });
  return new Response(JSON.stringify(body), {
    headers: { "Content-Type": "application/json", "Cache-Control": "public, max-age=3600" },
  });
}
