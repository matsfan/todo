#!/usr/bin/env bash
set -euo pipefail

# ---------------------------------------------------------------------------
# Usage: bash scripts/ibmi-deploy.sh [git-ref]     (git-ref defaults to main)
#
# Everything comes from environment variables -- normally set by the GitHub
# Actions workflow from its GitHub Environment (dev / test / prod). See
# docs/DEPLOY.md, "Environments".
#   IBMI_USER, IBMI_IDENTITY   pub400 profile + SSH key   (repo secrets)
#   IBMI_IFS_DIR               checkout under /home/<user>/source/ for this
#                              environment                (environment variable)
#   IBMI_SSH_PORT              optional, default 2222
#
# Each environment has its own checkout (todo-dev, todo-test, todo-prod) so
# one environment's reset/clean never touches another's working tree
# mid-build. Same profile, same IFS_ROOT parent, different leaf directory.
# ---------------------------------------------------------------------------
USER="${IBMI_USER:?IBMI_USER must be set}"
IDENTITY="${IBMI_IDENTITY:?IBMI_IDENTITY must be set}"
REF="${1:-main}"
IFS_DIR="${IBMI_IFS_DIR:?IBMI_IFS_DIR must be set}"
echo "Deploy target: IFS dir ${IFS_DIR}, ref ${REF}"
IFS_ROOT="/home/$USER/source/${IFS_DIR}"
REPO_URL="https://github.com/matsfan/todo.git"
PORT="${IBMI_SSH_PORT:-2222}"

SSH_OPTS=(-p "$PORT" -o BatchMode=yes -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -i "$IDENTITY")

# Pulls source directly from GitHub on pub400 itself (git is available at
# /QOpenSys/pkgs/bin/git there) instead of scp-ing local files. This means what
# gets compiled always matches an exact, known git commit, and a bad deploy can be
# rolled back with `git checkout <previous-good-sha>` instead of a separate backup.
#
# NOTE: git clean -fdx wipes anything not tracked/committed in $IFS_ROOT on pub400.
# Don't use this directory as a scratch space for ad-hoc edits between deploys.
#
# The script is base64-encoded and passed as a quoted SSH argument rather than
# piped via a heredoc. pub400.com closes connections when stdin is piped in a
# non-interactive SSH session (CI runners, Bob agent) -- the same technique
# ibmi-compile.sh uses.

REMOTE_SCRIPT=$(mktemp)
trap 'rm -f "$REMOTE_SCRIPT"' EXIT

cat > "$REMOTE_SCRIPT" << SCRIPT
set -euo pipefail

# Non-interactive SSH sessions don't always source .profile/.bashrc, so PATH may
# not include the Open Source package dir where git actually lives -- set it
# explicitly rather than relying on shell startup behavior.
export PATH="/QOpenSys/pkgs/bin:\$PATH"

if [ -d "${IFS_ROOT}/.git" ]; then
  echo "Existing checkout found at ${IFS_ROOT} -- updating."
  cd "${IFS_ROOT}"
  git fetch origin
else
  echo "No existing checkout -- cloning ${REPO_URL} into ${IFS_ROOT}."
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
SCRIPT

# pub400.com blocks SSH commands that name 'bash' as the explicit remote
# command (connection closed, exit 255). The workaround: have the default
# login shell (ksh on PASE) decode the script into a temp file, then exec
# it with the full-path bash. All constructs used here are POSIX sh/ksh safe.
#
# pub400.com also rate-limits rapid SSH connections from the same IP (e.g.
# GitHub Actions runners firing multiple CI jobs in quick succession). Retry
# up to 5 times with 30-second gaps before giving up.
FULL_B64=$(base64 < "$REMOTE_SCRIPT" | tr -d '\n')
SSH_CMD="export PATH=/QOpenSys/pkgs/bin:\$PATH; _f=/tmp/_deploy_\$\$; printf '%s' '${FULL_B64}' | base64 -d > \$_f && /QOpenSys/pkgs/bin/bash \$_f; _rc=\$?; rm -f \$_f; exit \$_rc"

for _attempt in 1 2 3 4 5; do
  echo "SSH attempt ${_attempt}/5..."
  ssh "${SSH_OPTS[@]}" "${USER}@pub400.com" "${SSH_CMD}" && break
  _ssh_rc=$?
  if [ ${_attempt} -lt 5 ]; then
    echo "Connection failed (exit ${_ssh_rc}), waiting 30s before retry..."
    sleep 30
  else
    echo "All 5 attempts failed."
    exit ${_ssh_rc}
  fi
done
