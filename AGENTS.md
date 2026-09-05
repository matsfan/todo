# AGENTS.md

This file provides guidance to agents when working with code in this repository.

## Project

IBM i RPG 5250 green-screen todo application targeting pub400.com.
No package manager, no build tool — compilation happens on the IBM i server via CL commands.

## Repo Layout

```
QDDSSRC/        ← DDS source, pulled directly onto the IFS on pub400 via `git clone`/`git pull`
QRPGLESRC/      ← RPG source, same git-based deploy — no source physical file involved
docs/           ← Human-readable docs only (not uploaded to IBM i)
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

## Compile Commands (must run in this exact order)

```cl
CRTPF     FILE(*CURLIB/TODOPF)     SRCSTMF('.../QDDSSRC/TODOPF.PF')
CRTLF     FILE(*CURLIB/TODOLF)     SRCSTMF('.../QDDSSRC/TODOLF.LF')
CRTDSPF   FILE(*CURLIB/TODODSPPF)  SRCSTMF('.../QDDSSRC/TODODSPPF.DSPF')
CRTBNDDIR BNDDIR(*CURLIB/TODOBND)
CRTRPGMOD MODULE(*CURLIB/TODOBL)   SRCSTMF('.../QRPGLESRC/TODOBL.RPGLE')
CRTSRVPGM SRVPGM(*CURLIB/TODOBL)  MODULE(*CURLIB/TODOBL)
ADDBNDDIRE BNDDIR(*CURLIB/TODOBND) OBJ((*CURLIB/TODOBL *SRVPGM))
CRTBNDRPG PGM(*CURLIB/TODOMAIN)   SRCSTMF('.../QRPGLESRC/TODOMAIN.RPGLE') BNDDIR(*CURLIB/TODOBND)
CRTRPGMOD MODULE(*CURLIB/TODOTEST) SRCSTMF('.../QRPGLESRC/TODOTEST.RPGLE')
CRTSRVPGM SRVPGM(*CURLIB/TODOTEST) MODULE(*CURLIB/TODOTEST) BNDDIR(*CURLIB/TODOBND) BNDSRVPGM(RPGUNIT/RUCRTTST)
```

`scripts/ibmi-compile.sh` runs this exact sequence (with `OPTION(*EVENTF) DBGVIEW(*SOURCE)
TGTCCSID(*JOB)` on each compile step) against source deployed by `scripts/ibmi-deploy.sh`.

Run: `CALL *CURLIB/TODOMAIN`

Run tests: `RUCALLTST TSTPGM(*CURLIB/TODOTEST)`

## Architecture

The project uses a two-module design:

- **`TODOBL` (`*SRVPGM`)** — owns all file I/O and business logic (`TODOLF`, `TODOPF`, all CRUD procedures). Bound into dependents via the `TODOBND` binding directory.
- **`TODOMAIN` (`*PGM`)** — thin 5250 UI shell. Declares only `TODODSPPF` and delegates all data operations to `TODOBL` via prototypes.

This split allows `TODOBL` to be bound by the RPGUnit test suite (`TODOTEST`) independently of the UI program.

## Critical Conventions

- **All RPG is fully free-form** (`**FREE` at line 1, no column restrictions).
- **`USROPN`** on file declarations in `TODOBL` — files are opened/closed explicitly via `OpenFiles`/`CloseFiles`, not automatically by the program cycle. `TODOMAIN` declares only `TODODSPPF`.
- **`TODOPF` is opened for `*UPDATE:*OUTPUT:*DELETE`**; `TODOLF` is opened read-only. Never write/update/delete through the logical file.
- **Subfile clear sequence is order-sensitive**: set `*IN52=*ON`, `WRITE TODOCTL`, then immediately `*IN52=*OFF` before writing any rows.
- **`*IN50` (SFLDSP) must stay `*OFF` when the subfile has zero rows** — displaying an empty subfile causes a runtime error.
- **`CHAIN` uses `TODOPF` (not `TODOLF`) for all updates, deletes, and mark-done** — positioning on the logical file is only for sequential reads.
- **`w_Found = NOT %EOF(TODOPF)`** — the project uses `%EOF` as the found check after `CHAIN`, not a dedicated `%FOUND` indicator.
- **`DeleteTodoRecord` in `TODOBL` uses a single `CHAIN` + `DELETE`** — the confirmation screen (`EXFMT TODODEL`) is handled in `TODOMAIN` before calling `DeleteTodoRecord`, so no re-chain is needed inside the procedure.
- **Variable prefixes**: `w_` = module-level working storage, `l_` = local to a procedure, `DET*` = TODODET screen fields, `DEL*` = TODODEL screen fields, `SFL*` = subfile fields.
- **DDS uses fixed-column layout** (columns 1–80): `A` in col 6, record/field name in cols 19–28, type in col 35, length/positions thereafter. Do not reformat DDS with a code formatter.
- **Indicator map** is documented in both `TODODSPPF.DSPF` header and `TODOMAIN.RPGLE` header — keep both in sync when adding indicators.
- **Target library is `*CURLIB`** — used in all compile commands and the `PFILE(*CURLIB/TODOPF)` reference in `TODOLF.LF`, so it resolves per-profile rather than to one hardcoded library name (pub400.com doesn't allow arbitrary library creation).
