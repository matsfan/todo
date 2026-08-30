#!/usr/bin/env bash
# Uploads local QDDSSRC/QRPGLESRC files to the IFS on pub400.com, then copies
# each into its source member in TODO/QDDSSRC and TODO/QRPGLESRC.
# Requires: TODO/QDDSSRC and TODO/QRPGLESRC source physical files already exist
# (docs/DEPLOY.md Step 4) and SSH access to pub400.com.
set -euo pipefail

USER="${1:?usage: ibmi-deploy.sh <pub400-username>}"
HOST="pub400.com"
LIB="TODO"
STAGE="/home/$USER/todo-src"

echo ">>> Staging source to $HOST:$STAGE"
ssh "$USER@$HOST" "mkdir -p $STAGE/QDDSSRC $STAGE/QRPGLESRC"
scp QDDSSRC/*.PF QDDSSRC/*.LF QDDSSRC/*.DSPF "$USER@$HOST:$STAGE/QDDSSRC/"
scp QRPGLESRC/*.RPGLE "$USER@$HOST:$STAGE/QRPGLESRC/"

copy_member() {
  local stmf="$1" srcpf="$2" mbr="$3"
  echo ">>> CPYFRMSTMF $stmf -> $LIB/$srcpf,$mbr"
  ssh "$USER@$HOST" "system \"CPYFRMSTMF FROMSTMF('$STAGE/$stmf') TOMBR('/QSYS.LIB/$LIB.LIB/$srcpf.FILE/$mbr.MBR') MBROPT(*REPLACE) STMFCCSID(437) DBFCCSID(*FILE)\""
}

copy_member "QDDSSRC/TODOPF.PF"        QDDSSRC   TODOPF
copy_member "QDDSSRC/TODOLF.LF"        QDDSSRC   TODOLF
copy_member "QDDSSRC/TODODSPPF.DSPF"   QDDSSRC   TODODSPPF
copy_member "QRPGLESRC/TODOBL.RPGLE"   QRPGLESRC TODOBL
copy_member "QRPGLESRC/TODOMAIN.RPGLE" QRPGLESRC TODOMAIN
copy_member "QRPGLESRC/TODOTEST.RPGLE" QRPGLESRC TODOTEST

echo ">>> Deploy complete."
