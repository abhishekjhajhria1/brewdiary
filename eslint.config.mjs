// ESLint flat config — Next.js 15 core-web-vitals + TypeScript rules via FlatCompat
// (eslint-config-next@15 is eslintrc-style). Run with `npm run lint`; keep it green
// alongside `npm test` and `npm run build`.
import { dirname } from "path";
import { fileURLToPath } from "url";
import { FlatCompat } from "@eslint/eslintrc";

const compat = new FlatCompat({ baseDirectory: dirname(fileURLToPath(import.meta.url)) });

const config = [
  { ignores: ["node_modules/**", ".next/**", "out/**", "public/**", "scripts/**", "ai-db/**", "next-env.d.ts"] },
  ...compat.extends("next/core-web-vitals", "next/typescript"),
];

export default config;
