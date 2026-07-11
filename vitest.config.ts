import { defineConfig } from "vitest/config";
import { fileURLToPath } from "node:url";

// Unit tests for the pure "brains" of the app (lib/derive, date, expenses math,
// ratelimit, aidb pseudonymize). Kept in /tests, out of the Next build (see tsconfig
// exclude). `@/…` resolves to ./src, matching the app.
export default defineConfig({
  resolve: {
    alias: { "@": fileURLToPath(new URL("./src", import.meta.url)) },
  },
  test: {
    environment: "node",
    include: ["tests/**/*.test.ts"],
  },
});
