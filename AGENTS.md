# AGENTS.md

This file provides guidance to agents when working with code in this repository.

## Project

IBM i RPG 5250 green-screen todo application targeting pub400.com.
No package manager, no build tool — compilation happens on the IBM i server via CL commands.

## Repo Layout

```
QDDSSRC/        ← DDS source (mirrors TODO/QDDSSRC source physical file on server)
QRPGLESRC/      ← RPG source (mirrors TODO/QRPGLESRC source physical file on server)
docs/           ← Human-readable docs only (not uploaded to IBM i)
```

File extensions are IBM i member types: `.PF`, `.LF`, `.DSPF`, `.RPGLE`

## Compile Commands (must run in this exact order)

```cl
CRTPF     FILE(TODO/TODOPF)     SRCFILE(TODO/QDDSSRC)    SRCMBR(TODOPF)
CRTLF     FILE(TODO/TODOLF)     SRCFILE(TODO/QDDSSRC)    SRCMBR(TODOLF)
CRTDSPF   FILE(TODO/TODODSPPF)  SRCFILE(TODO/QDDSSRC)    SRCMBR(TODODSPPF)
CRTBNDRPG PGM(TODO/TODOMAIN)    SRCFILE(TODO/QRPGLESRC)  SRCMBR(TODOMAIN)
```

Run: `CALL TODO/TODOMAIN`

## Critical Conventions

- **All RPG is fully free-form** (`**FREE` at line 1, no column restrictions).
- **`USROPN`** on both file declarations — files are opened/closed explicitly in `Main()`, not automatically by the program cycle.
- **`TODOPF` is opened for `*UPDATE:*OUTPUT:*DELETE`**; `TODOLF` is opened read-only. Never write/update/delete through the logical file.
- **Subfile clear sequence is order-sensitive**: set `*IN52=*ON`, `WRITE TODOCTL`, then immediately `*IN52=*OFF` before writing any rows.
- **`*IN50` (SFLDSP) must stay `*OFF` when the subfile has zero rows** — displaying an empty subfile causes a runtime error.
- **`CHAIN` uses `TODOPF` (not `TODOLF`) for all updates, deletes, and mark-done** — positioning on the logical file is only for sequential reads.
- **`w_Found = NOT %EOF(TODOPF)`** — the project uses `%EOF` as the found check after `CHAIN`, not a dedicated `%FOUND` indicator.
- **`DeleteTodo` re-chains before `DELETE`** — after `EXFMT TODODEL` the record lock is released, so a second `CHAIN` is required before deleting.
- **Variable prefixes**: `w_` = module-level working storage, `l_` = local to a procedure, `DET*` = TODODET screen fields, `DEL*` = TODODEL screen fields, `SFL*` = subfile fields.
- **DDS uses fixed-column layout** (columns 1–80): `A` in col 6, record/field name in cols 19–28, type in col 35, length/positions thereafter. Do not reformat DDS with a code formatter.
- **Indicator map** is documented in both `TODODSPPF.DSPF` header and `TODOMAIN.RPGLE` header — keep both in sync when adding indicators.
- **Library name is `TODO`** — hardcoded in all compile commands and `PFILE(TODO/TODOPF)` reference in `TODOLF.LF`. Update if deploying under a different library.
