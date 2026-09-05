# Project Documentation Rules (Non-Obvious Only)

- `docs/DEPLOY.md` is the single source of truth for compile commands and upload steps — the compile order in that file must match the dependency order: TODOPF → TODOLF → TODODSPPF → TODOMAIN.
- The indicator map exists in **two places**: `QDDSSRC/TODODSPPF.DSPF` header and `QRPGLESRC/TODOMAIN.RPGLE` header — both must be updated together when indicators change.
- `QDDSSRC/TODOLF.LF` references the physical file as `PFILE(*CURLIB/TODOPF)` — resolves to whichever library is current for the compiling profile, not a hardcoded name (pub400.com restricts library creation).
- There is no test suite and no linter — correctness is verified by compiling on the IBM i server and inspecting the job log (`DSPJOBLOG`).
