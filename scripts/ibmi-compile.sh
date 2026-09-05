#!/usr/bin/env bash
set -e

if [ -z "$1" ]; then
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

# NOTE: chk_del below combines the "does it exist" check and the delete into one
# &&/|| chain with a trailing `|| true` — see docs/plans/cicd-pipeline-plan.md
# Sub-Task 2, item 5. That also silently swallows a *failed* delete, not just a
# missing object. Flagged for RPG-teammate review before this runs unattended in
# CI; left unchanged here since it's a CL-semantics call, not a CI-plumbing one.
#
# NOTE: every `system "..."` call below redirects stdin from /dev/null. This whole
# script is fed to the remote shell over its own stdin (the ssh <<ENDSSH heredoc).
# When a CL command run via `system` fails, its error-handling path reads stdin
# for an inquiry-style reply — without </dev/null that read consumes the rest of
# THIS heredoc, silently skipping every remaining line with no error shown. Found
# by reproducing it live: a failing CHKOBJ with no redirect swallowed everything
# after it and exited as if nothing happened.
ssh "${SSH_OPTS[@]}" "${USER}@pub400.com" <<ENDSSH
set -e

# Helper: delete an object only if it exists
chk_del() {
  system "CHKOBJ OBJ(\$1) OBJTYPE(\$2)" </dev/null && system "\$3" </dev/null || true
}

# --- Clean up existing objects (reverse dependency order) ---
chk_del "*CURLIB/TODOTEST" "*SRVPGM" "DLTSRVPGM SRVPGM(*CURLIB/TODOTEST)"
chk_del "*CURLIB/TODOTEST" "*MODULE" "DLTMOD MODULE(*CURLIB/TODOTEST)"
chk_del "*CURLIB/TODOMAIN" "*PGM"    "DLTPGM PGM(*CURLIB/TODOMAIN)"
chk_del "*CURLIB/TODOBL"   "*SRVPGM" "DLTSRVPGM SRVPGM(*CURLIB/TODOBL)"
chk_del "*CURLIB/TODOBL"   "*MODULE" "DLTMOD MODULE(*CURLIB/TODOBL)"
chk_del "*CURLIB/TODOBND"  "*BNDDIR" "DLTBNDDIR BNDDIR(*CURLIB/TODOBND)"
chk_del "*CURLIB/TODODSPPF" "*FILE"  "DLTF FILE(*CURLIB/TODODSPPF)"
chk_del "*CURLIB/TODOLF"   "*FILE"   "DLTF FILE(*CURLIB/TODOLF)"
chk_del "*CURLIB/TODOPF"   "*FILE"   "DLTF FILE(*CURLIB/TODOPF)"

# --- Compile in dependency order ---

# CRTPF/CRTLF/CRTDSPF (DDS-based commands) have no SRCSTMF parameter at all —
# only the free-form language compilers (CRTBNDRPG, CRTRPGMOD) support compiling
# straight from an IFS stream file. DDS still requires a source physical file
# member, so bridge the git-cloned IFS files into one via CPYFRMSTMF first.
system "CRTSRCPF FILE(*CURLIB/QDDSSRC) RCDLEN(112) TEXT('DDS source (git-managed, see QDDSSRC/ in repo)')" </dev/null || true

system "CPYFRMSTMF FROMSTMF('${IFS_ROOT}/QDDSSRC/TODOPF.PF') TOMBR('/QSYS.LIB/QDDSSRC.FILE/TODOPF.MBR') MBROPT(*REPLACE) STMFCCSID(1208) DBFCCSID(*FILE)" </dev/null
system "CPYFRMSTMF FROMSTMF('${IFS_ROOT}/QDDSSRC/TODOLF.LF') TOMBR('/QSYS.LIB/QDDSSRC.FILE/TODOLF.MBR') MBROPT(*REPLACE) STMFCCSID(1208) DBFCCSID(*FILE)" </dev/null
system "CPYFRMSTMF FROMSTMF('${IFS_ROOT}/QDDSSRC/TODODSPPF.DSPF') TOMBR('/QSYS.LIB/QDDSSRC.FILE/TODODSPPF.MBR') MBROPT(*REPLACE) STMFCCSID(1208) DBFCCSID(*FILE)" </dev/null

# 1. Physical file
system "CRTPF FILE(*CURLIB/TODOPF) SRCFILE(*CURLIB/QDDSSRC) SRCMBR(TODOPF)" </dev/null

# 2. Logical file
system "CRTLF FILE(*CURLIB/TODOLF) SRCFILE(*CURLIB/QDDSSRC) SRCMBR(TODOLF)" </dev/null

# 3. Display file
system "CRTDSPF FILE(*CURLIB/TODODSPPF) SRCFILE(*CURLIB/QDDSSRC) SRCMBR(TODODSPPF) RSTDSP(*NO) OPTION(*EVENTF)" </dev/null

# 4. Binding directory
system "CRTBNDDIR BNDDIR(*CURLIB/TODOBND)" </dev/null

# 5. Business logic module
system "CRTRPGMOD MODULE(*CURLIB/TODOBL) SRCSTMF('${IFS_ROOT}/QRPGLESRC/TODOBL.RPGLE') OPTION(*EVENTF) DBGVIEW(*SOURCE) TGTCCSID(*JOB)" </dev/null

# 6. Business logic service program
system "CRTSRVPGM SRVPGM(*CURLIB/TODOBL) MODULE(*CURLIB/TODOBL)" </dev/null

# 7. Add service program to binding directory
system "ADDBNDDIRE BNDDIR(*CURLIB/TODOBND) OBJ((*CURLIB/TODOBL *SRVPGM))" </dev/null

# 8. Main program
system "CRTBNDRPG PGM(*CURLIB/TODOMAIN) SRCSTMF('${IFS_ROOT}/QRPGLESRC/TODOMAIN.RPGLE') OPTION(*EVENTF) DBGVIEW(*SOURCE) TGTCCSID(*JOB) BNDDIR(*CURLIB/TODOBND)" </dev/null

# 9. Test module
system "CRTRPGMOD MODULE(*CURLIB/TODOTEST) SRCSTMF('${IFS_ROOT}/QRPGLESRC/TODOTEST.RPGLE') OPTION(*EVENTF) DBGVIEW(*SOURCE) TGTCCSID(*JOB)" </dev/null

# 10. Test service program
system "CRTSRVPGM SRVPGM(*CURLIB/TODOTEST) MODULE(*CURLIB/TODOTEST) BNDDIR(*CURLIB/TODOBND) BNDSRVPGM(RPGUNIT/RUCRTTST)" </dev/null

echo "Compile complete."
ENDSSH
