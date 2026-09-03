#!/usr/bin/env bash
set -e

if [ -z "$1" ]; then
  echo "Usage: $0 <pub400-username>" >&2
  exit 1
fi

USER="$1"
IFS_ROOT="/home/$USER/todo"

ssh "${USER}@pub400.com" <<ENDSSH
set -e

# Helper: delete an object only if it exists
chk_del() {
  system "CHKOBJ OBJ(\$1) OBJTYPE(\$2)" && system "\$3" || true
}

# --- Clean up existing objects (reverse dependency order) ---
chk_del "TODO/TODOTEST" "*SRVPGM" "DLTSRVPGM SRVPGM(TODO/TODOTEST)"
chk_del "TODO/TODOTEST" "*MODULE" "DLTMOD MODULE(TODO/TODOTEST)"
chk_del "TODO/TODOMAIN" "*PGM"    "DLTPGM PGM(TODO/TODOMAIN)"
chk_del "TODO/TODOBL"   "*SRVPGM" "DLTSRVPGM SRVPGM(TODO/TODOBL)"
chk_del "TODO/TODOBL"   "*MODULE" "DLTMOD MODULE(TODO/TODOBL)"
chk_del "TODO/TODOBND"  "*BNDDIR" "DLTBNDDIR BNDDIR(TODO/TODOBND)"
chk_del "TODO/TODODSPPF" "*FILE"  "DLTF FILE(TODO/TODODSPPF)"
chk_del "TODO/TODOLF"   "*FILE"   "DLTF FILE(TODO/TODOLF)"
chk_del "TODO/TODOPF"   "*FILE"   "DLTF FILE(TODO/TODOPF)"

# --- Compile in dependency order ---

# 1. Physical file
system "CRTPF FILE(TODO/TODOPF) SRCSTMF('${IFS_ROOT}/QDDSSRC/TODOPF.PF')"

# 2. Logical file
system "CRTLF FILE(TODO/TODOLF) SRCSTMF('${IFS_ROOT}/QDDSSRC/TODOLF.LF')"

# 3. Display file
system "CRTDSPF FILE(TODO/TODODSPPF) SRCSTMF('${IFS_ROOT}/QDDSSRC/TODODSPPF.DSPF') RSTDSP(*NO) OPTION(*EVENTF)"

# 4. Binding directory
system "CRTBNDDIR BNDDIR(TODO/TODOBND)"

# 5. Business logic module
system "CRTRPGMOD MODULE(TODO/TODOBL) SRCSTMF('${IFS_ROOT}/QRPGLESRC/TODOBL.RPGLE') OPTION(*EVENTF) DBGVIEW(*SOURCE) TGTCCSID(*JOB)"

# 6. Business logic service program
system "CRTSRVPGM SRVPGM(TODO/TODOBL) MODULE(TODO/TODOBL)"

# 7. Add service program to binding directory
system "ADDBNDDIRE BNDDIR(TODO/TODOBND) OBJ((TODO/TODOBL *SRVPGM))"

# 8. Main program
system "CRTBNDRPG PGM(TODO/TODOMAIN) SRCSTMF('${IFS_ROOT}/QRPGLESRC/TODOMAIN.RPGLE') OPTION(*EVENTF) DBGVIEW(*SOURCE) TGTCCSID(*JOB) BNDDIR(TODO/TODOBND)"

# 9. Test module
system "CRTRPGMOD MODULE(TODO/TODOTEST) SRCSTMF('${IFS_ROOT}/QRPGLESRC/TODOTEST.RPGLE') OPTION(*EVENTF) DBGVIEW(*SOURCE) TGTCCSID(*JOB)"

# 10. Test service program
system "CRTSRVPGM SRVPGM(TODO/TODOTEST) MODULE(TODO/TODOTEST) BNDDIR(TODO/TODOBND) BNDSRVPGM(RPGUNIT/RUCRTTST)"

echo "Compile complete."
ENDSSH
