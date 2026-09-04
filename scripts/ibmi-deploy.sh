#!/usr/bin/env bash
set -euo pipefail

if [ -z "${1:-}" ]; then
  echo "Usage: $0 <pub400.com username> [git-ref] [ssh-identity-file]" >&2
  echo "  git-ref            branch, tag, or commit SHA to deploy (default: main)" >&2
  echo "  ssh-identity-file  path to a private key (default: use ssh-agent/default keys)" >&2
  exit 1
fi

USER="$1"
REF="${2:-main}"
IDENTITY="${3:-}"
IFS_ROOT="/home/$USER/source/todo"
REPO_URL="https://github.com/matsfan/todo.git"
PORT="${IBMI_SSH_PORT:-2222}"

SSH_OPTS=(-p "$PORT" -o BatchMode=yes -o StrictHostKeyChecking=accept-new)
if [ -n "$IDENTITY" ]; then
  SSH_OPTS+=(-i "$IDENTITY")
fi

# Pulls source directly from GitHub on pub400 itself (git is available at
# /QOpenSys/pkgs/bin/git there) instead of scp-ing local files. This means what
# gets compiled always matches an exact, known git commit, and a bad deploy can be
# rolled back with `git checkout <previous-good-sha>` instead of a separate backup.
#
# NOTE: git clean -fdx wipes anything not tracked/committed in $IFS_ROOT on pub400.
# Don't use this directory as a scratch space for ad-hoc edits between deploys.
ssh "${SSH_OPTS[@]}" "${USER}@pub400.com" <<ENDSSH
set -e

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

git checkout "${REF}"
git reset --hard "${REF}"
git clean -fdx

echo "Deployed \$(git rev-parse HEAD) (${REF}) to ${IFS_ROOT}"
ENDSSH
