#!/usr/bin/env bash
set -euo pipefail

# ---------------------------------------------------------------------------
# Credentials — sourced from .env at the repo root (git-ignored).
# Required variables: IBMI_USER, IBMI_IDENTITY
# Optional variable:  IBMI_SSH_PORT (default: 2222)
# See .env.example for the format.
# ---------------------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="${SCRIPT_DIR}/../.env"
if [ -f "$ENV_FILE" ]; then
  # shellcheck source=/dev/null
  source "$ENV_FILE"
fi

USER="${IBMI_USER:?'.env must set IBMI_USER'}"
IDENTITY="${IBMI_IDENTITY:?'.env must set IBMI_IDENTITY'}"
REF="${1:-main}"
IFS_ROOT="/home/$USER/source/todo"
REPO_URL="https://github.com/matsfan/todo.git"
PORT="${IBMI_SSH_PORT:-2222}"

SSH_OPTS=(-p "$PORT" -o BatchMode=yes -o StrictHostKeyChecking=accept-new -i "$IDENTITY")

# Pulls source directly from GitHub on pub400 itself (git is available at
# /QOpenSys/pkgs/bin/git there) instead of scp-ing local files. This means what
# gets compiled always matches an exact, known git commit, and a bad deploy can be
# rolled back with `git checkout <previous-good-sha>` instead of a separate backup.
#
# NOTE: git clean -fdx wipes anything not tracked/committed in $IFS_ROOT on pub400.
# Don't use this directory as a scratch space for ad-hoc edits between deploys.
ssh "${SSH_OPTS[@]}" "${USER}@pub400.com" <<ENDSSH
set -euo pipefail

# Non-interactive SSH sessions don't always source .profile/.bashrc, so PATH may
# not include the Open Source package dir where git actually lives — set it
# explicitly rather than relying on shell startup behavior.
export PATH="/QOpenSys/pkgs/bin:\$PATH"

if [ -d "${IFS_ROOT}/.git" ]; then
  echo "Existing checkout found at ${IFS_ROOT} — updating."
  cd "${IFS_ROOT}"
  git fetch origin
else
  echo "No existing checkout — cloning ${REPO_URL} into ${IFS_ROOT}."
  git clone "${REPO_URL}" "${IFS_ROOT}"
  cd "${IFS_ROOT}"
fi

if git rev-parse --verify "origin/${REF}" >/dev/null 2>&1; then
  TARGET="origin/${REF}"
else
  TARGET="${REF}"
fi

git checkout --detach "\$TARGET"
git reset --hard "\$TARGET"
git clean -fdx

echo "Deployed \$(git rev-parse HEAD) (${REF}) to ${IFS_ROOT}"
ENDSSH
