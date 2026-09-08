#!/usr/bin/env bash
# .bob/hooks/ibmi-post-stop.sh
# Bob Stop hook — deploy source to pub400 then compile via TOBi.
#
# Receives Bob's hook JSON payload on stdin:
#   {"session_id":"…","cwd":"…","hook_event_name":"Stop","last_assistant_message":…}
#
# All output is appended to $cwd/.bob/logs/ibmi-build.log.
# This script ALWAYS exits 0 so it never blocks or errors the Bob session.

set -uo pipefail

# --- read cwd from Bob's JSON payload ----------------------------------------
payload=$(cat)
cwd=$(printf '%s' "$payload" | grep -o '"cwd":"[^"]*"' | head -1 | sed 's/"cwd":"//;s/"//')

if [ -z "$cwd" ]; then
  # No cwd — nothing we can do; exit silently.
  exit 0
fi

# --- source .env (silent if absent) ------------------------------------------
# shellcheck source=/dev/null
[ -f "$cwd/.env" ] && source "$cwd/.env"

# --- ensure log directory exists ---------------------------------------------
log_dir="$cwd/.bob/logs"
mkdir -p "$log_dir"
log_file="$log_dir/ibmi-build.log"

# --- guard: IBMI_USER must be set --------------------------------------------
if [ -z "${IBMI_USER:-}" ]; then
  printf '[%s] WARNING: IBMI_USER is not set — skipping deploy+compile.\n' \
    "$(date '+%Y-%m-%dT%H:%M:%S%z')" >> "$log_file"
  exit 0
fi

# --- resolve git ref ---------------------------------------------------------
if [ -z "${IBMI_GIT_REF:-}" ]; then
  IBMI_GIT_REF=$(git -C "$cwd" rev-parse --abbrev-ref HEAD 2>/dev/null) || true
  [ -z "$IBMI_GIT_REF" ] && IBMI_GIT_REF="main"
fi

# --- timestamped header ------------------------------------------------------
{
  printf '=%.0s' {1..72}
  printf '\n'
  printf '[%s] ibmi-post-stop: user=%s ref=%s\n' \
    "$(date '+%Y-%m-%dT%H:%M:%S%z')" "$IBMI_USER" "$IBMI_GIT_REF"
  printf '=%.0s' {1..72}
  printf '\n'
} >> "$log_file"

# --- deploy ------------------------------------------------------------------
"$cwd/scripts/ibmi-deploy.sh" "$IBMI_USER" "$IBMI_GIT_REF" "${IBMI_IDENTITY:-}" \
  >> "$log_file" 2>&1
deploy_rc=$?

# --- compile -----------------------------------------------------------------
compile_rc=0
if [ $deploy_rc -eq 0 ]; then
  "$cwd/scripts/ibmi-compile.sh" "$IBMI_USER" "${IBMI_IDENTITY:-}" \
    >> "$log_file" 2>&1
  compile_rc=$?
else
  printf '[deploy failed with rc=%d — compile skipped]\n' "$deploy_rc" >> "$log_file"
fi

# --- footer ------------------------------------------------------------------
overall_rc=$(( deploy_rc != 0 ? deploy_rc : compile_rc ))
if [ $overall_rc -eq 0 ]; then
  printf '[%s] PASS (rc=0)\n' "$(date '+%Y-%m-%dT%H:%M:%S%z')" >> "$log_file"
else
  printf '[%s] FAIL (rc=%d)\n' "$(date '+%Y-%m-%dT%H:%M:%S%z')" "$overall_rc" >> "$log_file"
fi

exit 0
