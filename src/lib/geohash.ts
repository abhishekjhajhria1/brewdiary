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
