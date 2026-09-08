#!/usr/bin/env bash
set -euo pipefail

# ---------------------------------------------------------------------------
# Credentials — sourced from .env at the repo root (git-ignored).
# Required variables: IBMI_USER, IBMI_IDENTITY, IBMI_CURLIB
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
CURLIB="${IBMI_CURLIB:?'.env must set IBMI_CURLIB'}"
TARGET="${1:-all}"
IFS_ROOT="/home/$USER/source/todo"
PORT="${IBMI_SSH_PORT:-2222}"

SSH_OPTS=(-p "$PORT" -o BatchMode=yes -o StrictHostKeyChecking=accept-new -i "$IDENTITY")

# makei build has no positional target argument -- a full build is plain
# 'makei build'; a single target is passed via '-t <target>'.
if [ "$TARGET" = "all" ]; then
  MAKEI_TARGET_FLAG=""
else
  MAKEI_TARGET_FLAG=" -t ${TARGET}"
fi

# Builds via TOBi (makei), driven by the project's iproj.json/Rules.mk files.
# makei build is dependency-aware: it only rebuilds objects whose source (or
# dependencies) changed since the last run.
#
# The remote script is written to a temp file locally and piped into
# 'ssh ... bash' via process substitution.  This keeps the SSH channel's
# stdout/stderr fully connected to the local terminal (no stdin redirection on
# the ssh command itself) so makei output streams back in real time.
#
# Variables expanded locally (before the wire): IFS_ROOT, USER, CURLIB, TARGET.
# Variables expanded remotely (on IBM i):        PATH.
REMOTE_SCRIPT=$(mktemp)
trap 'rm -f "$REMOTE_SCRIPT"' EXIT

cat > "$REMOTE_SCRIPT" << SCRIPT
set -euo pipefail

export PATH="/QOpenSys/pkgs/bin:\$PATH"

cd "${IFS_ROOT}"

# makei resolves CURLIB from the environment -- it does not accept the CL
# special value *CURLIB. Non-interactive SSH jobs don't expose the profile's
# current library any other way, and DSPUSRPRF (or any screen-oriented Display
# command) kills the SSH session outright when run without a pty -- it prints
# its full output then the connection dies before any further script lines
# run, with no error. So the current library comes from IBMI_CURLIB in .env
# instead (it's a fixed, pre-provisioned value per pub400 profile, not
# something that needs to be looked up at build time).
export CURLIB="${CURLIB}"
echo "Building into library \$CURLIB (target: ${TARGET})"

# makei build has no positional target argument -- a full build is plain
# 'makei build'; a single target is passed via '-t <target>'.
OPT=*EVENTF makei build${MAKEI_TARGET_FLAG}

echo "Compile complete."
SCRIPT

ssh "${SSH_OPTS[@]}" "${USER}@pub400.com" bash < "$REMOTE_SCRIPT"
