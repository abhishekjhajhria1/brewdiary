// Admin: review venue verification requests.
//
// Connects with SUPABASE_DB_URL (the DB owner), so auth.uid() is NULL — which is
// exactly why the 010 trigger lets this flip venues.verified while a signed-in
// venue never can. This script is the ONLY intended way a venue gets verified.
//
// Usage:
//   node scripts/verify-venue.mjs --list             # show pending requests
//   node scripts/verify-venue.mjs <slug>             # approve → verified
//   node scripts/verify-venue.mjs <slug> --reject    # reject (stays unverified)
import { readFileSync } from "node:fs";
import { Client } from "pg";

// --- load .env.local (same minimal parser as db.mjs) ---
function loadEnv(path = ".env.local") {
  try {
    for (const line of readFileSync(path, "utf8").split("\n")) {
      const t = line.trim();
      if (!t || t.startsWith("#")) continue;
      const i = t.indexOf("=");
      if (i === -1) continue;
      const k = t.slice(0, i).trim();
      const v = t.slice(i + 1).trim();
      if (!(k in process.env)) process.env[k] = v;
    }
  } catch {
    /* no .env.local — rely on real env */
  }
}
loadEnv();

const conn = process.env.SUPABASE_DB_URL;
if (!conn) {
  console.error("SUPABASE_DB_URL is empty — paste the Session-mode connection string into .env.local first.");
  process.exit(1);
}

const args = process.argv.slice(2);
const list = args.includes("--list");
const reject = args.includes("--reject");
const slug = args.find((a) => !a.startsWith("--"));

if (!list && !slug) {
  console.error("usage: node scripts/verify-venue.mjs --list | <slug> [--reject]");
  process.exit(1);
}

const client = new Client({ connectionString: conn, ssl: { rejectUnauthorized: false } });

try {
  await client.connect();

  if (list) {
    const { rows } = await client.query(`
      select v.slug, v.name, v.city, r.contact, r.note, r.created_at
      from public.venue_verifications r
      join public.venues v on v.id = r.venue_id
      where r.status = 'pending'
      order by r.created_at
    `);
    if (rows.length === 0) {
      console.log("No pending verification requests.");
    } else {
      console.log(`${rows.length} pending:\n`);
      for (const r of rows) {
        console.log(`  ${r.slug}  —  ${r.name}${r.city ? ` (${r.city})` : ""}`);
        console.log(`     contact: ${r.contact}`);
        if (r.note) console.log(`     note:    ${r.note}`);
        console.log(`     asked:   ${new Date(r.created_at).toLocaleString()}\n`);
      }
      console.log("approve with:  node scripts/verify-venue.mjs <slug>");
    }
  } else {
    const { rows } = await client.query("select id, name, verified from public.venues where slug = $1", [slug]);
    const venue = rows[0];

    if (!venue) {
      console.error(`✗ no venue with slug "${slug}"`);
      process.exitCode = 1;
    } else if (reject) {
      const r = await client.query(
        "update public.venue_verifications set status = 'rejected', reviewed_at = now() where venue_id = $1",
        [venue.id],
      );
      console.log(
        r.rowCount > 0
          ? `✗ rejected — "${venue.name}" stays unverified (they can fix it and request again).`
          : `· no request on file for "${venue.name}" — nothing to reject.`,
      );
    } else if (venue.verified) {
      console.log(`· "${venue.name}" is already verified.`);
    } else {
      await client.query("begin");
      await client.query("update public.venues set verified = true where id = $1", [venue.id]);
      await client.query(
        "update public.venue_verifications set status = 'approved', reviewed_at = now() where venue_id = $1",
        [venue.id],
      );
      await client.query("commit");
      console.log(`✓ verified — "${venue.name}" can now offer house perks.`);
    }
  }
} catch (e) {
  console.error("✗ failed:\n", e.message);
  process.exitCode = 1;
} finally {
  await client.end();
}
