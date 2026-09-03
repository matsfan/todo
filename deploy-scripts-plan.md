# Plan: Create ibmi-deploy.sh and ibmi-compile.sh

## Overview

Two shell scripts need to be created under `scripts/` so that the existing VS Code tasks
in `.vscode/tasks.json` work end-to-end. Both scripts accept a single argument — the
pub400.com username — and use SSH key-based auth (no passwords).

- `scripts/ibmi-deploy.sh` — copies local `QDDSSRC/` and `QRPGLESRC/` to the IFS on
  pub400.com using `scp`.
- `scripts/ibmi-compile.sh` — SSHes to pub400.com and runs the ordered `CRT*` compile
  commands documented in `AGENTS.md`.

Both scripts must be executable (`chmod +x`).

---

## Sub-Task 1 — Create `scripts/ibmi-deploy.sh`

**Status:** [x] done

### Intent
Deploy local source members from `QDDSSRC/` and `QRPGLESRC/` to the IFS on pub400.com
so the compile script can reference them via stream file paths (`SRCSTMF`).

The IFS target path convention for pub400.com is:
```
/home/<USER>/todo/QDDSSRC/
/home/<USER>/todo/QRPGLESRC/
```

### Expected Outcomes
- Running `scripts/ibmi-deploy.sh <username>` from the workspace root uploads all
  `.PF`, `.LF`, `.DSPF`, and `.RPGLE` files to the correct IFS paths.
- The VS Code task **"IBM i: Deploy Source"** completes without error.

### Todo List
1. Create `scripts/` directory.
2. Write `scripts/ibmi-deploy.sh` that:
   - Accepts `$1` as the pub400.com username; exits with a usage error if omitted.
   - Sets `IFS_ROOT="/home/$USER/todo"`.
   - Uses `ssh $USER@pub400.com "mkdir -p ..."` to ensure target IFS directories exist.
   - Uses `scp -r QDDSSRC/ QRPGLESRC/ $USER@pub400.com:$IFS_ROOT/` to upload both
     source directories.
3. Make the script executable (`chmod +x scripts/ibmi-deploy.sh`).

### Relevant Context
- Task invocation: `.vscode/tasks.json` line 14 — `"command": "${workspaceFolder}/scripts/ibmi-deploy.sh"`, arg `${input:pub400User}`.
- Source directories: `QDDSSRC/` (3 files), `QRPGLESRC/` (3 files).
- SSH key auth assumed — no `-o BatchMode=yes` workaround needed.

---

## Sub-Task 2 — Create `scripts/ibmi-compile.sh`

**Status:** [x] done

### Intent
Run the full ordered compile sequence on pub400.com over SSH, exactly as documented in
`AGENTS.md`. Each `CRT*` command must succeed before the next runs (`set -e`).

### Expected Outcomes
- Running `scripts/ibmi-compile.sh <username>` SSHes to pub400.com and executes all
  compile commands in dependency order.
- The VS Code task **"IBM i: Compile All"** completes without error when source is
  already deployed on the IFS.
- The VS Code task **"IBM i: Deploy + Compile"** (which chains deploy then compile)
  works end-to-end from F5 / Run Task.

### Todo List
1. Write `scripts/ibmi-compile.sh` that:
   - Accepts `$1` as the pub400.com username; exits with a usage error if omitted.
   - Sets `IFS_ROOT="/home/$USER/todo"`.
   - SSHes to pub400.com and runs the following commands in order (using `system` or
     `QSH` as appropriate for pub400.com's shell):
     ```
     CRTPF     FILE(TODO/TODOPF)     SRCSTMF('<IFS_ROOT>/QDDSSRC/TODOPF.PF')
     CRTLF     FILE(TODO/TODOLF)     SRCSTMF('<IFS_ROOT>/QDDSSRC/TODOLF.LF')
     CRTDSPF   FILE(TODO/TODODSPPF)  SRCSTMF('<IFS_ROOT>/QDDSSRC/TODODSPPF.DSPF') RSTDSP(*NO) OPTION(*EVENTF)
     CRTBNDDIR BNDDIR(TODO/TODOBND)
     CRTRPGMOD MODULE(TODO/TODOBL)   SRCSTMF('<IFS_ROOT>/QRPGLESRC/TODOBL.RPGLE')   OPTION(*EVENTF) DBGVIEW(*SOURCE) TGTCCSID(*JOB)
     CRTSRVPGM SRVPGM(TODO/TODOBL)  MODULE(TODO/TODOBL)
     ADDBNDDIRE BNDDIR(TODO/TODOBND) OBJ((TODO/TODOBL *SRVPGM))
     CRTBNDRPG PGM(TODO/TODOMAIN)   SRCSTMF('<IFS_ROOT>/QRPGLESRC/TODOMAIN.RPGLE') OPTION(*EVENTF) DBGVIEW(*SOURCE) TGTCCSID(*JOB) BNDDIR(TODO/TODOBND)
     CRTRPGMOD MODULE(TODO/TODOTEST) SRCSTMF('<IFS_ROOT>/QRPGLESRC/TODOTEST.RPGLE') OPTION(*EVENTF) DBGVIEW(*SOURCE) TGTCCSID(*JOB)
     CRTSRVPGM SRVPGM(TODO/TODOTEST) MODULE(TODO/TODOTEST) BNDDIR(TODO/TODOBND) BNDSRVPGM(RPGUNIT/RUCRTTST)
     ```
   - Wraps all commands in a single SSH invocation using a heredoc or semicolons.
   - Uses `set -e` so the script aborts on the first failed compile.
   - Before re-creating each object, check whether it already exists and delete it
     only if it does. Use a conditional `system` call pattern:
     `system "CHKOBJ OBJ(TODO/TODOPF) OBJTYPE(*FILE)" && system "DLTF FILE(TODO/TODOPF)"`
     (or equivalent). This way a first-time run skips the delete and a repeat run
     cleans up the stale object before recompiling.
2. Make the script executable (`chmod +x scripts/ibmi-compile.sh`).

### Relevant Context
- Compile order from `AGENTS.md` — must be followed exactly; `TODOMAIN` depends on
  `TODOBL *SRVPGM` being in `TODOBND` binding directory first.
- `SRCFILE` parameter is NOT used — compile commands use `SRCSTMF` (IFS stream file
  path) because source lives on the IFS, not in a source physical file.
- `AGENTS.md` notes: `TODOPF` opened for `*UPDATE:*OUTPUT:*DELETE`; `TODOLF` read-only
  — the compile order enforces this naturally (PF before LF).
- Task invocation: `.vscode/tasks.json` line 22 — `"command": "${workspaceFolder}/scripts/ibmi-compile.sh"`, arg `${input:pub400User}`.
