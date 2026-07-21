// End-to-end verification of the bar layer against the LIVE database.
//
// It plays a real night: an owner creates a venue, gets verified, opens a room,
// two guests join, they check in, hand each other vibe, the bartender awards
// vibe and records a tab, a perk fills up, the kiosk board renders, the friends
// leaderboard renders, and profiles resolve at all three privacy tiers.
//
// Crucially it acts as REAL USERS: `set local role authenticated` + a real
// request.jwt.claims sub, so every RLS policy and every definer check applies
// exactly as it would from the browser. The security assertions (a guest trying
// to write their own spend, or mint a spark) are therefore meaningful.
//
// EVERYTHING RUNS IN ONE TRANSACTION THAT IS ROLLED BACK. Production is untouched.
import { readFileSync } from "node:fs";
import { randomUUID } from "node:crypto";
import { Client } from "pg";

// .env.local when run by hand; real env vars in CI, where no such file exists.
try {
  for (const line of readFileSync(".env.local", "utf8").split("\n")) {
    const t = line.trim();
    if (!t || t.startsWith("#")) continue;
    const i = t.indexOf("=");
    if (i > 0 && !(t.slice(0, i).trim() in process.env)) process.env[t.slice(0, i).trim()] = t.slice(i + 1).trim();
  }
} catch {
  /* no .env.local — rely on the real environment */
}

if (!process.env.SUPABASE_DB_URL) {
  console.error("SUPABASE_DB_URL is not set — put it in .env.local, or pass it as an env var in CI.");
  process.exit(1);
}

const db = new Client({ connectionString: process.env.SUPABASE_DB_URL, ssl: { rejectUnauthorized: false } });

let pass = 0;
const fails = [];
const ok = (name, cond, detail = "") => {
  if (cond) {
    pass++;
    console.log(`  ok   ${name}`);
  } else {
    fails.push(name);
    console.log(`  FAIL ${name} ${detail}`);
  }
};

/** Run SQL as a signed-in user (RLS on), exactly like the browser does. */
async function as(uid, sql, params = []) {
  await db.query("set local role authenticated");
  await db.query(`set local request.jwt.claims = '${JSON.stringify({ sub: uid, role: "authenticated" })}'`);
  try {
    return await db.query(sql, params);
  } finally {
    // If the query above failed, the transaction is aborted and these resets fail too —
    // and a throw from a `finally` REPLACES the original error, masking every real
    // failure as "current transaction is aborted". Swallow cleanup errors so the actual
    // cause survives; the caller's savepoint/rollback restores role state anyway.
    try {
      await db.query("reset role");
      await db.query("reset request.jwt.claims");
    } catch {
      /* transaction already aborted — the real error is on its way up */
    }
  }
}
/** Run as a signed-OUT visitor (the kiosk screen, a stranger). */
async function anon(sql, params = []) {
  await db.query("set local role anon");
  try {
    return await db.query(sql, params);
  } finally {
    await db.query("reset role");
  }
}
/** Expect a write to be REFUSED. Returns true when it was. */
// Did the database refuse this? Every check here runs inside ONE transaction we roll
// back at the end, and in Postgres a failed statement poisons the whole transaction —
// so a refusal MUST be caught at a savepoint. Without one, the first expected refusal
// aborts the run and every later assertion dies with "current transaction is aborted",
// which reads like a harness crash rather than what it is.
let sp = 0;
async function refused(fn) {
  const name = `refusal_${++sp}`;
  await db.query(`savepoint ${name}`);
  try {
    await fn();
    await db.query(`release savepoint ${name}`);
    return false;
  } catch {
    // Rewind to just before the refused statement; the transaction is usable again.
    await db.query(`rollback to savepoint ${name}`);
    return true;
  }
}

const mkUser = async (name, handle) => {
  const id = randomUUID();
  await db.query(
    `insert into auth.users (id, instance_id, aud, role, email, encrypted_password, email_confirmed_at, created_at, updated_at)
     values ($1, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', $2, 'x', now(), now(), now())`,
    [id, `${handle}@verify.local`],
  );
  await db.query(`insert into public.profiles (id, handle, display_name) values ($1, $2, $3)`, [id, handle, name]);
  return id;
};

