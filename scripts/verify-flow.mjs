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

for (const line of readFileSync(".env.local", "utf8").split("\n")) {
  const t = line.trim();
  if (!t || t.startsWith("#")) continue;
  const i = t.indexOf("=");
  if (i > 0 && !(t.slice(0, i).trim() in process.env)) process.env[t.slice(0, i).trim()] = t.slice(i + 1).trim();
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
  // strictest one, not the loosest. Before 021 this fell through to "anything goes".
  await db.query(`update public.venues set country = 'ZW' where id = $1`, [vid]);
  ok(
    "AN UNRESEARCHED COUNTRY gets NO perk (silence means 'no', not 'yes')",
    await refused(() =>
      as(owner, `update public.venue_perks set kind = 'visits', reward_alcoholic = false where venue_id = $1`, [vid]),
    ),
  );

  // Where alcohol is prohibited, a venue cannot exist at all.
  ok(
    "SAUDI ARABIA: a venue cannot even be created (the diary still works)",
    await refused(() => db.query(`update public.venues set country = 'SA' where id = $1`, [vid])),
  );

  // back to the home market, and restore the spend perk for the rest of the run
  await db.query(`update public.venues set country = 'IN', region = null where id = $1`, [vid]);
  await as(owner, `update public.venue_perks set kind = 'spend', threshold = 3000 where venue_id = $1`, [vid]);

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

  const row = (await anon(`select * from public.public_profile($1)`, [aHandle])).rows[0];
  ok("a profile leaks NO spend/notes — counts only", !("spend" in row) && !("notes" in row) && "total" in row);

  console.log("\n── 9. the guest's own view ───────────────────────────");
  const pb = await as(anita, `select * from public.party_points_board($1)`, [pid]);
  ok("the room board sums the ledger for members", pb.rows.length === 2);
  const outsider = await refused(async () => {
    const r = await as(stranger, `select * from public.party_points_board($1)`, [pid]);
    if (r.rows.length > 0) throw new Error("leaked");
  });
  ok("a non-member cannot read the room board", outsider);
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
