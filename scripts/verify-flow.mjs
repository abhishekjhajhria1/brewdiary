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
    await db.query("reset role");
    await db.query("reset request.jwt.claims");
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
async function refused(fn) {
  try {
    await fn();
    return false;
  } catch {
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
  ok("owner can create a venue", true);

  const selfVerify = await refused(() => as(owner, `update public.venues set verified = true where id = $1`, [vid]));
  const v1 = await db.query(`select verified from public.venues where id = $1`, [vid]);
  ok("a venue CANNOT verify itself", selfVerify || v1.rows[0].verified === false);

  await as(owner, `insert into public.venue_staff (venue_id, user_id, role) values ($1,$2,'bartender')`, [vid, barman]);
  ok("owner can add a bartender", true);

  await as(owner, `insert into public.venue_verifications (venue_id, requested_by, note) values ($1,$2,'please')`, [
    vid,
    owner,
  ]);
  const stat = await db.query(`select status from public.venue_verifications where venue_id = $1`, [vid]);
  ok("verification request lands as 'pending'", stat.rows[0].status === "pending");

  const selfApprove = await refused(() =>
    as(owner, `update public.venue_verifications set status='approved' where venue_id = $1`, [vid]),
  );
  ok("a venue CANNOT approve its own request", selfApprove);

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
  await db.query(`update public.venues set country = 'TH', region = null where id = $1`, [vid]);
  ok(
    "THAILAND: no loyalty perk at all — even visits + a coffee",
    await refused(() =>
      as(owner, `update public.venue_perks set kind = 'visits', reward_alcoholic = false, reward = 'a coffee'
                 where venue_id = $1`, [vid]),
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
  await as(owner, `update public.venue_perks set kind = 'spend', threshold = 3000 where venue_id = $1`, [vid]);

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

  await db.query(`update public.venues set quiet_nights = '{}' where id = $1`, [vid]);
  let q = await as(anita, `select progress from public.perk_status($1,$2)`, [vid, anita]);
  const base = Number(q.rows[0].progress);

  await db.query(`update public.venues set quiet_nights = array[$2::int] where id = $1`, [vid, roomDow]);
  q = await as(anita, `select progress from public.perk_status($1,$2)`, [vid, anita]);
  const boosted = Number(q.rows[0].progress);

  ok("a visit on a QUIET night is worth double toward the perk", boosted === base + 1);
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
  const outsider = await refused(async () => {
    const r = await as(stranger, `select * from public.party_points_board($1)`, [pid]);
    if (r.rows.length > 0) throw new Error("leaked");
  });
  ok("a non-member cannot read the room board", outsider);

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
