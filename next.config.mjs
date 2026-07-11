/** @type {import('next').NextConfig} */
const nextConfig = {
  reactStrictMode: true,
  // Keep the on-device embedding runtime (Transformers.js + onnxruntime) OUT of the
  // webpack bundle — it ships native/wasm assets that must be require()'d at runtime,
  // not bundled. Only the bartender API route (nodejs runtime) loads it. See src/lib/embed.ts.
  serverExternalPackages: ["@xenova/transformers"],
};

export default nextConfig;
