#!/usr/bin/env bash
# The guest app, LIVE, against a THROWAWAY Supabase on this machine — the real thing,
# not a stand-in: Postgres with schema.sql + every migration, Supabase Auth (the
# emailed codes land in a local mailbox), the API, photo storage, and the website for
# its server routes (account deletion). Then test_m_app/test/live walks every flow
# with real accounts: sign-up by code, a drink with a photo, friends, the feed,
# circles, parties, plans, Split, the bar's table menu, taste at the table, ordering
# from the table, export, and deleting the account.
#
# Nothing here touches a real project: the keys are the Supabase CLI's public
# local-only ones, and it all goes away at the end.
#
#   npm run live:local               # start, load, test, tear down
#   LIVE_KEEP=1 npm run live:local   # …and leave it running (prints the addresses)
#
# Needs Docker (running), Node, psql and Flutter. First run pulls the Supabase images
# (a few minutes, ~2 GB).
set -euo pipefail

cd "$(dirname "$0")/.."
WORK="${LIVE_DIR:-$(mktemp -d)}"
SITE_PORT="${LIVE_SITE_PORT:-3010}"
# Images come from Supabase's own registry mirror (public.ecr.aws) by default — no
# Docker Hub rate limits. SUPABASE_INTERNAL_IMAGE_REGISTRY=docker.io switches to Docker Hub.

for tool in docker npx psql flutter; do
  command -v "$tool" >/dev/null 2>&1 || { echo "needs $tool on PATH" >&2; exit 1; }
done
docker info >/dev/null 2>&1 || { echo "Docker isn't running — start it first." >&2; exit 1; }
if curl -s -o /dev/null "http://127.0.0.1:54321"; then
  echo "Something already answers on 127.0.0.1:54321 (another local Supabase?) — stop it first." >&2
  exit 1
fi

SITE_PID=""
stop() {
  [[ -n "$SITE_PID" ]] && kill "$SITE_PID" >/dev/null 2>&1 || true
  if [[ "${LIVE_KEEP:-}" != "1" ]]; then
    (cd "$WORK" && npx --yes supabase@2 stop --no-backup >/dev/null 2>&1) || true
    rm -rf "$WORK"
  fi
}
trap stop EXIT

echo "── a throwaway Supabase in $WORK"
mkdir -p "$WORK/supabase/templates"
cp supabase/templates/*.html "$WORK/supabase/templates/"
(cd "$WORK" && npx --yes supabase@2 init --force >/dev/null)
# The sign-in emails carry the 6-digit code — the same templates the real project uses.
cat >>"$WORK/supabase/config.toml" <<'EOF'

[auth.email.template.magic_link]
subject = "Your brewdiary code"
content_path = "./supabase/templates/magic_link.html"

[auth.email.template.confirmation]
subject = "Your brewdiary code"
content_path = "./supabase/templates/confirmation.html"
EOF
(cd "$WORK" && npx --yes supabase@2 start -x studio,edge-runtime,logflare,vector,supavisor,postgres-meta,imgproxy,realtime >/dev/null)
eval "$(cd "$WORK" && npx --yes supabase@2 status -o env 2>/dev/null | grep -E '^(API_URL|ANON_KEY|SERVICE_ROLE_KEY|DB_URL|MAILPIT_URL)=')"

echo "── the schema, then every migration in order"
PSQL=(psql "$DB_URL" -X -q -v ON_ERROR_STOP=1)
"${PSQL[@]}" --single-transaction -f supabase/schema.sql >/dev/null
for f in $(ls supabase/[0-9][0-9][0-9]_*.sql | sort); do
  if ! "${PSQL[@]}" --single-transaction -f "$f" >"$WORK/last.out" 2>&1; then
    echo "  ✗ $f"; cat "$WORK/last.out"; exit 1
  fi
done

echo "── the website (its server routes), on :$SITE_PORT"
NEXT_PUBLIC_SUPABASE_URL="$API_URL" NEXT_PUBLIC_SUPABASE_ANON_KEY="$ANON_KEY" SUPABASE_SERVICE_ROLE_KEY="$SERVICE_ROLE_KEY" \
  npx next dev -p "$SITE_PORT" >"$WORK/site.log" 2>&1 &
SITE_PID=$!
for _ in $(seq 1 90); do
  curl -s -o /dev/null "http://127.0.0.1:$SITE_PORT/api/account/delete" -X POST && break
  sleep 2
done

echo "── the guest app, live"
(cd test_m_app && flutter test test/live \
  --dart-define=SUPABASE_URL="$API_URL" \
  --dart-define=SUPABASE_ANON_KEY="$ANON_KEY" \
  --dart-define=MAILPIT_URL="$MAILPIT_URL" \
  --dart-define=LIVE_DB_URL="$DB_URL" \
  --dart-define=SITE_URL="http://127.0.0.1:$SITE_PORT")

if [[ "${LIVE_KEEP:-}" == "1" ]]; then
  echo "── left running: API $API_URL · mailbox $MAILPIT_URL · site http://127.0.0.1:$SITE_PORT · db $DB_URL"
  echo "   stop with: (cd $WORK && npx supabase stop --no-backup)"
  SITE_PID=""
fi
