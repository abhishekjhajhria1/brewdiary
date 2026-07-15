// READ-ONLY audit of the live database. Writes nothing, changes nothing.
//
// Checks that every migration actually landed, and — more importantly — that the
// SECURITY INVARIANTS still hold. Migrations can succeed and still leave the app
// unsafe: a policy that was supposed to be absent, an RLS flag that never got
// enabled, a definer function that lost its grant. This asserts the shape of the
// schema, not just its existence.
//
//   node scripts/db-audit.mjs
import { readFileSync } from "node:fs";
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

const one = async (sql, params = []) => (await db.query(sql, params)).rows[0];
const all = async (sql, params = []) => (await db.query(sql, params)).rows;

await db.connect();
try {
  console.log("\n── tables ───────────────────────────────────────────");
  const wantTables = [
    "profiles", "entries", "friendships", "comments", "reactions",
    "expenses", "expense_shares", "settlements",
    "circles", "circle_members", "circle_shares",
    "parties", "party_members", "party_shares",
    "wishlist_items",
    "point_events", "venues", "venue_staff", "venue_perks", "venue_verifications",
    "spend_events", "room_consent", "jurisdiction_policy",
    "perk_redemptions", "staff_kudos",
    "plans", "plan_joins", "plan_invites", "blocks", "reports",
    "vouches",
    "moderators", "user_sanctions", "moderation_actions",
  ];
  const have = (await all(`select tablename from pg_tables where schemaname = 'public'`)).map((r) => r.tablename);
  for (const t of wantTables) ok(`table ${t}`, have.includes(t), "— MISSING");

  console.log("\n── every table has RLS enabled ──────────────────────");
  const noRls = await all(`
    select c.relname from pg_class c
    join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'public' and c.relkind = 'r' and not c.relrowsecurity`);
  ok("no public table is left without RLS", noRls.length === 0, `— ${noRls.map((r) => r.relname).join(", ")}`);

  console.log("\n── functions ────────────────────────────────────────");
  const wantFns = [
    "award_checkin", "award_diary", "staff_award", "party_points_board",
    "room_board", "room_tabs", "board_live", "friends_board",
    "record_spend", "venue_spend", "venue_visits",
    "is_venue_staff", "is_venue_manager", "is_party_member", "is_approved_party_member",
    "public_profile", "is_fof",
    "perk_policy", "currency_for_country", "k_anon",
    "perk_status", "redeem_perk", "last_redeemed", "visit_weight",
    "room_staff", "thank_staff", "my_kudos", "venue_kudos_total",
    "venue_insights", "discover_venues",
    "plan_visible_to", "blocked_between", "request_join", "respond_join",
    "withdraw_join", "block_user", "plan_signals", "upcoming_plans", "search_users",
    "is_plan_invited", "invite_to_plan", "uninvite_from_plan", "plan_invitees", "my_plan_days",
    "vouch_count",
    "is_moderator", "is_sanctioned", "suspend_user", "ban_user", "lift_sanction", "open_reports",
  ];
  const fns = (await all(`
    select p.proname from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'`)).map((r) => r.proname);
  for (const f of wantFns) ok(`fn ${f}()`, fns.includes(f), "— MISSING");

  console.log("\n── THE SECURITY INVARIANTS (the ones that matter) ───");
  // These tables must have NO write policy at all — they are server-written only.
  // A stray insert policy here is the difference between "a guest cannot fake a
  // tab" and "a guest can hand themselves a free drink".
  for (const t of ["spend_events", "perk_redemptions", "staff_kudos"]) {
    const w = await all(
      `select policyname, cmd from pg_policies where schemaname='public' and tablename=$1 and cmd <> 'SELECT'`,
      [t],
    );
    ok(`${t}: NO client write policy (server-written only)`, w.length === 0, `— found ${w.map((x) => x.policyname).join(", ")}`);
  }

  // Plans/meetups (031/036). plan_joins, plan_invites and reports are server-written
  // only — a client that could insert an 'approved' join, forge an invite, or read
  // reports back, breaks the feature.
  for (const t of ["plan_joins", "plan_invites", "reports"]) {
    const w = await all(
      `select policyname, cmd from pg_policies where schemaname='public' and tablename=$1 and cmd <> 'SELECT'`,
      [t],
    );
    const bad = w.filter((x) => !(t === "reports" && x.cmd === "INSERT")); // reports: insert-only is allowed
    ok(`${t}: no unexpected client write policy`, bad.length === 0, `— found ${bad.map((x) => `${x.policyname}/${x.cmd}`).join(", ")}`);
  }
  // reports must have NO select policy — a report is a one-way message to us.
  const reportSel = await all(`select policyname from pg_policies where schemaname='public' and tablename='reports' and cmd='SELECT'`);
  ok("reports: NO select policy (nobody reads reports back)", reportSel.length === 0);
  // Report de-dup (035): one person can't inflate another's report count into a weapon.
  const rIdx = await one(
    `select indexdef from pg_indexes where schemaname='public' and tablename='reports' and indexname='reports_reporter_subject_uidx'`,
  );
  ok(
    "reports: unique (reporter_id, subject_user_id) — one reporter counts once",
    rIdx && /UNIQUE/i.test(rIdx.indexdef) && /reporter_id/.test(rIdx.indexdef) && /subject_user_id/.test(rIdx.indexdef),
  );
  const orDef = await one(`select pg_get_functiondef('public.open_reports()'::regprocedure) d`);
  ok("open_reports: repeat-offender count is DISTINCT reporters, not total rows", orDef && /count\(\s*distinct/i.test(orDef.d));

  // A block list is private to its owner — you can see who YOU blocked, never who
  // blocked you (so a block can't be detected).
  const blockSel = await one(`select qual::text q from pg_policies where schemaname='public' and tablename='blocks' and cmd='SELECT'`);
  ok("blocks: readable only by the blocker (a block is undetectable)", blockSel && /blocker_id/.test(blockSel.q) && !/blocked_id/.test(blockSel.q));

  // THE deny-by-default gate for the meetup layer: the ONLY policies are private /
  // invite / friends / fof — there is NO 'open'/stranger tier. 036 added private+invite
  // (narrower audiences, still in the graph). If this ever fails, someone widened plans
  // to strangers without the trust-&-safety work — a separate decision, by design.
  const jpDef = await one(`
    select pg_get_constraintdef(c.oid) d from pg_constraint c
    where c.conrelid='public.plans'::regclass and c.contype='c'
      and pg_get_constraintdef(c.oid) ilike '%join_policy%'`);
  ok("plans: join_policy = private/invite/friends/fof — still NO stranger tier",
    jpDef && /friends/.test(jpDef.d) && /fof/.test(jpDef.d) && /private/.test(jpDef.d) && /invite/.test(jpDef.d)
      && !/open|public|anyone|stranger/i.test(jpDef.d),
    `— ${jpDef?.d ?? "constraint missing"}`);
  // The 'invite' branch must be wired through is_plan_invited (named-guest gate), and
  // 'private' must have NO branch (host-only) — so a private plan can never leak.
  const pvDef = await one(`select pg_get_functiondef('public.plan_visible_to(uuid,uuid)'::regprocedure) d`);
  ok("plan_visible_to: 'invite' opens only to named guests (is_plan_invited), and 'private' has NO branch",
    pvDef && /is_plan_invited/.test(pvDef.d) && !/join_policy\s*=\s*'private'/i.test(pvDef.d));

  // Vouches (033): a friend stakes their word. The insert MUST be friend-gated in the
  // DB (are_friends), not just the UI, and MUST be yourself-as-voucher — otherwise a
  // client could forge a vouch for a stranger, or vouch on someone else's behalf.
  const vIns = await one(
    `select with_check::text w from pg_policies where schemaname='public' and tablename='vouches' and cmd='INSERT'`,
  );
  ok("vouches: insert is friend-gated in the DB (are_friends), not just the UI",
    vIns && /are_friends/.test(vIns.w) && /voucher_id\s*=\s*auth\.uid\(\)/.test(vIns.w) && /blocked_between/.test(vIns.w),
    `— ${vIns?.w ?? "no insert policy"}`);
  // No self-vouch: the table CHECK forbids voucher = vouchee, so nobody inflates their own standing.
  const vChk = await one(`
    select pg_get_constraintdef(c.oid) d from pg_constraint c
    where c.conrelid='public.vouches'::regclass and c.contype='c'`);
  ok("vouches: no self-vouch (voucher <> vouchee, a guest can't reward themselves)",
    vChk && /voucher_id\s*<>\s*vouchee_id/.test(vChk.d), `— ${vChk?.d ?? "constraint missing"}`);
  // The full "who vouched for whom" graph is never public — only voucher/vouchee see a row.
  const vSel = await one(`select qual::text q from pg_policies where schemaname='public' and tablename='vouches' and cmd='SELECT'`);
  ok("vouches: readable only by voucher or vouchee (a count is public, the graph is not)",
    vSel && /voucher_id\s*=\s*auth\.uid\(\)/.test(vSel.q) && /vouchee_id\s*=\s*auth\.uid\(\)/.test(vSel.q));
  // plan_signals now carries the host's vouch COUNT (a soft signal, never a rating).
  const psCols = await one(`select pg_get_function_result('public.plan_signals(uuid)'::regprocedure) r`);
  ok("plan_signals: returns host_vouches (soft meetup signal, counts-only)",
    psCols && /host_vouches/.test(psCols.r), `— ${psCols?.r ?? "?"}`);

  // Moderation (034). The `moderators` table is the trust root — if a client could
  // write it, anyone could make themselves a moderator and then ban anyone. It, plus
  // sanctions and the audit log, must be server-written only.
  for (const t of ["moderators", "user_sanctions", "moderation_actions"]) {
    const w = await all(
      `select policyname, cmd from pg_policies where schemaname='public' and tablename=$1 and cmd <> 'SELECT'`,
      [t],
    );
    ok(`${t}: NO client write policy (server-seeded / server-written only)`, w.length === 0,
      `— found ${w.map((x) => `${x.policyname}/${x.cmd}`).join(", ")}`);
  }
  // A person can only ever read their OWN moderator row (the team list isn't exposed).
  const modSel = await one(`select qual::text q from pg_policies where schemaname='public' and tablename='moderators' and cmd='SELECT'`);
  ok("moderators: readable only as your own row (team roster not exposed to the client)",
    modSel && /user_id\s*=\s*auth\.uid\(\)/.test(modSel.q) && !/is_moderator/.test(modSel.q));
  // A sanctioned account is walled out of creating a plan — the gate is in the policy.
  const planIns = await one(`select with_check::text w from pg_policies where schemaname='public' and tablename='plans' and cmd='INSERT'`);
  ok("plans: a sanctioned account can't create one (is_sanctioned in the insert gate)",
    planIns && /is_sanctioned/.test(planIns.w), `— ${planIns?.w ?? "no insert policy"}`);

  // Sparks became server-authoritative in 016: the client may insert VIBE, never SPARK.
  const sparkPolicy = await all(
    `select policyname from pg_policies where schemaname='public' and tablename='point_events' and policyname like '%spark%'`,
  );
  ok("point_events: the old client spark-insert policy is GONE", sparkPolicy.length === 0);

  // A venue can never verify itself, and can never approve its own request.
  const vGuard = await one(`select count(*)::int n from pg_trigger where tgname = 'venues_protect_admin_fields'`);
  ok("venues: the admin-field guard trigger exists (no self-verification)", Number(vGuard.n) > 0);
  const vJur = await one(`select count(*)::int n from pg_trigger where tgname = 'venues_jurisdiction'`);
  ok("venues: the jurisdiction guard exists (no venue where alcohol is banned)", Number(vJur.n) > 0);
  const pGuard = await one(`select count(*)::int n from pg_trigger where tgname = 'venue_perks_policy'`);
  ok("venue_perks: the policy guard exists (no unlawful perk)", Number(pGuard.n) > 0);
  const vvUpdate = await all(
    `select policyname from pg_policies where schemaname='public' and tablename='venue_verifications' and cmd = 'UPDATE'`,
  );
  ok("venue_verifications: NO update policy (can't self-approve)", vvUpdate.length === 0);

  // Kudos: a manager must NOT be able to read who was thanked.
  const kRead = await one(
    `select qual::text q from pg_policies where schemaname='public' and tablename='staff_kudos' and cmd='SELECT'`,
  );
  ok(
    "staff_kudos: readable ONLY by the thanked and the thanker (no manager league table)",
    kRead && /staff_id/.test(kRead.q) && /from_user/.test(kRead.q) && !/is_venue_manager/.test(kRead.q),
  );

  // Insights: the k-anonymity threshold must be 5, not 3.
  const k = await one(`select public.k_anon() as k`);
  ok("insights: k-anonymity threshold is 5 (differencing-safe)", Number(k.k) === 5);

  // Vibe/points are positive-only — the CHECK must still be there.
  const pos = await one(`
    select count(*)::int n from pg_constraint
    where conrelid = 'public.point_events'::regclass and contype='c'
      and pg_get_constraintdef(oid) ilike '%value > 0%'`);
  ok("point_events: positive-only (no negative vibe, ever)", Number(pos.n) > 0);

  console.log("\n── jurisdiction policy (deny by default) ────────────");
  const jp = await one(`select count(*)::int n from public.jurisdiction_policy`);
  ok("jurisdiction_policy is seeded", Number(jp.n) >= 30, `— only ${jp.n} rows`);

  const cls = async (c, r = "") => await one(`select * from public.perk_policy($1,$2)`, [c, r]);
  ok("IN: full (alcohol reward + spend)", (await cls("IN")).allow_alcohol_reward === true);
  ok("GB: perks yes, alcohol reward NO", (await cls("GB")).allow_alcohol_reward === false);
  ok("IE: spend-based perk NO", (await cls("IE")).allow_spend_perk === false);
  ok("US-MA: alcohol reward NO", (await cls("US", "MA")).allow_alcohol_reward === false);
  ok("US-NY: alcohol reward yes", (await cls("US", "NY")).allow_alcohol_reward === true);
  ok("TH: no perk of any kind", (await cls("TH")).allow_perks === false);
  ok("SA: alcohol not legal → no venue layer", (await cls("SA")).alcohol_legal === false);
  const unknown = await all(`select * from public.perk_policy('ZW','')`);
  ok("an UNRESEARCHED country returns NO ROW (deny by default)", unknown.length === 0);

  console.log("\n── columns added by later migrations ────────────────");
  const col = async (t, c) =>
    Number(
      (
        await one(
          `select count(*)::int n from information_schema.columns
            where table_schema='public' and table_name=$1 and column_name=$2`,
          [t, c],
        )
      ).n,
    ) > 0;
  ok("profiles.compete_visible", await col("profiles", "compete_visible"));
  ok("parties.venue_id", await col("parties", "venue_id"));
  ok("parties.board_until", await col("parties", "board_until"));
  ok("point_events.party_id is NULLABLE (diary sparks)", !(await one(`
    select attnotnull from pg_attribute
    where attrelid='public.point_events'::regclass and attname='party_id'`)).attnotnull);
  ok("venues.country", await col("venues", "country"));
  ok("venues.currency", await col("venues", "currency"));
  ok("venues.quiet_nights", await col("venues", "quiet_nights"));
  ok("venue_perks.reward_alcoholic", await col("venue_perks", "reward_alcoholic"));
  ok("venue_staff.thankable", await col("venue_staff", "thankable"));
  ok("profiles.presence_checked (free anti-bot trust signal, 032)", await col("profiles", "presence_checked"));
  ok("profiles.verified (paid-KYC output, separate from presence)", await col("profiles", "verified"));

  console.log("\n── perk tiers (029) ─────────────────────────────────");
  // A venue offers up to 3 rewards, each an independent punch-card. The PK moved
  // from venue_id to id — if a later migration ever puts it back, a venue silently
  // loses every tier but one, so assert the shape.
  const perkPk = await all(`
    select a.attname from pg_index i
    join pg_attribute a on a.attrelid = i.indrelid and a.attnum = any(i.indkey)
    where i.indrelid = 'public.venue_perks'::regclass and i.indisprimary`);
  ok("venue_perks: PK is id (one row per TIER, not per venue)",
    perkPk.length === 1 && perkPk[0].attname === "id",
    `— PK is (${perkPk.map((r) => r.attname).join(", ")})`);

  const tierUniq = await one(`
    select count(*)::int n from pg_indexes
    where schemaname='public' and tablename='venue_perks' and indexname='venue_perks_tier_uniq'`);
  ok("venue_perks: the same reward can't be offered twice at one venue", Number(tierUniq.n) > 0);

  ok("perk_redemptions.perk_id (a claim names the TIER it was claimed against)",
    await col("perk_redemptions", "perk_id"));

  // The claim clock is per-tier: claiming the coffee must not wipe progress toward
  // the pour. That only holds if last_redeemed() keys on the perk, not the venue.
  const lr = await one(`
    select pg_get_functiondef(p.oid) d from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname='public' and p.proname='last_redeemed'`);
  ok("last_redeemed(): the clock is PER TIER (r.perk_id), not per venue",
    lr && /perk_id\s*=\s*pk/.test(lr.d));

  // No venue may run more tiers than a bartender can explain while pouring.
  const fat = await all(`
    select v.slug, count(*)::int n from public.venue_perks p
    join public.venues v on v.id = p.venue_id group by v.slug having count(*) > 3`);
  ok("no venue has more than 3 tiers", fat.length === 0,
    `— ${fat.map((r) => `${r.slug}:${r.n}`).join(", ")}`);

  console.log("\n── off-trade: a shop is not a quieter bar (030) ──────");
  ok("venues.kind", await col("venues", "kind"));
  ok("jurisdiction_policy.allow_offtrade_perks", await col("jurisdiction_policy", "allow_offtrade_perks"));
  ok("table venue_checkins", have.includes("venue_checkins"));

  // A guest must NEVER be able to punch their own card. No write policy at all:
  // record_visit() is the only door in.
  const cw = await all(
    `select policyname from pg_policies where schemaname='public' and tablename='venue_checkins' and cmd <> 'SELECT'`,
  );
  ok("venue_checkins: NO client write policy (staff punch it, not the guest)", cw.length === 0);

  // One punch per person per shop per day. Without this a shop could punch ten times
  // for ten bottles, turning a visits card back into a volume card.
  const oneADay = await one(`
    select count(*)::int n from pg_indexes
    where schemaname='public' and tablename='venue_checkins' and indexname='venue_checkins_one_a_day'`);
  ok("venue_checkins: one punch per guest per day (a visits card can't become a volume card)",
    Number(oneADay.n) > 0);

  const kindGuard = await one(`select count(*)::int n from pg_trigger where tgname = 'parties_venue_kind'`);
  ok("parties: an off-licence can't run a room", Number(kindGuard.n) > 0);
  const recheck = await one(`select count(*)::int n from pg_trigger where tgname = 'venues_recheck_perks'`);
  ok("venues: switching bar→shop re-tests every perk against the shop's rules", Number(recheck.n) > 0);

  const off = async (c, r = "") => await one(`select * from public.perk_policy($1,$2)`, [c, r]);
  ok("IE: bar perk yes, SHOP card NO (there, a visit is the sale)",
    (await off("IE")).allow_perks === true && (await off("IE")).allow_offtrade_perks === false);
  ok("GB-NIR: NO perks at all (Art. 57ZB reaches every licensed premises)",
    (await off("GB", "NIR")).allow_perks === false);
  ok("GB-SCT: bar perk yes, shop card NO", (await off("GB", "SCT")).allow_offtrade_perks === false);
  ok("GB (England/Wales): shop card yes", (await off("GB")).allow_offtrade_perks === true);
  ok("IN: shop card yes", (await off("IN")).allow_offtrade_perks === true);

  // perk_status() is a SET since 029 — anything treating it as a scalar now raises.
  const vi = await one(`
    select pg_get_functiondef(p.oid) d from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname='public' and p.proname='venue_insights'`);
  ok("venue_insights(): reads perk_status as a SET, not a scalar (the 029 regression)",
    vi && !/\(\s*select\s+earned\s+from\s+public\.perk_status/i.test(vi.d));
  ok("venue_insights(): counts a shop's punched cards, not just rooms",
    vi && /venue_checkins/.test(vi.d));

  console.log("\n── orphans / drift ──────────────────────────────────");
  const badCurrency = await one(`
    select count(*)::int n from public.venues v
    where v.currency <> public.currency_for_country(v.country)`);
  ok("every venue's currency matches its country", Number(badCurrency.n) === 0);

  // The one that matters. Judges every LIVE perk against the policy for the venue's
  // ACTUAL place and kind — including anything grandfathered in before a rule
  // tightened, which a trigger (it only fires on write) would never catch.
  const unlawful = await all(`
    select v.slug, v.country, v.kind
    from public.venue_perks p
    join public.venues v on v.id = p.venue_id
    cross join lateral public.perk_policy(v.country, coalesce(v.region, '')) pol
    where not pol.allow_perks
       or (v.kind = 'store' and not pol.allow_offtrade_perks)
       or (v.kind = 'store' and (p.reward_alcoholic or p.kind = 'spend'))
       or (v.kind <> 'store' and p.reward_alcoholic and not pol.allow_alcohol_reward)
       or (v.kind <> 'store' and p.kind = 'spend' and not pol.allow_spend_perk)`);
  ok(
    "NO existing perk is unlawful where its venue actually is",
    unlawful.length === 0,
    `— ${unlawful.map((r) => `${r.slug}/${r.country}/${r.kind}`).join(", ")}`,
  );

  // A venue in an unresearched country gets NO policy row at all — the lateral join
  // above would silently drop it, so check for that separately rather than call it a pass.
  const unpoliced = await all(`
    select v.slug, v.country from public.venues v
    where not exists (select 1 from public.perk_policy(v.country, coalesce(v.region, '')))`);
  ok(
    "every live venue sits in a jurisdiction we have actually researched",
    unpoliced.length === 0,
    `— ${unpoliced.map((r) => `${r.slug}/${r.country}`).join(", ")}`,
  );
} catch (e) {
  console.log(`\n!! audit crashed: ${e.message}`);
  fails.push(`audit: ${e.message}`);
} finally {
  await db.end();
}

console.log(`\n═══════════════════════════════════════════════════════`);
console.log(`  ${pass} passed, ${fails.length} failed   (read-only — nothing was changed)`);
if (fails.length) {
  console.log("\n  FAILURES:");
  for (const f of fails) console.log(`   ✗ ${f}`);
  process.exitCode = 1;
}
