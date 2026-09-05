#!/usr/bin/env bash
set -euo pipefail

if [ -z "${1:-}" ]; then
  echo "Usage: $0 <pub400-username> [ssh-identity-file]" >&2
  exit 1
fi

USER="$1"
IDENTITY="${2:-}"
IFS_ROOT="/home/$USER/source/todo"
PORT="${IBMI_SSH_PORT:-2222}"

SSH_OPTS=(-p "$PORT" -o BatchMode=yes -o StrictHostKeyChecking=accept-new)
if [ -n "$IDENTITY" ]; then
  SSH_OPTS+=(-i "$IDENTITY")
fi

# Builds via TOBi (makei), driven by the project's iproj.json/Rules.mk files,
# instead of the hand-maintained delete-everything-and-recompile-all CL
# sequence this script used before - see docs/plans/cicd-pipeline-plan.md
# Sub-Task 7. makei build is dependency-aware: it only rebuilds objects whose
# source (or dependencies) changed since the last run.
ssh "${SSH_OPTS[@]}" "${USER}@pub400.com" <<ENDSSH
set -e

# Non-interactive SSH sessions don't always source .profile/.bashrc, so PATH may
# not include the Open Source package dir where makei actually lives.
export PATH="/QOpenSys/pkgs/bin:\$PATH"

cd "${IFS_ROOT}"
OPT=*EVENTF BUILDLIB=*CURLIB makei build

echo "Compile complete."
ENDSSH
