#!/usr/bin/env bash
# Applies every migration to a throwaway Postgres 16 and runs the SQL tests.
# Usage: scripts/test-db.sh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PGBIN="${PGBIN:-/usr/lib/postgresql/16/bin}"
WORK="$(mktemp -d)"
PORT="${PGPORT_TEST:-54329}"
DB=erp_test

as_pg() { if [ "$(id -u)" = 0 ]; then runuser -u postgres -- "$@"; else "$@"; fi; }

chmod 755 "$WORK"
[ "$(id -u)" = 0 ] && chown postgres "$WORK"
cleanup() { as_pg "$PGBIN/pg_ctl" -D "$WORK/data" -m immediate stop >/dev/null 2>&1 || true; rm -rf "$WORK"; }
trap cleanup EXIT

as_pg "$PGBIN/initdb" -D "$WORK/data" -U postgres --auth=trust >/dev/null
as_pg "$PGBIN/pg_ctl" -D "$WORK/data" -o "-p $PORT -k $WORK -c listen_addresses=''" -l "$WORK/log" -w start >/dev/null

PSQL=(psql -X -q -v ON_ERROR_STOP=1 -h "$WORK" -p "$PORT" -U postgres)
"${PSQL[@]}" -d postgres -c "create database $DB" >/dev/null
"${PSQL[@]}" -d postgres -c "alter database $DB set search_path = public, extensions" >/dev/null

"${PSQL[@]}" -d "$DB" -f "$ROOT/supabase/tests/00_supabase_stub.sql"
for f in "$ROOT"/supabase/migrations/*.sql; do
  echo "migrate $(basename "$f")"
  PGOPTIONS='-c client_min_messages=warning' "${PSQL[@]}" -d "$DB" -o /dev/null -f "$f"
done

for f in "$ROOT"/supabase/tests/[1-9]*.sql; do
  echo "test    $(basename "$f")"
  "${PSQL[@]}" -d "$DB" -f "$f" 2>&1 | sed -n 's/^psql:[^:]*:[0-9]*: NOTICE:  /  /p; s/^NOTICE:  /  /p; /ERROR\|FAIL/p; /^==/p'
  test "${PIPESTATUS[0]}" -eq 0
done
