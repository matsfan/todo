#!/usr/bin/env bash
# .bob/hooks/ibmi-post-stop.sh
#
# Bob Stop hook — runs automatically after Bob finishes implementation work.
# Deploys the current local branch to pub400 and compiles all objects.
# Output is appended to .bob/logs/ibmi-build.log.
#
# Credentials are read from .env at the repo root (see .env.example).
# If .env is missing or incomplete the scripts fail with a clear error message.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
LOG_DIR="${REPO_ROOT}/.bob/logs"
LOG_FILE="${LOG_DIR}/ibmi-build.log"

mkdir -p "$LOG_DIR"

# Determine the branch currently checked out locally — this is what the deploy
# script will instruct pub400 to check out.
BRANCH=$(git -C "$REPO_ROOT" symbolic-ref --short HEAD 2>/dev/null || git -C "$REPO_ROOT" rev-parse --short HEAD)

echo "=== IBM i deploy+compile: $(date '+%Y-%m-%d %H:%M:%S') branch=${BRANCH} ===" | tee -a "$LOG_FILE"

bash "${REPO_ROOT}/scripts/ibmi-deploy.sh"  "$BRANCH"  2>&1 | tee -a "$LOG_FILE"
bash "${REPO_ROOT}/scripts/ibmi-compile.sh"            2>&1 | tee -a "$LOG_FILE"

echo "=== Done: $(date '+%Y-%m-%d %H:%M:%S') ===" | tee -a "$LOG_FILE"
