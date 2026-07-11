// Rasterize the SVG marks into the PNG app icons that Android / iOS / the Play Store
// need (SVG alone isn't enough for home-screen install or a TWA/Bubblewrap build).
// Run after changing icon.svg / icon-maskable.svg:  node scripts/gen-icons.mjs
import sharp from "sharp";
import { readFileSync } from "node:fs";

const rounded = readFileSync("public/icon.svg"); // transparent rounded corners → purpose "any"
const bleed = readFileSync("public/icon-maskable.svg"); // full-bleed → "maskable" + iOS

const jobs = [
  [rounded, 192, "public/icon-192.png"],
  [rounded, 512, "public/icon-512.png"],
  [bleed, 512, "public/icon-maskable-512.png"],
  [bleed, 180, "public/apple-touch-icon.png"], // iOS home screen (full-bleed → no black corners)
];

for (const [src, size, out] of jobs) {
  await sharp(src).resize(size, size).png().toFile(out);
  console.log(`✓ ${out} (${size}×${size})`);
}
console.log("icons generated.");
