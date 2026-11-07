# AGENTS.md

This file provides guidance to agents when working with code in this repository.

## Project

IBM i RPG 5250 green-screen todo application targeting pub400.com.
No package manager — compilation happens on the IBM i server, driven by **TOBi**
(`/QOpenSys/pkgs/bin/makei build`), not hand-run CL commands.

## Repo Layout

```
QDDSSRC/            ← DDS source, pulled directly onto the IFS on pub400 via `git clone`/`git pull`
QRPGLESRC/          ← RPG source, same git-based deploy — no source physical file involved
QBNDSRC/            ← Binder source (TOBi requires this to build a *SRVPGM; see Compile Commands)
scripts/            ← ibmi-deploy.sh / ibmi-compile.sh — the only permitted way to touch pub400
.github/workflows/  ← deploy-dev.yml: deploys + compiles MBPRICE1 on push to any branch except main
                      deploy-test.yml: deploys + compiles MBPRICE2 on every push to main
                      deploy-prod.yml: deploys + compiles MBPRICEB, manual + approval only
.bob/               ← Bob's rule files (rules-agent/, rules-plan/, rules-ask/), the Stop hook
                      (hooks/ibmi-post-stop.sh) and its build log (logs/ibmi-build.log)
docs/               ← Human-readable docs only (not uploaded to IBM i)
iproj.json          ← TOBi project config (target library, build command)
Rules.mk            ← TOBi build rules (root + one per source directory)
CLAUDE.md           ← Instructions for Claude Code; points back to this file and to
                      .bob/rules-*/AGENTS.md for the rules Bob follows
```

File extensions are IBM i member types: `.PF`, `.LF`, `.DSPF`, `.RPGLE`

## Target Library

All compile commands target **`*CURLIB`**, not a hardcoded library name. Library creation is
restricted on pub400.com — each profile is pre-provisioned with its own current library.

**Three libraries, one profile**: `MBPRICE1` (dev), `MBPRICE2` (test), `MBPRICEB` (production).
`MBPRICE1` is updated automatically on every push to any branch except `main` by
`.github/workflows/deploy-dev.yml` (IFS directory: `todo-dev`). `MBPRICE2` is updated automatically
on every push to `main` by `.github/workflows/deploy-test.yml` (IFS directory: `todo-test`) —
never deploy or compile into either by hand. `MBPRICEB` is updated only by
`.github/workflows/deploy-prod.yml` (IFS directory: `todo-prod`), started by hand from the Actions
tab on the user's explicit instruction; see [Environments](#environments) below.

**Qualifying `CALL` alone does not select which library's data you hit.** Files in `TODOBL`
are declared unqualified and resolve at `OPEN` time via the job's current-library slot, independent
of which library the program object was loaded from. To exercise a given library's data:
```
CHGCURLIB CURLIB(MBPRICE2)
CALL MBPRICE2/TODOMAIN
```

## Compile Commands

`scripts/ibmi-deploy.sh` + `scripts/ibmi-compile.sh` are the **only** permitted way to build.
Never hand-craft `CRT*` commands or `scp` calls directly.

Dependency order (for editing `Rules.mk` — not a sequence to run manually):
```
TODOPF.FILE → TODOLF.FILE → TODODSPPF.FILE → TODOBL.MODULE
  → TODOBL.SRVPGM → TODOBND.BNDDIR → TODOMAIN.PGM
```

**Why `scripts/ibmi-compile.sh` is more than `makei build` once:**
- TOBi's installed version silently reports `*SRVPGM` and `*BNDDIR` targets as "up to date" even
  when the objects don't exist. The script runs `makei build` (allowed to fail), then explicitly
  runs `DLTSRVPGM`/`CRTSRVPGM` for `TODOBL`, `DLTBNDDIR`/`CRTBNDDIR`/`ADDBNDDIRE` for `TODOBND`,
  then `makei build` a second time.
- `makei`'s generated `CRTBNDRPG` never emits a `BNDDIR()` parameter, so `TODOMAIN.PGM` always
  requires an explicit `CRTBNDRPG ... BNDDIR($CURLIB/TODOBND)` as the final step.
- All CL `system()` calls inside the script pipe `< /dev/null` — without it, the CL command reads
  from the same stdin stream the remote script is fed through, silently swallowing the rest.
- The entire build runs inside a CL wrapper that calls `CHGCURLIB` then `QSH`s into the build
  body, because a bare `CHGCURLIB` in one `system()` call has no effect on any later separate
  `system()` call — only descendants of the `QSH` inherit the current library change.

**RPGUnit is not installed on pub400** — `TODOTEST.RPGLE` cannot compile or run. `iproj.json`'s
`preUsrlibl` is intentionally empty; adding `RPGUNIT` back would block all RPG compiles.
Run tests: `RUCALLTST TSTPGM(*CURLIB/TODOTEST)` — currently blocked, not available today.

## Deploy & Compile (triggering)

Deploy and compile are handled entirely by GitHub Actions CI — the Bob Stop hook is a no-op.

| Push target | Workflow | IFS directory | Compiled into |
|---|---|---|---|
| any branch except `main` | `deploy-dev.yml` | `todo-dev` | `MBPRICE1` |
| `main` | `deploy-test.yml` | `todo-test` | `MBPRICE2` |
| manual "Run workflow" on `main` | `deploy-prod.yml` | `todo-prod` | `MBPRICEB` |

