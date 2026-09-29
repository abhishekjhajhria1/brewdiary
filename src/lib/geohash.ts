// Geohash — turn coordinates into a short, coarse cell label, entirely on-device.
// We only ever keep a LOW-precision hash (a big cell), so it says "roughly which
// city" and never "where you are". No dependency; the standard base-32 algorithm.
//
// Precision → approximate cell size:
//   4 ≈ 39 km  (city-scale — what area trends use)
//   5 ≈ 4.9 km (neighbourhood)  6 ≈ 1.2 km (block)
// See 041_geo_area.sql. Keep AREA_PRECISION in sync on both sides (user + venue).
export const AREA_PRECISION = 4;

const BASE32 = "0123456789bcdefghjkmnpqrstuvwxyz";

export function encodeGeohash(lat: number, lon: number, precision = AREA_PRECISION): string {
  let idx = 0;
  let bit = 0;
  let evenBit = true;
  let hash = "";
  let latMin = -90;
  let latMax = 90;
  let lonMin = -180;
  let lonMax = 180;

  while (hash.length < precision) {
    if (evenBit) {
      // bisect longitude
      const mid = (lonMin + lonMax) / 2;
      if (lon >= mid) {
        idx = idx * 2 + 1;
        lonMin = mid;
      } else {
        idx = idx * 2;
        lonMax = mid;
      }
    } else {
      // bisect latitude
      const mid = (latMin + latMax) / 2;
      if (lat >= mid) {
        idx = idx * 2 + 1;
        latMin = mid;
      } else {
        idx = idx * 2;
        latMax = mid;
      }
    }
    evenBit = !evenBit;
    if (++bit === 5) {
      hash += BASE32[idx];
      bit = 0;
      idx = 0;
    }
  }
  return hash;
}

// ── the area heat map's grid (048) — the twin of packages/brewdiary_core/lib/geo.dart ──
// A geohash-4 area (~39 × 20 km) splits into 32 geohash-5 neighbourhoods (~5 km): a
// fifth character adds three longitude bits and two latitude bits, so they lie in 8
// columns (west → east) by 4 rows (south → north).

/** A venue's location: ~1.2 × 0.6 km — enough to place it in its neighbourhood, and a
 *  venue's address is public anyway. People are never stored finer than AREA_PRECISION. */
export const VENUE_PRECISION = 6;
export const NEIGHBOURHOOD_KM = 5;

export function isGeohash(s: string): boolean {
  return s.length > 0 && s.length <= 12 && [...s].every((c) => BASE32.includes(c));
}

export interface GridCell {
  cell: string;
  /** 0 (west) … 7 (east) */
  col: number;
  /** 0 (north) … 3 (south): screen order, top row first */
  row: number;
}

/** The 32 neighbourhoods of an area, in screen order (north-west first). */
export function subcells(area: string): GridCell[] {
  const a = area.slice(0, 4);
  const out: GridCell[] = [];
  for (let i = 0; i < 32; i++) {
    const col = ((i >> 4) & 1) * 4 + ((i >> 2) & 1) * 2 + (i & 1);
    const south = ((i >> 3) & 1) * 2 + ((i >> 1) & 1);
    out.push({ cell: a + BASE32[i], col, row: 3 - south });
  }
  return out.sort((x, y) => (x.row !== y.row ? x.row - y.row : x.col - y.col));
}

/** Where `cell` lies from `from`, in plain words: "~10 km north-west". */
export function directionFrom(from: string, cell: string): string {
  const find = (c: string) => (c.length < 5 ? undefined : subcells(c).find((g) => g.cell === c.slice(0, 5)));
  const a = find(from);
  const b = find(cell);
  if (!a || !b) return "nearby";
  const dx = b.col - a.col;
  const dy = a.row - b.row; // + = north
  if (dx === 0 && dy === 0) return "your own neighbourhood";
  const steps = Math.max(Math.abs(dx), Math.abs(dy));
  const ns = dy > 0 ? "north" : dy < 0 ? "south" : "";
  const ew = dx > 0 ? "east" : dx < 0 ? "west" : "";
  const diagonal = ns && ew && Math.abs(dx) * 2 >= Math.abs(dy) && Math.abs(dy) * 2 >= Math.abs(dx);
  const dir = diagonal ? `${ns}-${ew}` : Math.abs(dx) >= Math.abs(dy) ? ew : ns;
  return `~${steps * NEIGHBOURHOOD_KM} km ${dir}`;
}
