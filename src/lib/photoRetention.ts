// Photos are kept for a year, at most (057). Shared by the daily cleanup route
// and account deletion: remove storage files in batches the API accepts, then
// the rows that pointed at them. Server-only — it needs the service key.
import type { SupabaseClient } from "@supabase/supabase-js";

/** Days a photo is kept. The database never goes below 30, whatever it's asked. */
export const PHOTO_DAYS = 365;

/** Split a list into runs of at most [size]. */
export function chunks<T>(list: T[], size: number): T[][] {
  const n = Math.max(1, Math.floor(size));
  const out: T[][] = [];
  for (let i = 0; i < list.length; i += n) out.push(list.slice(i, i + n));
  return out;
}

/** Remove [names] from the photos bucket, then the entry_photos rows for them.
 *  Returns how many files went. */
export async function removePhotoFiles(admin: SupabaseClient, names: string[]): Promise<number> {
  let gone = 0;
  for (const batch of chunks(names, 100)) {
    const { error } = await admin.storage.from("photos").remove(batch);
    if (error) continue; // leave the rows: the files are still there, try again tomorrow
    await admin.from("entry_photos").delete().in("url", batch);
    gone += batch.length;
  }
  return gone;
}
