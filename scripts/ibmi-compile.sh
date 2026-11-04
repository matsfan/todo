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

SSH_OPTS=(-p "$PORT" -o BatchMode=yes -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -i "$IDENTITY")

# makei build has no positional target argument -- a full build is plain
# 'makei build'; a single target is passed via '-t <target>'.
if [ "$TARGET" = "all" ]; then
  MAKEI_TARGET_FLAG=""
else
  MAKEI_TARGET_FLAG=" -t ${TARGET}"
fi

# ---------------------------------------------------------------------------
# Why this file has two layers (a CL wrapper CALLing a body shell script)
# instead of one flat remote script:
#
# Confirmed live (2026-09-09/10) that a bare 'CHGCURLIB' run via one
# PASE system() call has NO effect on any *later*, separate system() call --
# each system() invocation runs as its own isolated unit and does not share
# job-attribute state (current library, library list) with the next one,
# even within the same continuous SSH/bash session. (QTEMP behaves the same
# way, which is the earlier-documented reason CL calls can't rely on it
# across separate system() calls either.) This was the root cause of a
# CPF4131 level-check failure: TODOMAIN.RPGLE's unqualified
# "DCL-F TODODSPPF WORKSTN" (and TODOBL.RPGLE's TODOPF/TODOLF) resolve at
# compile time via the job's real *LIBL/current library, which a standalone
# CHGCURLIB system() call earlier in the script could never actually change
# for that later compile step.
#
# What *does* work, confirmed by direct test: a single CL *program*'s own
# sequential statements share one job/activation as normal, and a QSH
# statement's child process (and *its* own nested system() calls, however
# many) correctly inherit whatever CHGCURLIB that same program already ran.
# So the fix is to make the entire build -- both makei build passes and all
# of our explicit CRT*/DLT* steps -- run as descendants of one CHGCURLIB,
# inside one CL program, invoked via exactly one system()/CALL.
# ---------------------------------------------------------------------------

# The body: everything that actually builds the app. Unchanged in substance
# from before this fix, except it no longer attempts its own CHGCURLIB --
# that happens exactly once, in the CL wrapper that CALLs this via QSH.
BODY_SCRIPT=$(mktemp)
WRAPPER_CL=$(mktemp)
REMOTE_SCRIPT=$(mktemp)
trap 'rm -f "$BODY_SCRIPT" "$WRAPPER_CL" "$REMOTE_SCRIPT"' EXIT

cat > "$BODY_SCRIPT" << BODY
set -euo pipefail

export PATH="/QOpenSys/pkgs/bin:\$PATH"
export CURLIB="${CURLIB}"

cd "${IFS_ROOT}"

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
# TOBi's up-to-date check compares IFS source mtime to the QSYS object
# creation time. After a fresh git checkout (git clean -fdx wipes .deps/),
# the IFS files are older than any previously-compiled QSYS objects, so
# TOBi silently skips them. Pre-delete the DDS objects so TOBi is forced
# to rebuild them every time.
#
# < /dev/null here too: makei itself reads stdin, which -- same as the CL
# calls below -- would otherwise swallow the rest of this remote script.
echo "Deleting DDS objects to force recompile..."
system "DLTF FILE(\$CURLIB/TODODSPPF)" < /dev/null 2>&1 || true
system "DLTF FILE(\$CURLIB/TODOLF)"    < /dev/null 2>&1 || true
system "DLTF FILE(\$CURLIB/TODOPF)"    < /dev/null 2>&1 || true
system "DLTMOD MODULE(\$CURLIB/TODOBL)" < /dev/null 2>&1 || true
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
# fed through -- silently swallowing the rest of the script after that
# command, with no error (this is also what was really going on with
# DSPUSRPRF in an earlier investigation, and cost a lot of debugging to pin
# down).
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
BODY

BODY_REMOTE_PATH="${IFS_ROOT}/.ibmi-compile-body.sh"
WRAPPER_REMOTE_PATH="${IFS_ROOT}/.ibmi-compile-wrapper.clle"

# The CL wrapper: CHGCURLIB, then run the body via QSH as its child. Confirmed
# live that a QSH child process (and any system() calls made from within it,
# however many) correctly inherits a CHGCURLIB done earlier in the same CL
# program -- unlike a standalone system()-call CHGCURLIB, which doesn't
# survive to any later, separate system() call.
cat > "$WRAPPER_CL" << CLSRC
PGM
CHGCURLIB CURLIB(${CURLIB})
QSH CMD('bash "${BODY_REMOTE_PATH}"')
ENDPGM
CLSRC

# Build the full remote execution script (upload + compile) as a single
# local file, then base64-encode and pass it as a quoted SSH argument.
# This avoids all heredoc stdin issues: pub400 drops connections when stdin
# is piped via heredoc in non-interactive SSH (CI runners, Bob agent).
# Passing the script as a quoted 'bash -c ...' argument avoids stdin entirely.
cat > "$REMOTE_SCRIPT" << SCRIPT
set -euo pipefail
export PATH="/QOpenSys/pkgs/bin:\$PATH"

# Decode and write the build body script
printf '%s' '$(base64 < "$BODY_SCRIPT" | tr -d '\n')' | base64 -d > '${BODY_REMOTE_PATH}'

# Decode and write the CL wrapper
printf '%s' '$(base64 < "$WRAPPER_CL" | tr -d '\n')' | base64 -d > '${WRAPPER_REMOTE_PATH}'

# Compile and run the CL wrapper (CHGCURLIB + QSH into the body script).
# Each system() call gets </dev/null to prevent it reading our script stream.
system "DLTPGM PGM(${CURLIB}/IBMICLRUN)" </dev/null 2>&1 || true
system "CRTBNDCL PGM(${CURLIB}/IBMICLRUN) SRCSTMF('${WRAPPER_REMOTE_PATH}')" </dev/null
system "CALL PGM(${CURLIB}/IBMICLRUN)" </dev/null
system "DLTPGM PGM(${CURLIB}/IBMICLRUN)" </dev/null 2>&1 || true
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
SSH_CMD="export PATH=/QOpenSys/pkgs/bin:\$PATH; _f=/tmp/_compile_\$\$; printf '%s' '${FULL_B64}' | base64 -d > \$_f && /QOpenSys/pkgs/bin/bash \$_f; _rc=\$?; rm -f \$_f; exit \$_rc"

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
