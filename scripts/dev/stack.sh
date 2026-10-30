#!/usr/bin/env bash
# Local demo stack: Postgres 16 + PostgREST + dev gateway, with the demo group loaded.
#   scripts/dev/stack.sh            start (creates and seeds the database the first time)
#   scripts/dev/stack.sh reset      wipe and start again
#   scripts/dev/stack.sh stop
# Then: cd apps/web && cp .env.example .env.local (URL http://localhost:54321, anon key dev-anon) && npm run dev
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
DEV="${DEV_DIR:-$ROOT/.dev}"
PGBIN="${PGBIN:-/usr/lib/postgresql/16/bin}"
PORT=54322
SECRET="dev-jwt-secret-dev-jwt-secret-dev-jwt-secret!"
POSTGREST="${POSTGREST:-postgrest}"
as_pg() { if [ "$(id -u)" = 0 ]; then runuser -u postgres -- "$@"; else "$@"; fi; }
PSQL="psql -X -q -v ON_ERROR_STOP=1 -h $DEV -p $PORT -U postgres -d erp"

stop() {
  [ -f "$DEV/pgrst.pid" ] && kill "$(cat "$DEV/pgrst.pid")" 2>/dev/null || true
  [ -f "$DEV/gateway.pid" ] && kill "$(cat "$DEV/gateway.pid")" 2>/dev/null || true
  [ -d "$DEV/data" ] && as_pg "$PGBIN/pg_ctl" -D "$DEV/data" -m fast stop >/dev/null 2>&1 || true
}

case "${1:-start}" in
  stop) stop; exit 0 ;;
  reset) stop; rm -rf "$DEV" ;;
esac

mkdir -p "$DEV"
chmod 755 "$DEV"
[ "$(id -u)" = 0 ] && chown postgres "$DEV"
FRESH=0
if [ ! -d "$DEV/data" ]; then
  as_pg "$PGBIN/initdb" -D "$DEV/data" -U postgres --auth=trust >/dev/null
  FRESH=1
fi
as_pg "$PGBIN/pg_ctl" -D "$DEV/data" -o "-p $PORT -k $DEV -c listen_addresses=127.0.0.1" -l "$DEV/pg.log" -w start >/dev/null || true

if [ "$FRESH" = 1 ]; then
  psql -X -q -h "$DEV" -p $PORT -U postgres -d postgres -c "create database erp" >/dev/null
  psql -X -q -h "$DEV" -p $PORT -U postgres -d postgres -c "alter database erp set search_path = public, extensions" >/dev/null
  $PSQL -f "$ROOT/supabase/tests/00_supabase_stub.sql"
  $PSQL -c "alter table auth.users add column encrypted_password text; create role authenticator login noinherit; grant anon, authenticated, service_role to authenticator;"
  for f in "$ROOT"/supabase/migrations/*.sql; do PGOPTIONS='-c client_min_messages=warning' $PSQL -o /dev/null -f "$f"; done
  PGOPTIONS='-c client_min_messages=warning' $PSQL -o /dev/null -f "$ROOT/supabase/dev/seed_demo.sql"
  echo "database created and demo data loaded"
fi

cat > "$DEV/pgrst.conf" <<EOF
db-uri = "postgres://authenticator@127.0.0.1:$PORT/erp"
db-schemas = "public"
db-anon-role = "anon"
jwt-secret = "$SECRET"
server-port = 3001
server-host = "127.0.0.1"
EOF
"$POSTGREST" "$DEV/pgrst.conf" > "$DEV/pgrst.log" 2>&1 & echo $! > "$DEV/pgrst.pid"
JWT_SECRET="$SECRET" FILES_DIR="$DEV/files" PSQL="psql -h $DEV -p $PORT -U postgres -d erp" \
  node "$ROOT/scripts/dev/gateway.mjs" > "$DEV/gateway.log" 2>&1 & echo $! > "$DEV/gateway.pid"
sleep 1
echo "API on http://localhost:54321 — sign in as owner@demo.in / demo1234, or mobile 9000000002 / 9000000003 with code 123456"
