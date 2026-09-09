# AGENTS.md

This file provides guidance to agents when working with code in this repository.

## Project

IBM i RPG 5250 green-screen todo application targeting pub400.com.
No package manager — compilation happens on the IBM i server, driven by **TOBi**
(`/QOpenSys/pkgs/bin/makei build`), not hand-run CL commands.

## Repo Layout

```
QDDSSRC/        ← DDS source, pulled directly onto the IFS on pub400 via `git clone`/`git pull`
QRPGLESRC/      ← RPG source, same git-based deploy — no source physical file involved
QBNDSRC/        ← Binder source (TOBi requires this to build a *SRVPGM; see Compile Commands)
docs/           ← Human-readable docs only (not uploaded to IBM i)
iproj.json      ← TOBi project config (target library, build command)
Rules.mk        ← TOBi build rules (root + one per source directory)
```

File extensions are IBM i member types: `.PF`, `.LF`, `.DSPF`, `.RPGLE`

## Target library

All compile commands target **`*CURLIB`**, not a hardcoded library name. Library creation is
restricted on pub400.com (a shared free system) — each profile is pre-provisioned with its own
current library (e.g. `MBPRICE1`), and `*CURLIB` resolves to whatever that is for the profile
running the command. This also means each developer's work naturally lands in their own
library with no extra setup. See
[docs/plans/cicd-pipeline-plan.md](docs/plans/cicd-pipeline-plan.md) Sub-Task 2 for the full
story of why this changed from an earlier hardcoded `TODO` library.

**Three libraries, one profile**: `MBPRICE1` (dev), `MBPRICE2` (test), `MBPRICEB` (production).
Local/interactive work (including Bob's post-stop hook, driven by `.env`'s `IBMI_CURLIB`)
targets `MBPRICE1`. `MBPRICE2` is updated automatically on every push to `main` by
[.github/workflows/deploy-test.yml](.github/workflows/deploy-test.yml) — never deploy or compile
into it by hand, since a manual run would use the shared dev IFS checkout path and diverge from
what CI last put there. `MBPRICEB` is updated manually, by separate instruction, not by either of
the above. See `docs/plans/cicd-pipeline-plan.md` Sub-Task 5 for the full story, including why
`ibmi-deploy.sh`/`ibmi-compile.sh` gained an `IBMI_IFS_DIR` variable to keep the dev and test
IFS checkouts from clobbering each other.

## Compile Commands

`scripts/ibmi-compile.sh` builds via **TOBi** (`/QOpenSys/pkgs/bin/makei build`, formerly
"Bob"/"Better Object Builder") against source deployed by `scripts/ibmi-deploy.sh`, driven by
the project's `iproj.json` and per-directory `Rules.mk` files rather than a hand-maintained CL
sequence. See `docs/plans/cicd-pipeline-plan.md` Sub-Task 7 for why this replaced the old
delete-everything-and-recompile-all script.

The dependency order TOBi builds in is still the one that matters when editing `Rules.mk`:

```cl
CRTPF     FILE(*CURLIB/TODOPF)     SRCSTMF('.../QDDSSRC/TODOPF.PF')
CRTLF     FILE(*CURLIB/TODOLF)     SRCSTMF('.../QDDSSRC/TODOLF.LF')
CRTDSPF   FILE(*CURLIB/TODODSPPF)  SRCSTMF('.../QDDSSRC/TODODSPPF.DSPF')
CRTRPGMOD MODULE(*CURLIB/TODOBL)   SRCSTMF('.../QRPGLESRC/TODOBL.RPGLE')
CRTSRVPGM SRVPGM(*CURLIB/TODOBL)  MODULE(*CURLIB/TODOBL) SRCSTMF('.../QBNDSRC/TODOBL.BND')
CRTBNDDIR BNDDIR(*CURLIB/TODOBND) (with TODOBL *SRVPGM added)
CRTBNDRPG PGM(*CURLIB/TODOMAIN)   SRCSTMF('.../QRPGLESRC/TODOMAIN.RPGLE') BNDDIR(*CURLIB/TODOBND)
CRTRPGMOD MODULE(*CURLIB/TODOTEST) SRCSTMF('.../QRPGLESRC/TODOTEST.RPGLE')
CRTSRVPGM SRVPGM(*CURLIB/TODOTEST) MODULE(*CURLIB/TODOTEST) SRCSTMF('.../QBNDSRC/TODOTEST.BND')
          BNDDIR(*CURLIB/TODOBND) BNDSRVPGM(RPGUNIT/RUCRTTST)
```

