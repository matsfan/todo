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
ssh "${SSH_OPTS[@]}" "${USER}@pub400.com" <<ENDSSH
set -e

# Helper: delete an object only if it exists
chk_del() {
  system "CHKOBJ OBJ(\$1) OBJTYPE(\$2)" && system "\$3" || true
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

# 1. Physical file
system "CRTPF FILE(*CURLIB/TODOPF) SRCSTMF('${IFS_ROOT}/QDDSSRC/TODOPF.PF')"

# 2. Logical file
system "CRTLF FILE(*CURLIB/TODOLF) SRCSTMF('${IFS_ROOT}/QDDSSRC/TODOLF.LF')"

# 3. Display file
system "CRTDSPF FILE(*CURLIB/TODODSPPF) SRCSTMF('${IFS_ROOT}/QDDSSRC/TODODSPPF.DSPF') RSTDSP(*NO) OPTION(*EVENTF)"

# 4. Binding directory
system "CRTBNDDIR BNDDIR(*CURLIB/TODOBND)"

# 5. Business logic module
system "CRTRPGMOD MODULE(*CURLIB/TODOBL) SRCSTMF('${IFS_ROOT}/QRPGLESRC/TODOBL.RPGLE') OPTION(*EVENTF) DBGVIEW(*SOURCE) TGTCCSID(*JOB)"

# 6. Business logic service program
system "CRTSRVPGM SRVPGM(*CURLIB/TODOBL) MODULE(*CURLIB/TODOBL)"

# 7. Add service program to binding directory
system "ADDBNDDIRE BNDDIR(*CURLIB/TODOBND) OBJ((*CURLIB/TODOBL *SRVPGM))"

# 8. Main program
system "CRTBNDRPG PGM(*CURLIB/TODOMAIN) SRCSTMF('${IFS_ROOT}/QRPGLESRC/TODOMAIN.RPGLE') OPTION(*EVENTF) DBGVIEW(*SOURCE) TGTCCSID(*JOB) BNDDIR(*CURLIB/TODOBND)"

# 9. Test module
system "CRTRPGMOD MODULE(*CURLIB/TODOTEST) SRCSTMF('${IFS_ROOT}/QRPGLESRC/TODOTEST.RPGLE') OPTION(*EVENTF) DBGVIEW(*SOURCE) TGTCCSID(*JOB)"

# 10. Test service program
system "CRTSRVPGM SRVPGM(*CURLIB/TODOTEST) MODULE(*CURLIB/TODOTEST) BNDDIR(*CURLIB/TODOBND) BNDSRVPGM(RPGUNIT/RUCRTTST)"

echo "Compile complete."
ENDSSH
