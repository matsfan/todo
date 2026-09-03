#!/usr/bin/env bash
set -euo pipefail

if [ -z "${1:-}" ]; then
  echo "Usage: $0 <pub400.com username>" >&2
  exit 1
fi

USER="$1"
IFS_ROOT="/home/$USER/todo"

ssh "$USER@pub400.com" "mkdir -p \"$IFS_ROOT/QDDSSRC\" \"$IFS_ROOT/QRPGLESRC\""

scp -r QDDSSRC/ QRPGLESRC/ "$USER@pub400.com:$IFS_ROOT/"
