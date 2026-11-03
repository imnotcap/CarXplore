#!/usr/bin/env bash
# Kører migrationerne mod en tom Postgres-database og tester venne-backenden.
# Brug PGHOST/PGPORT/PGUSER/PGPASSWORD til at pege på serveren.
set -euo pipefail
cd "$(dirname "$0")/../.."
DB=carxplore_test
dropdb --if-exists "$DB"
createdb "$DB"
psql -d "$DB" -v ON_ERROR_STOP=1 -q \
  -f supabase/tests/supabase_stub.sql \
  $(printf -- '-f %s ' supabase/migrations/*.sql) \
  -f supabase/tests/friends_test.sql
