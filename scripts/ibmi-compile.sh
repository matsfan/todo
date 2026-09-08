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
TARGET="${1:-all}"
IFS_ROOT="/home/$USER/source/todo"
PORT="${IBMI_SSH_PORT:-2222}"

SSH_OPTS=(-p "$PORT" -o BatchMode=yes -o StrictHostKeyChecking=accept-new -i "$IDENTITY")

# Builds via TOBi (makei), driven by the project's iproj.json/Rules.mk files.
# makei build is dependency-aware: it only rebuilds objects whose source (or
# dependencies) changed since the last run.
#
# The remote script is written to a temp file locally and piped into
# 'ssh ... bash' via process substitution.  This keeps the SSH channel's
# stdout/stderr fully connected to the local terminal (no stdin redirection on
# the ssh command itself) so makei output streams back in real time.
#
# Variables expanded locally (before the wire): IFS_ROOT, USER, TARGET.
# Variables expanded remotely (on IBM i):        CURLIB, PATH.
REMOTE_SCRIPT=$(mktemp)
trap 'rm -f "$REMOTE_SCRIPT"' EXIT

cat > "$REMOTE_SCRIPT" << SCRIPT
set -euo pipefail

export PATH="/QOpenSys/pkgs/bin:\$PATH"

cd "${IFS_ROOT}"

# makei resolves CURLIB from the environment -- it does not accept the CL
# special value *CURLIB. Non-interactive SSH jobs don't expose the profile's
# current library any other way, so look it up via DSPUSRPRF.
CURLIB=\$(system "DSPUSRPRF USRPRF(${USER}) TYPE(*BASIC)" 2>/dev/null \
  | grep "Current library" | awk -F: '{print \$NF}' | tr -d ' ')
if [ -z "\$CURLIB" ]; then
  echo "Could not determine current library for ${USER}" >&2
  exit 1
fi
export CURLIB
echo "Building into library \$CURLIB (target: ${TARGET})"

OPT=*EVENTF makei build ${TARGET}

echo "Compile complete."
SCRIPT

ssh "${SSH_OPTS[@]}" "${USER}@pub400.com" bash < "$REMOTE_SCRIPT"
