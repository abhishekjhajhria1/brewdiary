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
    "venue_guest_notes",
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
    "venue_insights", "discover_venues", "taste_trends",
    "plan_visible_to", "blocked_between", "request_join", "respond_join",
    "withdraw_join", "block_user", "plan_signals", "upcoming_plans", "search_users",
    "is_plan_invited", "invite_to_plan", "uninvite_from_plan", "plan_invitees", "my_plan_days", "respond_invite",
    "vouch_count",
    "is_moderator", "is_sanctioned", "suspend_user", "ban_user", "lift_sanction", "open_reports",
    "has_venue_interaction", "set_guest_note", "venue_guest_card", "my_venue_books",
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
  // 038 (venue_insights v2) is applied incrementally — assert it only when present,
  // so this audit stays green while the migration is still on hold.
  if (vi && /visits_by_dow/.test(vi.d)) {
    ok("venue_insights(): v2 exposes weekday visits + previous-window trend",
      /prev_guests/.test(vi.d) && /prev_takings/.test(vi.d));
  } else {
    console.log("  ~ venue_insights v2 (038) not applied — skipping");
  }

  // 039 (area_taste_trends). When applied, it must be k-anon at ≥5 (a city slice is a
  // smaller crowd than global taste_trends' ≥3) and gate on the OPT-IN flag.
  const at = await one(`
    select pg_get_functiondef(p.oid) d from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname='public' and p.proname='area_taste_trends'`);
  if (at) {
    ok("area_taste_trends(): suppresses below 5 distinct people (k-anon for a small area)",
      /count\(distinct[^)]*\)\s*>=\s*5/i.test(at.d) && !/>=\s*3\b/.test(at.d));
    ok("area_taste_trends(): only counts opt-in sharers (share_trends), matched by coarse geohash",
      /share_trends/.test(at.d) && /trends_geo/.test(at.d));
  } else {
    console.log("  ~ area_taste_trends (039) not applied — skipping");
  }

  // ── the guest book (040): a FIRST-PARTY CRM, machine-enforced ──────────────
  // Writes are staff-only via set_guest_note(): the table itself takes no client
  // INSERT/UPDATE (a guest can't be made to author their own file).
  const gbWrite = await all(
    `select policyname, cmd from pg_policies where schemaname='public' and tablename='venue_guest_notes' and cmd in ('INSERT','UPDATE')`);
  ok("venue_guest_notes: no client INSERT/UPDATE (staff-written via set_guest_note only)",
    gbWrite.length === 0, `— found ${gbWrite.map((x) => `${x.policyname}/${x.cmd}`).join(", ")}`);

  // THE line that makes this a CRM and not surveillance: a venue's view of a guest —
  // and the guest's own view — NEVER read public.entries. No diary ever reaches a bar.
  const gcDef = await one(`select pg_get_functiondef('public.venue_guest_card(uuid,uuid)'::regprocedure) d`);
  ok("venue_guest_card(): FIRST-PARTY — never touches public.entries (no diary leak)",
    gcDef && !/\bentries\b/.test(gcDef.d));
  const mbDef = await one(`select pg_get_functiondef('public.my_venue_books()'::regprocedure) d`);
  ok("my_venue_books(): the guest's own view never touches the diary either",
    mbDef && !/\bentries\b/.test(mbDef.d));

  // A book may only be opened on a guest who actually came (interaction gate) by staff.
  const sgDef = await one(`select pg_get_functiondef('public.set_guest_note(uuid,uuid,text,text[])'::regprocedure) d`);
  ok("set_guest_note(): gated on has_venue_interaction + a staff capability",
    sgDef && /has_venue_interaction/.test(sgDef.d) && /(is_venue_staff|venue_can\s*\(\s*vid\s*,\s*me\s*,\s*'guests\.notes')/.test(sgDef.d));

  // ── menus (042): the paper menu on the table, never an offer ──────────────
  const vmDef = await one(`
    select pg_get_functiondef(p.oid) d from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname='public' and p.proname='venue_menu'`);
  if (vmDef) {
    ok("venue_menu(): serves VERIFIED venues only", /v\.verified/.test(vmDef.d));
    ok("venue_menu(): never touches the diary or the perks (a menu is not an offer)",
      !/\bentries\b/.test(vmDef.d) && !/venue_perks/.test(vmDef.d));
    const menuCols = (await all(
      `select column_name from information_schema.columns where table_schema='public' and table_name='venue_menu_items'`))
      .map((r) => r.column_name);
    ok("venue_menu_items: no discount / offer / happy-hour column",
      !menuCols.some((c) => /discount|offer|promo|happy|deal/.test(c)), `— ${menuCols.join(", ")}`);
    const dvDef = await one(`select pg_get_functiondef('public.discover_venues(text,int)'::regprocedure) d`);
    ok("discover_venues(): lists the bar, never its menu (no join to venue_menu_items)",
      dvDef && !/venue_menu/.test(dvDef.d));
  } else {
    console.log("  ~ venue_menu (042) not applied — skipping");
  }

  // ── a diary is never deleted (055): put away, with a fresh code to clear it all ──
  const arcCol = await one(`select 1 x from information_schema.columns where table_schema='public' and table_name='entries' and column_name='archived_at'`);
  if (arcCol) {
    const entPol = await all(`select policyname, cmd, permissive from pg_policies where schemaname='public' and tablename='entries'`);
    ok("entries: no client DELETE policy (nothing is destroyed from an app)", !entPol.some((p) => p.cmd === "DELETE"), `— ${entPol.map((p) => p.policyname).join(", ")}`);
    ok("entries: a RESTRICTIVE read policy keeps put-away entries out of every read",
      entPol.some((p) => p.cmd === "SELECT" && p.permissive === "RESTRICTIVE"));
    const trig = await one(`select 1 x from pg_trigger where tgrelid='public.entries'::regclass and tgname='entries_guard_archive' and not tgisinternal`);
    ok("entries: a trigger stops a client setting archived_at itself", !!trig);
    const amd = await one(`select pg_get_functiondef('public.archive_my_diary()'::regprocedure) d`);
    ok("archive_my_diary(): refuses without a fresh emailed code", amd && /signed_in_by_code_recently/.test(amd.d));
    ok("archive_my_diary(): puts away, never deletes", amd && !/\bdelete\b/i.test(amd.d));
  } else {
    console.log("  ~ diary archive (055) not applied — skipping");
  }

  // ── your taste at the table (056): tonight only, the drink-makers only ──────
  const vgt = await one(`select pg_get_functiondef(p.oid) d from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.proname='venue_guests_tonight'`);
  if (vgt) {
    ok("venue_guests_tonight(): gated by venue_can(…, 'guests.taste')", /venue_can\(.*'guests\.taste'\)/.test(vgt.d));
    ok("venue_guests_tonight(): only live shares (expires_at > now())", /expires_at\s*>\s*now\(\)/.test(vgt.d));
    ok("venue_guests_tonight(): never reads the diary", !/\bentries\b/.test(vgt.d));
    const tsPol = await all(`select cmd from pg_policies where schemaname='public' and tablename='taste_shares'`);
    ok("taste_shares: no client INSERT or UPDATE (share_taste() is the only way in)", !tsPol.some((p) => p.cmd === "INSERT" || p.cmd === "UPDATE" || p.cmd === "ALL"));
    const st = await one(`select pg_get_functiondef('public.share_taste(text,jsonb)'::regprocedure) d`);
    ok("share_taste(): cleans what's shared and expires it", st && /clean_taste/.test(st.d) && /interval '8 hours'/.test(st.d));
    ok("share_taste(): records no visit and no perk (a guest can't write their own reward)", st && !/venue_checkins|perk_redemptions|spend_events|record_visit/.test(st.d));
    const sta = await one(`select pg_get_functiondef('public.share_taste_at(text,jsonb)'::regprocedure) d`);
    ok("share_taste_at(): verified venues only, cleaned, expires, no reward", sta && /verified/.test(sta.d) && /clean_taste/.test(sta.d) && /interval '8 hours'/.test(sta.d) && !/venue_checkins|perk_redemptions|spend_events/.test(sta.d));
    const caps = await all(`select role from public.role_capabilities where capability='guests.taste'`);
    ok("guests.taste: never the host or the kitchen", !caps.some((r) => r.role === "host" || r.role === "kitchen"), `— ${caps.map((r) => r.role).join(", ")}`);
    const gcPol = await all(`select 1 from pg_policies where schemaname='public' and tablename='guest_codes'`);
    ok("guest_codes: no client policy at all", gcPol.length === 0);
    const vfg = await one(`select pg_get_functiondef('public.venue_find_guest(uuid,text)'::regprocedure) d`);
    ok("venue_find_guest(): gated by perks.redeem, live codes only", vfg && /'perks\.redeem'/.test(vfg.d) && /expires_at\s*>\s*now\(\)/.test(vfg.d));
  } else {
    console.log("  ~ taste at the table (056) not applied — skipping");
  }

  // ── more challenges (043): counts only, inside the circle ─────────────────
  const cb2 = await one(`
    select pg_get_functiondef(p.oid) d from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname='public' and p.proname='challenge_board_v2'`);
  if (cb2) {
    ok("challenge_board_v2(): gated on circle membership", /is_circle_member/.test(cb2.d));
    ok("challenge_board_v2(): returns counts, never a drink name or place",
      !/returns table[^)]*\b(drink|venue)\b\s+text/i.test(cb2.d));
  } else {
    console.log("  ~ challenge_board_v2 (043) not applied — skipping");
  }

  // ── staff roles (045) + capability gates (046) ───────────────────────────
  // Checked once 045 is applied; before that the live schema simply predates it.
  if (!have.includes("role_capabilities")) {
    console.log("  ~ staff roles (045) not applied — skipping");
  } else {
    console.log("\n── staff roles: who may do what, decided by the DB (045/046) ──");
    for (const f of ["venue_role", "venue_can", "can_grant_role", "set_staff_role", "set_thankable",
                     "create_staff_invite", "accept_staff_invite"]) {
      ok(`fn ${f}()`, fns.includes(f), "— MISSING");
    }
    ok("table staff_invites", have.includes("staff_invites"), "— MISSING");
    const rcw = await all(`select policyname from pg_policies where schemaname='public' and tablename='role_capabilities' and cmd <> 'SELECT'`);
    ok("role_capabilities: NO client write policy (the matrix is data we write, not the venue)", rcw.length === 0);
    const caps = await all(`select role, capability from public.role_capabilities`);
    const has = (role, cap) => caps.some((r) => r.role === role && r.capability === cap);
    const every = [...new Set(caps.map((r) => r.capability))];
    ok("owner holds every capability", every.every((c) => has("owner", c)));
    ok("a manager holds everything but deleting the venue",
      every.filter((c) => c !== "venue.delete").every((c) => has("manager", c)) && !has("manager", "venue.delete"));
    for (const role of ["kitchen", "host"]) {
      ok(`${role}: can't touch a guest's tab, perks, card or notes`,
        ["spend.record", "perks.redeem", "guests.card", "guests.notes"].every((c) => !has(role, c)));
    }
    ok("only owner/manager run the team, the reports, the menu, the perks and the settings",
      ["team.manage", "reports.view", "menu.edit", "perks.edit", "settings.edit"].every(
        (c) => caps.filter((r) => r.capability === c).every((r) => r.role === "owner" || r.role === "manager")));
    ok("today's bartender keeps every power it had (tab, vibe, perks, room, guest book)",
      ["spend.record", "guests.vibe", "perks.redeem", "rooms.open", "guests.card", "guests.notes", "guests.at_tables"].every((c) => has("bartender", c)));

    const vsPol = await all(`select policyname, cmd, coalesce(qual,'') q, coalesce(with_check,'') w
                               from pg_policies where schemaname='public' and tablename='venue_staff'`);
    ok("venue_staff: still NO update policy (roles change via set_staff_role only)", !vsPol.some((p) => p.cmd === "UPDATE" || p.cmd === "ALL"));
    const ins = vsPol.find((p) => p.cmd === "INSERT");
    if (fns.includes("enrol_staff")) {
      // 053: nobody is inserted onto a roster from a client — the owner's code or an approved invite.
      ok("venue_staff insert: only the creator's own owner row (everyone else: the owner's code or an approved invite)",
        ins && /created_by/.test(ins.w) && /'owner'/.test(ins.w) && !/can_grant_role/.test(ins.w));
    } else {
      ok("venue_staff insert: a role is granted only by someone senior enough (can_grant_role)", ins && /can_grant_role/.test(ins.w));
    }
    const del = vsPol.find((p) => p.cmd === "DELETE");
    ok("venue_staff delete: the owner's row can't be removed from a client", del && /owner/.test(del.q) && /can_grant_role/.test(del.q));
    const cg = await one(`select pg_get_functiondef('public.can_grant_role(uuid,uuid,text)'::regprocedure) d`);
    ok("can_grant_role(): 'owner' is never granted from an app", cg && /<>\s*'owner'/.test(cg.d));
    const ssr = await one(`select pg_get_functiondef('public.set_staff_role(uuid,uuid,text)'::regprocedure) d`);
    ok("set_staff_role(): nobody changes their own role", ssr && /own role/.test(ssr.d));
    const st = await one(`select pg_get_functiondef('public.set_thankable(uuid,boolean)'::regprocedure) d`);
    ok("set_thankable(): only ever your OWN row (the opt-out that actually works)", st && /user_id\s*=\s*auth\.uid\(\)/.test(st.d));
    const ga = await one(`select pg_get_functiondef('public.venues_guard_admin_fields()'::regprocedure) d`);
    ok("venues: a VERIFIED venue can't move country/region, change kind or slug by itself",
      ga && ["country", "region", "kind", "slug"].every((c) => new RegExp(`new\\.${c}\\s+is distinct from`).test(ga.d)));
    const iw = await all(`select policyname from pg_policies where schemaname='public' and tablename='staff_invites' and cmd <> 'SELECT'`);
    ok("staff_invites: NO client write policy (created and accepted through functions)", iw.length === 0);

    const gated = {
      "record_spend(uuid,uuid,numeric)": "spend.record",
      "staff_award(uuid,uuid,text)": "guests.vibe",
      "redeem_perk(uuid,uuid)": "perks.redeem",
      "record_visit(uuid,uuid)": "perks.redeem",
      "perk_status(uuid,uuid)": "perks.redeem",
      "set_guest_note(uuid,uuid,text,text[])": "guests.notes",
      "venue_guest_card(uuid,uuid)": "guests.card",
      "room_guests(uuid)": "guests.at_tables",
      "parties_guard_venue()": "rooms.open",
    };
    for (const [sig, cap] of Object.entries(gated)) {
      const d = await one(`select pg_get_functiondef('public.${sig}'::regprocedure) d`);
      ok(`${sig.split("(")[0]}(): asks the '${cap}' capability, not just "on the team"`,
        d && d.d.includes(`'${cap}'`) && /venue_can\s*\(/.test(d.d) && !/is_venue_staff\s*\(/.test(d.d));
    }
    for (const [t, cap] of [["spend_events", "spend.record"], ["perk_redemptions", "perks.redeem"],
                            ["venue_checkins", "perks.redeem"], ["venue_guest_notes", "guests.card"]]) {
      const r = await one(`select coalesce(qual,'') q from pg_policies where schemaname='public' and tablename=$1 and cmd='SELECT'`, [t]);
      ok(`${t}: staff read it with the '${cap}' capability`, r && r.q.includes(cap));
    }
  }

  // ── every kind of shop (047): the law follows what a place SELLS ──────────
  if (!fns.includes("venue_legal_class")) {
    console.log("  ~ every kind of shop (047) not applied — skipping");
  } else {
    console.log("\n── every kind of shop: the law follows what's sold (047) ──");
    const kc = await one(`select pg_get_constraintdef(oid) d from pg_constraint where conname = 'venues_kind_check'`);
    ok("venues.kind: bar, club, restaurant, cafe, store, sweet_shop, bakery, shop",
      kc && ["bar", "club", "restaurant", "cafe", "store", "sweet_shop", "bakery", "shop"].every((k) => kc.d.includes(`'${k}'`)));
    const lc = await all(`select k, a, public.venue_legal_class(k, a) c from (values
      ('bar', false), ('club', false), ('store', false), ('cafe', true), ('cafe', false),
      ('restaurant', true), ('sweet_shop', true), ('bakery', false), ('shop', true)) t(k, a)`);
    const cls = Object.fromEntries(lc.map((r) => [`${r.k}:${r.a}`, r.c]));
    ok("a bar or club is on-trade whatever it claims", cls["bar:false"] === "on_trade" && cls["club:false"] === "on_trade");
    ok("a liquor store is off-trade", cls["store:false"] === "off_trade");
    ok("a café or restaurant is on-trade only if it serves alcohol",
      cls["cafe:true"] === "on_trade" && cls["cafe:false"] === "no_alcohol" && cls["restaurant:true"] === "on_trade");
    ok("a sweet shop, bakery or shop never sells alcohol (a shop that does is a store)",
      cls["sweet_shop:true"] === "no_alcohol" && cls["bakery:false"] === "no_alcohol" && cls["shop:true"] === "no_alcohol");
    const pg = await one(`select pg_get_functiondef('public.venue_perks_guard()'::regprocedure) d`);
    ok("venue_perks_guard(): decides by legal class, and a no-alcohol card still can't reward alcohol",
      pg && /venue_legal_class/.test(pg.d) && /no_alcohol/.test(pg.d) && /reward_alcoholic/.test(pg.d));
    ok("venue_perks_guard(): an unresearched country is still NO for every kind", pg && /pol is null/.test(pg.d));
    const rg = await one(`select pg_get_functiondef('public.parties_guard_venue_kind()'::regprocedure) d`);
    ok("a COUNTER (store, sweet shop, bakery, shop) runs no rooms", rg && /venue_is_counter/.test(rg.d));
    const ga2 = await one(`select pg_get_functiondef('public.venues_guard_admin_fields()'::regprocedure) d`);
    ok("a verified venue can't flip its alcohol licence by itself", ga2 && /new\.serves_alcohol\s+is distinct from/.test(ga2.d));
    const sa = await one(`select pg_get_constraintdef(oid) d from pg_constraint where conname = 'venues_serves_alcohol_check'`);
    ok("the venues table can't hold a sober bar or a licensed bakery", Boolean(sa));
  }

  // ── the area heat map (048): consenting groups, never a person ─────────────
  if (!fns.includes("area_heat_map")) {
    console.log("  ~ the area heat map (048) not applied — skipping");
  } else {
    console.log("\n── the area heat map: consenting groups, never a person (048) ──");
    const hm = await one(`select pg_get_functiondef('public.area_heat_map(uuid,integer,text)'::regprocedure) d,
      (select prosecdef from pg_proc where oid = 'public.area_heat_map(uuid,integer,text)'::regprocedure) sd,
      (select proconfig::text from pg_proc where oid = 'public.area_heat_map(uuid,integer,text)'::regprocedure) cfg`);
    ok("area_heat_map(): SECURITY DEFINER with a pinned search_path", hm && hm.sd && /search_path=public/.test(hm.cfg ?? ""));
    ok("area_heat_map(): only a role with area.view, only a verified venue",
      hm && /venue_can\(vid, auth\.uid\(\), 'area\.view'\)/.test(hm.d) && /not v\.verified/.test(hm.d));
    ok("area_heat_map(): counts only people who said yes to BOTH trends and nights out",
      hm && (hm.d.match(/share_trends and p\.share_nights_out/g) ?? []).length >= 2);
    ok("area_heat_map(): a cell needs 5+ people AND 3+ venues", hm && /count\(distinct c\.user_id\) >= 5 and count\(distinct c\.venue_id\) >= 3/.test(hm.d));
    ok("area_heat_map(): spend needs the caller's AND each venue's yes (give to get), in bands",
      hm && /where v\.area_share/.test(hm.d) && /vc\.area_share/.test(hm.d) && /spend_band_floor/.test(hm.d));
    ok("area_heat_map(): every figure rounded down to 5s, nothing under 5", hm && /\(a\.n \/ 5\) \* 5/.test(hm.d) && /where a\.n >= 5/.test(hm.d));
    ok("area_heat_map(): fixed windows of whole days", hm && /when days_back <= 7 then 7 when days_back <= 30 then 30 else 90/.test(hm.d) && /< current_date/.test(hm.d));
    ok("area_heat_map(): returns no person and no venue", hm && !/returns table \([^)]*(user_id|venue_id|name)/i.test(hm.d));
    ok("area_heat_map(): nothing about age, gender or religion", hm && !/\b(birth|age_|gender|sex|religio|caste)/i.test(hm.d));
    const optin = await all(`select table_name, column_name, column_default from information_schema.columns
      where table_schema = 'public' and ((table_name = 'profiles' and column_name = 'share_nights_out') or (table_name = 'venues' and column_name = 'area_share'))`);
    ok("both opt-ins exist and default to OFF", optin.length === 2 && optin.every((r) => r.column_default === "false"));
    const gg = await one(`select pg_get_functiondef('public.venues_guard_geohash()'::regprocedure) d`);
    ok("a verified venue can't move to another area", gg && /left\(new\.geohash, 4\) <> left\(old\.geohash, 4\)/.test(gg.d));
    const gc = await one(`select pg_get_constraintdef(oid) d from pg_constraint where conname = 'venues_geohash_chars'`);
    ok("a venue's location is a real geohash, not free text", Boolean(gc));
    const bands = await one(`select public.spend_band_floor(1200, 'INR') a, public.spend_band_floor(400, 'INR') b, public.spend_band_floor(60, 'USD') c`);
    ok("spend_band_floor() matches money.ts", bands && Number(bands.a) === 1000 && Number(bands.b) === 0 && Number(bands.c) === 50);
    const at = await one(`select pg_get_functiondef('public.area_taste_trends(text,integer)'::regprocedure) d`);
    ok("area_taste_trends(): still consenting-only, k ≥ 5, matched on the ~40 km cell",
      at && /p\.share_trends/.test(at.d) && />= 5/.test(at.d) && /left\(p\.trends_geo, 4\) = left\(trim\(in_geo\), 4\)/.test(at.d));
  }

  // ── outside signals (049): public facts about places, never people ──────────
  if (!fns.includes("venue_area_signals")) {
    console.log("  ~ outside signals (049) not applied — skipping");
  } else {
    console.log("\n── outside signals: places and happenings, never people (049) ──");
    const rls = await one(`select relrowsecurity r from pg_class where oid = 'public.area_signals'::regclass`);
    ok("area_signals: RLS on", rls && rls.r === true);
    const pol = await one(`select count(*)::int n from pg_policies where schemaname = 'public' and tablename = 'area_signals'`);
    ok("area_signals: no client policy at all (server-only writes, reads via a function)", pol && pol.n === 0);
    const cols = (await all(`select column_name c from information_schema.columns where table_schema = 'public' and table_name = 'area_signals'`)).map((r) => r.c);
    ok("area_signals: no column that could hold a person", cols.length > 0 && !cols.some((c) => /user|profile|author|person|email|phone|handle|name/.test(c)), `— ${cols.join(", ")}`);
    const g = await one(`select pg_get_functiondef('public.area_signals_guard()'::regprocedure) d`);
    ok("area_signals_guard(): refuses emails, phone numbers, @handles and personal fact keys",
      g && /email address/.test(g.d) && /phone number/.test(g.d) && /@handle/.test(g.d) && /jsonb_object_keys/.test(g.d));
    const trg = await one(`select count(*)::int n from pg_trigger where tgrelid = 'public.area_signals'::regclass and tgname = 'area_signals_guard'`);
    ok("area_signals_guard fires on insert and update", trg && trg.n === 1);
    const rd = await one(`select pg_get_functiondef('public.venue_area_signals(uuid,integer)'::regprocedure) d`);
    ok("venue_area_signals(): the venue's own staff, a verified venue, its own area, unexpired",
      rd && /is_venue_staff\(vid, auth\.uid\(\)\)/.test(rd.d) && /not v\.verified/.test(rd.d) && /s\.area = left\(v\.geohash, 4\)/.test(rd.d) && /expires_at > now\(\)/.test(rd.d));
  }

  // ── the counter (050): stock, sales, and the law on a bottle ────────────────
  if (!fns.includes("ring_sale")) {
    console.log("  ~ the counter (050) not applied — skipping");
  } else {
    console.log("\n── the counter: stock, sales, and the law on a bottle (050) ──");
    const writes = await all(`select tablename, cmd from pg_policies where schemaname = 'public'
      and tablename in ('stock_moves', 'shop_sales', 'shop_sale_lines') and cmd <> 'SELECT'`);
    ok("stock_moves, shop_sales, shop_sale_lines: no client write policy (functions only)", writes.length === 0,
      `— ${writes.map((w) => `${w.tablename}:${w.cmd}`).join(", ")}`);
    const rs = await one(`select pg_get_functiondef('public.ring_sale(uuid,uuid,jsonb,text,boolean)'::regprocedure) d`);
    ok("ring_sale(): needs payments.take", rs && /venue_can\(vid, auth\.uid\(\), 'payments\.take'\)/.test(rs.d));
    ok("ring_sale(): the SERVER prices every line (p.price), never the till", rs && /p\.price \* q/.test(rs.d) && !/l->>'price'/.test(rs.d));
    ok("ring_sale(): alcohol needs a researched state, open hours, an ID check and the per-sale limit",
      rs && /store_sale_status/.test(rs.d) && /not st\.researched or not st\.allowed_now/.test(rs.d) && /check ID first/.test(rs.d) && /max_ml/.test(rs.d));
    const ss = await one(`select pg_get_functiondef('public.store_sale_status(uuid)'::regprocedure) d`);
    ok("store_sale_status(): no retail rule → no alcohol (deny-by-default), dry days stop it all day",
      ss && /r\.country is null/.test(ss.d) && /dry_days/.test(ss.d));
    const mrp = await all(`select pg_get_constraintdef(oid) d from pg_constraint where conrelid = 'public.shop_products'::regclass`);
    ok("shop_products: a price can never exceed the MRP", mrp.some((c) => /price <= mrp/.test(c.d)));
    const pg2 = await one(`select pg_get_functiondef('public.shop_products_guard()'::regprocedure) d`);
    ok("a shop that sells no alcohol can't list any", pg2 && /venue_legal_class/.test(pg2.d) && /no_alcohol/.test(pg2.d));
    const saleCols = (await all(`select column_name c from information_schema.columns where table_schema = 'public' and table_name = 'shop_sales'`)).map((r) => r.c);
    ok("shop_sales: no guest column — the till sells to \"a customer\"", saleCols.length > 0 && !saleCols.some((c) => /guest|customer|subject|user_id/.test(c)), `— ${saleCols.join(", ")}`);
    ok("shop_sales: an alcohol sale can't exist without an ID check", (await all(`select pg_get_constraintdef(oid) d from pg_constraint where conrelid = 'public.shop_sales'::regclass`)).some((c) => /has_alcohol/.test(c.d) && /id_checked/.test(c.d)));
    const ruleWrites = await all(`select tablename from pg_policies where schemaname = 'public' and tablename in ('retail_alcohol_rules', 'dry_days') and cmd <> 'SELECT'`);
    ok("retail rules and dry days are written out-of-band only", ruleWrites.length === 0);
    const unsourced = await one(`select (select count(*) from public.retail_alcohol_rules where char_length(trim(source)) < 5)
      + (select count(*) from public.dry_days where char_length(trim(source)) < 5) n`);
    ok("every retail rule and dry day cites its source", unsourced && Number(unsourced.n) === 0);
  }

  // ── service (051): the floor, tabs, stations, the bill, the table link ──────
  if (!fns.includes("close_tab")) {
    console.log("  ~ service (051) not applied — skipping");
  } else {
    console.log("\n── service: tabs, stations, bills, the table link (051) ──");
    const w = await all(`select tablename, cmd from pg_policies where schemaname = 'public'
      and tablename in ('tabs', 'order_lines', 'tab_payments', 'order_requests', 'table_calls') and cmd <> 'SELECT'`);
    ok("tabs, lines, payments, requests, calls: no client write policy (functions only)", w.length === 0, `— ${w.map((x) => `${x.tablename}:${x.cmd}`).join(", ")}`);
    const al = await one(`select pg_get_functiondef('public.add_order_lines(uuid,jsonb,text)'::regprocedure) d`);
    ok("add_order_lines(): orders.take; name, price and station copied from the menu; 86'd refused",
      al && /'orders\.take'/.test(al.d) && /m\.price/.test(al.d) && /m\.station/.test(al.d) && /not m\.available/.test(al.d));
    const ct = await one(`select pg_get_functiondef('public.close_tab(uuid,jsonb,numeric)'::regprocedure) d`);
    ok("close_tab(): payments.take; the subtotal is the non-void lines, kept as a snapshot", ct && /'payments\.take'/.test(ct.d) && /status <> 'void'/.test(ct.d) && /subtotal = sub/.test(ct.d));
    const vl = await one(`select pg_get_functiondef('public.void_line(uuid,text)'::regprocedure) d`);
    ok("void_line(): a reason always; your own fresh line, or a supervisor", vl && /char_length\(trim\(coalesce\(reason/.test(vl.d) && /orders\.void_own/.test(vl.d) && /orders\.approve/.test(vl.d));
    const sl = await one(`select pg_get_functiondef('public.set_line_status(uuid,text)'::regprocedure) d`);
    ok("set_line_status(): the bar moves bar tickets, the kitchen kitchen tickets, forward only", sl && /station\.bar/.test(sl.d) && /station\.kitchen/.test(sl.d) && /rank_to <= rank_from/.test(sl.d));
    const ro = await one(`select pg_get_functiondef('public.request_order(text,uuid,jsonb,text)'::regprocedure) d`);
    ok("request_order(): signed in, the venue switched it on, rate-limited — a request, never lines",
      ro && /auth\.uid\(\) is null/.test(ro.d) && /v\.table_service/.test(ro.d) && /interval '20 seconds'/.test(ro.d) && !/insert into public\.order_lines/.test(ro.d));
    const si = await one(`select pg_get_functiondef('public.service_inbox(uuid)'::regprocedure) d`);
    ok("service_inbox(): never returns who asked", si && !/returns table \([^)]*requested_by/.test(si.d) && !/select[^;]*r\.requested_by/.test(si.d));
    const rq = await all(`select policyname, qual from pg_policies where schemaname = 'public' and tablename in ('order_requests', 'table_calls')`);
    ok("a guest reads only their own requests and calls", rq.length === 2 && rq.every((p) => /requested_by = auth\.uid\(\)/.test(p.qual)));
    const wf = await one(`select pg_get_functiondef('public.waitlist_forget()'::regprocedure) d`);
    ok("the waitlist forgets names within a day", wf && /interval '20 hours'/.test(wf.d));
    const ts = await one(`select column_default d from information_schema.columns where table_schema = 'public' and table_name = 'venues' and column_name = 'table_service'`);
    ok("ordering from the table is off until a venue switches it on", ts && ts.d === "false");
    const al2 = await one(`select pg_get_constraintdef(oid) d from pg_constraint where conname = 'venue_menu_items_allergens_check'`);
    ok("menu allergens are the EU's 14", al2 && ["gluten", "crustaceans", "sesame", "lupin", "molluscs"].every((a) => al2.d.includes(a)));
    const tabCols = (await all(`select column_name c from information_schema.columns where table_schema = 'public' and table_name in ('tabs', 'order_lines')`)).map((r) => r.c);
    ok("tabs and lines hold no guest: no user column", !tabCols.some((c) => /guest_id|user_id|subject/.test(c)), `— ${tabCols.join(", ")}`);
  }

  // ── the door (052) ──────────────────────────────────────────────────────────
  if (!fns.includes("door_tick")) {
    console.log("  ~ the door (052) not applied — skipping");
  } else {
    console.log("\n── the door: counts, never people (052) ──");
    const dw = await all(`select cmd from pg_policies where schemaname = 'public' and tablename = 'door_events' and cmd <> 'SELECT'`);
    ok("door_events: no client write policy (door_tick() only)", dw.length === 0);
    const dc = (await all(`select column_name c from information_schema.columns where table_schema = 'public' and table_name = 'door_events'`)).map((r) => r.c);
    ok("door_events: a count and a time — no column that could say who came in", !dc.some((c) => /guest|user_id|name|photo|id_number|subject/.test(c)), `— ${dc.join(", ")}`);
    const dt = await one(`select pg_get_functiondef('public.door_tick(uuid,integer)'::regprocedure) d`);
    ok("door_tick(): the door role (guests.seat), 1 to 12 at a time", dt && /'guests\.seat'/.test(dt.d) && /n < -12 or n > 12/.test(dt.d));
  }

  // ── staff access (053) ──────────────────────────────────────────────────────
  if (!fns.includes("enrol_staff")) {
    console.log("  ~ staff access (053) not applied — skipping");
  } else {
    console.log("\n── staff access: the owner's code, approvals, lock-out, the clock (053) ──");
    for (const f of ["enrol_staff", "reissue_staff_code", "revoke_staff_enrolment", "staff_enrolments_open", "my_staff_enrolments",
                     "claim_staff_enrolment", "approve_staff", "decline_staff", "lock_staff", "unlock_staff", "set_staff_details",
                     "team_roster", "my_staff_status", "staff_history", "clock_in", "clock_out", "end_staff_shift", "my_shift", "shift_hours"]) {
      ok(`fn ${f}()`, fns.includes(f), "— MISSING");
    }
    const sc = await one(`select pg_get_constraintdef(oid) d from pg_constraint where conname = 'venue_staff_status_check'`);
    ok("venue_staff.status is pending | active | locked", sc && /pending/.test(sc.d) && /active/.test(sc.d) && /locked/.test(sc.d));
    for (const f of ["is_venue_staff(uuid,uuid)", "is_venue_manager(uuid,uuid)", "venue_role(uuid,uuid)"]) {
      const d = await one(`select pg_get_functiondef('public.${f}'::regprocedure) d`);
      ok(`${f.split("(")[0]}(): only ACTIVE staff count, so a lock-out stops everything`, d && /status = 'active'/.test(d.d));
    }
    const enPol = await all(`select policyname from pg_policies where schemaname='public' and tablename='staff_enrolments'`);
    ok("staff_enrolments: no policies at all (a code's hash never leaves the database)", enPol.length === 0);
    const enCols = (await all(`select column_name c from information_schema.columns where table_schema='public' and table_name='staff_enrolments'`)).map((r) => r.c);
    ok("staff_enrolments: the code is kept only as a hash", enCols.includes("code_hash") && !enCols.includes("code"));
    for (const tb of ["staff_events", "staff_shifts", "staff_details"]) {
      const w = await all(`select policyname from pg_policies where schemaname='public' and tablename=$1 and cmd <> 'SELECT'`, [tb]);
      ok(`${tb}: no client write policy (functions and the trigger only)`, w.length === 0);
    }
    const cr = await one(`select pg_get_function_result('public.claim_staff_enrolment(uuid,text)'::regprocedure) r`);
    ok("claim_staff_enrolment() returns a result, so a wrong try is counted, not rolled back", cr && cr.r === "jsonb");
    ok("every roster change is written to the history by a trigger",
      !!(await one(`select 1 from pg_trigger where tgname = 'venue_staff_log' and not tgisinternal`)));
    const ai = await one(`select pg_get_functiondef('public.accept_staff_invite(text)'::regprocedure) d`);
    ok("accept_staff_invite(): joins as PENDING, a manager's yes comes first", ai && /'pending'/.test(ai.d));
    const rd = await one(`select qual from pg_policies where schemaname='public' and tablename='venue_staff' and policyname='venue_staff_read'`);
    ok("venue_staff: a paused or waiting person can read their own row", rd && /user_id = auth\.uid\(\)/.test(rd.qual));
    const vu = await all(`select policyname from pg_policies where schemaname='public' and tablename='venue_staff' and cmd = 'UPDATE'`);
    ok("venue_staff: still no update policy (status and role change through functions)", vu.length === 0);
    for (const f of ["room_staff(uuid)", "thank_staff(uuid,uuid,text)"]) {
      const d = await one(`select pg_get_functiondef('public.${f}'::regprocedure) d`);
      ok(`${f.split("(")[0]}(): thanks go to active staff only`, d && /status = 'active'/.test(d.d));
    }
    const sh = await one(`select pg_get_functiondef('public.shift_hours(uuid,timestamptz)'::regprocedure) d`);
    ok("shift_hours(): listed by name, never ranked by hours", sh && /order by 2/.test(sh.d) && !/order by[^;]*minutes/i.test(sh.d));
  }

  // ── the rota, breaks and payroll (054) ────────────────────────────────────
  if (!fns.includes("payroll_days")) {
    console.log("  ~ the rota, breaks and payroll (054) not applied — skipping");
  } else {
    console.log("\n── the rota, breaks, corrections, pay and payroll (054) ──");
    for (const f of ["rota_save_shift", "rota_delete_shift", "rota_publish", "rota_copy", "rota_week", "rota_offer_shift",
                     "rota_take_shift", "rota_decide_swap", "rota_withdraw_swap", "request_time_off", "decide_time_off",
                     "cancel_time_off", "time_off_list", "set_cannot_work", "start_break", "end_break", "my_shift_state",
                     "staff_timesheet", "correct_shift", "add_missed_shift", "set_break_paid", "set_staff_pay", "pay_rates", "payroll_days"]) {
      ok(`fn ${f}()`, fns.includes(f), "— MISSING");
    }
    for (const tb of ["rota_shifts", "rota_swaps", "time_off", "shift_breaks", "shift_corrections"]) {
      const r = await one(`select relrowsecurity r from pg_class where oid = $1::regclass`, [`public.${tb}`]);
      ok(`${tb}: row-level security on`, r?.r === true);
      const w = await all(`select policyname from pg_policies where schemaname='public' and tablename=$1 and cmd <> 'SELECT'`, [tb]);
      ok(`${tb}: no client write policy (functions only)`, w.length === 0);
    }
    const touch = await all(`
      select p.proname from pg_proc p join pg_namespace n on n.oid = p.pronamespace
      where n.nspname = 'public' and p.prokind = 'f'
        and pg_get_functiondef(p.oid) ~* '(update\\s+public\\.shift_corrections|delete\\s+from\\s+public\\.shift_corrections)'`);
    ok("shift corrections are append-only: no function updates or deletes one", touch.length === 0,
      `— ${touch.map((r) => r.proname).join(", ")}`);
    const pd = await one(`select pg_get_functiondef('public.payroll_days(uuid,date,date,text)'::regprocedure) d`);
    ok("payroll_days(): owners and managers only (team.manage)", pd && /'team\.manage'/.test(pd.d));
    ok("payroll_days(): in name order, never ranked by hours or pay", pd && /order by 2, 4/.test(pd.d) && !/order by[^;]*(worked|pay|minutes)/i.test(pd.d));
    const sh = await one(`select pg_get_functiondef('public.shift_hours(uuid,timestamptz)'::regprocedure) d`);
    ok("shift_hours(): unpaid breaks come off, still listed by name", sh && /shift_minutes/.test(sh.d) && /order by 2/.test(sh.d));
    const cs = await one(`select pg_get_functiondef('public.correct_shift(uuid,timestamptz,timestamptz,text)'::regprocedure) d`);
    ok("correct_shift(): nobody corrects their own times, and a reason is required", cs && /own times/.test(cs.d) && /say why/.test(cs.d));
    const sp = await one(`select pg_get_functiondef('public.set_staff_pay(uuid,uuid,numeric)'::regprocedure) d`);
    ok("set_staff_pay(): nobody sets their own pay; the history never records the amount",
      sp && /own pay/.test(sp.d) && /'pay_changed', '\{\}'/.test(sp.d));
    ok("start_break(): nobody marks their own break paid (no 'paid' argument)",
      !(await one(`select to_regprocedure('public.start_break(uuid,boolean)') f`))?.f && !!(await one(`select to_regprocedure('public.start_break(uuid)') f`))?.f);
    const bp = await one(`select pg_get_functiondef('public.set_break_paid(uuid,boolean)'::regprocedure) d`);
    ok("set_break_paid(): never your own; the same people who correct times",
      bp && /own pay/.test(bp.d) && /can_correct_times/.test(bp.d) && /'break_changed'/.test(bp.d));
    const inv = await one(`select prosecdef d from pg_proc where oid = 'public.shift_minutes(uuid,timestamptz,timestamptz)'::regprocedure`);
    ok("shift_minutes(): runs as the caller (SECURITY INVOKER)", inv && inv.d === false);
    for (const f of ["public.shift_minutes(uuid,timestamptz,timestamptz)", "public.can_correct_times(uuid,uuid,uuid)"]) {
      const g = await one(`select has_function_privilege('authenticated', $1, 'EXECUTE') a,
                                  coalesce((select has_function_privilege('anon', $1, 'EXECUTE')), false) b`, [f]);
      ok(`${f.split("(")[0].replace("public.", "")}(): not callable from an app`, g && !g.a && !g.b);
    }
    for (const tg of ["staff_shift_closed", "staff_shift_rate", "venue_staff_left_rota"]) {
      ok(`trigger ${tg}`, !!(await one(`select 1 from pg_trigger where tgname = $1 and not tgisinternal`, [tg])));
    }
    const rp = await one(`select qual from pg_policies where schemaname='public' and tablename='rota_shifts' and policyname='rota_shifts_read'`);
    ok("rota_shifts: the team reads the PUBLISHED rota; drafts are the planners'", rp && /published_at IS NOT NULL/i.test(rp.qual) && /rota\.edit/.test(rp.qual));
    const kc = await one(`select pg_get_constraintdef(oid) d from pg_constraint where conname = 'staff_events_kind_check'`);
    ok("the team's history knows rota, swap, time-off, correction, break and pay changes",
      kc && ["rota_published", "swap_decided", "time_off_decided", "shift_corrected", "shift_added", "pay_changed", "break_changed"].every((k) => kc.d.includes(k)));
  }

  // Supabase keeps extensions (pgcrypto…) in the `extensions` schema. A public function
  // pinned to search_path=public that calls one unqualified works on a laptop and fails
  // in production. None may.
  // (OFFSET 0 keeps the schema filter first: pg_get_functiondef() refuses aggregates.)
  const unq = await all(`
    select f.proname from (
      select p.oid, p.proname from pg_proc p join pg_namespace n on n.oid = p.pronamespace
      where n.nspname = 'public' and p.prokind = 'f' offset 0
    ) f
    where pg_get_functiondef(f.oid) ~ '(^|[^.])(gen_random_bytes|digest|crypt|gen_salt|hmac)\\s*\\('`);
  ok("no public function calls a pgcrypto function without its schema", unq.length === 0,
    `— ${unq.map((r) => r.proname).join(", ")}`);

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
