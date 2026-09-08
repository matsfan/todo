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
#
# The remote commands are passed via 'bash -s' (stdin) rather than a heredoc
# on the ssh command itself. Both approaches pipe stdin to the remote shell,
# but 'bash -s' explicitly binds the script to bash's stdin and keeps the SSH
# channel's stdout/stderr fully connected to the local terminal, which ensures
# makei's build output is always streamed back.
ssh "${SSH_OPTS[@]}" "${USER}@pub400.com" bash -s << ENDSSH
set -e

# Non-interactive SSH sessions don't always source .profile/.bashrc, so PATH may
# not include the Open Source package dir where makei actually lives.
export PATH="/QOpenSys/pkgs/bin:\$PATH"

cd "${IFS_ROOT}"

# iproj.json's curlib/objlib are "&CURLIB", which makei resolves from a real
# CURLIB environment variable - it is not the CL special value *CURLIB, and
# makei errors out immediately ("CURLIB must be defined first in the
# environment variable") if it's unset. Non-interactive SSH jobs don't expose
# the profile's current library any other way, so look it up explicitly.
CURLIB=\$(system "DSPUSRPRF USRPRF(${USER}) TYPE(*BASIC)" 2>/dev/null | grep "Current library" | awk -F: '{print \$NF}' | tr -d ' ')
if [ -z "\$CURLIB" ]; then
  echo "Could not determine current library for ${USER}" >&2
  exit 1
fi
export CURLIB
echo "Building into library \$CURLIB"

OPT=*EVENTF makei build

echo "Compile complete."
ENDSSH