`QBNDSRC/TODOBL.BND` and `QBNDSRC/TODOTEST.BND` are binder source added for TOBi — it has no
rule for building a `*SRVPGM` straight from a module the way plain `CRTSRVPGM ... MODULE(...)`
(implicit `EXPORT(*ALL)`) does, so each service program's exports are now declared explicitly
via `STRPGMEXP`/`EXPORT SYMBOL`/`ENDPGMEXP`, matching the `EXPORT`-flagged procedures already in
`TODOBL.RPGLE`/`TODOTEST.RPGLE`.

**RPGUnit is not installed on pub400 (confirmed 2026-09-08)** — the `RPGUNIT` library does not
exist anywhere on this profile (`DSPOBJD OBJ(*ALL/RPGUNIT) OBJTYPE(*LIB)` → object not found), and
it isn't available via `yum`/PASE packages either. Since `iproj.json`'s `preUsrlibl` used to list
`RPGUNIT` unconditionally, this was blocking **every** RPG compile, not just `TODOTEST` — the
`ADDLIBLE` step failing aborted `TODOBL`/`TODOMAIN` too. `preUsrlibl` has been cleared so the main
app builds; `TODOTEST.RPGLE` still can't compile (it needs `/COPY RPGUNIT/QINCLUDE,TESTCASE` at
compile time, not just bind time) and `QBNDSRC/Rules.mk`'s `TODOTEST.SRVPGM` rule still can't
resolve its `| /QSYS.LIB/RPGUNIT.LIB/RUCRTTST.SRVPGM` order-only prerequisite. This is a real
decision point for the team, not a bug to silently work around further: either get RPGUnit
installed on pub400 (likely needs a pub400 admin, or restoring your own SAVF into a personal
library and adjusting the `BNDSRVPGM(RPGUNIT/RUCRTTST)` reference accordingly), or pick a
different automated-test strategy for Sub-Task 3.

**`TODODSPPF.DSPF` had six DDS bugs fixed (2026-09-08):**
1. Two date fields (`TDDUE`, `DETDUE`, `DELDUE`) had `L` in the length column (34) instead of
   the type column (35) — an off-by-one column shift.
2. The `*IN60` conditioning indicator on the TODODET error message was in the keyword area
   (cols 40–41) instead of the field condition columns (cols 7–16).
3. A `+` continuation line in TODODET's instruction constant started one column too far right
   (col 50 instead of 49).
4. All three numeric ID fields (`TDID`, `DETID`, `DELID`) were declared with type `P` (packed
   decimal) — not valid in a DSPF. Changed to `S` (zoned decimal); RPG handles the packed↔zoned
   conversion automatically and `EDTCDE(Z)` continues to suppress leading zeros on output.
5. The Description column-heading underline constant (TODOCTL) was 101 characters — the closing
   `'` was beyond the 80-col `CPYFRMSTMF` truncation point, leaving an unterminated string that
   cascaded `CPD7484` errors across the rest of the file. Shortened to fit within 80 cols.
6. The `+` continuation on the TODODET blank-description error message had the `+` at col 81,
   also beyond the truncation point. Removed one trailing space to move `+` to col 80.

Run: `CALL *CURLIB/TODOMAIN`

Run tests: `RUCALLTST TSTPGM(*CURLIB/TODOTEST)`

## Deploy & Compile

`scripts/ibmi-deploy.sh` and `scripts/ibmi-compile.sh` are the **only** permitted way to deploy
and compile against pub400.com. Never hand-craft `scp` calls or `CRT*` commands directly.

Credentials are read from a `.env` file at the repo root (git-ignored — never commit it). See
`.env.example` for the required variables: `IBMI_USER`, `IBMI_IDENTITY`, and `IBMI_CURLIB` (the
profile's pre-provisioned current library — fixed per pub400 profile, not auto-detected, since
non-interactive SSH jobs have no reliable way to look it up: screen-oriented Display commands
like `DSPUSRPRF` kill the SSH session outright when run without a pty).