To trigger a build: push your branch. The relevant workflow will deploy the commit to pub400
and run `scripts/ibmi-compile.sh` automatically. Build output appears in the Actions run log.

### Environments

Each library is defined in exactly one place: a **GitHub Environment** (repo Settings →
Environments) named `dev`, `test` or `prod`, holding the variables `IBMI_CURLIB` and
`IBMI_IFS_DIR`. Each workflow job declares `environment: <name>` and passes those values to the
scripts. `IBMI_USER` and `IBMI_SSH_KEY` are repo-level secrets shared by all three. The scripts
read only environment variables, with no defaults for library or checkout, and there is no
`.env` file. To change where an environment builds, edit its variables in GitHub, not the
workflow files.

- `test` and `prod` only accept the `main` branch.
- `prod` requires reviewer approval before the job starts. `deploy-prod.yml` also refuses any
  commit that isn't on `main` or that hasn't had a successful `deploy-test.yml` run.
- `workflow_dispatch` only works for workflow files already on the default branch, so a new or
  changed `deploy-prod.yml` can't be run until it's merged.

## Architecture

- **`TODOBL` (`*SRVPGM`)** — owns all file I/O and business logic. Exports exactly 11 procedures:
  `OpenFiles`, `CloseFiles`, `GetNextId`, `ValidateDescription`, `AddTodoRecord`, `EditTodoRecord`,
  `MarkDoneRecord`, `DeleteTodoRecord`, `ReadFirstTodo`, `ReadNextTodo`, `GetTodoById`.
- **`TODOMAIN` (`*PGM`)** — thin 5250 UI shell. Declares only `TODODSPPF`; delegates all data
  operations to `TODOBL` via prototypes. Opens `TODODSPPF` itself with `OPEN TODODSPPF` inside
  `Main()` (not via `OpenFiles`/`CloseFiles` — those only manage `TODOLF`/`TODOPF`).

## Critical Conventions

- **All RPG is fully free-form** (`**FREE` at line 1).
- **`CTL-OPT NOMAIN`** on `TODOBL.RPGLE`; **`CTL-OPT DFTACTGRP(*NO) ACTGRP(*NEW)`** on
  `TODOMAIN.RPGLE` (required to call a `*SRVPGM` — default activation group cannot).
- **`USROPN`** on all file declarations in `TODOBL`; `TODOMAIN` also declares `TODODSPPF USROPN`.
- **`TODOPF` opened `USAGE(*UPDATE:*OUTPUT:*DELETE)`**; `TODOLF` read-only. Never write through LF.
- **`TODOLF` declared `RENAME(TODOR:TODOLFR)`** — TODOLF reuses TODOPF's format name `TODOR`.
  Reads use `TODOLFR`; writes/updates/deletes against `TODOPF` use `TODOR`.
- **Block-closing keywords are `ENDIF`/`ENDDO`/`ENDSL` — no hyphen.** Only structured-definition
  closers take a hyphen: `END-PI`, `END-PR`, `END-DS`, `END-PROC`. `END-IF`/`END-DO` are compile
  errors in fully free-form RPG.
- **`TODOFTR` is a separate record format from `TODOCTL`** — footer at row 23 can't live inside
  the subfile control record. Both declare `OVERLAY`. `Main` does `WRITE TODOFTR;` before
  `EXFMT TODOCTL;` every pass.
- **Subfile clear sequence**: `*IN52=*ON` → `WRITE TODOCTL` → `*IN52=*OFF` immediately.
- **`*IN50` (SFLDSP) must be `*OFF` when zero rows exist** — displaying empty subfile abends.
- **`CHAIN` uses `TODOPF` for all updates, deletes, mark-done** — never `TODOLF`.
- **`w_Found = NOT %EOF(TODOPF)`** after `CHAIN` — never use `%FOUND`.
- **`DeleteTodoRecord`** does single `CHAIN` + `DELETE` — no re-chain; confirmation screen in
  `TODOMAIN` happens before the call.
- **Variable prefixes**: `w_` = module-level, `l_` = local, `DET*` = TODODET fields,
  `DEL*` = TODODEL fields, `SFL*` = subfile fields. Procedure parameters: `i_` = input, `o_` = output.
- **DDS uses fixed-column layout** (cols 1–80). Do not reformat `.PF`, `.LF`, `.DSPF` files.
- **Indicator map** is documented in both `TODODSPPF.DSPF` header and `TODOMAIN.RPGLE` header —
  keep both in sync when adding indicators.
- **`EXTPROC` names are uppercase strings** (e.g. `EXTPROC('OPENFILES')`) — match exactly.
- **`TDDONE='1'` filtering** is done in RPG (`LoadSubfile`), not at the LF level — `TODOLF` has
  no select/omit. Adding one would require recompiling `TODOLF`, `TODOBL`, and `TODOMAIN`.
- **`GetNextId`** uses `SETLL *END` + `READP` on `TODOLF` — a max-ID-plus-one scheme, not a
  sequence object. Safe for single-user pub400 use only.
- **`GetTodoById`** is listed in `QBNDSRC/TODOBL.BND` exports but not in the `TODOBL.RPGLE`
  header comment's export list — both sources of truth must be kept in sync when adding exports.
