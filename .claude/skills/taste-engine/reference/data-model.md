# brewdiary data model (decided 2026-06-27)

Plain-language + field-level schema for the build. "Stored" = a real record; "Derived" = computed on the
fly from entries, never stored (so it can't drift). Phase tags note when each is needed.

## Core principle
The mosaic, streaks, milestones, mood lexicon, recent-drinks quick-pick, and leaderboards are ALL
**derived** from `entry` rows. Don't store them. The only thing the ritual writes is an `entry`.

## Stored entities

### user  (Phase 2 — Phase 1 is local/anonymous)
- `id`, `handle` (unique), `display_name`, `avatar_url`, `bio?`
- `reminder_enabled` (bool), `reminder_time` (local time), `created_at`
- `connected_socials` (for external share-out)
- Profile visibility: **mutual-friends model** (no public profiles in v1; see `friendship`).

### entry  (Phase 1 — the heart)
- `id`, `user_id`
- **`date`** — the calendar day the entry is FOR (backfillable). The mosaic/streaks count THIS, not `created_at`.
- `created_at`, `updated_at`, `time_of_day` (derived from created_at, editable)
- `drink_name` (text), `drink_type?` (tag: coffee/wine/beer/spirit/other — for shelf filter, NOT mosaic color)
- `mood` (single word string → feeds the user's derived lexicon)
- `note?` (text)
- `venue?` (text) + `place?` (lat/lng or map place_id → tap opens the map app for directions)
- `who_with?` — array of friend `user_id`s + optional free-text names for non-users
- `party_id?` — if set, this entry is part of a party's shared log
- **`visibility`** — see "Sharing" below. **Default: private.**
- `deleted` (soft delete, for edit/undo)
- Multiple logs per day allowed (intensity = count of entries on `date`).

### photo  (Phase 1)  — **several per entry (up to ~4)**
- `id`, `entry_id`, `url`, `sort_order`, `created_at`
- Photo wall = all of a user's photos across entries. Party recap pulls photos of party entries.

### friendship  (Phase 3)  — **mutual**
- `id`, `requester_id`, `addressee_id`, `status` (pending | accepted), `created_at`, `responded_at`
- Friends are symmetric once accepted. No one-way follow, no public profiles in v1.

### circle  (Phase 4)
- `id`, `name`, `avatar?`, `created_by`, `created_at`
- `circle_member` (`circle_id`, `user_id`, `role`: owner|member, `joined_at`)
- Circle feed = entries shared to the circle. Combined circle mosaic = aggregate of members' circle-shared entries.

### party / event  (Phase 4)
- `party` (`id`, `host_id`, `title`, `description?`, `starts_at`, `venue?`+`place?`, `created_at`)
- `party_invite` (`party_id`, `user_id?` OR `invite_token` for link-invites to non-users, `status`:
  invited|going|maybe|declined)
- Shared party log = entries with that `party_id`. Party recap (derived): attendees + all party entries +
  their photos + moods + a party mini-mosaic.

### challenge  (Phase 4 — opt-in, INSIDE circles only)
- `challenge` (`id`, `circle_id`, `type`: streak|most_kinds|most_logged|custom, `title`, `target?`,
  `starts_at`, `ends_at`, `created_by`)
- `challenge_participant` (`challenge_id`, `user_id`, `opted_in_at`)
- Leaderboard = derived from participants' entries within the window. Never shown outside the circle.

### wishlist_item  (Phase 3 — to-try)
- `id`, `user_id`, `drink_name`, `drink_type?`, `note?`
- `source_entry_id?` + `source_user_id?` (if saved from a friend's log)
- `fulfilled_entry_id?` (set when the user actually logs it → marks the to-try done)

### recommendation  (Phase 3)  — **regulars + explicit, combined**
- Two sources feed "things friends loved":
  1. **Derived "regulars":** a friend's frequently/repeatedly logged drinks (no UI, pure frequency).
  2. **Explicit `recommendation` record:** `id`, `from_user_id`, `to_scope` (friend/all-friends),
     `drink_name`, `source_entry_id?`, `created_at` — created when someone taps "recommend" on an entry.
- The user's suggestions blend both signals.

### reaction  (Phase 3)
- `id`, `entry_id`, `user_id`, `type` (just `cheers` for now), `created_at`. One per user per entry.

### comment  (Phase 3)
- `id`, `entry_id`, `user_id`, `body`, `created_at`, `deleted`.

### notification  (Phase 2+)
- `id`, `user_id`, `type` (reminder | friend_request | party_invite | cheers | comment | challenge),
  `payload`, `read`, `created_at`.

## Sharing / visibility (model supports it now; UX finalized later)
`entry.visibility` must express audiences. Use a flexible model, NOT a single on/off:
- Simplest acceptable v1: enum `private | friends | circle:<id> | party:<id>`.
- Preferred (more flexible, allows multi-target like friends AND a circle): a normalized
  `entry_share` (`entry_id`, `audience_type`: friends|circle|party|public, `audience_id?`).
- **Default everywhere: private.** External social share-out is an explicit export action, separate from
  in-app visibility. The full sharing UX (the audience picker) is a deferred discussion.

## Derived (never stored)
streak (consecutive `date`s with ≥1 entry, **grace = one gap forgiven**) · milestones (from total count) ·
mood lexicon (distinct `mood` + counts) · recent-drinks quick-pick (distinct `drink_name` by
frequency/recency) · leaderboards · friend "regulars".