Bob runs these scripts automatically via a `Stop` hook (`.bob/hooks/ibmi-post-stop.sh`) after
finishing implementation work. Build output is appended to `.bob/logs/ibmi-build.log`. The hook
deploys the currently checked-out local branch.

## Architecture

The project uses a two-module design:

- **`TODOBL` (`*SRVPGM`)** — owns all file I/O and business logic (`TODOLF`, `TODOPF`, all CRUD procedures). Bound into dependents via the `TODOBND` binding directory.
- **`TODOMAIN` (`*PGM`)** — thin 5250 UI shell. Declares only `TODODSPPF` and delegates all data operations to `TODOBL` via prototypes.

This split allows `TODOBL` to be bound by the RPGUnit test suite (`TODOTEST`) independently of the UI program.

## Critical Conventions

- **All RPG is fully free-form** (`**FREE` at line 1, no column restrictions).
- **`CTL-OPT NOMAIN`** is required on `TODOBL.RPGLE` (it's a `*SRVPGM` module, no program entry point). **`CTL-OPT DFTACTGRP(*NO) ACTGRP(*NEW)`** is required on `TODOMAIN.RPGLE` (it calls a `*SRVPGM` — default activation group cannot bind service programs).
- **`USROPN`** on file declarations in `TODOBL` — files are opened/closed explicitly via `OpenFiles`/`CloseFiles`, not automatically by the program cycle. `TODOMAIN` declares only `TODODSPPF`.
- **`TODOPF` is opened for `*UPDATE:*OUTPUT:*DELETE`**; `TODOLF` is opened read-only. Never write/update/delete through the logical file.
- **`TODOLF` is declared with `RENAME(TODOR:TODOLFR)`** — `TODOLF`'s DDS reuses `TODOPF`'s record format name (`TODOR`). RPG won't allow two open files with the same external format name, so reads against `TODOLF` use the renamed format `TODOLFR` (e.g. `READ TODOLFR`, `READP TODOLFR`), while writes/updates/deletes against `TODOPF` use `TODOR` directly.
- **Block-closing keywords are `ENDIF`/`ENDDO`/`ENDSL` — no hyphen.** Only structured-definition closers take a hyphen: `END-PI`, `END-PR`, `END-DS`, `END-PROC`. Using `END-IF`/`END-DO` is a compile error in fully free-form RPG.
- **Subfile clear sequence is order-sensitive**: set `*IN52=*ON`, `WRITE TODOCTL`, then immediately `*IN52=*OFF` before writing any rows.
- **`*IN50` (SFLDSP) must stay `*OFF` when the subfile has zero rows** — displaying an empty subfile causes a runtime error.
- **`CHAIN` uses `TODOPF` (not `TODOLF`) for all updates, deletes, and mark-done** — positioning on the logical file is only for sequential reads.
- **`w_Found = NOT %EOF(TODOPF)`** — the project uses `%EOF` as the found check after `CHAIN`, not a dedicated `%FOUND` indicator.
- **`DeleteTodoRecord` in `TODOBL` uses a single `CHAIN` + `DELETE`** — the confirmation screen (`EXFMT TODODEL`) is handled in `TODOMAIN` before calling `DeleteTodoRecord`, so no re-chain is needed inside the procedure.
- **Variable prefixes**: `w_` = module-level working storage, `l_` = local to a procedure, `DET*` = TODODET screen fields, `DEL*` = TODODEL screen fields, `SFL*` = subfile fields.
- **DDS uses fixed-column layout** (columns 1–80): `A` in col 6, record/field name in cols 19–28, type in col 35, length/positions thereafter. Do not reformat DDS with a code formatter.
- **Indicator map** is documented in both `TODODSPPF.DSPF` header and `TODOMAIN.RPGLE` header — keep both in sync when adding indicators.
- **Target library is `*CURLIB`** — used in all compile commands and the `PFILE(*CURLIB/TODOPF)` reference in `TODOLF.LF`, so it resolves per-profile rather than to one hardcoded library name (pub400.com doesn't allow arbitrary library creation).
