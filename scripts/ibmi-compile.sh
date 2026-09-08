#!/usr/bin/env bash
set -euo pipefail

if [ -z "${1:-}" ]; then
  echo "Usage: $0 <pub400-username> [ssh-identity-file] [make-target]" >&2
  echo "  make-target  optional TOBi target, e.g. TODODSPPF.FILE (default: all)" >&2
  exit 1
fi

USER="$1"
IDENTITY="${2:-}"
TARGET="${3:-all}"
IFS_ROOT="/home/$USER/source/todo"
PORT="${IBMI_SSH_PORT:-2222}"

SSH_OPTS=(-p "$PORT" -o BatchMode=yes -o StrictHostKeyChecking=accept-new)
if [ -n "$IDENTITY" ]; then
  SSH_OPTS+=(-i "$IDENTITY")
fi

# Builds via TOBi (makei), driven by the project's iproj.json/Rules.mk files.
# makei build is dependency-aware: it only rebuilds objects whose source (or
# dependencies) changed since the last run.
#
# The remote script is passed as a 'bash -c' argument string rather than via a
# heredoc on stdin. A heredoc pipes to the remote shell's stdin, which causes
# makei to think stdin is a pipe and buffers/drops its progress output in some
# SSH implementations. Passing an explicit 'bash -c <script>' argument keeps
# the SSH channel's stdout/stderr fully connected to the local terminal so
# makei output streams back in real time.
#
# Variables expanded locally (before the wire): IFS_ROOT, USER, TARGET.
# Variables expanded remotely (on IBM i):        PATH, CURLIB.
ssh "${SSH_OPTS[@]}" "${USER}@pub400.com" bash -c "$(cat <<REMOTE
set -euo pipefail

export PATH='/QOpenSys/pkgs/bin:\$PATH'

cd '${IFS_ROOT}'

# makei resolves CURLIB from the environment -- it does not accept the CL
# special value *CURLIB. Non-interactive SSH jobs don't expose the profile's
# current library any other way, so look it up via DSPUSRPRF.
CURLIB=\$(system \"DSPUSRPRF USRPRF(${USER}) TYPE(*BASIC)\" 2>/dev/null \
  | grep 'Current library' | awk -F: '{print \$NF}' | tr -d ' ')
if [ -z \"\$CURLIB\" ]; then
  echo 'Could not determine current library for ${USER}' >&2
  exit 1
fi
export CURLIB
echo \"Building into library \$CURLIB (target: ${TARGET})\"

OPT=*EVENTF makei build ${TARGET}

echo 'Compile complete.'
REMOTE
)"
