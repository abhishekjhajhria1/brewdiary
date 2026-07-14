/** @type {import('next').NextConfig} */
const nextConfig = {
  reactStrictMode: true,
  // Keep the on-device embedding runtime (Transformers.js + onnxruntime) OUT of the
  // webpack bundle — it ships native/wasm assets that must be require()'d at runtime,
  // not bundled. Only the bartender API route (nodejs runtime) loads it. See src/lib/embed.ts.
  serverExternalPackages: ["@huggingface/transformers"],
  async headers() {
    return [
      {
        source: "/:path*",
        headers: [
          // Once a browser has seen this over HTTPS it refuses plain HTTP for two
          // years — which kills SSL-stripping on café wifi, where people actually
          // use a drink diary. Vercel serves HTTPS-only anyway; this makes the
          // BROWSER enforce it too. (Not preload-listed yet — preload is a one-way
          // door for every future subdomain, so it's a deliberate later step.)
          { key: "Strict-Transport-Security", value: "max-age=63072000; includeSubDomains" },
          // no screen in this app should ever render inside someone else's iframe
          { key: "X-Frame-Options", value: "DENY" },
          // …the modern spelling of the same rule, plus the two CSP directives we can
          // adopt without a nonce build. (Next injects inline scripts and our
          // theme/age-gate bootstraps are inline by design, so a full script-src CSP
          // needs nonces — that's a dedicated change, not a header sweep.)
          { key: "Content-Security-Policy", value: "frame-ancestors 'none'; base-uri 'self'; form-action 'self'" },
          { key: "X-Content-Type-Options", value: "nosniff" },
          { key: "Referrer-Policy", value: "strict-origin-when-cross-origin" },
          // camera/mic never used; geolocation reserved for Discover (same origin only)
          { key: "Permissions-Policy", value: "camera=(), microphone=(), geolocation=(self)" },
        ],
      },
    ];
  },
};

export default nextConfig;
