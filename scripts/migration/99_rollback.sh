#!/usr/bin/env bash
# Rollback plan — truncate Supabase tables imported during migration.
#
# ONLY USE BEFORE REOPENING WRITES TO USERS.
# Once users are operating on Supabase, this script destroys their new data.
#
# Usage:
#   SUPABASE_DB_URL=postgres://... bash scripts/migration/99_rollback.sh
#
# Set SUPABASE_DB_URL to a direct connection string (not pooler) with superuser or
# service role credentials. Example:
#   postgresql://postgres:[password]@db.[project].supabase.co:5432/postgres
#
# Or use psql directly with the Supabase dashboard connection string.

set -euo pipefail

if [[ -z "${SUPABASE_DB_URL:-}" ]]; then
  echo "ERROR: SUPABASE_DB_URL is required"
  echo "  export SUPABASE_DB_URL=postgres://postgres:password@db.xxx.supabase.co:5432/postgres"
  exit 1
fi

echo "======================================================"
echo " RuralTech Migration ROLLBACK"
echo " This will TRUNCATE all migrated tables."
echo " THIS IS DESTRUCTIVE AND IRREVERSIBLE."
echo "======================================================"
read -r -p "Type CONFIRM to proceed: " confirmation
if [[ "$confirmation" != "CONFIRM" ]]; then
  echo "Aborted."
  exit 0
fi

echo "Starting rollback at $(date -u +%Y-%m-%dT%H:%M:%SZ)..."

psql "$SUPABASE_DB_URL" <<'SQL'
-- Disable triggers temporarily to avoid cascade ordering issues
SET session_replication_role = replica;

TRUNCATE TABLE
  public.property_command_events,
  public.property_commands,
  public.property_events,
  public.property_health_history,
  public.property_health_latest,
  public.property_telemetry_history,
  public.property_telemetry_latest,
  public.matrix_command_results,
  public.matrix_command_queues,
  public.matrix_queue_keys,
  public.matrix_bindings,
  public.events,
  public.herding_operations,
  public.herding_plans,
  public.fences,
  public.areas,
  public.collars,
  public.gateways,
  public.rural_properties,
  public.pending_notifications,
  public.user_push_tokens,
  public.profiles
CASCADE;

-- Re-enable triggers
SET session_replication_role = DEFAULT;

SQL

echo "Supabase tables truncated."

echo ""
echo "Next steps:"
echo "  1. Re-deploy the previous app version (Firebase-based)"
echo "  2. Re-configure gateway-matriz with Firebase RTDB host"
echo "  3. Remove the 'audit/remove-firebase-complete' branch from production"
echo ""
echo "Rollback complete at $(date -u +%Y-%m-%dT%H:%M:%SZ)."
