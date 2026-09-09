#!/usr/bin/env bash
set -euo pipefail

# ---------------------------------------------------------------------------
# Credentials — sourced from .env at the repo root (git-ignored).
# Required variables: IBMI_USER, IBMI_IDENTITY, IBMI_CURLIB
# Optional variables: IBMI_SSH_PORT (default: 2222), IBMI_IFS_DIR (default: todo)
# See .env.example for the format.
#
# IBMI_IFS_DIR must match whatever ibmi-deploy.sh was given for this same
# build — it's what points the compile at the right IFS checkout when a
# profile has more than one (e.g. a dev checkout vs. an automated
# test-library pipeline's own checkout).
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
IFS_DIR="${IBMI_IFS_DIR:-todo}"
IFS_ROOT="/home/$USER/source/${IFS_DIR}"
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
#
# Run it twice around the *SRVPGM/*BNDDIR step below: TOBi's Rules.mk-driven
# build cannot actually create a *SRVPGM or *BNDDIR from binder source on this
# pub400 install (see the block below), so anything binding against TODOBND
# (TODOMAIN.PGM) fails on a first pass where TODOBND doesn't exist yet. The
# first pass is allowed to fail -- it still builds everything TOBi *can*
# handle (DSPF/PF/LF/MODULE) -- and the second pass is what actually
# determines success once TODOBL/TODOBND exist.
#
# < /dev/null here too: makei itself reads stdin, which -- same as the CL
# calls below -- would otherwise swallow the rest of this remote script.
OPT=*EVENTF makei build${MAKEI_TARGET_FLAG} < /dev/null || true

# TOBi references MODULE_TO_BND_RECIPE / BND_TO_BNDDIR_RECIPE for building a
# *SRVPGM from binder source and a *BNDDIR from a *SRVPGM, but neither macro
# is actually defined anywhere in this installed version -- 'make' expands
# them to an empty recipe and reports the target "up to date" even when the
# object doesn't exist (confirmed via 'makei -l build' and CHKOBJ). Build
# them explicitly instead. TODOBL.SRVPGM predates the switch to TOBi and is
# rebuilt here too so it can't silently drift from TODOBL.MODULE.
#
# Every CL call below redirects stdin from /dev/null. Without it, the CL
# command reads from the SAME stdin stream this whole remote script is being
# fed through via 'bash < file' -- silently swallowing the rest of the
# script after that command, with no error (this is also what was really
# going on with DSPUSRPRF above, and cost a lot of debugging to pin down).
echo "Rebuilding TODOBL service program and TODOBND binding directory..."
system "DLTSRVPGM SRVPGM(\$CURLIB/TODOBL)" < /dev/null 2>&1 || true
system "CRTSRVPGM SRVPGM(\$CURLIB/TODOBL) MODULE(\$CURLIB/TODOBL) EXPORT(*SRCFILE) SRCSTMF('${IFS_ROOT}/QBNDSRC/TODOBL.BND')" < /dev/null
system "DLTBNDDIR BNDDIR(\$CURLIB/TODOBND)" < /dev/null 2>&1 || true
system "CRTBNDDIR BNDDIR(\$CURLIB/TODOBND)" < /dev/null
system "ADDBNDDIRE BNDDIR(\$CURLIB/TODOBND) OBJ((\$CURLIB/TODOBL *SRVPGM *IMMED))" < /dev/null

echo "Re-running build now that TODOBND exists..."
OPT=*EVENTF makei build${MAKEI_TARGET_FLAG} < /dev/null || true

# Even with TODOBND in place, TODOMAIN.PGM still fails to bind: makei's own
# generated CRTBNDRPG command never includes a BNDDIR() parameter at all (see
# it above -- TGTCCSID/DBGVIEW/OPTION/etc are all there, BNDDIR just isn't),
# so it can never resolve TODOBL's exported procedures no matter how correct
# TODOBND itself is. Bind it explicitly here instead, as the authoritative
# last step -- this always runs (not just on failure) so TODOMAIN.PGM can't
# silently drift from a stale prior build.
echo "Binding TODOMAIN against TODOBND..."
system "DLTPGM PGM(\$CURLIB/TODOMAIN)" < /dev/null 2>&1 || true
system "CRTBNDRPG PGM(\$CURLIB/TODOMAIN) SRCSTMF('${IFS_ROOT}/QRPGLESRC/TODOMAIN.RPGLE') TGTCCSID(*JOB) DBGVIEW(*ALL) DBGENCKEY(*NONE) USRPRF(*USER) OPTION(*EVENTF) DFTACTGRP(*NO) ACTGRP(*NEW) BNDDIR(\$CURLIB/TODOBND)" < /dev/null

echo "Compile complete."
SCRIPT

ssh "${SSH_OPTS[@]}" "${USER}@pub400.com" bash < "$REMOTE_SCRIPT"
