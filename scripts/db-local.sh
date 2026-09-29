#!/usr/bin/env bash
# Build a THROWAWAY Postgres, apply supabase/schema.sql + every numbered migration in
# order, then run db:audit and db:verify against it. Nothing here touches a real project.
#
# Why: `npm run db:audit` / `db:verify` need the live database's URL, so they only run
# where that secret exists. This runs the same checks on a fresh local copy of the schema,
# so a migration is proven to apply cleanly — and the security rules proven to hold —
# before the maintainer ever runs it for real. Needs the Postgres server binaries
# (initdb, pg_ctl): `apt install postgresql` on Linux, `brew install postgresql` on a Mac.
#
#   npm run db:local                  # apply everything, audit, verify, tear down
#   DB_LOCAL_KEEP=1 npm run db:local  # …and leave it running (prints the URL)
#   DB_LOCAL_ONLY_APPLY=1 npm run db:local   # apply the migrations, skip the checks
set -euo pipefail

cd "$(dirname "$0")/.."

PGBIN="${PGBIN:-}"
if [[ -z "$PGBIN" ]]; then
  if command -v pg_ctl >/dev/null 2>&1; then
    PGBIN="$(dirname "$(command -v pg_ctl)")"
  else
    PGBIN="$(ls -d /usr/lib/postgresql/*/bin 2>/dev/null | sort -V | tail -1 || true)"
  fi
fi
if [[ -z "$PGBIN" || ! -x "$PGBIN/initdb" ]]; then
  echo "Postgres server binaries not found. Install postgresql, or set PGBIN=/path/to/bin." >&2
  exit 1
fi

PORT="${DB_LOCAL_PORT:-54329}"
DIR="${DB_LOCAL_DIR:-$(mktemp -d)}"
URL="postgresql://postgres@127.0.0.1:${PORT}/postgres?sslmode=disable"

# initdb refuses to run as root; CI runners and dev containers often are root.
mkdir -p "$DIR"
RUN=()
if [[ "$(id -u)" == "0" ]]; then
  id postgres >/dev/null 2>&1 || useradd -m postgres
  chown -R postgres "$DIR"
  RUN=(sudo -u postgres)
  command -v sudo >/dev/null 2>&1 || RUN=(su postgres -c)
fi
as_pg() {
  if [[ ${#RUN[@]} -eq 0 ]]; then "$@";
  elif [[ "${RUN[0]}" == "su" ]]; then su postgres -c "$(printf '%q ' "$@")";
  else "${RUN[@]}" "$@"; fi
}

stop() {
  if [[ "${DB_LOCAL_KEEP:-}" != "1" ]]; then
    as_pg "$PGBIN/pg_ctl" -D "$DIR/data" -m immediate -w stop >/dev/null 2>&1 || true
    rm -rf "$DIR"
  fi
}
trap stop EXIT

if "$PGBIN/pg_isready" -h 127.0.0.1 -p "$PORT" >/dev/null 2>&1; then
  echo "Something is already listening on port $PORT — stop it, or set DB_LOCAL_PORT." >&2
  exit 1
fi

echo "── a throwaway Postgres in $DIR (port $PORT)"
as_pg "$PGBIN/initdb" -D "$DIR/data" -U postgres --auth=trust -E UTF8 >/dev/null
as_pg "$PGBIN/pg_ctl" -D "$DIR/data" -l "$DIR/log" -o "-p $PORT -k $DIR -c listen_addresses=127.0.0.1" -w start >/dev/null

PSQL=(psql "$URL" -X -q -v ON_ERROR_STOP=1)

echo "── Supabase stand-ins (auth, storage, roles)"
"${PSQL[@]}" -f scripts/db-local/supabase-stubs.sql >/dev/null

echo "── the schema, then every migration in order"
"${PSQL[@]}" --single-transaction -f supabase/schema.sql >/dev/null
for f in $(ls supabase/[0-9][0-9][0-9]_*.sql | sort); do
  if ! "${PSQL[@]}" --single-transaction -f "$f" >"$DIR/last.out" 2>&1; then
    echo "  ✗ $f"
    cat "$DIR/last.out"
    exit 1
  fi
  echo "  ✓ $f"
done

if [[ "${DB_LOCAL_ONLY_APPLY:-}" != "1" ]]; then
  echo "── db:audit"
  SUPABASE_DB_URL="$URL" node scripts/db-audit.mjs
  echo "── db:verify"
  SUPABASE_DB_URL="$URL" node scripts/verify-flow.mjs
fi

if [[ "${DB_LOCAL_KEEP:-}" == "1" ]]; then
  echo
  echo "Left running: $URL"
  echo "Stop it with: $PGBIN/pg_ctl -D $DIR/data stop"
fi
