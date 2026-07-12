/** @type {import('next').NextConfig} */
const nextConfig = {
  reactStrictMode: true,
  // Keep the on-device embedding runtime (Transformers.js + onnxruntime) OUT of the
  // webpack bundle — it ships native/wasm assets that must be require()'d at runtime,
  // not bundled. Only the bartender API route (nodejs runtime) loads it. See src/lib/embed.ts.
  serverExternalPackages: ["@xenova/transformers"],
  async headers() {
    return [
      {
        source: "/:path*",
        headers: [
          // no screen in this app should ever render inside someone else's iframe
          { key: "X-Frame-Options", value: "DENY" },
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