await db.connect();
await db.query("begin");
try {
  console.log("\n── cast ─────────────────────────────────────────────");
  const owner = await mkUser("Bar Owner", `vf-owner-${Date.now()}`);
  const barman = await mkUser("Bartender", `vf-barman-${Date.now()}`);
  const anita = await mkUser("Anita", `vf-anita-${Date.now()}`);
  const rohan = await mkUser("Rohan", `vf-rohan-${Date.now()}`);
  const stranger = await mkUser("Stranger", `vf-strange-${Date.now()}`);
  console.log("  owner, bartender, two guests (Anita, Rohan), one stranger");

  console.log("\n── 1. the bar sets itself up ─────────────────────────");
  const vid = randomUUID();
  await as(owner, `insert into public.venues (id, name, slug, created_by) values ($1,'Verify Tap Room',$2,$3)`, [
    vid,
    `verify-tap-${Date.now()}`,
    owner,
  ]);
  // createVenue() (lib/venues.ts) inserts this row immediately after the venue: being
  // `created_by` is not the same as being STAFF, and every venue power is gated on
  // is_venue_staff/is_venue_manager. Without it the harness wasn't playing the real flow.
  await as(owner, `insert into public.venue_staff (venue_id, user_id, role) values ($1,$2,'owner')`, [vid, owner]);
  ok("owner can create a venue", true);

  const selfVerify = await refused(() => as(owner, `update public.venues set verified = true where id = $1`, [vid]));
  const v1 = await db.query(`select verified from public.venues where id = $1`, [vid]);
  ok("a venue CANNOT verify itself", selfVerify || v1.rows[0].verified === false);

  await as(owner, `insert into public.venue_staff (venue_id, user_id, role) values ($1,$2,'bartender')`, [vid, barman]);
  ok("owner can add a bartender", true);

  // `contact` is NOT NULL (015): a verification request must say how we reach the venue.
  await as(
    owner,
    `insert into public.venue_verifications (venue_id, requested_by, contact, note) values ($1,$2,$3,'please')`,
    [vid, owner, "owner@example.test"],
  );
  const stat = await db.query(`select status from public.venue_verifications where venue_id = $1`, [vid]);
  ok("verification request lands as 'pending'", stat.rows[0].status === "pending");

  // There is no UPDATE policy on this table, so RLS doesn't raise — it silently matches
  // zero rows. "Refused" therefore has to be judged on the OUTCOME, not on an exception,
  // exactly like the self-verify check above. Asserting only on a throw would let a future
  // stray UPDATE policy through green.
  const selfApprove = await refused(() =>
    as(owner, `update public.venue_verifications set status='approved' where venue_id = $1`, [vid]),
  );
  const st2 = await db.query(`select status from public.venue_verifications where venue_id = $1`, [vid]);
  ok("a venue CANNOT approve its own request", selfApprove || st2.rows[0].status === "pending");

  console.log("\n── 2. an unverified venue is powerless ───────────────");
  const pid = randomUUID();
  await as(
    owner,
    `insert into public.parties (id, name, host_id, date, venue_id, invite_code) values ($1,'Friday',$2,current_date,$3,$4)`,
    [pid, owner, vid, `vf${Date.now()}`.slice(0, 8)],
  );
  await db.query(`insert into public.party_members (party_id, user_id, status) values ($1,$2,'approved')`, [pid, anita]);
  await db.query(`insert into public.party_members (party_id, user_id, status) values ($1,$2,'approved')`, [pid, rohan]);

  ok(
    "UNVERIFIED venue cannot record spend",
    await refused(() => as(barman, `select public.record_spend($1,$2,1000)`, [pid, anita])),
  );
  ok(
    "UNVERIFIED venue cannot award vibe",
    await refused(() => as(barman, `select public.staff_award($1,$2,'great vibe')`, [pid, anita])),
  );

  // the maintainer verifies it out-of-band (what scripts/verify-venue.mjs does)
  await db.query(`update public.venues set verified = true where id = $1`, [vid]);
  console.log("  (maintainer verifies the venue — the service-key path)");

  console.log("\n── 3. the guests' night ──────────────────────────────");
  const c1 = await as(anita, `select public.award_checkin($1) as v`, [pid]);
  const c2 = await as(anita, `select public.award_checkin($1) as v`, [pid]);
  ok("a NEW venue gives a spark", c1.rows[0].v === true);
  ok("checking in twice does NOT farm a second spark", c2.rows[0].v === false);
  await as(rohan, `select public.award_checkin($1)`, [pid]);

  // THE POINT OF 019: coming back to your local is not a score.
  const pid2 = randomUUID();
  await as(
    owner,
    `insert into public.parties (id, name, host_id, date, venue_id, invite_code) values ($1,'Saturday',$2,current_date,$3,$4)`,
    [pid2, owner, vid, `vg${Date.now()}`.slice(0, 8)],
  );
  await db.query(`insert into public.party_members (party_id, user_id, status) values ($1,$2,'approved')`, [pid2, anita]);
  const again = await as(anita, `select public.award_checkin($1) as v`, [pid2]);
  ok("RETURNING to the same venue earns NO spark (variety, not frequency)", again.rows[0].v === false);

  await as(anita, `insert into public.point_events (party_id, subject_user_id, awarder_id, currency, reason, value)
                   values ($1,$2,$3,'vibe','great vibe',1)`, [pid, rohan, anita]);
  ok("a guest can hand a fellow guest vibe", true);
  ok(
    "the same vibe twice is blocked (no farming)",
    await refused(() =>
      as(anita, `insert into public.point_events (party_id, subject_user_id, awarder_id, currency, reason, value)
                 values ($1,$2,$3,'vibe','great vibe',1)`, [pid, rohan, anita]),
    ),
  );

  ok(
    "a guest CANNOT mint their own spark",
    await refused(() =>
      as(anita, `insert into public.point_events (party_id, subject_user_id, awarder_id, currency, reason, value)
                 values ($1,$2,$2,'spark','i am great',99)`, [pid, anita]),
    ),
  );

  await as(barman, `select public.staff_award($1,$2,'kept it classy')`, [pid, anita]);
  ok("the BARTENDER can award vibe (verified venue)", true);
  ok(
    "a bartender CANNOT dock anyone (negative value)",
    await refused(() =>
      as(barman, `insert into public.point_events (party_id, subject_user_id, awarder_id, currency, reason, value)
                 values ($1,$2,$3,'vibe','bad',-1)`, [pid, anita, barman]),
    ),
  );

  console.log("\n── 3b. the diary pays for variety + dry days ─────────");
  const mkEntry = (uid, date, drink, type) =>
    db.query(
      `insert into public.entries (id, user_id, date, created_at, drink, type) values ($1,$2,$3,now(),$4,$5)`,
      [randomUUID(), uid, date, drink, type],
    );

  await mkEntry(anita, "2026-07-10", "espresso martini", "cocktail");
  const nd1 = await as(anita, `select public.award_diary('new-drink','espresso martini') as v`);
  ok("a NEW drink earns a spark", nd1.rows[0].v === true);
  const nd2 = await as(anita, `select public.award_diary('new-drink','espresso martini') as v`);
  ok("the same drink twice does not pay twice", nd2.rows[0].v === false);

  const fake = await as(anita, `select public.award_diary('new-drink','unicorn tears') as v`);
  ok("you CANNOT mint a spark for a drink you never logged", fake.rows[0].v === false);

  await mkEntry(anita, "2026-07-11", "dry day", "none");
  const dd = await as(anita, `select public.award_diary('dry-day','2026-07-11') as v`);
  ok("a logged DRY DAY earns a spark", dd.rows[0].v === true);
  const fakeDry = await as(anita, `select public.award_diary('dry-day','2026-07-12') as v`);
  ok("you cannot claim a dry day you didn't log", fakeDry.rows[0].v === false);

  console.log("\n── 4. the tab (the rule that matters most) ───────────");
  ok(
    "a GUEST CANNOT write their own spend",
    await refused(() =>
      as(anita, `insert into public.spend_events (party_id, subject_user_id, amount) values ($1,$2,99999)`, [pid, anita]),
    ),
  );
  ok(
    "a STRANGER cannot record spend for someone",
    await refused(() => as(stranger, `select public.record_spend($1,$2,500)`, [pid, anita])),
  );
  await as(barman, `select public.record_spend($1,$2,2400)`, [pid, anita]);
  ok("the BARTENDER can record a tab", true);
  ok(
    "a bartender cannot bill someone who isn't in the room",
    await refused(() => as(barman, `select public.record_spend($1,$2,500)`, [pid, stranger])),
  );

  const mySpend = await as(anita, `select public.venue_spend($1) as v`, [vid]);
  ok("the guest sees her own total (₹2,400)", Number(mySpend.rows[0].v) === 2400);
  const otherSpend = await as(rohan, `select public.venue_spend($1) as v`, [vid]);
  ok("another guest CANNOT see her total", Number(otherSpend.rows[0].v) === 0);

  console.log("\n── 5. the house perk ─────────────────────────────────");
  await as(owner, `insert into public.venue_perks (venue_id, kind, threshold, reward)
                   values ($1,'spend',3000,'a free pour')`, [vid]);
  const perk = await as(anita, `select kind, threshold, reward from public.venue_perks where venue_id = $1`, [vid]);
  ok("a ₹3,000 spend perk is set and visible to the guest", perk.rows[0].kind === "spend" && Number(perk.rows[0].threshold) === 3000);
  ok("perk threshold is not capped at 100 (the old int ceiling is gone)", Number(perk.rows[0].threshold) === 3000);

  console.log("\n── 5b. the perk is LAWFUL where the venue is ─────────");
  // The regression 020 fixes: a "visit" must count rooms attended, NOT check-in
  // sparks — 019 stopped paying a spark for returning, so the old count would
  // have frozen at 1 and no perk would ever have paid out.
  const visits = await as(anita, `select public.venue_visits($1) as v`, [vid]);
  ok("a VISIT counts rooms attended, not sparks (she's in 2 rooms)", Number(visits.rows[0].v) === 2);

  // Move the venue to Dublin and the same perk becomes unlawful — in the DB, not the UI.
  // The move itself is refused while the now-unlawful perk still stands: venues_recheck_perks()
  // re-tests every existing perk against the new jurisdiction, so a venue can't be walked
  // across a border to escape the rules. Clear the perk first, then the move is allowed.
  ok(
    "a venue CANNOT relocate out from under its perks (they're re-tested on the move)",
    await refused(() => db.query(`update public.venues set country = 'IE' where id = $1`, [vid])),
  );
  await db.query(`delete from public.venue_perks where venue_id = $1`, [vid]);
  await db.query(`update public.venues set country = 'IE' where id = $1`, [vid]);
  ok(
    "IRELAND: a spend-based perk is refused by the database",
    await refused(() =>
      as(owner, `insert into public.venue_perks (venue_id, kind, threshold, reward, reward_alcoholic)
                 values ($1,'spend',3000,'a free pour',false)
                 on conflict (venue_id) do update set kind = 'spend', threshold = 3000`, [vid]),
    ),
  );
  await db.query(`delete from public.venue_perks where venue_id = $1`, [vid]);
  ok(
    "IRELAND: an ALCOHOLIC reward is refused",
    await refused(() =>
      as(owner, `insert into public.venue_perks (venue_id, kind, threshold, reward, reward_alcoholic)
                 values ($1,'visits',5,'a free pint',true)`, [vid]),
    ),
  );
  await as(owner, `insert into public.venue_perks (venue_id, kind, threshold, reward, reward_alcoholic)
                   values ($1,'visits',5,'a free coffee',false)`, [vid]);
  ok("IRELAND: visits → a NON-alcoholic reward is allowed (the feature survives)", true);

  await db.query(`update public.venues set country = 'GB' where id = $1`, [vid]);
  ok(
    "UK: an alcoholic reward is refused (irresponsible promotion)",
    await refused(() => as(owner, `update public.venue_perks set reward_alcoholic = true where venue_id = $1`, [vid])),
  );

  await db.query(`update public.venues set country = 'US', region = 'MA' where id = $1`, [vid]);
  ok(
    "MASSACHUSETTS: an alcoholic reward is refused",
    await refused(() => as(owner, `update public.venue_perks set reward_alcoholic = true where venue_id = $1`, [vid])),
  );
  await db.query(`update public.venues set region = 'NY' where id = $1`, [vid]);
  await as(owner, `update public.venue_perks set reward_alcoholic = true where venue_id = $1`, [vid]);
  ok("NEW YORK: the same reward is allowed (policy is per-jurisdiction, not global)", true);

  // Thailand bans discounts/giveaways outright — no perk of ANY kind.
  // Clear the NY perk first: the venue can't cross the border while holding one that
  // would be unlawful on the other side (asserted above), so relocating is a two-step.
  await db.query(`delete from public.venue_perks where venue_id = $1`, [vid]);
  await db.query(`update public.venues set country = 'TH', region = null where id = $1`, [vid]);
  ok(
    "THAILAND: no loyalty perk at all — even visits + a coffee",
    await refused(() =>
      as(owner, `insert into public.venue_perks (venue_id, kind, threshold, reward, reward_alcoholic)
                 values ($1,'visits',5,'a coffee',false)`, [vid]),
    ),
  );

  // THE DENY-BY-DEFAULT RULE: a country we never researched must behave like the
  // strictest one, not the loosest. (028 hardened this: an unknown country now
  // refuses the VENUE itself, not just its perk — silence means "we don't operate
  // here", which is the only safe reading.)
  ok(
    "AN UNRESEARCHED COUNTRY refuses the venue outright (silence means 'no')",
    await refused(() => db.query(`update public.venues set country = 'ZW' where id = $1`, [vid])),
  );

  // Where alcohol is prohibited, a venue cannot exist at all.
  ok(
    "SAUDI ARABIA: a venue cannot even be created (the diary still works)",
    await refused(() => db.query(`update public.venues set country = 'SA' where id = $1`, [vid])),
  );

  // And the home market must actually WORK — this is the assertion that would have
  // caught the perk_policy bug: India was silently being judged by Massachusetts.
  await db.query(`update public.venues set country = 'IN', region = null where id = $1`, [vid]);
  const inPol = await as(owner, `select * from public.perk_policy('IN', '')`);
  ok(
    "INDIA (home) really is Class A: alcohol reward + spend perk allowed",
    inPol.rows[0]?.allow_alcohol_reward === true && inPol.rows[0]?.allow_spend_perk === true,
  );
  const zwPol = await as(owner, `select * from public.perk_policy('ZW', '')`);
  ok("an unresearched country returns NO ROW at all", zwPol.rows.length === 0);

  // back to the home market, and restore the spend perk for the rest of the run.
  // INSERT, not UPDATE: the jurisdiction tour above has to clear the perk to move the
  // venue between countries, so there may be no row left to update — an UPDATE would
  // silently affect zero rows and the next section would read an empty perk_status.
  await db.query(`update public.venues set country = 'IN', region = null where id = $1`, [vid]);
  await db.query(`delete from public.venue_perks where venue_id = $1`, [vid]);
  await as(
    owner,
    `insert into public.venue_perks (venue_id, kind, threshold, reward, reward_alcoholic)
     values ($1,'spend',3000,'a free pour',false)`,
    [vid],
  );

  console.log("\n── 5c. the perk can be CLAIMED — once ────────────────");
  // The bug 023 fixes: progress used to be all-time, so once you crossed the line
  // you stayed across it forever — the same free drink, every visit, and two
  // bartenders could each honour it without knowing.
  await as(owner, `update public.venue_perks set kind = 'visits', threshold = 2, reward = 'a free coffee'
                   where venue_id = $1`, [vid]);

  let st = await as(anita, `select * from public.perk_status($1,$2)`, [vid, anita]);
  ok("the guest sees her progress (2 rooms → earned)", Number(st.rows[0].progress) === 2 && st.rows[0].earned === true);

  const staffSees = await as(barman, `select * from public.perk_status($1,$2)`, [vid, anita]);
  ok("the BARTENDER sees the same number (one source of truth)", Number(staffSees.rows[0].progress) === 2);

  ok(
    "a STRANGER cannot read her standing",
    await refused(() => as(stranger, `select * from public.perk_status($1,$2)`, [vid, anita])),
  );
  ok(
    "a GUEST cannot write her own claim",
    await refused(() =>
      as(anita, `insert into public.perk_redemptions (venue_id, user_id, kind, threshold, reward)
                 values ($1,$2,'visits',2,'a free coffee')`, [vid, anita]),
    ),
  );

  const perk1 = st.rows[0].perk_id;
  await as(barman, `select public.redeem_perk($1,$2)`, [perk1, anita]);
  ok("the bartender hands it over", true);

  st = await as(anita, `select * from public.perk_status($1,$2)`, [vid, anita]);
  ok("…and her progress RESTARTS from zero", Number(st.rows[0].progress) === 0);
  ok("…she is no longer 'earned'", st.rows[0].earned === false);
  ok("…the claim is on the record", Number(st.rows[0].claims) === 1);

  ok(
    "THE BUG IS DEAD: it cannot be claimed twice for the same earn",
    await refused(() => as(barman, `select public.redeem_perk($1,$2)`, [perk1, anita])),
  );
  ok(
    "a second bartender cannot double-honour it either",
    await refused(() => as(owner, `select public.redeem_perk($1,$2)`, [perk1, anita])),
  );

  // ── TIERS (029): each reward is its own punch-card with its own clock ──────
  await as(owner, `insert into public.venue_perks (venue_id, kind, threshold, reward, reward_alcoholic)
                   values ($1,'visits',10,'a free pour',true)`, [vid]);
  const tiers = await as(anita, `select * from public.perk_status($1,$2) order by threshold`, [vid, anita]);
  ok("a venue can run several tiers", tiers.rows.length === 2);
  ok("…each with its OWN clock (the claimed one is back at 0)", Number(tiers.rows[0].progress) === 0);
  ok(
    "…and the un-claimed tier keeps its progress (claiming one doesn't wipe the other)",
    Number(tiers.rows[1].progress) === 2,
  );
  ok(
    "…the big tier isn't earned yet",
    tiers.rows[1].earned === false && Number(tiers.rows[1].threshold) === 10,
  );
  ok(
    "a tier that isn't earned cannot be handed over",
    await refused(() => as(barman, `select public.redeem_perk($1,$2)`, [tiers.rows[1].perk_id, anita])),
  );

  // Jurisdiction still applies PER TIER — a Dublin bar can't sneak alcohol in as tier 2.
  // Make the tiers it already has IE-lawful before relocating: the move re-tests every
  // existing perk, so a venue holding an alcoholic reward can't cross into Ireland at all.
  await db.query(`update public.venue_perks set reward_alcoholic = false, reward = 'a free coffee' where venue_id = $1`, [vid]);
  await db.query(`update public.venues set country = 'IE' where id = $1`, [vid]);
  ok(
    "IRELAND: an alcoholic reward can't sneak in as a second TIER either",
    await refused(() =>
      as(owner, `insert into public.venue_perks (venue_id, kind, threshold, reward, reward_alcoholic)
                 values ($1,'visits',20,'a free pint',true)`, [vid]),
    ),
  );
  await db.query(`update public.venues set country = 'IN' where id = $1`, [vid]);
  await db.query(`delete from public.venue_perks where venue_id = $1 and threshold = 10`, [vid]);

  console.log("\n── 5d. quiet nights count double (the dead Tuesday) ──");
  // The dead-Tuesday fix, done WITHOUT rewarding drinking: a visit on a quiet night
  // is worth 2 toward the PRIVATE perk. No spark, no discount, no public score.
  const roomDow = (
    await db.query(`select extract(dow from date)::int as d from public.parties where id = $1`, [pid2])
  ).rows[0].d;

  // Start from a FRESH card. 5c redeemed the perk, and a claim restarts the clock — so
  // every visit above now predates it and progress sits at 0. Doubling zero is zero, and
  // the assertion below would be measuring nothing. A new perk row has no claim behind it,
  // so both readings actually see Anita's two rooms.
  await db.query(`delete from public.venue_perks where venue_id = $1`, [vid]);
  await as(
    owner,
    `insert into public.venue_perks (venue_id, kind, threshold, reward, reward_alcoholic)
     values ($1,'visits',5,'a free coffee',false)`,
    [vid],
  );

  await db.query(`update public.venues set quiet_nights = '{}' where id = $1`, [vid]);
  let q = await as(anita, `select progress from public.perk_status($1,$2)`, [vid, anita]);
  const base = Number(q.rows[0].progress);

  await db.query(`update public.venues set quiet_nights = array[$2::int] where id = $1`, [vid, roomDow]);
  q = await as(anita, `select progress from public.perk_status($1,$2)`, [vid, anita]);
  const boosted = Number(q.rows[0].progress);

  // Both of this venue's rooms are opened on current_date, so they share a weekday:
  // marking it quiet doubles BOTH visits, not one. (The older `base + 1` expectation
  // assumed the rooms fell on different days, which the fixture has never done.)
  ok("a visit on a QUIET night is worth double toward the perk", boosted === base * 2 && base > 0);
  ok("…and it is a PRIVATE perk boost — no spark was minted", true);

  const boardAfter = await as(anita, `select sparks from public.party_points_board($1) where user_id = $2`, [pid, anita]);
  ok(
    "the public board is UNCHANGED by the quiet-night boost (variety, not frequency)",
    Number(boardAfter.rows[0].sparks) === 1,
  );
  await db.query(`update public.venues set quiet_nights = '{}' where id = $1`, [vid]);

  console.log("\n── 5e. staff kudos (a thank-you box, NOT a scoreboard) ──");
  const seeStaff = await as(anita, `select * from public.room_staff($1)`, [pid]);
  ok("a guest can see who's on tonight", seeStaff.rows.some((r) => r.id === barman));

  await as(anita, `select public.thank_staff($1,$2,'looked after us')`, [pid, barman]);
  ok("a guest can thank the bartender by name", true);
  const dupe = await as(anita, `select public.thank_staff($1,$2,'looked after us') as v`, [pid, barman]);
  ok("the same thanks twice is a no-op (no inflating one person)", dupe.rows[0].v === false);

  const mine = await as(barman, `select * from public.my_kudos($1)`, [vid]);
  ok("the BARTENDER sees their own thanks", mine.rows.length === 1 && Number(mine.rows[0].n) === 1);

  // THE LINE THAT MATTERS. A manager gets a team total and nothing else — a
  // per-person breakdown would make this employee monitoring (DPIA + works
  // councils in seven EU states). It must be impossible, not merely absent from
  // the UI.
  const teamTotal = await as(owner, `select public.venue_kudos_total($1, 30) as n`, [vid]);
  ok("a manager sees the TEAM TOTAL", Number(teamTotal.rows[0].n) === 1);

  const snoop = await as(owner, `select staff_id, count(*) from public.staff_kudos
                                 where venue_id = $1 group by staff_id`, [vid]);
  ok(
    "a manager CANNOT get a per-person breakdown, even querying the table directly",
    snoop.rows.length === 0,
  );

  // Opting out actually works — you disappear from the list entirely.
  await db.query(`update public.venue_staff set thankable = false where venue_id = $1 and user_id = $2`, [vid, barman]);
  const after = await as(anita, `select * from public.room_staff($1)`, [pid]);
  ok("a staff member who opts out cannot be thanked at all", !after.rows.some((r) => r.id === barman));
  ok(
    "…and thanking them anyway is refused",
    await refused(() => as(anita, `select public.thank_staff($1,$2,'made the night')`, [pid, barman])),
  );
  await db.query(`update public.venue_staff set thankable = true where venue_id = $1 and user_id = $2`, [vid, barman]);

  console.log("\n── 5f. insights: counts, and a profile of nobody ─────");
  const ins = await as(owner, `select * from public.venue_insights($1, 30)`, [vid]);
  const row = ins.rows[0];
  ok("a manager gets counts for their own venue", Number(row.guests) >= 2 && Number(row.rooms) >= 2);
  ok("…including their own takings (their staff typed them in)", Number(row.takings) === 2400);

  // v2 metrics (038): weekday visit volume + a previous-window baseline. Applied
  // incrementally, so only assert the columns when the migration is present.
  if ("visits_by_dow" in row) {
    ok("insights v2: weekday visits come back as 7 slots", Array.isArray(row.visits_by_dow) && row.visits_by_dow.length === 7);
    ok("insights v2: a previous-window trend baseline is returned",
      row.prev_guests !== undefined && row.prev_takings !== undefined);
  } else {
    console.log("  ~ venue_insights v2 (038) not applied — skipping");
  }

  // THE SUPPRESSION. With only 2 guests, a new/returning split would point at a
  // named person ("the new one" = that individual). It must come back NULL, and
  // NULL must be distinguishable from 0.
  ok("a split over a group SMALLER THAN 5 is HIDDEN (null, not 0)", row.new_guests === null);
  ok("…and the same for regulars", row.returning_guests === null);
  ok("…and for perks waiting", row.perks_earned === null);

  ok(
    "a BARTENDER cannot see insights (managers only)",
    await refused(() => as(barman, `select * from public.venue_insights($1, 30)`, [vid])),
  );
  ok(
    "a STRANGER cannot see another venue's insights",
    await refused(() => as(stranger, `select * from public.venue_insights($1, 30)`, [vid])),
  );

  // Insights must never reach ACROSS venues — a bar learning what a guest does at
  // another bar is the worst leak available here.
  const otherVid = randomUUID();
  await as(stranger, `insert into public.venues (id, name, slug, created_by) values ($1,'Rival Bar',$2,$3)`, [
    otherVid,
    `rival-${Date.now()}`,
    stranger,
  ]);
  ok(
    "a manager cannot read ANOTHER venue's insights",
    await refused(() => as(owner, `select * from public.venue_insights($1, 30)`, [otherVid])),
  );

  // Area taste trends: aggregate, k-anon (≥5). With no consenting pool in a made-up
  // area, it must hand back NOTHING — never a sub-threshold row.
  // 039 (area trends) may be on hold — calling a missing function would abort the
  // whole run, so probe first (to_regprocedure returns NULL instead of throwing).
  const hasAreaTrends = (
    await db.query(`select to_regprocedure('public.area_taste_trends(text,int)') is not null as ok`)
  ).rows[0].ok;
  if (hasAreaTrends) {
    const areaEmpty = await as(owner, `select * from public.area_taste_trends($1, 30)`, [`Nowhere-${randomUUID()}`]);
    ok("area trends: an area with no consenting pool yields nothing (k-anon)", areaEmpty.rows.length === 0);
  } else {
    console.log("  ~ area_taste_trends (039) not applied — skipping");
  }

  console.log("\n── 5f2. guest book: a first-party CRM, done legally ──");
  // A book may only ever be opened on a guest who has ACTUALLY been to the venue.
  ok(
    "a note on a STRANGER who never visited is refused (interaction gate)",
    await refused(() => as(owner, `select public.set_guest_note($1,$2,'hi','{}')`, [vid, stranger])),
  );
  // anita joined the room, so she's a real guest of this venue — staff may note her.
  await as(owner, `select public.set_guest_note($1,$2,'Likes a smoky mezcal',array['regular','friday'])`, [vid, anita]);
  const gbCard = (await as(owner, `select * from public.venue_guest_card($1,$2)`, [vid, anita])).rows[0];
  ok(
    "the card shows first-party history + the staff note",
    gbCard && gbCard.been_here === true && Number(gbCard.visits) >= 1 && gbCard.note === "Likes a smoky mezcal",
  );
  ok(
    "a non-staff person cannot read the venue's guest book",
    await refused(() => as(stranger, `select * from public.venue_guest_card($1,$2)`, [vid, anita])),
  );
  // TRANSPARENCY: the guest can see every note kept on them, and erase it.
  const books = await as(anita, `select * from public.my_venue_books()`);
  ok("the guest sees the note kept on them", books.rows.some((r) => r.venue_id === vid && r.body === "Likes a smoky mezcal"));
  await as(anita, `delete from public.venue_guest_notes where venue_id = $1 and subject_id = $2`, [vid, anita]);
  const gone = await as(anita, `select * from public.my_venue_books()`);
  ok("…and can ERASE it — their right", !gone.rows.some((r) => r.venue_id === vid));

  console.log("\n── 5g. Discover: the bar, never the offer ───────────");
  let disc = await anon(`select * from public.discover_venues('IN', 30)`);
  const listed = disc.rows.find((r) => r.slug && r.name === "Verify Tap Room");
  ok("a VERIFIED venue is listed (signed-out, like a directory)", Boolean(listed));

  // THE WALL. A listing carries a name and a city. It must NOT carry the offer —
  // that's alcohol advertising, illegal in India and banned outright elsewhere.
  const cols = Object.keys(disc.rows[0] ?? {});
  ok(
    "a listing carries NO perk, reward, price or drink",
    !cols.some((c) => /perk|reward|price|drink|offer|threshold/i.test(c)),
  );

  // Deny-by-default reaches here too: no bar layer → no listing.
  // Clear the perk before the move: a venue can't relocate while holding one that would
  // be unlawful at the destination (venues_recheck_perks), and TH permits none at all.
  await db.query(`delete from public.venue_perks where venue_id = $1`, [vid]);
  await db.query(`update public.venues set country = 'TH' where id = $1`, [vid]);
  disc = await anon(`select * from public.discover_venues('TH', 30)`);
  ok("a bar in a NO-PERK country (Thailand) is not listed at all", disc.rows.length === 0);

  disc = await anon(`select * from public.discover_venues('ZW', 30)`);
  ok("an UNRESEARCHED country lists nothing at all", disc.rows.length === 0);

  await db.query(`update public.venues set country = 'IN', verified = false where id = $1`, [vid]);
  disc = await anon(`select * from public.discover_venues('IN', 30)`);
  ok("an UNVERIFIED bar is nobody's recommendation", !disc.rows.some((r) => r.name === "Verify Tap Room"));
  await db.query(`update public.venues set verified = true where id = $1`, [vid]);

  console.log("\n── 6. the wall screen — per-night consent ────────────");
  const code = (await db.query(`select invite_code from public.parties where id = $1`, [pid])).rows[0].invite_code;
  let board = await anon(`select * from public.room_board($1)`, [code]);
  ok("kiosk shows NOBODY before anyone opts in", board.rows.length === 0);

  const consent = (uid, onBoard, showTab) =>
    as(uid, `insert into public.room_consent (party_id, user_id, on_board, show_tab) values ($1,$2,$3,$4)
             on conflict (party_id, user_id) do update set on_board = $3, show_tab = $4`, [pid, uid, onBoard, showTab]);

  await consent(anita, true, false);
  board = await anon(`select * from public.room_board($1)`, [code]);
  ok("after opting in FOR THIS ROOM, she appears on the wall", board.rows.length === 1 && board.rows[0].display_name === "Anita");
  ok("…with her sparks and vibe", board.rows[0].sparks === 1 && board.rows[0].vibe === 1);
  ok("…and the guest who did NOT opt in is absent", !board.rows.some((r) => r.display_name === "Rohan"));

  let tabs = await anon(`select * from public.room_tabs($1)`, [code]);
  ok("her TAB is still hidden (being on the board is not consent to flex)", tabs.rows.length === 0);

  await consent(anita, true, true);
  tabs = await anon(`select * from public.room_tabs($1)`, [code]);
  ok("with BOTH consents, the tab shows", tabs.rows.length === 1 && Number(tabs.rows[0].spend) === 2400);

  await consent(anita, false, true);
  tabs = await anon(`select * from public.room_tabs($1)`, [code]);
  ok("show_tab ALONE shows nothing (the double gate holds)", tabs.rows.length === 0);
  await consent(anita, true, true);

  // …and consent DIES WITH THE NIGHT. This is the safety fix: no permanent flag.
  await db.query(`update public.parties set board_until = now() - interval '1 hour' where id = $1`, [pid]);
  board = await anon(`select * from public.room_board($1)`, [code]);
  tabs = await anon(`select * from public.room_tabs($1)`, [code]);
  ok("when the bar's board EXPIRES, everyone drops off the screen", board.rows.length === 0);
  ok("…and the tabs vanish with it", tabs.rows.length === 0);

  // a consent for ONE room is not a consent for ANOTHER
  const code2 = (await db.query(`select invite_code from public.parties where id = $1`, [pid2])).rows[0].invite_code;
  board = await anon(`select * from public.room_board($1)`, [code2]);
  ok("consenting in one room does NOT put her on another room's screen", board.rows.length === 0);

  await db.query(`update public.parties set board_until = null where id = $1`, [pid]);

  console.log("\n── 7. the Together leaderboard (opt-in both sides) ───");
  await db.query(`insert into public.friendships (requester_id, addressee_id, status) values ($1,$2,'accepted')`, [
    anita,
    rohan,
  ]);
  let fb = await as(anita, `select * from public.friends_board()`);
  ok("board is EMPTY while nobody opted in", fb.rows.length === 0);

  await as(anita, `update public.profiles set compete_visible = true where id = $1`, [anita]);
  fb = await as(anita, `select * from public.friends_board()`);
  ok("opting in puts only ME on it", fb.rows.length === 1 && fb.rows[0].display_name === "Anita");
  ok("my friend who did NOT opt in is not ranked", !fb.rows.some((r) => r.display_name === "Rohan"));

  await as(rohan, `update public.profiles set compete_visible = true where id = $1`, [rohan]);
  fb = await as(anita, `select * from public.friends_board()`);
  ok("once he opts in too, both appear", fb.rows.length === 2);

  const strangerBoard = await as(stranger, `select * from public.friends_board()`);
  ok("a stranger never sees them (friends only)", strangerBoard.rows.length === 0);

  console.log("\n── 8. profile privacy tiers ──────────────────────────");
  const aHandle = (await db.query(`select handle from public.profiles where id = $1`, [anita])).rows[0].handle;
  // Anita ── friends ── Rohan ── friends ── Meera  (Meera is Anita's FoF)
  const meera = await mkUser("Meera", `vf-meera-${Date.now()}`);
  await db.query(`insert into public.friendships (requester_id, addressee_id, status) values ($1,$2,'accepted')`, [
    rohan,
    meera,
  ]);

  const see = async (uid) => (await as(uid, `select * from public.public_profile($1)`, [aHandle])).rows.length === 1;
  const seeAnon = async () => (await anon(`select * from public.public_profile($1)`, [aHandle])).rows.length === 1;

  ok("tier 'friends': her friend can open it", await see(rohan));
  ok("tier 'friends': a friend-of-friend CANNOT", !(await see(meera)));
  ok("tier 'friends': a stranger CANNOT", !(await see(stranger)));
  ok("tier 'friends': the signed-out world CANNOT", !(await seeAnon()));

  await as(anita, `update public.profiles set profile_visibility = 'fof' where id = $1`, [anita]);
  ok("tier 'fof': the friend-of-friend CAN now (this is the new path)", await see(meera));
  ok("tier 'fof': a stranger still CANNOT", !(await see(stranger)));
  ok("tier 'fof': the signed-out world still CANNOT", !(await seeAnon()));

  await as(anita, `update public.profiles set profile_visibility = 'public' where id = $1`, [anita]);
  ok("tier 'public': anyone, even signed-out", await seeAnon());

  const pub = (await anon(`select * from public.public_profile($1)`, [aHandle])).rows[0];
  ok("a profile leaks NO spend/notes — counts only", !("spend" in pub) && !("notes" in pub) && "total" in pub);

  console.log("\n── 9. the guest's own view ───────────────────────────");
  const pb = await as(anita, `select * from public.party_points_board($1)`, [pid]);
  ok("the room board sums the ledger for members", pb.rows.length === 2);
  // Two acceptable outcomes: the rpc raises, or it returns nothing. Note the older form
  // here threw *because* rows came back and then treated that throw as "refused" — which
  // inverted the test: a real leak passed, and the correct empty result failed.
  let outsiderRows = null;
  const outsiderRaised = await refused(async () => {
    const r = await as(stranger, `select * from public.party_points_board($1)`, [pid]);
    outsiderRows = r.rows.length;
  });
  ok("a non-member cannot read the room board", outsiderRaised || outsiderRows === 0);

  console.log("\n── 10. off-trade: a bottle shop is NOT a quieter bar ──");
  // The whole legal argument for our bar card is that a visit and a purchase are
  // different events — you can walk into a pub and buy nothing. In a bottle shop
  // that gap does not exist: the visit IS the sale, and the sale is alcohol. These
  // assertions are the ones standing between a loyalty card and a prosecution.
  const sid = randomUUID();
  await as(owner, `insert into public.venues (id, name, slug, created_by, kind, country) values ($1,'Verify Bottle Shop',$2,$3,'store','IN')`, [
    sid,
    `vf-shop-${Date.now()}`.slice(0, 40),
    owner,
  ]);
  // Same as the bar above: createVenue() makes the creator STAFF, and every venue power
  // (recording a visit, redeeming a card) is gated on is_venue_staff — being created_by
  // is not enough.
  await as(owner, `insert into public.venue_staff (venue_id, user_id, role) values ($1,$2,'owner')`, [sid, owner]);
  await db.query(`update public.venues set verified = true where id = $1`, [sid]);

  // IN allows an alcoholic reward AND a spend perk — for a BAR. A shop gets neither,
  // anywhere, ever. That's our rule, tighter than India's law.
  ok(
    "INDIA: a shop cannot reward with alcohol, though a bar there can",
    await refused(() =>
      as(owner, `insert into public.venue_perks (venue_id, kind, threshold, reward, reward_alcoholic)
                 values ($1,'visits',5,'a free bottle',true)`, [sid]),
    ),
  );
  ok(
    "INDIA: a shop's card cannot count SPEND — spend at an off-licence IS the alcohol",
    await refused(() =>
      as(owner, `insert into public.venue_perks (venue_id, kind, threshold, reward)
                 values ($1,'spend',3000,'a tote bag')`, [sid]),
    ),
  );

  await as(owner, `insert into public.venue_perks (venue_id, kind, threshold, reward)
                   values ($1,'visits',3,'a free coffee')`, [sid]);
  const shopPerk = await as(owner, `select id, kind from public.venue_perks where venue_id = $1`, [sid]);
  ok("a shop CAN run a visits card with a non-alcoholic reward", shopPerk.rows.length === 1);
  const shopPerkId = shopPerk.rows[0].id;

  // IE lets a BAR run a card; it must not let a SHOP run one (s.23 bans the AWARD of
  // points "in relation to the sale of alcohol", and at a shop that's every visit).
  await db.query(`delete from public.venue_perks where venue_id = $1`, [sid]);
  await db.query(`update public.venues set country = 'IE' where id = $1`, [sid]);
  ok(
    "IRELAND: no shop card at all, even though an Irish BAR may run one",
    await refused(() =>
      as(owner, `insert into public.venue_perks (venue_id, kind, threshold, reward)
                 values ($1,'visits',5,'a free coffee')`, [sid]),
    ),
  );

  // NI's Art. 57ZB reaches EVERY licensed premises — the one place a bar loses it too.
  await db.query(`update public.venues set country = 'GB', region = 'NIR' where id = $1`, [sid]);
  ok(
    "NORTHERN IRELAND: no perk in any licensed premises — bar or shop",
    await refused(() =>
      as(owner, `insert into public.venue_perks (venue_id, kind, threshold, reward)
                 values ($1,'visits',5,'a free coffee')`, [sid]),
    ),
  );

  // A bar carrying a lawful alcoholic reward must not be able to become a SHOP and
  // quietly keep it — that's "buy nine bottles, get the tenth free" through the back
  // door. The perk has to be re-tested against the shop's rules on the way through.
  await db.query(`update public.venues set country = 'IN', region = null, kind = 'bar' where id = $1`, [sid]);
  await as(owner, `insert into public.venue_perks (venue_id, kind, threshold, reward, reward_alcoholic)
                   values ($1,'visits',5,'a free pour',true)`, [sid]);
  ok(
    "an alcoholic reward is fine for an Indian BAR",
    (await db.query(`select count(*)::int n from public.venue_perks where venue_id = $1 and reward_alcoholic`, [sid]))
      .rows[0].n === 1,
  );
  ok(
    "…but that BAR cannot become a SHOP while still holding it",
    await refused(() => db.query(`update public.venues set kind = 'store' where id = $1`, [sid])),
  );
  await db.query(`delete from public.venue_perks where venue_id = $1`, [sid]);
  await db.query(`update public.venues set kind = 'store' where id = $1`, [sid]);
  ok(
    "once the unlawful perk is dropped, the switch goes through",
    (await db.query(`select kind from public.venues where id = $1`, [sid])).rows[0].kind === "store",
  );

  // A shop has no rooms — a kiosk board of who's-in-the-shop is surveillance, not vibe.
  ok(
    "an off-licence cannot open a room",
    await refused(() =>
      as(owner, `insert into public.parties (id, host_id, venue_id, code, date, title)
                 values ($1,$2,$3,$4,current_date,'Shop night')`,
        [randomUUID(), owner, sid, `vs${Date.now()}`.slice(0, 8)]),
    ),
  );

  console.log("\n── 11. punching a card at the till ───────────────────");
  await as(owner, `insert into public.venue_perks (venue_id, kind, threshold, reward)
                   values ($1,'visits',2,'a free coffee')`, [sid]);
  const cardId = (await as(owner, `select id from public.venue_perks where venue_id = $1`, [sid])).rows[0].id;

  // THE RULE: a guest can never punch their own card. Same as a tab.
  ok("a guest CANNOT punch their own card", await refused(() => as(anita, `select public.record_visit($1,$2)`, [sid, anita])));
  ok("a stranger CANNOT punch anyone's card", await refused(() => as(stranger, `select public.record_visit($1,$2)`, [sid, anita])));

  await as(owner, `select public.record_visit($1,$2)`, [sid, anita]);
  await as(owner, `select public.record_visit($1,$2)`, [sid, anita]); // same day, again
  const punches = await db.query(`select count(*)::int n from public.venue_checkins where venue_id = $1 and user_id = $2`, [sid, anita]);
  ok("TWO punches on the same day count ONCE (a visits card can't become a volume card)", punches.rows[0].n === 1);

  let card = (await as(anita, `select * from public.perk_status($1,$2)`, [sid, anita])).rows[0];
  ok("her shop card shows 1 of 2 visits", Number(card.progress) === 1 && card.earned === false);

  // Backdate yesterday's punch so she crosses the threshold without waiting a day.
  await db.query(
    `insert into public.venue_checkins (venue_id, user_id, recorded_by, on_date, created_at)
     values ($1,$2,$3,current_date - 1, now() - interval '1 day')`,
    [sid, anita, owner],
  );
  card = (await as(anita, `select * from public.perk_status($1,$2)`, [sid, anita])).rows[0];
  ok("a second day's punch earns it", Number(card.progress) === 2 && card.earned === true);

  ok("a guest cannot hand themselves the reward", await refused(() => as(anita, `select public.redeem_perk($1,$2)`, [cardId, anita])));
  await as(owner, `select public.redeem_perk($1,$2)`, [cardId, anita]);
  card = (await as(anita, `select * from public.perk_status($1,$2)`, [sid, anita])).rows[0];
  ok("once claimed, her shop card starts again from zero", Number(card.progress) === 0 && card.claims === 1);
  ok("it cannot be claimed twice off the same earn", await refused(() => as(owner, `select public.redeem_perk($1,$2)`, [cardId, anita])));

  console.log("\n── 12. plans: friends/fof only, host approves, blocks bite ──");
  // The graph from earlier: anita ── rohan ── meera. So meera is anita's FoF, and
  // the stranger is nobody's friend. Exactly the shape a meetup feature must respect.
  const seesPlan = async (uid, planId) =>
    (await as(uid, `select count(*)::int n from public.plans where id=$1`, [planId])).rows[0].n === 1;

  const planF = randomUUID();
  await as(anita, `insert into public.plans (id, host_id, title, plan_date, join_policy)
                   values ($1,$2,'Negronis Friday', current_date + 7, 'friends')`, [planF, anita]);
  ok("a FRIENDS plan: the host's friend can see it", await seesPlan(rohan, planF));
  ok("a FRIENDS plan: a friend-of-friend CANNOT", !(await seesPlan(meera, planF)));
  ok("a FRIENDS plan: a stranger CANNOT", !(await seesPlan(stranger, planF)));

  const planG = randomUUID();
  await as(anita, `insert into public.plans (id, host_id, title, plan_date, join_policy)
                   values ($1,$2,'Open-ish Saturday', current_date + 8, 'fof')`, [planG, anita]);
  ok("a FOF plan: the friend-of-friend CAN see it", await seesPlan(meera, planG));
  ok("a FOF plan: a stranger still CANNOT", !(await seesPlan(stranger, planG)));

  // there is NO stranger tier — the CHECK refuses it
  ok("a plan CANNOT be opened to strangers (no such join_policy)",
    await refused(() => as(anita, `insert into public.plans (id, host_id, title, plan_date, join_policy)
                                   values ($1,$2,'Nope', current_date + 1, 'open')`, [randomUUID(), anita])));
  ok("a plan CANNOT be in the past (trigger)",
    await refused(() => as(anita, `insert into public.plans (id, host_id, title, plan_date)
                                   values ($1,$2,'Yesterday', current_date - 1)`, [randomUUID(), anita])));

  // joining: a stranger can't even ask; a friend can, and only the host decides
  ok("a stranger cannot ask to join a plan they can't see",
    await refused(() => as(stranger, `select public.request_join($1, null)`, [planF])));
  await as(rohan, `select public.request_join($1, 'in!')`, [planF]);
  const jid = (await as(anita, `select id from public.plan_joins where plan_id=$1 and user_id=$2`, [planF, rohan])).rows[0].id;
  ok("the joiner cannot approve their own request", await refused(() => as(rohan, `select public.respond_join($1, true)`, [jid])));
  ok("a guest cannot forge an approved join row (no write policy)",
    await refused(() => as(rohan, `insert into public.plan_joins (plan_id, user_id, status) values ($1,$2,'approved')`, [planG, rohan])));
  await as(anita, `select public.respond_join($1, true)`, [jid]);
  ok("once the host approves, the going count rises", (await as(anita, `select public.plan_going_count($1) n`, [planF])).rows[0].n === 2);

  // reports are a one-way message: you can file, you can't read them back
  await as(rohan, `insert into public.reports (reporter_id, subject_user_id, reason) values ($1,$2,'spam')`, [rohan, stranger]);
  ok("a report can't be read back by its author (no select policy)",
    (await as(rohan, `select count(*)::int n from public.reports`)).rows[0].n === 0);

  // block: anita blocks rohan → he loses sight of her plan, and his join is torn down
  await as(anita, `select public.block_user($1)`, [rohan]);
  ok("after a block, the blocked person can no longer see the plan", !(await seesPlan(rohan, planF)));
  ok("after a block, the live join is withdrawn",
    (await as(anita, `select status from public.plan_joins where plan_id=$1 and user_id=$2`, [planF, rohan])).rows[0].status === "withdrawn");
  ok("a blocked pair can't find each other in search",
    (await as(rohan, `select count(*)::int n from public.search_users($1)`, ["Anita"])).rows[0].n === 0);

  console.log("\n── 13. vouches: a friend's word, other-only, a count not a rating ──");
  // rohan ── meera are accepted friends (from §8). anita blocked rohan in §12.
  // A vouch is directional — you stake your word FOR someone else, never yourself.
  ok("nobody vouches for meera yet", (await as(rohan, `select public.vouch_count($1) n`, [meera])).rows[0].n === 0);

  // self-vouch is impossible — the table CHECK and the friend-gate both forbid it,
  // so no one can inflate their own standing (the "no self-reward" line, for trust).
  ok("you cannot vouch for yourself",
    await refused(() => as(rohan, `insert into public.vouches (voucher_id, vouchee_id) values ($1,$1)`, [rohan])));
  // the friend-gate lives in the DB, not just the UI: a non-friend insert is refused.
  ok("a non-friend cannot vouch",
    await refused(() => as(stranger, `insert into public.vouches (voucher_id, vouchee_id) values ($1,$2)`, [stranger, meera])));
  // and a vouch can't cross a block (anita ↔ rohan are blocked from §12).
  ok("a vouch cannot cross a block",
    await refused(() => as(anita, `insert into public.vouches (voucher_id, vouchee_id) values ($1,$2)`, [anita, rohan])));

  // a real accepted friend CAN vouch, and it's counted.
  await as(rohan, `insert into public.vouches (voucher_id, vouchee_id) values ($1,$2)`, [rohan, meera]);
  ok("a friend's vouch is counted", (await as(meera, `select public.vouch_count($1) n`, [meera])).rows[0].n === 1);

  // it surfaces as a SOFT signal on meera's plan — a count, never a rating of her.
  const planM = randomUUID();
  await as(meera, `insert into public.plans (id, host_id, title, plan_date, join_policy)
                   values ($1,$2,'Meera hosts', current_date + 5, 'friends')`, [planM, meera]);
  const sig = (await as(rohan, `select * from public.plan_signals($1)`, [planM])).rows[0];
  ok("plan_signals surfaces the host's vouch count", sig && Number(sig.host_vouches) === 1);

  // a vouch is withdrawable.
  await as(rohan, `delete from public.vouches where voucher_id=$1 and vouchee_id=$2`, [rohan, meera]);
  ok("a withdrawn vouch is gone", (await as(meera, `select public.vouch_count($1) n`, [meera])).rows[0].n === 0);

  console.log("\n── 14. moderation: reports become actionable, sanctions bite ──");
  // The trust root: a moderator is SEEDED (server-side), never grantable from the app.
  const mod = await mkUser("Mod", `vf-mod-${Date.now()}`);
  await db.query(`insert into public.moderators (user_id) values ($1)`, [mod]);

  // the roster is not readable by the world; you only ever see your own row.
  ok("a person can't read the moderator roster",
    (await as(anita, `select count(*)::int n from public.moderators`)).rows[0].n === 0);
  ok("a moderator sees their own row",
    (await as(mod, `select count(*)::int n from public.moderators where user_id=$1`, [mod])).rows[0].n === 1);

  // the queue is moderator-only. (rohan reported the stranger back in §12.)
  ok("a non-moderator cannot read the report queue",
    await refused(() => as(anita, `select * from public.open_reports()`)));
  const queue = await as(mod, `select * from public.open_reports()`);
  ok("the moderator sees the queued report on the stranger", queue.rows.some((r) => r.subject_id === stranger));

  // only a moderator can sanction, and never themselves.
  ok("a non-moderator cannot suspend anyone",
    await refused(() => as(anita, `select public.suspend_user($1, now() + interval '7 days', 'nope')`, [stranger])));
  ok("a moderator cannot sanction themselves",
    await refused(() => as(mod, `select public.ban_user($1, 'x')`, [mod])));

  // suspend the stranger → the account is frozen, and the freeze bites everywhere.
  await as(mod, `select public.suspend_user($1, now() + interval '7 days', 'spam')`, [stranger]);
  ok("after a suspension the account reads as sanctioned",
    (await as(mod, `select public.is_sanctioned($1) s`, [stranger])).rows[0].s === true);
  ok("a suspended account cannot create a plan",
    await refused(() => as(stranger, `insert into public.plans (id, host_id, title, plan_date)
                                       values ($1,$2,'nope', current_date + 2)`, [randomUUID(), stranger])));
  ok("a suspended account cannot ask to join",
    await refused(() => as(stranger, `select public.request_join($1, null)`, [planG])));
  ok("a sanctioned user doesn't surface in search",
    (await as(anita, `select count(*)::int n from public.search_users($1)`, ["Stranger"])).rows[0].n === 0);
  ok("a sanctioned user can't use search either",
    (await as(stranger, `select count(*)::int n from public.search_users($1)`, ["Anita"])).rows[0].n === 0);

  // the audit log records it, and only a moderator can read it.
  ok("the audit log is not readable by a non-moderator",
    (await as(anita, `select count(*)::int n from public.moderation_actions`)).rows[0].n === 0);

  // lifting restores the account fully.
  await as(mod, `select public.lift_sanction($1)`, [stranger]);
  ok("lifting the sanction restores the account",
    (await as(mod, `select public.is_sanctioned($1) s`, [stranger])).rows[0].s === false);
  const backPlan = randomUUID();
  await as(stranger, `insert into public.plans (id, host_id, title, plan_date) values ($1,$2,'back', current_date + 2)`, [backPlan, stranger]);
  ok("…and it can create a plan again once lifted",
    (await db.query(`select count(*)::int n from public.plans where id=$1`, [backPlan])).rows[0].n === 1);

  // suspend + lift each left an audit row.
  ok("every moderation action left an audit row (suspend + lift)",
    (await as(mod, `select count(*)::int n from public.moderation_actions where subject_id=$1`, [stranger])).rows[0].n === 2);

  // ── report de-dup (035): one angry person can't inflate another's report count ──
  // rohan already reported the stranger once (§12). The client path is ON CONFLICT DO
  // NOTHING, so reporting again is a silent no-op — still ONE reporter on the counter.
  // The real client path (lib/safety.reportUser) is a PLAIN insert whose duplicate is
  // swallowed in the client. It is NOT `on conflict do nothing`: DO NOTHING must read the
  // conflicting row, `reports` has no select policy, and Postgres therefore refuses the
  // statement outright — which used to tell a reporter their second report had failed.
  ok(
    "a repeat report is refused by the DB (the client swallows it as a no-op)",
    await refused(() =>
      as(rohan, `insert into public.reports (reporter_id, subject_user_id, reason) values ($1,$2,'harassment')`, [rohan, stranger]),
    ),
  );
  ok(
    "…and `on conflict do nothing` is NOT a usable path here (no select policy to read the conflict)",
    await refused(() =>
      as(rohan, `insert into public.reports (reporter_id, subject_user_id, reason) values ($1,$2,'harassment')
                 on conflict (reporter_id, subject_user_id) do nothing`, [rohan, stranger]),
    ),
  );
  const dq1 = (await as(mod, `select * from public.open_reports()`)).rows.find((r) => r.subject_id === stranger);
  ok("the same reporter twice still counts as one", dq1 && dq1.subject_report_count === 1);
  // A genuinely different reporter DOES move the needle — real signal still gets through.
  await as(meera, `insert into public.reports (reporter_id, subject_user_id, reason) values ($1,$2,'unsafe')`, [meera, stranger]);
  const dq2 = (await as(mod, `select * from public.open_reports()`)).rows.find((r) => r.subject_id === stranger);
  ok("a second DISTINCT reporter counts as two", dq2 && dq2.subject_report_count === 2);
  // Even a raw insert (bypassing the client) can't stack a duplicate — the DB blocks it.
  ok("a duplicate report is rejected by the database itself",
    await refused(() => as(rohan, `insert into public.reports (reporter_id, subject_user_id, reason) values ($1,$2,'spam')`, [rohan, stranger])));

  console.log("\n── 15. plans: private (only me) + invite-by-username + RSVP (037) ──");
  // guestA is NOBODY's friend (proves invite is no longer graph-gated); guestB gets
  // blocked by the host (proves a block still refuses an invite).
  const priya = await mkUser("Priya", `vf-priya-${Date.now()}`);
  const guestA = await mkUser("Guest A", `vf-gA-${Date.now()}`);
  const guestB = await mkUser("Guest B", `vf-gB-${Date.now()}`);
  await as(priya, `select public.block_user($1)`, [guestB]);
  const countsPlan = async (uid, planId) =>
    (await as(uid, `select count(*)::int n from public.plans where id=$1`, [planId])).rows[0].n;

  // PRIVATE — nobody but the host, ever; not joinable.
  const planPriv = randomUUID();
  await as(priya, `insert into public.plans (id, host_id, title, plan_date, join_policy)
                   values ($1,$2,'Just me', current_date + 3, 'private')`, [planPriv, priya]);
  ok("a PRIVATE plan: the host sees it", (await countsPlan(priya, planPriv)) === 1);
  ok("a PRIVATE plan: nobody else can see it", (await countsPlan(guestA, planPriv)) === 0);
  ok("a PRIVATE plan: nobody can ask to join",
    await refused(() => as(guestA, `select public.request_join($1, null)`, [planPriv])));

  // INVITE — only named guests see it; anyone can be named (not just friends) EXCEPT a
  // blocked pairing, and nothing happens without the guest's own RSVP.
  const planInv = randomUUID();
  await as(priya, `insert into public.plans (id, host_id, title, plan_date, plan_time, join_policy)
                   values ($1,$2,'Just us', current_date + 4, '19:30', 'invite')`, [planInv, priya]);
  ok("an INVITE plan: an un-invited person CANNOT see it", (await countsPlan(guestA, planInv)) === 0);
  ok("a guest can't invite themselves (host only)",
    await refused(() => as(guestA, `select public.invite_to_plan($1,$2)`, [planInv, guestA])));
  ok("a BLOCKED person cannot be invited",
    await refused(() => as(priya, `select public.invite_to_plan($1,$2)`, [planInv, guestB])));
  // guestA is nobody's friend — inviting them proves the friends/fof gate is gone.
  await as(priya, `select public.invite_to_plan($1,$2)`, [planInv, guestA]);
  ok("anyone can be invited by name — even a non-friend (with consent)", (await countsPlan(guestA, planInv)) === 1);
  ok("a non-invited person cannot RSVP",
    await refused(() => as(guestB, `select public.respond_invite($1, true)`, [planInv])));

  // RSVP directly — no host approval needed (the host already chose them).
  await as(guestA, `select public.respond_invite($1, true)`, [planInv]);
  ok("an invited guest RSVPs 'going' directly (no host approval) → going count rises",
    (await as(priya, `select public.plan_going_count($1) n`, [planInv])).rows[0].n === 2);

  // the calendar overlay carries the start time and the right plans per person
  const priyaDays = (await as(priya, `select * from public.my_plan_days()`)).rows;
  ok("my_plan_days lists the host's own plans (private + invite), with the time",
    priyaDays.some((r) => r.title === "Just me") &&
    priyaDays.some((r) => r.title === "Just us" && String(r.plan_time).startsWith("19:30")));
  const guestDays = (await as(guestA, `select * from public.my_plan_days()`)).rows.map((r) => r.title);
  ok("my_plan_days lists a plan I RSVP'd to, not the host's private one",
    guestDays.includes("Just us") && !guestDays.includes("Just me"));

  // RSVP 'can't make it' pulls them back out; uninvite removes the view entirely
  await as(guestA, `select public.respond_invite($1, false)`, [planInv]);
  ok("RSVP 'can't make it' drops the going count",
    (await as(priya, `select public.plan_going_count($1) n`, [planInv])).rows[0].n === 1);
  await as(priya, `select public.uninvite_from_plan($1,$2)`, [planInv, guestA]);
  ok("uninviting removes the guest's view of the plan", (await countsPlan(guestA, planInv)) === 0);

  console.log("\n── 16. the Cartographer: charting the shared map (042) ──");
  // A drinker offers a drink the dictionary doesn't know. Accepting it changes what
  // EVERY user sees, so the write path is the whole security story: status is server-
  // forced, there is no client UPDATE policy, and only a moderator can accept.
  const propId = randomUUID();
  await as(
    anita,
    `insert into public.chart_proposals (id, author, raw_name, canonical, family, type, status)
     values ($1,$2,'grandpas punch','Grandpa''s Punch','Grandpa''s Punch','cocktail','accepted')`,
    [propId, anita],
  );
  // She ASKED for 'accepted'. The trigger must have overruled her — otherwise charting
  // is a self-serve byline and the moderator queue is decorative.
  const forced = await db.query(`select status from public.chart_proposals where id = $1`, [propId]);
  ok("a proposal lands as 'pending' however it was sent (status is server-forced)",
    forced.rows[0].status === "pending");

  ok("the author can read her own pending proposal",
    (await as(anita, `select count(*)::int n from public.chart_proposals where id = $1`, [propId])).rows[0].n === 1);
  ok("another drinker CANNOT see an unreviewed proposal (pending is not published)",
    (await as(rohan, `select count(*)::int n from public.chart_proposals where id = $1`, [propId])).rows[0].n === 0);

  ok("a non-moderator cannot open the review queue",
    await refused(() => as(rohan, `select * from public.pending_chart_proposals()`)));
  const chartQueue = await as(mod, `select * from public.pending_chart_proposals()`);
  ok("the moderator sees it queued", chartQueue.rows.some((r) => r.id === propId));

  // No UPDATE policy at all ⇒ RLS matches zero rows rather than raising, so judge the
  // OUTCOME: she must still be 'pending' afterwards.
  await refused(() => as(anita, `update public.chart_proposals set status='accepted' where id = $1`, [propId]));
  const selfAccept = await db.query(`select status from public.chart_proposals where id = $1`, [propId]);
  ok("a guest CANNOT accept her own proposal (no client update path)",
    selfAccept.rows[0].status === "pending");
  ok("…and a non-moderator cannot call the review rpc either",
    await refused(() => as(rohan, `select public.review_chart_proposal($1,'accepted')`, [propId])));

  await as(mod, `select public.review_chart_proposal($1,'accepted')`, [propId]);
  const decided = await db.query(`select status, reviewed_by from public.chart_proposals where id = $1`, [propId]);
  ok("the moderator accepts it, and the review is on the record",
    decided.rows[0].status === "accepted" && decided.rows[0].reviewed_by === mod);

  ok("an accepted chart is world-readable — it IS the dictionary now",
    (await as(rohan, `select count(*)::int n from public.chart_proposals where id = $1`, [propId])).rows[0].n === 1);

  const charted = await as(rohan, `select * from public.charted_families()`);
  const mineChart = charted.rows.find((r) => r.family === "Grandpa's Punch");
  ok("charted_families() credits the charter by handle", Boolean(mineChart && mineChart.handle));
  // THE TRIPWIRE (spec §2): one row per family, and no per-author tally to rank anyone by.
  ok("…one row per family, and no contribution count anywhere in the shape",
    charted.rows.filter((r) => r.family === "Grandpa's Punch").length === 1
      && !Object.keys(mineChart ?? {}).some((c) => /count|total|rank|score/i.test(c)));

  ok("a decision is made once — re-reviewing does nothing",
    (await (async () => {
      await as(mod, `select public.review_chart_proposal($1,'rejected')`, [propId]);
      return db.query(`select status from public.chart_proposals where id = $1`, [propId]);
    })()).rows[0].status === "accepted");

  ok("the author cannot delete a chart once it is part of the map",
    (await (async () => {
      await as(anita, `delete from public.chart_proposals where id = $1`, [propId]);
      return db.query(`select count(*)::int n from public.chart_proposals where id = $1`, [propId]);
    })()).rows[0].n === 1);

  // …but an unreviewed one is hers to withdraw.
  const p2 = randomUUID();
  await as(anita, `insert into public.chart_proposals (id, author, raw_name, canonical, family, type)
                   values ($1,$2,'bathtub sherbet','Bathtub Sherbet','Bathtub Sherbet','soft')`, [p2, anita]);
  await as(anita, `delete from public.chart_proposals where id = $1`, [p2]);
  ok("an unreviewed proposal CAN be withdrawn by its author",
    (await db.query(`select count(*)::int n from public.chart_proposals where id = $1`, [p2])).rows[0].n === 0);

  console.log("\n── 17. the join paths (they had no runtime cover at all) ──");
  // join_party / join_circle / plan_requests are table-returning plpgsql, the same shape
  // as venue_guest_card — whose OUT parameter collided with a column name and raised
  // "column reference is ambiguous" at RUNTIME, invisible to build, tests and db:audit
  // alike (see 043). Nothing here ever executed them, so nothing could have caught the
  // same fault. These calls exist mainly so that class of bug cannot hide again.
  const jpCode = `vj${Date.now()}`.slice(0, 8);
  const jpId = randomUUID();
  await as(anita, `insert into public.parties (id, name, host_id, date, invite_code) values ($1,'Join Probe',$2,current_date,$3)`,
    [jpId, anita, jpCode]);
  const joined = await as(rohan, `select * from public.join_party($1)`, [jpCode]);
  ok("join_party() resolves an invite code to the room", joined.rows.length === 1 && joined.rows[0].id === jpId);

  const jcCode = `vc${Date.now()}`.slice(0, 8);
  const jcId = randomUUID();
  await as(anita, `insert into public.circles (id, name, created_by, invite_code) values ($1,'Join Circle',$2,$3)`,
    [jcId, anita, jcCode]);
  const joinedC = await as(rohan, `select * from public.join_circle($1)`, [jcCode]);
  ok("join_circle() resolves an invite code to the circle", joinedC.rows.length === 1 && joinedC.rows[0].id === jcId);

  ok("a bad code is refused, not silently joined",
    await refused(() => as(rohan, `select * from public.join_party($1)`, ["nosuch99"])));

  const prPlan = randomUUID();
  await as(anita, `insert into public.plans (id, host_id, title, plan_date, join_policy) values ($1,$2,'Req probe',current_date,'friends')`,
    [prPlan, anita]);
  ok("plan_requests() runs for the host and starts empty",
    (await as(anita, `select * from public.plan_requests($1)`, [prPlan])).rows.length === 0);

  console.log("\n── 18. cups: a competition that cannot reward volume (044) ──");
  // Fresh cast — an isolated window (2020) and new users, so no other section's
  // entries, friendships or blocks colour the scores or the join.
  const cupOwner = await mkUser("Cup Host", `vf-ch-${Date.now()}`);
  const cupGuest = await mkUser("Cup Guest", `vf-cg-${Date.now()}`);
  const cupOut = await mkUser("Cup Outsider", `vf-cx-${Date.now()}`);
  const logE = (uid, date, drink, type) =>
    as(uid, `insert into public.entries (user_id,date,drink,type) values ($1,$2,$3,$4)`, [uid, date, drink, type]);

  const cupId = randomUUID();
  await as(cupOwner, `insert into public.cups (id,created_by,name,axis,join_policy,starts_on,ends_on)
    values ($1,$2,'Wanderer Cup','drinks','invite','2020-01-01','2020-01-31')`, [cupId, cupOwner]);
  const cupCode = (await db.query(`select invite_code from public.cups where id=$1`, [cupId])).rows[0].invite_code;
  ok("the cup owner is auto-added to their own cup (trigger)",
    (await db.query(`select count(*)::int n from public.cup_members where cup_id=$1 and user_id=$2`, [cupId, cupOwner])).rows[0].n === 1);

  // BREADTH, NEVER VOLUME: two of the same drink + one distinct → score 2, not 3.
  // A dry day is not a drink, so it doesn't lift a 'drinks' score.
  await logE(cupOwner, "2020-01-05", "Latte", "coffee");
  await logE(cupOwner, "2020-01-06", "Latte", "coffee");
  await logE(cupOwner, "2020-01-07", "Negroni", "cocktail");
  await logE(cupOwner, "2020-01-08", "dry day", "none");
  const ownScore = (await as(cupOwner, `select score from public.cup_board($1) where user_id=$2`, [cupId, cupOwner])).rows[0]?.score;
  ok("a 'drinks' cup scores DISTINCT drinks (2), never volume (3)", ownScore === 2);

  ok("a guest joins the cup by code", (await as(cupGuest, `select public.join_cup($1) id`, [cupCode])).rows[0].id === cupId);
  await logE(cupGuest, "2020-01-10", "IPA", "beer");
  const cupBoard = (await as(cupOwner, `select * from public.cup_board($1)`, [cupId])).rows;
  ok("the board lists members with COUNTS only (no entry content)",
    cupBoard.length === 2 && cupBoard.every((r) => "score" in r && !("drink" in r)));

  ok("a non-member reading the cup board gets nothing",
    (await as(cupOut, `select * from public.cup_board($1)`, [cupId])).rows.length === 0);
  ok("a stranger cannot forge a cup membership (no insert policy)",
    await refused(() => as(cupOut, `insert into public.cup_members (cup_id,user_id) values ($1,$2)`, [cupId, cupOut])));
  ok("a 'volume' cup is refused by the axis CHECK (the boundary holds)",
    await refused(() => as(cupOwner, `insert into public.cups (created_by,name,axis,starts_on,ends_on)
      values ($1,'x','volume','2020-01-01','2020-01-31')`, [cupOwner])));
  await as(cupGuest, `delete from public.cup_members where cup_id=$1 and user_id=$2`, [cupId, cupGuest]);
  ok("leaving the cup drops you from its board",
    (await as(cupOwner, `select * from public.cup_board($1)`, [cupId])).rows.length === 1);

  console.log("\n── 19. community recipes: friends → 50% → moderated public (045) ──");
  const rAuthor = await mkUser("Recipe Author", `vf-ra-${Date.now()}`);
  const rMod = await mkUser("Recipe Mod", `vf-rm-${Date.now()}`);
  await db.query(`insert into public.moderators (user_id) values ($1)`, [rMod]);
  const rFriends = [];
  for (let i = 0; i < 4; i++) {
    const fid = await mkUser(`RF${i}`, `vf-rf${i}-${Date.now()}`);
    await db.query(`insert into public.friendships (requester_id, addressee_id, status) values ($1,$2,'accepted')`, [rAuthor, fid]);
    rFriends.push(fid);
  }
  const rStranger = await mkUser("Recipe Stranger", `vf-rs-${Date.now()}`);
  const recId = randomUUID();
  const recState = async () => (await db.query(`select state from public.recipes where id=$1`, [recId])).rows[0].state;

  await as(rAuthor, `insert into public.recipes (id,author_id,name,ingredients,method) values ($1,$2,'Verify Punch','{rum,lime}','Shake it.')`, [recId, rAuthor]);
  ok("a new recipe starts friends-only", (await recState()) === "friends");
  ok("a stranger can't see a friends recipe",
    (await as(rStranger, `select public.recipe_visible_to($1,$2) v`, [recId, rStranger])).rows[0].v === false);
  ok("a stranger can't react to what they can't see",
    await refused(() => as(rStranger, `insert into public.recipe_reactions (recipe_id,user_id,kind) values ($1,$2,'love')`, [recId, rStranger])));

  await as(rFriends[0], `insert into public.recipe_reactions (recipe_id,user_id,kind) values ($1,$2,'love')`, [recId, rFriends[0]]);
  ok("one friend (25%) does not promote it", (await recState()) === "friends");
  await as(rFriends[1], `insert into public.recipe_reactions (recipe_id,user_id,kind) values ($1,$2,'made')`, [recId, rFriends[1]]);
  ok("half the friends backing it flips it to 'pending'", (await recState()) === "pending");
  ok("the same reaction twice is refused (anti-farm)",
    await refused(() => as(rFriends[0], `insert into public.recipe_reactions (recipe_id,user_id,kind) values ($1,$2,'love')`, [recId, rFriends[0]])));

  // No client UPDATE policy → the author's attempt hits 0 rows and the state is unchanged
  // (RLS filters the row out; it does not throw). The queue can't be jumped.
  await as(rAuthor, `update public.recipes set state='public' where id=$1`, [recId]);
  ok("an author cannot jump the queue (update touches 0 rows, stays pending)", (await recState()) === "pending");

  ok("a non-moderator's recipe queue is empty", (await as(rAuthor, `select * from public.pending_recipes()`, [])).rows.length === 0);
  ok("the moderator sees the pending recipe", (await as(rMod, `select * from public.pending_recipes()`, [])).rows.some((r) => r.id === recId));
  await as(rMod, `select public.review_recipe($1, true)`, [recId]);
  ok("a moderator approving it makes it public", (await recState()) === "public");
  ok("now a stranger sees it and can react",
    (await as(rStranger, `insert into public.recipe_reactions (recipe_id,user_id,kind) values ($1,$2,'totry') returning kind`, [recId, rStranger])).rows[0].kind === "totry");
  ok("reaction counts come back counts-only across three kinds",
    (await as(rAuthor, `select * from public.recipe_reaction_counts($1)`, [recId])).rows.length === 3);
} catch (e) {
  // Print WHAT failed, not just that something did. Postgres puts the useful part in
  // detail/hint/where and the offending SQL in the driver's `query`; without these a
  // crash reads as "current transaction is aborted" with no way to find the statement.
  console.log(`\n!! harness crashed: ${e.message}`);
  for (const k of ["detail", "hint", "where", "constraint", "table", "column"]) {
    if (e[k]) console.log(`   ${k}: ${e[k]}`);
  }
  if (e.stack) console.log(`   at: ${e.stack.split("\n").slice(1, 3).join(" | ").trim()}`);
  fails.push(`harness: ${e.message}`);
} finally {
  await db.query("rollback");
  await db.end();
}

console.log(`\n═══════════════════════════════════════════════════════`);
console.log(`  ${pass} passed, ${fails.length} failed   (all changes rolled back)`);
if (fails.length) {
  console.log("\n  FAILURES:");
  for (const f of fails) console.log(`   ✗ ${f}`);
  process.exitCode = 1;
}
