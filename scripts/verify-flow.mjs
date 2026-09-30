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

/** Run SQL as a signed-in user (RLS on), exactly like the browser does. If the statement
 *  fails, its own error propagates (a reset in a `finally` would fail too, on the aborted
 *  transaction, and hide the real message); `refused()` rolls the role back with the rest. */
async function as(uid, sql, params = []) {
  await db.query("set local role authenticated");
  await db.query(`set local request.jwt.claims = '${JSON.stringify({ sub: uid, role: "authenticated" })}'`);
  const res = await db.query(sql, params);
  await db.query("reset role");
  await db.query("reset request.jwt.claims");
  return res;
}
/** Run as a signed-OUT visitor (the kiosk screen, a stranger). */
async function anon(sql, params = []) {
  await db.query("set local role anon");
  const res = await db.query(sql, params);
  await db.query("reset role");
  return res;
}
/** Expect a write to be REFUSED. Returns true when it was.
 *
 *  A refused statement aborts the transaction, and every later statement would then fail
 *  with "current transaction is aborted" — so the attempt runs inside a SAVEPOINT, and a
 *  refusal rolls back to it (which also undoes the attempt's SET LOCAL role and claims). */
async function refused(fn) {
  await db.query("savepoint expect_refusal");
  try {
    await fn();
    await db.query("release savepoint expect_refusal");
    return false;
  } catch {
    await db.query("rollback to savepoint expect_refusal");
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

/** Put someone on a team for a scene that's testing something else. From 053 no client can
 *  insert a roster row (the owner's code or an approved invite are the ways on, tested in 16
 *  and 23), so the scenery goes in as the database, like the rest of the fixtures. */
const seat = (venueId, uid, role) =>
  db.query(`insert into public.venue_staff (venue_id, user_id, role) values ($1,$2,$3) on conflict do nothing`, [venueId, uid, role]);

await db.connect();
await db.query("begin");
// 053 (staff access) closes the direct roster insert; the scenes adapt to either schema.
const has053 = !!(await db.query(`select to_regprocedure('public.claim_staff_enrolment(uuid,text)') f`)).rows[0].f;
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
  // createVenue() in src/lib/venues.ts puts the creator on the team as 'owner' straight
  // after the insert — every staff-gated function checks venue_staff, not created_by.
  await as(owner, `insert into public.venue_staff (venue_id, user_id, role) values ($1,$2,'owner')`, [vid, owner]);
  ok("owner can create a venue", true);

  const selfVerify = await refused(() => as(owner, `update public.venues set verified = true where id = $1`, [vid]));
  const v1 = await db.query(`select verified from public.venues where id = $1`, [vid]);
  ok("a venue CANNOT verify itself", selfVerify || v1.rows[0].verified === false);

  const addBarman = () => as(owner, `insert into public.venue_staff (venue_id, user_id, role) values ($1,$2,'bartender')`, [vid, barman]);
  if (has053) {
    ok("nobody is inserted onto a team from an app, not even by the owner (053: the owner's code is the way on)",
      await refused(addBarman));
    await seat(vid, barman, "bartender");
  } else {
    await addBarman();
    ok("owner can add a bartender", true);
  }

  await as(owner, `insert into public.venue_verifications (venue_id, requested_by, contact, note) values ($1,$2,'owner@verify.local','please')`, [
    vid,
    owner,
  ]);
  const stat = await db.query(`select status from public.venue_verifications where venue_id = $1`, [vid]);
  ok("verification request lands as 'pending'", stat.rows[0].status === "pending");

  // There is no UPDATE policy at all, so the attempt either errors or matches no row —
  // what matters is that the request is still pending afterwards.
  const selfApprove = await refused(() =>
    as(owner, `update public.venue_verifications set status='approved' where venue_id = $1`, [vid]),
  );
  const stat2 = await db.query(`select status from public.venue_verifications where venue_id = $1`, [vid]);
  ok("a venue CANNOT approve its own request", selfApprove || stat2.rows[0].status === "pending");

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
  // 030: moving a venue re-tests every perk it already has, so the ₹ spend perk from
  // scene 5 cannot come along to Ireland at all.
  ok(
    "a venue CANNOT carry an unlawful perk into a new jurisdiction (030 re-check)",
    await refused(() => db.query(`update public.venues set country = 'IE' where id = $1`, [vid])),
  );
  await db.query(`delete from public.venue_perks where venue_id = $1`, [vid]);
  await db.query(`update public.venues set country = 'IE' where id = $1`, [vid]);
  ok(
    "IRELAND: a spend-based perk is refused by the database",
    await refused(() =>
      as(owner, `insert into public.venue_perks (venue_id, kind, threshold, reward, reward_alcoholic)
                 values ($1,'spend',3000,'a free pour',false)`, [vid]),
    ),
  );
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

  // Thailand bans discounts/giveaways outright — no perk of ANY kind. A venue holding a
  // perk can't even move there (030 re-check); without one, none can be created.
  ok(
    "THAILAND: a venue holding a perk cannot move there",
    await refused(() => db.query(`update public.venues set country = 'TH', region = null where id = $1`, [vid])),
  );
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

  // back to the home market, and restore the spend perk for the rest of the run
  await db.query(`update public.venues set country = 'IN', region = null where id = $1`, [vid]);
  await as(owner, `insert into public.venue_perks (venue_id, kind, threshold, reward, reward_alcoholic)
                   values ($1,'spend',3000,'a free coffee',false)`, [vid]);

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
  // (030: nor can a venue move to Ireland while holding the alcoholic 'free pour' tier.)
  ok(
    "a venue holding an alcoholic tier cannot move to Ireland",
    await refused(() => db.query(`update public.venues set country = 'IE' where id = $1`, [vid])),
  );
  await db.query(`delete from public.venue_perks where venue_id = $1 and threshold = 10`, [vid]);
  await db.query(`update public.venues set country = 'IE' where id = $1`, [vid]);
  ok(
    "IRELAND: an alcoholic reward can't sneak in as a second TIER either",
    await refused(() =>
      as(owner, `insert into public.venue_perks (venue_id, kind, threshold, reward, reward_alcoholic)
                 values ($1,'visits',20,'a free pint',true)`, [vid]),
    ),
  );
  await db.query(`update public.venues set country = 'IN' where id = $1`, [vid]);

  console.log("\n── 5d. quiet nights count double (the dead Tuesday) ──");
  // The dead-Tuesday fix, done WITHOUT rewarding drinking: a visit on a quiet night
  // is worth 2 toward the PRIVATE perk. No spark, no discount, no public score.
  const roomDow = (
    await db.query(`select extract(dow from date)::int as d from public.parties where id = $1`, [pid2])
  ).rows[0].d;

  // Measured on a tier nobody has claimed: a claim restarts that tier's clock (023), and
  // the coffee tier was just claimed, so its progress is 0 either way. Both of Anita's
  // rooms are dated today, so marking today's weekday quiet doubles every visit.
  const freshTier = randomUUID();
  await as(owner, `insert into public.venue_perks (id, venue_id, kind, threshold, reward)
                   values ($1,$2,'visits',50,'a dessert')`, [freshTier, vid]);
  await db.query(`update public.venues set quiet_nights = '{}' where id = $1`, [vid]);
  let q = await as(anita, `select progress from public.perk_status($1,$2) where perk_id = $3`, [vid, anita, freshTier]);
  const base = Number(q.rows[0].progress);

  await db.query(`update public.venues set quiet_nights = array[$2::int] where id = $1`, [vid, roomDow]);
  q = await as(anita, `select progress from public.perk_status($1,$2) where perk_id = $3`, [vid, anita, freshTier]);
  const boosted = Number(q.rows[0].progress);
  await db.query(`delete from public.venue_perks where id = $1`, [freshTier]);

  ok("a visit on a QUIET night is worth double toward the perk", base > 0 && boosted === base * 2);
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

  // Deny-by-default reaches here too: no bar layer → no listing. (A second, verified
  // venue with no perk: this one holds a perk, and 030 won't let it move to Thailand.)
  await db.query(
    `insert into public.venues (id, name, slug, created_by, country, verified) values ($1,'Verify Bangkok',$2,$3,'TH',true)`,
    [randomUUID(), `verify-bkk-${Date.now()}`, owner],
  );
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
  // Refused outright, or an empty board — either way nothing reaches a non-member.
  let outsiderRows = 0;
  const outsiderRefused = await refused(async () => {
    outsiderRows = (await as(stranger, `select * from public.party_points_board($1)`, [pid])).rows.length;
  });
  ok("a non-member cannot read the room board", outsiderRefused || outsiderRows === 0);

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
  // rohan already reported the stranger once (§12). The client path is a plain insert
  // that treats the unique violation as success — so reporting again is a silent no-op,
  // still ONE reporter on the counter. (It was an upsert with a conflict target, which
  // Postgres also checks against SELECT policies — reports has none, so every report
  // from the apps was refused. That exact statement must stay refused:)
  ok("an upsert naming a conflict target is refused by RLS (why the apps use a plain insert)",
    await refused(() => as(rohan, `insert into public.reports (reporter_id, subject_user_id, reason)
                                   values ($1,$2,'harassment') on conflict (reporter_id, subject_user_id) do nothing`,
                                   [rohan, stranger])));
  const dupRefused = await refused(() =>
    as(rohan, `insert into public.reports (reporter_id, subject_user_id, reason) values ($1,$2,'harassment')`, [rohan, stranger]));
  ok("reporting the same person again hits the unique index (the app answers it like a success)", dupRefused);
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

  // ── 16. staff roles (045/046): the database decides who may do what ──────────
  if ((await db.query(`select to_regclass('public.role_capabilities') t`)).rows[0].t) {
    console.log("\n── 16. staff roles: who may do what (045/046) ───────");
    const mgr = await mkUser("Manager", `vf-mgr-${Date.now()}`);
    const srv = await mkUser("Server", `vf-srv-${Date.now()}`);
    const cook = await mkUser("Cook", `vf-cook-${Date.now()}`);
    const hostP = await mkUser("Host", `vf-host-${Date.now()}`);
    // Adding someone: before 053 a senior member inserted the row; from 053 they enrol the
    // person (the seniority rules live in enrol_staff) and the person types the code.
    const addAs = async (who, uid, role) => {
      if (!has053) return as(who, `insert into public.venue_staff (venue_id, user_id, role) values ($1,$2,$3)`, [vid, uid, role]);
      const email = (await db.query(`select email from auth.users where id=$1`, [uid])).rows[0].email;
      const e = (await as(who, `select * from public.enrol_staff($1,'New starter',$2,null,$3)`, [vid, email, role])).rows[0];
      const r = (await as(uid, `select public.claim_staff_enrolment($1,$2) r`, [e.enrolment_id, e.code])).rows[0].r;
      if (!r.ok) throw new Error(`claim refused: ${r.error}`);
    };
    const roleOf = async (uid) =>
      (await db.query(`select role from public.venue_staff where venue_id=$1 and user_id=$2`, [vid, uid])).rows[0]?.role;

    await addAs(owner, mgr, "manager");
    ok("the owner can add a manager", (await roleOf(mgr)) === "manager");
    await addAs(mgr, srv, "server");
    ok("a manager can add a server", (await roleOf(srv)) === "server");
    ok("a manager CANNOT add another manager", await refused(() => addAs(mgr, rohan, "manager")));
    ok("a manager CANNOT crown an owner", await refused(() => addAs(mgr, rohan, "owner")));
    ok("nobody grants 'owner' from an app — not even the owner", await refused(() => addAs(owner, rohan, "owner")));
    ok("a server CANNOT add anyone", await refused(() => addAs(srv, rohan, "bartender")));
    await refused(() => as(mgr, `delete from public.venue_staff where venue_id=$1 and user_id=$2`, [vid, owner]));
    ok("a manager CANNOT remove the owner", (await roleOf(owner)) === "owner");

    const code = (await as(mgr, `select public.create_staff_invite($1,'kitchen') c`, [vid])).rows[0].c;
    ok("a manager can invite someone to the kitchen", /^[a-z0-9]{10}$/.test(code));
    ok("a manager CANNOT invite a manager",
      await refused(() => as(mgr, `select public.create_staff_invite($1,'manager')`, [vid])));
    const venueName = (await as(cook, `select public.accept_staff_invite($1) n`, [code])).rows[0].n;
    ok("accepting an invite joins the team at the invite's role",
      venueName === "Verify Tap Room" && (await roleOf(cook)) === "kitchen");
    if ((await db.query(`select to_regprocedure('public.approve_staff(uuid,uuid)') f`)).rows[0].f) {
      // 053: an invite code puts them on the list as WAITING; a manager's yes comes first.
      ok("…as WAITING, until a manager says yes (053)",
        (await db.query(`select status from public.venue_staff where venue_id=$1 and user_id=$2`, [vid, cook])).rows[0].status === "pending");
      await as(mgr, `select public.approve_staff($1,$2)`, [vid, cook]);
    }
    ok("an invite works once", await refused(() => as(hostP, `select public.accept_staff_invite($1)`, [code])));

    ok("the KITCHEN can't record a guest's tab",
      await refused(() => as(cook, `select public.record_spend($1,$2,100)`, [pid, anita])));
    ok("…can't read a guest's card",
      await refused(() => as(cook, `select * from public.venue_guest_card($1,$2)`, [vid, anita])));
    ok("…can't see where a guest is up to on the perks",
      await refused(() => as(cook, `select * from public.perk_status($1,$2)`, [vid, anita])));
    ok("…and doesn't get tonight's guest list", (await as(cook, `select * from public.room_guests($1)`, [pid])).rows.length === 0);

    await addAs(owner, hostP, "host");
    ok("a HOST sees who's in tonight's room (to seat them)",
      (await as(hostP, `select * from public.room_guests($1)`, [pid])).rows.length >= 2);
    ok("…but can't record a tab", await refused(() => as(hostP, `select public.record_spend($1,$2,100)`, [pid, anita])));
    ok("…or read the guest book", await refused(() => as(hostP, `select * from public.venue_guest_card($1,$2)`, [vid, anita])));

    await as(srv, `select public.record_spend($1,$2,650)`, [pid, rohan]);
    ok("a SERVER records a tab", true);
    await as(mgr, `select public.set_staff_role($1,$2,'supervisor')`, [vid, srv]);
    ok("a manager promotes a server to supervisor", (await roleOf(srv)) === "supervisor");
    ok("a manager CANNOT promote anyone to manager",
      await refused(() => as(mgr, `select public.set_staff_role($1,$2,'manager')`, [vid, srv])));
    ok("a manager CANNOT demote the owner",
      await refused(() => as(mgr, `select public.set_staff_role($1,$2,'bartender')`, [vid, owner])));
    ok("nobody changes their own role",
      await refused(() => as(mgr, `select public.set_staff_role($1,$2,'bartender')`, [vid, mgr])));

    const off = (await as(barman, `select public.set_thankable($1,false) v`, [vid])).rows[0].v;
    const thankableNow = (await db.query(`select thankable from public.venue_staff where venue_id=$1 and user_id=$2`, [vid, barman])).rows[0].thankable;
    ok("a bartender can switch thanks OFF (the opt-out that never worked now does)", off === true && thankableNow === false);
    ok("…and then cannot be thanked",
      await refused(() => as(anita, `select public.thank_staff($1,$2,'quick and kind')`, [pid, barman])));
    await as(barman, `select public.set_thankable($1,true)`, [vid]);

    ok("a VERIFIED venue can't move itself to another country",
      await refused(() => as(owner, `update public.venues set country='GB' where id=$1`, [vid])));
    ok("…nor change its web address (it's printed on the tables)",
      await refused(() => as(owner, `update public.venues set slug='somewhere-else' where id=$1`, [vid])));
    await as(owner, `update public.venues set name='Verify Tap Room' where id=$1`, [vid]);
    ok("…but it can still edit its name", true);

    await as(cook, `delete from public.venue_staff where venue_id=$1 and user_id=$2`, [vid, cook]);
    ok("staff can leave a team", (await roleOf(cook)) === undefined);
    await as(owner, `delete from public.venue_staff where venue_id=$1 and user_id=$2`, [vid, owner]);
    ok("the owner can't walk out of their own venue (delete the venue instead)", (await roleOf(owner)) === "owner");
  }

  // ── 17. every kind of shop (047): the law follows what a place SELLS ─────────
  if ((await db.query(`select to_regprocedure('public.venue_legal_class(text,boolean)') f`)).rows[0].f) {
    console.log("\n── 17. every kind of shop: sweet shops, bakeries, cafés (047) ──");
    const mkVenue = async (who, name, kind, country, extra = {}) => {
      const id = randomUUID();
      const cols = { id, name, slug: `vf-${kind.replace("_", "")}-${Date.now()}-${Math.floor(Math.random() * 1e4)}`.slice(0, 40), created_by: who, kind, country, ...extra };
      const keys = Object.keys(cols);
      await as(who, `insert into public.venues (${keys.join(",")}) values (${keys.map((_, i) => `$${i + 1}`).join(",")})`, keys.map((k) => cols[k]));
      await as(who, `insert into public.venue_staff (venue_id, user_id, role) values ($1,$2,'owner')`, [id, who]);
      return id;
    };
    const sweets = await mkVenue(owner, "Verify Mithai", "sweet_shop", "IN", { serves_alcohol: true });
    const sa = (await db.query(`select serves_alcohol from public.venues where id=$1`, [sweets])).rows[0].serves_alcohol;
    ok("a sweet shop never sells alcohol — even if the app says it does", sa === false);
    await db.query(`update public.venues set verified = true where id = $1`, [sweets]);

    await as(owner, `insert into public.venue_perks (venue_id, kind, threshold, reward) values ($1,'spend',1000,'a box of kaju katli')`, [sweets]);
    ok("a sweet shop may count SPEND (it sells no alcohol, so it's just a loyalty card)", true);
    ok("…but its reward can never be alcohol",
      await refused(() => as(owner, `insert into public.venue_perks (venue_id, kind, threshold, reward, reward_alcoholic) values ($1,'visits',5,'a beer',true)`, [sweets])));
    ok("a sweet shop runs no rooms (a counter punches cards instead)",
      await refused(() => as(owner, `insert into public.parties (id, name, host_id, date, venue_id) values ($1,'x',$2,current_date,$3)`, [randomUUID(), owner, sweets])));

    await as(owner, `insert into public.venue_perks (venue_id, kind, threshold, reward) values ($1,'visits',2,'a ladoo')`, [sweets]);
    await as(owner, `select public.record_visit($1,$2)`, [sweets, anita]);
    const sweetSt = (await as(anita, `select * from public.perk_status($1,$2) where kind = 'visits'`, [sweets, anita])).rows[0];
    ok("a punched card counts toward the sweet shop's visits tier", sweetSt && Number(sweetSt.progress) >= 1);

    ok("a BAKERY can open in a prohibition country (it sells no alcohol)",
      !(await refused(() => mkVenue(owner, "Verify Riyadh Bakery", "bakery", "SA"))));
    ok("…a BAR can't", await refused(() => mkVenue(owner, "Verify Riyadh Bar", "bar", "SA")));
    ok("an unresearched country is still closed to every kind", await refused(() => mkVenue(owner, "Verify Harare Bakery", "bakery", "ZW")));

    const bkk = await mkVenue(owner, "Verify Bangkok Bakery", "bakery", "TH");
    await db.query(`update public.venues set verified = true where id = $1`, [bkk]);
    await as(owner, `insert into public.venue_perks (venue_id, kind, threshold, reward) values ($1,'visits',5,'a croissant')`, [bkk]);
    ok("THAILAND bans ALCOHOL promotions — a bakery's card is not one", true);
    const listed = (await anon(`select * from public.discover_venues('TH', 30)`)).rows.map((r) => r.name);
    ok("Discover lists a verified bakery in Thailand (no alcohol, no advertising problem)", listed.includes("Verify Bangkok Bakery"));

    const cafe = await mkVenue(owner, "Verify Café", "cafe", "IN", { serves_alcohol: false });
    await db.query(`update public.venues set verified = true where id = $1`, [cafe]);
    ok("a verified café can't turn itself into a licensed bar by itself",
      await refused(() => as(owner, `update public.venues set serves_alcohol = true where id=$1`, [cafe])));
  }

  // ── 18. the area heat map (048): groups of people who said yes, never a person ─
  if ((await db.query(`select to_regprocedure('public.area_heat_map(uuid,integer,text)') f`)).rows[0].f) {
    console.log("\n── 18. the area heat map: consenting groups, never a person (048) ──");
    const t = Date.now();
    const rnd = () => Math.floor(Math.random() * 1e6);
    const mkBar = async (name, geo, share) => {
      const id = randomUUID();
      await as(owner, `insert into public.venues (id, name, slug, created_by, kind, country, geohash, area_share) values ($1,$2,$3,$4,'bar','IN',$5,$6)`,
        [id, name, `vf-area-${t}-${rnd()}`.slice(0, 40), owner, geo, share]);
      await as(owner, `insert into public.venue_staff (venue_id, user_id, role) values ($1,$2,'owner')`, [id, owner]);
      await db.query(`update public.venues set verified = true where id = $1`, [id]);
      const room = randomUUID();
      await as(owner, `insert into public.parties (id, name, host_id, date, venue_id, invite_code) values ($1,'Area night',$2,current_date,$3,$4)`,
        [room, owner, id, `ar${rnd()}`.slice(0, 8)]);
      return { id, room };
    };
    // Three bars in one ~5 km cell (tdr1w), a lone bar next door (tdr1x), two in a third (tdr1y).
    const A = await mkBar("Verify Area A", "tdr1wb", true);
    const B = await mkBar("Verify Area B", "tdr1wc", true);
    const C = await mkBar("Verify Area C", "tdr1wd", true);
    const D = await mkBar("Verify Area D", "tdr1xe", true);
    const E = await mkBar("Verify Area E", "tdr1yf", true);
    const F = await mkBar("Verify Area F", "tdr1yg", true);

    // Seven people out last night at 7 pm (India time). g6 shares taste trends but
    // never said yes to neighbourhood maps.
    const g = [];
    for (let i = 0; i < 7; i++) g.push(await mkUser(`Area ${i}`, `vf-area${i}-${t}`));
    const evening = `((current_date - 1) + time '19:00') at time zone 'Asia/Kolkata'`;
    for (const [i, uid] of g.entries()) {
      await db.query(`update public.profiles set share_trends = true, trends_geo = 'tdr1', share_nights_out = $2 where id = $1`, [uid, i < 4]);
      for (const bar of [A, B, C, E, F]) {
        await db.query(`insert into public.party_members (party_id, user_id, status, joined_at) values ($1,$2,'approved',${evening})`, [bar.room, uid]);
      }
      for (let k = 0; k < 3; k++) {
        await db.query(`insert into public.entries (id, user_id, date, drink, type) values ($1,$2,current_date - 1,'filter coffee','coffee')`, [randomUUID(), uid]);
      }
    }
    await db.query(`insert into public.party_members (party_id, user_id, status, joined_at) values ($1,$2,'approved',${evening})`, [D.room, g[0]]);
    for (const [drink, type] of [["IPA", "beer"], ["Sula", "wine"], ["Negroni", "cocktail"]]) {
      await db.query(`insert into public.entries (id, user_id, date, drink, type) values ($1,$2,current_date - 1,$3,$4)`, [randomUUID(), g[0], drink, type]);
    }
    const map = async (who = owner, vid_ = A.id, days = 7) =>
      (await as(who, `select * from public.area_heat_map($1, $2, 'Asia/Kolkata')`, [vid_, days])).rows;
    const row = (rows, cell, layer, label = "") => rows.find((r) => r.cell === cell && r.layer === layer && r.label === label);

    let rows = await map();
    ok("4 who said yes + 1 who didn't: the cell stays dark (a 'no' is never counted)", !rows.some((r) => r.cell === "tdr1w"));

    await db.query(`update public.profiles set share_nights_out = true where id = any($1)`, [[g[4], g[5]]]);
    rows = await map();
    ok("the fifth and sixth yes light the cell", row(rows, "tdr1w", "people")?.people === 5, JSON.stringify(rows));
    ok("counts are rounded DOWN to 5s — six people read as 5", row(rows, "tdr1w", "people")?.people === 5);
    ok("every figure on the map is ≥ 5 and a multiple of 5", rows.length > 0 && rows.every((r) => r.people >= 5 && r.people % 5 === 0));
    ok("the kinds of people are TASTE personas (5 coffee-and-tea people)", row(rows, "tdr1w", "persona", "coffee_tea")?.people === 5);
    ok("a persona of one (the explorer) stays hidden", !row(rows, "tdr1w", "persona", "explorer"));
    ok("what they like: coffee, counted in people", row(rows, "tdr1w", "taste", "coffee")?.people === 5);
    ok("a drink only one person logged never shows", !row(rows, "tdr1w", "taste", "beer"));
    ok("when they come out, on the venue's clock (7 pm → evening)", row(rows, "tdr1w", "hours", "evening")?.people === 5);
    ok("a cell with one person and one bar stays dark", !rows.some((r) => r.cell === "tdr1x"));
    ok("a cell of TWO venues stays dark even with a crowd (no competitor's night on show)", !rows.some((r) => r.cell === "tdr1y"));
    ok("the answer is (cell, layer, label, people) — no name, no venue, no row per person",
      JSON.stringify(Object.keys(rows[0] ?? {})) === JSON.stringify(["cell", "layer", "label", "people"]));

    // Spend: a night's tab per guest, only between venues that share.
    for (const bar of [A, B, C]) {
      for (const uid of g.slice(0, 6)) {
        await db.query(`insert into public.spend_events (party_id, subject_user_id, recorded_by, amount, created_at) values ($1,$2,$3,1200,${evening})`, [bar.room, uid, owner]);
      }
    }
    rows = await map();
    ok("sharing venues see the cell's typical tab as a BAND (₹1,200 tabs → '₹1,000+')", row(rows, "tdr1w", "spend", "1000")?.people === 5, JSON.stringify(rows.filter((r) => r.layer === "spend")));
    await as(owner, `update public.venues set area_share = false where id = $1`, [C.id]);
    rows = await map();
    ok("a venue that doesn't share is left out — two sharing venues are too few to show", !rows.some((r) => r.layer === "spend"));
    await as(owner, `update public.venues set area_share = true where id = $1`, [C.id]);
    await as(owner, `update public.venues set area_share = false where id = $1`, [A.id]);
    rows = await map();
    ok("give to get: a venue that doesn't share sees no one else's spend", !rows.some((r) => r.layer === "spend") && row(rows, "tdr1w", "people"));
    await as(owner, `update public.venues set area_share = true where id = $1`, [A.id]);

    ok("the windows are fixed (8 days reads as 30), so two answers can't be subtracted",
      JSON.stringify(await map(owner, A.id, 8)) === JSON.stringify(await map(owner, A.id, 30)));

    await seat(A.id, barman, "bartender");
    ok("a bartender can't open the area map (it's a manager's view)", await refused(() => map(barman)));
    ok("a stranger can't open it", await refused(() => map(stranger)));
    ok("a venue with no location set is told to set one", await refused(() => map(owner, vid)));
    const unv = randomUUID();
    await as(owner, `insert into public.venues (id, name, slug, created_by, kind, country, geohash) values ($1,'Verify Unverified',$2,$3,'bar','IN','tdr1wh')`,
      [unv, `vf-unv-${t}`, owner]);
    await as(owner, `insert into public.venue_staff (venue_id, user_id, role) values ($1,$2,'owner')`, [unv, owner]);
    ok("an UNVERIFIED venue can't read the map (no pop-up venue to peek at an area)", await refused(() => map(owner, unv)));

    ok("a verified venue can't MOVE to another area to look at it",
      await refused(() => as(owner, `update public.venues set geohash = 'ttnfvb' where id = $1`, [A.id])));
    ok("…but it can refine its spot within its area",
      !(await refused(() => as(owner, `update public.venues set geohash = 'tdr1wbz' where id = $1`, [A.id]))));
    ok("a location must be a real geohash, not free text",
      await refused(() => as(owner, `update public.venues set geohash = 'tdr1 main st' where id = $1`, [A.id])));

    const trends = (await as(owner, `select * from public.area_taste_trends('tdr1wbz', 30)`)).rows;
    ok("area trends read a finer venue location at city scale", trends.some((r) => r.kind === "drink" && r.users >= 5));

    const band = async (a, c) => Number((await db.query(`select public.spend_band_floor($1, $2) b`, [a, c])).rows[0].b);
    ok("spend bands match money.ts (₹1,200 → ₹1,000; ₹400 → under ₹500; $60 → $50)",
      (await band(1200, "INR")) === 1000 && (await band(400, "INR")) === 0 && (await band(60, "usd")) === 50);
  }

  // ── 19. outside signals (049): public facts about places, never people ────────
  if ((await db.query(`select to_regclass('public.area_signals') t`)).rows[0].t) {
    console.log("\n── 19. outside signals: places and happenings, never people (049) ──");
    const t = Date.now();
    const sig = (extra = {}) => {
      const r = { area: "tdr1", cell: "tdr1v9", kind: "event", title: "Dussehra fair at the grounds", source: "verify", dedupe_key: `verify:${t}:${Math.random()}`, starts_on: null, ...extra };
      const keys = Object.keys(r);
      return [`insert into public.area_signals (${keys.join(",")}) values (${keys.map((_, i) => `$${i + 1}`).join(",")})`, keys.map((k) => (k === "facts" ? JSON.stringify(r[k]) : r[k]))];
    };
    // The import path is the service role (no auth.uid()) — this harness's own connection.
    await db.query(...sig({ starts_on: new Date(Date.now() + 3 * 864e5).toISOString().slice(0, 10) }));
    await db.query(...sig({ kind: "venue", title: "New brewpub opened on 12th Main", facts: { rating: 4.4, review_count: 120 } }));
    await db.query(...sig({ area: "ttnf", cell: null, title: "A fair in another city" }));
    await db.query(...sig({ title: "Yesterday's thing", expires_at: new Date(Date.now() - 864e5).toISOString() }));
    ok("the import path writes clean public facts", true);

    ok("a signal can't carry an email", await refused(() => db.query(...sig({ detail: "tickets: ravi@example.com" }))));
    ok("…or a phone number", await refused(() => db.query(...sig({ detail: "call +91 98450 12345" }))));
    ok("…or an @handle", await refused(() => db.query(...sig({ detail: "hosted by @ravi_k" }))));
    ok("…or a fact that names a person", await refused(() => db.query(...sig({ facts: { owner_name: "Ravi" } }))));
    ok("a date is not mistaken for a phone number", !(await refused(() => db.query(...sig({ detail: "from 2026-10-02 to 2026-10-05" })))));
    ok("a location must be a real cell in its area", await refused(() => db.query(...sig({ cell: "ttnfvb" }))));
    ok("only an https link", await refused(() => db.query(...sig({ source_url: "http://example.com" }))));

    ok("no client can write a signal (no policy at all)",
      await refused(() => as(owner, ...sig({ title: "A venue writing its own news" }))));
    const nPolicies = (await db.query(`select count(*)::int n from pg_policies where schemaname='public' and tablename='area_signals'`)).rows[0].n;
    ok("area_signals has no client policies", nPolicies === 0);

    // Venue A of scene 18 sits in tdr1 and is verified (or make one here if 18 didn't run).
    let vA = (await db.query(`select id from public.venues where name = 'Verify Area A' limit 1`)).rows[0]?.id;
    if (!vA) {
      vA = randomUUID();
      await as(owner, `insert into public.venues (id, name, slug, created_by, kind, country, geohash) values ($1,'Verify Signals',$2,$3,'bar','IN','tdr1v9')`, [vA, `vf-sig-${t}`, owner]);
      await as(owner, `insert into public.venue_staff (venue_id, user_id, role) values ($1,$2,'owner')`, [vA, owner]);
      await db.query(`update public.venues set verified = true where id = $1`, [vA]);
    }
    await seat(vA, rohan, "server");
    const seen = (await as(rohan, `select * from public.venue_area_signals($1, 14)`, [vA])).rows;
    ok("any staff member reads their own area's signals (a server too)", seen.some((r) => r.title === "Dussehra fair at the grounds"));
    ok("a venue fact carries numbers, not people", seen.some((r) => r.kind === "venue" && r.facts.rating === 4.4));
    ok("another city's signals never show", !seen.some((r) => r.title === "A fair in another city"));
    ok("an expired signal never shows", !seen.some((r) => r.title === "Yesterday's thing"));
    ok("a stranger can't read a venue's area", await refused(() => as(stranger, `select * from public.venue_area_signals($1, 14)`, [vA])));
    ok("nobody reads the table directly", (await as(owner, `select count(*)::int n from public.area_signals`)).rows[0].n === 0);
  }

  // ── 20. the counter (050): products, stock, sales, and the liquor-store rules ──
  if ((await db.query(`select to_regprocedure('public.ring_sale(uuid,uuid,jsonb,text,boolean)') f`)).rows[0].f) {
    console.log("\n── 20. the counter: stock, sales, and the law on a bottle (050) ──");
    const t = Date.now();
    const shop = randomUUID();
    await as(owner, `insert into public.venues (id, name, slug, created_by, kind, country, region) values ($1,'Verify Bottle Shop',$2,$3,'store','IN','KA')`,
      [shop, `vf-bottles-${t}`, owner]);
    await as(owner, `insert into public.venue_staff (venue_id, user_id, role) values ($1,$2,'owner')`, [shop, owner]);
    await seat(shop, barman, "bartender");
    await db.query(`update public.venues set verified = true where id = $1`, [shop]);

    const whisky = randomUUID();
    const soda = randomUUID();
    await as(owner, `insert into public.shop_products (id, venue_id, name, brand, category, size, unit, price, mrp) values ($1,$2,'Single malt','Amrut','spirit',750,'ml',1500,1600)`, [whisky, shop]);
    await as(owner, `insert into public.shop_products (id, venue_id, name, category, price) values ($1,$2,'Soda','soft',20)`, [soda, shop]);
    ok("a liquor store lists a bottle with its MRP", true);
    ok("a price above the printed MRP can't be saved",
      await refused(() => as(owner, `update public.shop_products set price = 1700 where id = $1`, [whisky])));
    ok("a bartender can't edit the shelf (menu.edit)",
      await refused(() => as(barman, `insert into public.shop_products (venue_id, name, category, price) values ($1,'x','soft',1)`, [shop])));

    await as(barman, `select public.receive_stock($1, 10)`, [whisky]);
    await as(barman, `select public.receive_stock($1, 50)`, [soda]);
    ok("a bartender can't adjust stock without a manager",
      await refused(() => as(barman, `select public.adjust_stock($1, -1, 'adjust', 'miscount')`, [whisky])));
    ok("an adjustment needs a note", await refused(() => as(owner, `select public.adjust_stock($1, -1, 'adjust', '')`, [whisky])));
    await as(owner, `select public.adjust_stock($1, -1, 'waste', 'broken bottle')`, [whisky]);
    const onHand = async (pid) => Number((await as(owner, `select on_hand from public.shop_stock($1) where product_id = $2`, [shop, pid])).rows[0].on_hand);
    ok("stock on hand is the ledger's sum (10 in, 1 broken → 9)", (await onHand(whisky)) === 9);

    const ring = (who, lines, idChecked = false, sale = randomUUID()) =>
      as(who, `select public.ring_sale($1, $2, $3::jsonb, 'upi', $4) total`, [shop, sale, JSON.stringify(lines), idChecked]);
    const sodaSale = randomUUID();
    const r1 = await ring(barman, [{ product: soda, qty: 2 }], false, sodaSale);
    ok("anything that isn't alcohol rings up anywhere (2 sodas = ₹40, priced by the server)", Number(r1.rows[0].total) === 40);
    const again = await ring(barman, [{ product: soda, qty: 2 }], false, sodaSale);
    ok("a retry of the same sale doesn't ring twice", Number(again.rows[0].total) === 40 && (await onHand(soda)) === 48);

    ok("NO retail rule for the state → no alcohol sale (deny-by-default)",
      await refused(() => ring(barman, [{ product: whisky, qty: 1 }], true)));
    const status0 = (await as(barman, `select * from public.store_sale_status($1)`, [shop])).rows[0];
    ok("the till says why before anyone tries", status0.researched === false && /haven't researched/.test(status0.reason));

    await db.query(`insert into public.retail_alcohol_rules (country, region, tz, sale_start, sale_end, max_ml_per_sale, source)
                    values ('IN','KA','Asia/Kolkata','00:00','23:59:59.999',2250,'verify harness — not a real rule')`);
    ok("…without an ID check, still no", await refused(() => ring(barman, [{ product: whisky, qty: 1 }], false)));
    const r2 = await ring(barman, [{ product: whisky, qty: 1 }], true);
    ok("with the state researched and ID checked, the bottle rings up at its price", Number(r2.rows[0].total) === 1500);
    ok("over the per-sale limit (4 × 750 ml > 2250 ml) is refused",
      await refused(() => ring(barman, [{ product: whisky, qty: 4 }], true)));

    await db.query(`insert into public.dry_days (country, region, day, reason, source)
                    values ('IN','', (now() at time zone 'Asia/Kolkata')::date, 'a verify dry day', 'verify harness')`);
    ok("a dry day stops alcohol all day", await refused(() => ring(barman, [{ product: whisky, qty: 1 }], true)));
    ok("…but the soda still sells", !(await refused(() => ring(barman, [{ product: soda, qty: 1 }]))));
    const status1 = (await as(barman, `select * from public.store_sale_status($1)`, [shop])).rows[0];
    ok("the till shows the dry day", status1.allowed_now === false && /Dry day/.test(status1.reason));
    await db.query(`delete from public.dry_days where reason = 'a verify dry day'`);
    await db.query(`update public.retail_alcohol_rules set sale_start = '00:00', sale_end = '00:00' where country = 'IN' and region = 'KA'`);
    ok("outside legal sale hours is refused", await refused(() => ring(barman, [{ product: whisky, qty: 1 }], true)));

    ok("a guest can't ring a sale", await refused(() => ring(anita, [{ product: soda, qty: 1 }])));
    ok("nobody writes a sale directly (no client policy)",
      await refused(() => as(owner, `insert into public.shop_sales (id, venue_id, paid_by, total) values ($1,$2,'cash',0)`, [randomUUID(), shop])));
    ok("a guest sees none of the shop's stock", (await as(anita, `select count(*)::int n from public.stock_moves where venue_id = $1`, [shop])).rows[0].n === 0);
    ok("sale lines carry the server's price", (await db.query(`select bool_and(unit_price = 1500) ok from public.shop_sale_lines where product_id = $1`, [whisky])).rows[0].ok === true);

    const reg = (await as(owner, `select * from public.excise_register($1, (now() at time zone 'Asia/Kolkata')::date, (now() at time zone 'Asia/Kolkata')::date)`, [shop])).rows;
    const w = reg.find((r) => r.product_id === whisky);
    ok("the excise register reads the ledger, on the state's clock (received 10, sold 1, other −1, closing 8)",
      w && Number(w.received) === 10 && Number(w.sold) === 1 && Number(w.other) === -1 && Number(w.closing) === 8, JSON.stringify(w));
    ok("the register lists only alcohol", !reg.some((r) => r.product_id === soda));
    ok("a bartender can't read the register", await refused(() => as(barman, `select * from public.excise_register($1, current_date, current_date)`, [shop])));

    const sweets = randomUUID();
    await as(owner, `insert into public.venues (id, name, slug, created_by, kind, country) values ($1,'Verify Sweets',$2,$3,'sweet_shop','IN')`, [sweets, `vf-sweets-${t}`, owner]);
    await as(owner, `insert into public.venue_staff (venue_id, user_id, role) values ($1,$2,'owner')`, [sweets, owner]);
    ok("a sweet shop can't list whisky",
      await refused(() => as(owner, `insert into public.shop_products (venue_id, name, category, size, unit, price) values ($1,'Whisky','spirit',750,'ml',900)`, [sweets])));
    const kaju = randomUUID();
    await as(owner, `insert into public.shop_products (id, venue_id, name, category, unit, sold_by, price) values ($1,$2,'Kaju katli','sweet','g','weight',1200)`, [kaju, sweets]);
    const kg = await as(owner, `select public.ring_sale($1, $2, $3::jsonb, 'cash', false) total`, [sweets, randomUUID(), JSON.stringify([{ product: kaju, qty: 250 }])]);
    ok("sold by weight: 250 g of ₹1,200/kg kaju katli = ₹300", Number(kg.rows[0].total) === 300);
  }

  // ── 21. service (051): tables, tabs, the bar and kitchen, the bill, the guest's link ─
  if ((await db.query(`select to_regprocedure('public.close_tab(uuid,jsonb,numeric)') f`)).rows[0].f) {
    console.log("\n── 21. service: tables, tabs, stations, bills, the table link (051) ──");
    const t = Date.now();
    const waiter = await mkUser("Waiter", `vf-waiter-${t}`);
    const chef = await mkUser("Chef", `vf-chef-${t}`);
    const hostess = await mkUser("Host", `vf-hostess-${t}`);
    const bistro = randomUUID();
    await as(owner, `insert into public.venues (id, name, slug, created_by, kind, serves_alcohol, country) values ($1,'Verify Bistro',$2,$3,'restaurant',true,'IN')`, [bistro, `vf-bistro-${t}`, owner]);
    await as(owner, `insert into public.venue_staff (venue_id, user_id, role) values ($1,$2,'owner')`, [bistro, owner]);
    for (const [uid, role] of [[waiter, "server"], [chef, "kitchen"], [hostess, "host"], [barman, "bartender"]]) {
      await seat(bistro, uid, role);
    }
    await db.query(`update public.venues set verified = true where id = $1`, [bistro]);

    const item = async (name, kind, price, extra = {}) => {
      const id = randomUUID();
      const cols = { id, venue_id: bistro, name, kind, price, no_alcohol: ["soft", "food", "coffee", "tea"].includes(kind), ...extra };
      const k = Object.keys(cols);
      await as(owner, `insert into public.venue_menu_items (${k.join(",")}) values (${k.map((_, i) => `$${i + 1}`).join(",")})`, k.map((x) => cols[x]));
      return id;
    };
    const paneer = await item("Paneer Tikka", "food", 320, { diet: "veg", allergens: ["milk"] });
    const soda = await item("Masala Soda", "soft", 90);
    const negroni = await item("Negroni", "cocktail", 450);
    const lager = await item("Craft Lager", "beer", 300);
    ok("food goes to the kitchen by itself", (await db.query(`select station from public.venue_menu_items where id = $1`, [paneer])).rows[0].station === "kitchen");
    ok("an allergen off the EU list is refused",
      await refused(() => as(owner, `update public.venue_menu_items set allergens = '{glitter}' where id = $1`, [paneer])));
    const pub = (await anon(`select * from public.venue_menu($1)`, [`vf-bistro-${t}`])).rows;
    ok("the public menu carries the veg mark and allergens", pub.some((r) => r.name === "Paneer Tikka" && r.diet === "veg" && r.allergens.includes("milk")));

    const area = randomUUID();
    const t1 = randomUUID();
    await as(owner, `insert into public.venue_areas (id, venue_id, name) values ($1,$2,'Patio')`, [area, bistro]);
    await as(owner, `insert into public.venue_tables (id, venue_id, area_id, label, seats) values ($1,$2,$3,'T1',4)`, [t1, bistro, area]);
    ok("a server can't add tables (settings.edit)",
      await refused(() => as(waiter, `insert into public.venue_tables (venue_id, label) values ($1,'T9')`, [bistro])));
    ok("a table's code can't be edited by hand",
      await refused(() => as(owner, `update public.venue_tables set code = 'abcdefgh' where id = $1`, [t1])));
    const code0 = (await db.query(`select code from public.venue_tables where id = $1`, [t1])).rows[0].code;
    const code = (await as(owner, `select public.rotate_table_code($1) c`, [t1])).rows[0].c;
    ok("rotating a table's code retires the old tag", code !== code0 && (await anon(`select * from public.table_info($1)`, [code0])).rows.length === 0);
    const counterShop = (await db.query(`select id from public.venues where kind = 'sweet_shop' and created_by = $1 limit 1`, [owner])).rows[0]?.id;
    if (counterShop) {
      ok("a counter (sweet shop) has no tables",
        await refused(() => as(owner, `insert into public.venue_tables (venue_id, label) values ($1,'T1')`, [counterShop])));
    }

    const tab = randomUUID();
    await as(waiter, `select public.open_tab($1,$2,$3,null,3)`, [bistro, tab, t1]);
    await as(waiter, `select public.open_tab($1,$2,$3,null,3)`, [bistro, tab, t1]);
    ok("opening the same tab twice (a retry) makes one tab", (await db.query(`select count(*)::int n from public.tabs where id = $1`, [tab])).rows[0].n === 1);
    ok("a chef can't open tabs", await refused(() => as(chef, `select public.open_tab($1,$2,$3,null,2)`, [bistro, randomUUID(), t1])));
    const n = (await as(waiter, `select public.add_order_lines($1, $2::jsonb) n`, [tab, JSON.stringify([{ item: paneer, qty: 2, note: "less spicy" }, { item: negroni, qty: 1, seat: 2 }, { item: soda, qty: 1 }])])).rows[0].n;
    ok("a server takes an order; each line priced by the server", n === 3);
    const lines = (await db.query(`select * from public.order_lines where tab_id = $1`, [tab])).rows;
    const lineOf = (name) => lines.find((l) => l.name === name);
    ok("the paneer goes to the kitchen, the negroni to the bar", lineOf("Paneer Tikka").station === "kitchen" && lineOf("Negroni").station === "bar");
    await as(owner, `update public.venue_menu_items set price = 999 where id = $1`, [paneer]);
    ok("a later menu edit never rewrites an open tab", Number((await db.query(`select unit_price from public.order_lines where id = $1`, [lineOf("Paneer Tikka").id])).rows[0].unit_price) === 320);
    await as(owner, `update public.venue_menu_items set available = false where id = $1`, [negroni]);
    ok("an 86'd item can't be ordered", await refused(() => as(waiter, `select public.add_order_lines($1, $2::jsonb)`, [tab, JSON.stringify([{ item: negroni, qty: 1 }])])));

    const move = (who, line, to) => as(who, `select public.set_line_status($1,$2)`, [line, to]);
    await move(chef, lineOf("Paneer Tikka").id, "preparing");
    await move(chef, lineOf("Paneer Tikka").id, "ready");
    ok("the kitchen moves its own tickets", true);
    ok("the kitchen can't touch the bar's", await refused(() => move(chef, lineOf("Negroni").id, "ready")));
    await move(barman, lineOf("Negroni").id, "ready");
    await move(waiter, lineOf("Paneer Tikka").id, "served");
    await move(waiter, lineOf("Negroni").id, "served");
    ok("a served line can't go back", await refused(() => move(chef, lineOf("Paneer Tikka").id, "preparing")));
    ok("a void needs a reason", await refused(() => as(waiter, `select public.void_line($1,'')`, [lineOf("Masala Soda").id])));
    await as(waiter, `select public.void_line($1,'rang it twice')`, [lineOf("Masala Soda").id]);
    ok("a server voids their own fresh line", (await db.query(`select status from public.order_lines where id = $1`, [lineOf("Masala Soda").id])).rows[0].status === "void");
    ok("…but not a served one (a supervisor's call)", await refused(() => as(waiter, `select public.void_line($1,'sent back')`, [lineOf("Negroni").id])));

    ok("the kitchen can't settle a bill", await refused(() => as(chef, `select public.close_tab($1, '[]'::jsonb)`, [tab])));
    const sub = Number((await as(waiter, `select public.close_tab($1, $2::jsonb, 50) s`, [tab, JSON.stringify([{ method: "UPI", amount: 700 }, { method: "cash", amount: 390 }])])).rows[0].s);
    ok("the bill: 2 × ₹320 + ₹450 (the void doesn't count) = ₹1,090", sub === 1090);
    ok("staff decide how it's paid — any method, any split, recorded as said",
      (await db.query(`select string_agg(method || ':' || amount, ',' order by method) m from public.tab_payments where tab_id = $1`, [tab])).rows[0].m === "UPI:700.00,cash:390.00");
    ok("a closed tab takes no more orders", await refused(() => as(waiter, `select public.add_order_lines($1, $2::jsonb)`, [tab, JSON.stringify([{ item: soda, qty: 1 }])])));
    ok("nobody writes a line directly (functions only)",
      await refused(() => as(owner, `insert into public.order_lines (tab_id, venue_id, name, qty, station) values ($1,$2,'free drink',1,'bar')`, [tab, bistro])));
    ok("a guest sees no tabs", (await as(anita, `select count(*)::int n from public.tabs where venue_id = $1`, [bistro])).rows[0].n === 0);

    // The guest's side: the table's link.
    const info = (await anon(`select * from public.table_info($1)`, [code])).rows[0];
    ok("the table's link opens its venue and table, signed out", info && info.table_label === "T1" && info.venue_slug === `vf-bistro-${t}`);
    ok("ordering from the table is off until the venue switches it on",
      await refused(() => as(anita, `select public.request_order($1,$2,$3::jsonb)`, [code, randomUUID(), JSON.stringify([{ item: soda, qty: 1 }])])));
    await as(owner, `update public.venues set table_service = true where id = $1`, [bistro]);
    ok("a signed-out visitor can't order", await refused(() => anon(`select public.request_order($1,$2,$3::jsonb)`, [code, randomUUID(), JSON.stringify([{ item: soda, qty: 1 }])])));
    const req = randomUUID();
    await as(anita, `select public.request_order($1,$2,$3::jsonb,'no ice please')`, [code, req, JSON.stringify([{ item: lager, qty: 2 }, { item: soda, qty: 1 }])]);
    ok("a guest can send an order from the table", (await as(anita, `select status from public.order_requests where id = $1`, [req])).rows[0]?.status === "pending");
    ok("…not two in twenty seconds", await refused(() => as(anita, `select public.request_order($1,$2,$3::jsonb)`, [code, randomUUID(), JSON.stringify([{ item: soda, qty: 1 }])])));
    ok("another guest can't see it", (await as(rohan, `select count(*)::int n from public.order_requests where id = $1`, [req])).rows[0].n === 0);
    const inbox = (await as(waiter, `select * from public.service_inbox($1)`, [bistro])).rows;
    const got = inbox.find((r) => r.id === req);
    ok("staff see the order in the inbox: the table, what, and that it has alcohol (check ID)", got && got.table_label === "T1" && got.has_alcohol === true);
    ok("…and never who asked", got && !Object.keys(got).some((k) => /requested|user|guest/.test(k)));
    const tab2 = randomUUID();
    await as(waiter, `select public.accept_request($1,$2)`, [req, tab2]);
    const glines = (await db.query(`select name, qty, unit_price, source from public.order_lines where tab_id = $1 order by name`, [tab2])).rows;
    ok("accepted: it becomes lines on a new tab, priced by the server", glines.length === 2 && glines.every((l) => l.source === "guest") && Number(glines[0].unit_price) === 300);
    ok("the guest sees it was accepted", (await as(anita, `select status from public.order_requests where id = $1`, [req])).rows[0].status === "accepted");
    const req2 = randomUUID();
    await as(rohan, `select public.request_order($1,$2,$3::jsonb)`, [code, req2, JSON.stringify([{ item: soda, qty: 1 }])]);
    await as(waiter, `select public.decline_request($1,'kitchen closed')`, [req2]);
    ok("a request can be declined, with a reason the guest sees", (await as(rohan, `select status, decline_reason from public.order_requests where id = $1`, [req2])).rows[0].decline_reason === "kitchen closed");

    await as(anita, `select public.call_table_staff($1,'bill')`, [code]);
    await as(anita, `select public.call_table_staff($1,'bill')`, [code]);
    const calls = (await as(waiter, `select * from public.service_inbox($1) where item_kind = 'call'`, [bistro])).rows;
    ok("\"bill please\" reaches the floor once, however often it's tapped", calls.length === 1 && calls[0].call_kind === "bill" && calls[0].table_label === "T1");
    await as(waiter, `select public.resolve_call($1)`, [calls[0].id]);
    ok("…and clears when handled", (await as(waiter, `select count(*)::int n from public.service_inbox($1) where item_kind = 'call'`, [bistro])).rows[0].n === 0);

    await db.query(`insert into public.waitlist (id, venue_id, name, party, created_at) values ($1,$2,'Yesterday',2, now() - interval '2 days')`, [randomUUID(), bistro]);
    await as(hostess, `insert into public.waitlist (id, venue_id, name, party, quoted_min) values ($1,$2,'Priya',4,15)`, [randomUUID(), bistro]);
    const wl = (await as(hostess, `select name from public.waitlist where venue_id = $1`, [bistro])).rows.map((r) => r.name);
    ok("the host keeps a waitlist, and yesterday's names are gone", wl.includes("Priya") && !wl.includes("Yesterday"));
    ok("a chef can't add to the waitlist", await refused(() => as(chef, `insert into public.waitlist (id, venue_id, name, party) values ($1,$2,'x',2)`, [randomUUID(), bistro])));

    const board = (await as(owner, `select public.service_board($1) b`, [bistro])).rows[0].b;
    ok("the live board: open tabs, sales, the payment mix — business numbers only",
      board.open_tabs === 1 && Number(board.sales) === 1090 && Number(board.tips) === 50 && board.methods.upi !== undefined && board.methods.cash !== undefined, JSON.stringify(board));
    ok("a server doesn't see the live board", await refused(() => as(waiter, `select public.service_board($1)`, [bistro])));
  }

  // ── 22. the door (052): counts, never people ──────────────────────────────────
  if ((await db.query(`select to_regprocedure('public.door_tick(uuid,integer)') f`)).rows[0].f) {
    console.log("\n── 22. the door: how many inside, against capacity (052) ──");
    const t = Date.now();
    const club = randomUUID();
    const doorman = await mkUser("Door", `vf-door-${t}`);
    await as(owner, `insert into public.venues (id, name, slug, created_by, kind, country) values ($1,'Verify Club',$2,$3,'club','IN')`, [club, `vf-club-${t}`, owner]);
    await as(owner, `insert into public.venue_staff (venue_id, user_id, role) values ($1,$2,'owner')`, [club, owner]);
    await seat(club, doorman, "host");
    await as(owner, `update public.venues set capacity = 3 where id = $1`, [club]);
    await as(doorman, `select public.door_tick($1, 2)`, [club]);
    await as(doorman, `select public.door_tick($1, 1)`, [club]);
    await as(doorman, `select public.door_tick($1, -1)`, [club]);
    const c = (await as(doorman, `select * from public.door_count($1)`, [club])).rows[0];
    ok("the door counts in and out: 3 came in, 2 inside, capacity 3", c.inside === 2 && c.came_in === 3 && c.capacity === 3, JSON.stringify(c));
    await as(doorman, `select public.door_tick($1, -5)`, [club]);
    ok("inside never goes below zero", (await as(doorman, `select inside from public.door_count($1)`, [club])).rows[0].inside === 0);
    ok("a tap is 1 to 12 people", await refused(() => as(doorman, `select public.door_tick($1, 40)`, [club])));
    ok("a guest can't work the door", await refused(() => as(anita, `select public.door_tick($1, 1)`, [club])));
    ok("nobody writes the ledger directly", await refused(() => as(owner, `insert into public.door_events (venue_id, delta) values ($1, 1)`, [club])));
  }

  // ── 23. staff access (053): the owner's code, approvals, lock-out, history, the clock ──
  if ((await db.query(`select to_regprocedure('public.enrol_staff(uuid,text,text,text,text)') f`)).rows[0].f) {
    console.log("\n── 23. staff access: the owner's code, approvals, lock-out, history, the clock (053) ──");
    const t = Date.now();
    const bar = randomUUID();
    const hs = { boss: `vf-boss-${t}`, priya: `vf-priya-${t}`, rahul: `vf-rahul-${t}`, sam: `vf-sam-${t}`, other: `vf-other-${t}`, joiner: `vf-joiner-${t}`, late: `vf-late-${t}`, mgr2: `vf-mgr2-${t}` };
    const boss = await mkUser("Boss", hs.boss);
    const priya = await mkUser("Priya", hs.priya);
    const rahul = await mkUser("Rahul", hs.rahul);
    const sam = await mkUser("Sam", hs.sam);
    const other = await mkUser("Other", hs.other);
    const joiner = await mkUser("Joiner", hs.joiner);
    const late = await mkUser("Late", hs.late);
    const mgr2 = await mkUser("Second Manager", hs.mgr2);
    const mail = (h) => `${h}@verify.local`;
    await as(boss, `insert into public.venues (id, name, slug, created_by, kind, country) values ($1,'Verify Staff Bar',$2,$3,'bar','IN')`, [bar, `vf-staff-${t}`, boss]);
    await as(boss, `insert into public.venue_staff (venue_id, user_id, role) values ($1,$2,'owner')`, [bar, boss]);
    await seat(bar, priya, "manager");
    await seat(bar, mgr2, "manager");
    await seat(bar, sam, "bartender");
    ok("a manager can't put someone on the team directly — the code is the way on",
      await refused(() => as(priya, `insert into public.venue_staff (venue_id, user_id, role) values ($1,$2,'server')`, [bar, other])));
    ok("…nor slip someone in already paused or waiting",
      await refused(() => as(priya, `insert into public.venue_staff (venue_id, user_id, role, status) values ($1,$2,'server','pending')`, [bar, other])));
    const can = async (who, cap) => (await as(who, `select public.venue_can($1, auth.uid(), $2) c`, [bar, cap])).rows[0].c === true;
    const claim = async (who, eid, code) => (await as(who, `select public.claim_staff_enrolment($1,$2) r`, [eid, code])).rows[0].r;
    const notIt = (code) => (code === "000000" ? "111111" : "000000");
    const statusOf = async (uid) => (await db.query(`select status from public.venue_staff where venue_id=$1 and user_id=$2`, [bar, uid])).rows[0]?.status;

    // adding an employee: details + the owner's code
    const en = (await as(priya, `select * from public.enrol_staff($1,'Rahul S.',$2,'+91 98765 43210','server')`, [bar, mail(hs.rahul)])).rows[0];
    ok("a manager adds an employee and sees a 6-digit code, once", /^\d{6}$/.test(en.code));
    const stored = (await db.query(`select code_hash from public.staff_enrolments where id=$1`, [en.enrolment_id])).rows[0];
    ok("the code is stored hashed, never in the clear", stored && stored.code_hash !== en.code && stored.code_hash.length === 64);
    ok("nobody reads the enrolments table directly", (await as(priya, `select * from public.staff_enrolments`)).rows.length === 0);
    ok("a manager CANNOT add a manager", await refused(() => as(priya, `select * from public.enrol_staff($1,'X',$2,null,'manager')`, [bar, `x-${t}@verify.local`])));
    ok("a bartender CANNOT add anyone", await refused(() => as(sam, `select * from public.enrol_staff($1,'X',$2,null,'server')`, [bar, `y-${t}@verify.local`])));
    ok("someone already on the team can't be added twice", await refused(() => as(boss, `select * from public.enrol_staff($1,'Sam',$2,null,'server')`, [bar, mail(hs.sam)])));
    ok("a manager sees who's added but not in yet", (await as(priya, `select * from public.staff_enrolments_open($1)`, [bar])).rows.some((r) => r.email === mail(hs.rahul) && r.role === "server"));

    const mine = (await as(rahul, `select * from public.my_staff_enrolments()`)).rows;
    ok("the employee, signed in with that email, sees where and as what — never the code",
      mine.length === 1 && mine[0].venue_name === "Verify Staff Bar" && mine[0].role === "server" && mine[0].tries_left === 5 && !("code" in mine[0]));
    ok("anyone else signed in sees nothing", (await as(other, `select * from public.my_staff_enrolments()`)).rows.length === 0);
    ok("the right code on the wrong account does nothing", (await claim(other, en.enrolment_id, en.code)).error === "not_found");
    ok("before the code, no powers at all", !(await can(rahul, "floor.view")));
    const w1 = await claim(rahul, en.enrolment_id, notIt(en.code));
    ok("a wrong code is refused, with the tries left", w1.ok === false && w1.error === "wrong_code" && w1.left === 4);
    ok("…and the wrong try is COUNTED, not rolled back",
      (await db.query(`select attempts from public.staff_enrolments where id=$1`, [en.enrolment_id])).rows[0].attempts === 1);
    const good = await claim(rahul, en.enrolment_id, en.code);
    ok("the right code joins the team at the role the manager chose", good.ok === true && good.role === "server" && good.venue === "Verify Staff Bar");
    ok("…with powers now", await can(rahul, "floor.view"));
    ok("…and the venue keeps their name and phone", (await as(priya, `select phone from public.staff_details where venue_id=$1 and user_id=$2`, [bar, rahul])).rows[0]?.phone === "+91 98765 43210");
    ok("a code works once", (await claim(rahul, en.enrolment_id, en.code)).error === "closed");
    ok("a colleague can't read Rahul's phone", (await as(sam, `select * from public.staff_details where venue_id=$1 and user_id=$2`, [bar, rahul])).rows.length === 0);
    ok("…nor see it on the roster", (await as(sam, `select * from public.team_roster($1)`, [bar])).rows.some((r) => r.user_id === rahul && r.phone === null));

    const en2 = (await as(boss, `select * from public.enrol_staff($1,'Other P',$2,null,'kitchen')`, [bar, mail(hs.other)])).rows[0];
    for (let i = 0; i < 4; i++) await claim(other, en2.enrolment_id, notIt(en2.code));
    ok("five wrong tries close the code", (await claim(other, en2.enrolment_id, notIt(en2.code))).error === "too_many");
    ok("…even for the right code after that", (await claim(other, en2.enrolment_id, en2.code)).error === "too_many");
    const re = (await as(boss, `select * from public.reissue_staff_code($1)`, [en2.enrolment_id])).rows[0];
    ok("a new code resets the tries and works", (await claim(other, en2.enrolment_id, re.code)).ok === true);

    const en3 = (await as(boss, `select * from public.enrol_staff($1,'Late L',$2,null,'host')`, [bar, mail(hs.late)])).rows[0];
    await db.query(`update public.staff_enrolments set expires_at = now() - interval '1 minute' where id=$1`, [en3.enrolment_id]);
    ok("an expired code is refused", (await claim(late, en3.enrolment_id, en3.code)).error === "expired");
    await as(boss, `select public.revoke_staff_enrolment($1)`, [en3.enrolment_id]);
    ok("a cancelled code is closed", (await claim(late, en3.enrolment_id, en3.code)).error === "closed");

    // invite codes wait for a yes
    const inv = (await as(priya, `select public.create_staff_invite($1,'bartender') c`, [bar])).rows[0].c;
    await as(joiner, `select public.accept_staff_invite($1)`, [inv]);
    ok("an invite code puts the person on the list as WAITING", (await statusOf(joiner)) === "pending");
    ok("…with no powers until someone says yes", !(await can(joiner, "orders.take")));
    ok("…and they see where they stand", (await as(joiner, `select * from public.my_staff_status()`)).rows.some((r) => r.venue_name === "Verify Staff Bar" && r.status === "pending"));
    ok("a colleague can't approve them", await refused(() => as(sam, `select public.approve_staff($1,$2)`, [bar, joiner])));
    await as(priya, `select public.approve_staff($1,$2)`, [bar, joiner]);
    ok("a manager's yes makes them active", await can(joiner, "orders.take"));
    const inv2 = (await as(priya, `select public.create_staff_invite($1,'host') c`, [bar])).rows[0].c;
    await as(late, `select public.accept_staff_invite($1)`, [inv2]);
    await as(priya, `select public.decline_staff($1,$2)`, [bar, late]);
    ok("a manager can decline someone waiting", (await statusOf(late)) === undefined);

    // lock-out
    ok("a bartender can't lock anyone out", await refused(() => as(sam, `select public.lock_staff($1,$2,'x')`, [bar, joiner])));
    ok("a manager can't lock out another manager", await refused(() => as(priya, `select public.lock_staff($1,$2,'x')`, [bar, mgr2])));
    ok("nobody locks the owner out", await refused(() => as(priya, `select public.lock_staff($1,$2)`, [bar, boss])));
    ok("nobody locks themself out", await refused(() => as(priya, `select public.lock_staff($1,$2)`, [bar, priya])));
    ok("they report to an owner or a manager, not a colleague", await refused(() => as(priya, `select public.lock_staff($1,$2,'x',$3)`, [bar, joiner, sam])));
    const since1 = (await as(rahul, `select public.clock_in($1) s`, [bar])).rows[0].s;
    const since2 = (await as(rahul, `select public.clock_in($1) s`, [bar])).rows[0].s;
    ok("staff clock in, and a second tap changes nothing", since1 && String(since1) === String(since2));
    await as(priya, `select public.lock_staff($1,$2,'Cash count is off — come and see me',$3)`, [bar, rahul, boss]);
    ok("locked: every power stops at once", !(await can(rahul, "floor.view")) && !(await can(rahul, "shift.own")));
    ok("…they can't even read the venue now", (await as(rahul, `select id from public.venues where id=$1`, [bar])).rows.length === 0);
    ok("…the clock stopped with the lock", (await db.query(`select count(*)::int n from public.staff_shifts where venue_id=$1 and user_id=$2 and ended_at is null`, [bar, rahul])).rows[0].n === 0);
    ok("…and they can't clock back in", await refused(() => as(rahul, `select public.clock_in($1)`, [bar])));
    const st = (await as(rahul, `select * from public.my_staff_status()`)).rows.find((r) => r.venue_name === "Verify Staff Bar");
    ok("the locked person sees why, and who to report to",
      st?.status === "locked" && /Cash count/.test(st.lock_reason) && st.report_to === "Boss" && st.report_to_role === "owner");
    ok("a manager sees the lock and the reason on the roster",
      (await as(priya, `select * from public.team_roster($1)`, [bar])).rows.some((r) => r.user_id === rahul && r.status === "locked" && /Cash count/.test(r.lock_reason)));
    ok("colleagues don't see who's paused, or why", !(await as(sam, `select * from public.team_roster($1)`, [bar])).rows.some((r) => r.user_id === rahul));
    ok("a paused person can't be re-added with a fresh code",
      await refused(() => as(boss, `select * from public.enrol_staff($1,'Rahul again',$2,null,'server')`, [bar, mail(hs.rahul)])));
    await as(priya, `select public.unlock_staff($1,$2)`, [bar, rahul]);
    ok("unlocking gives the powers back", await can(rahul, "floor.view"));

    // the time clock
    await as(rahul, `select public.clock_in($1)`, [bar]);
    ok("a manager sees who's on", (await as(priya, `select * from public.shift_hours($1, now() - interval '1 day')`, [bar])).rows.some((r) => r.user_id === rahul && r.on_since));
    ok("a server sees only their own hours", (await as(rahul, `select * from public.shift_hours($1, now() - interval '1 day')`, [bar])).rows.every((r) => r.user_id === rahul));
    ok("a server can't clock out a colleague", await refused(() => as(rahul, `select public.end_staff_shift($1,$2)`, [bar, sam])));
    await as(priya, `select public.end_staff_shift($1,$2)`, [bar, rahul]);
    ok("a manager clocks out someone who forgot", (await as(rahul, `select public.my_shift($1) s`, [bar])).rows[0].s === null);
    ok("nobody writes shifts directly", await refused(() => as(rahul, `insert into public.staff_shifts (venue_id, user_id) values ($1,$2)`, [bar, rahul])));

    // details, roles, leaving — and the history of all of it
    await as(priya, `select public.set_staff_details($1,$2,'Rahul Sharma','+91 90000 00000')`, [bar, rahul]);
    ok("a manager updates someone's details", (await as(priya, `select staff_name from public.staff_details where venue_id=$1 and user_id=$2`, [bar, rahul])).rows[0]?.staff_name === "Rahul Sharma");
    ok("a colleague can't", await refused(() => as(sam, `select public.set_staff_details($1,$2,'x',null)`, [bar, rahul])));
    await as(boss, `select public.set_staff_role($1,$2,'supervisor')`, [bar, rahul]);
    await as(joiner, `delete from public.venue_staff where venue_id=$1 and user_id=$2`, [bar, joiner]);
    const hist = (await as(priya, `select kind from public.staff_history($1)`, [bar])).rows.map((r) => r.kind);
    ok("the team's history has every step",
      ["enrolled", "code_reissued", "enrolment_revoked", "joined", "requested", "approved", "declined", "locked", "unlocked",
       "role_changed", "left", "details_changed", "shift_ended_by_manager"].every((k) => hist.includes(k)), `— ${[...new Set(hist)].join(", ")}`);
    const rh = (await as(rahul, `select kind, detail from public.staff_history($1,$2)`, [bar, rahul])).rows;
    ok("a person reads their own history, the lock's reason included",
      rh.some((r) => r.kind === "locked" && /Cash count/.test(r.detail.reason ?? "")));
    ok("…but not the team's", await refused(() => as(rahul, `select * from public.staff_history($1)`, [bar])));
    ok("nobody writes the history directly", await refused(() => as(priya, `insert into public.staff_events (venue_id, kind) values ($1,'joined')`, [bar])));
    ok("nobody edits the roster's status directly (no update policy)",
      (await as(priya, `update public.venue_staff set status='active' where venue_id=$1 and user_id=$2 returning 1`, [bar, sam])).rows.length === 0);
  }
} catch (e) {
  console.log(`\n!! harness crashed: ${e.message}`);
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
