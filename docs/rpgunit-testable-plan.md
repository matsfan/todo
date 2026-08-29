# RPGUnit Testable Refactor Plan

## Overview

The existing `TODOMAIN` program is a monolithic RPG source member that mixes screen I/O, file I/O, and business logic in the same procedures. RPGUnit tests call procedures inside a `*SRVPGM` (service program), so the program must first be split so that the testable logic lives in a service program that both the UI program and the test suite can bind to.

**Goal:** Refactor `TODOMAIN` into a thin UI shell plus a separate business/data service program (`TODOBL`), then write an RPGUnit test service program (`TODOTEST`) that exercises the four agreed behaviours.

**Scope:**
- New source member `TODOBL.RPGLE` — business + data logic compiled as `CRTSRVPGM`
- New source member `TODOTEST.RPGLE` — RPGUnit test suite compiled as `CRTSRVPGM`
- Modified `TODOMAIN.RPGLE` — thin screen-loop shell that calls `TODOBL` by prototype
- New `TODOBND` binding directory to link `TODOBL` into both `TODOMAIN` and `TODOTEST`
- `AGENTS.md` and the docs directory updated to reflect the new architecture

**Non-goals:**
- No UI changes (screens, indicators, DDS files stay identical)
- No changes to `TODOPF.PF` or `TODOLF.LF`
- No modernisation of the 5250 flow beyond what is needed for testability

---

## RPGUnit Background (for newcomers)

RPGUnit is an open-source unit-testing framework for IBM i RPG programs. A test suite is a `*SRVPGM` where every exported procedure whose name starts with `test` is automatically discovered and executed by the RPGUnit runner. Inside each test procedure you call `ASSERT*` macros (e.g., `aEqual`, `iEqual`, `assert`) provided by the RPGUnit copy member `RUTESTCASE`. The runner reports pass/fail for each `test*` procedure.

The typical workflow is:
1. Write a `*SRVPGM` (`TODOTEST`) that binds to your business service program (`TODOBL`).
2. Each `test*` procedure sets up data, calls a `TODOBL` procedure, and asserts the result.
3. Run with: `RUCALLTST TSTPGM(TODO/TODOTEST)`

---

## Sub-Tasks

---

### Sub-Task 1 — Create `TODOBL.RPGLE` service program

**Status:** [x] done

**Intent:**
Extract all file declarations, `OpenFiles`/`CloseFiles`, and every data-manipulation procedure from `TODOMAIN` into a new self-contained service program. This is the prerequisite for all subsequent sub-tasks. After this sub-task, `TODOBL` is the single place that owns `TODOLF`, `TODOPF`, and all CRUD logic.

**Expected Outcomes:**
- `QRPGLESRC/TODOBL.RPGLE` exists and compiles cleanly with `CRTSRVPGM`
- The following procedures are exported with prototypes visible to callers:
  - `OpenFiles` — opens `TODOLF` and `TODOPF` (replaces the open calls currently in `Main`)
  - `CloseFiles` — closes both files
  - `GetNextId` — returns the next available todo ID (5 0 numeric)
  - `ValidateDescription(desc)` — returns `*ON` if description is non-blank, `*OFF` if blank/spaces
  - `AddTodoRecord(id, desc, due)` — writes a new record to `TODOPF`
  - `EditTodoRecord(id, desc, due)` — updates an existing record in `TODOPF`
  - `MarkDoneRecord(id)` — sets `TDDONE='1'` on the record with the given ID
  - `DeleteTodoRecord(id)` — deletes the record with the given ID
  - `ReadFirstTodo(rec)` — positions `TODOLF` to `*START` and reads the first non-done record; returns `*ON` if found
  - `ReadNextTodo(rec)` — reads the next non-done record; returns `*ON` if found
- All procedures use `TODOPF` for mutations and `TODOLF` for sequential reads, matching current conventions
- File declarations keep `USROPN`

**Todo List:**
1. Create `QRPGLESRC/TODOBL.RPGLE` starting with `**FREE`
2. Copy file declarations for `TODOLF` and `TODOPF` from `TODOMAIN.RPGLE` (keep `USROPN`)
3. Write the `OpenFiles` and `CloseFiles` procedures
4. Move `GetNextId` logic verbatim; expose as exported procedure with a prototype
5. Write `ValidateDescription` as a new pure procedure (the blank-check currently embedded in `AddTodo`/`EditTodo`)
6. Move CRUD body logic from `AddTodo`, `EditTodo`, `MarkDone`, `DeleteTodo` into the corresponding `*Record` procedures; strip away all `EXFMT`/screen references — these procedures only do file I/O
7. Write `ReadFirstTodo` and `ReadNextTodo` to encapsulate the sequential-read loop that `LoadSubfile` currently does inline
8. Add a `/COPY` copybook section (or inline prototypes) so callers can include the prototypes
9. Verify the source compiles: `CRTSRVPGM SRVPGM(TODO/TODOBL) MODULE(TODO/TODOBL) SRCFILE(TODO/QRPGLESRC)`

**Relevant Context:**
- `QRPGLESRC/TODOMAIN.RPGLE` lines 33–44: file declarations to copy
- `TODOMAIN.RPGLE` lines 179–195: `GetNextId` — move verbatim
- `TODOMAIN.RPGLE` lines 285–293: `MarkDone` — move, rename `MarkDoneRecord`
- `TODOMAIN.RPGLE` lines 299–321: `DeleteTodo` — move data-only part, rename `DeleteTodoRecord`
- `TODOMAIN.RPGLE` lines 218–221 and 265–268: the blank-description check to extract into `ValidateDescription`
- `TODOMAIN.RPGLE` lines 143–162: the `READ TODOLF` / `WRITE TODOSFL` loop — `ReadFirstTodo`/`ReadNextTodo` replaces the file-I/O portion

---

### Sub-Task 2 — Refactor `TODOMAIN.RPGLE` into a thin UI shell

**Status:** [x] done

**Intent:**
Strip `TODOMAIN` down to only what a screen-handling program needs: the display file declaration, the `EXFMT` loops, indicator management, and calls to `TODOBL` procedures via prototypes. No file declarations, no `CHAIN`, no `READ`, no `WRITE TODOPF` remain in `TODOMAIN`.

**Expected Outcomes:**
- `TODOMAIN.RPGLE` retains only:
  - `TODODSPPF` display file declaration
  - Working storage for screen state (indicators, `w_Rrn`, `w_Mode`, etc.)
  - `Main` procedure with the screen loop, `LoadSubfile`, `AddTodo`, `EditTodo`, `MarkDone`, `DeleteTodo` — but these now call `TODOBL` procedures for all data operations
- `TODOMAIN` compiles cleanly: `CRTBNDRPG PGM(TODO/TODOMAIN) SRCFILE(TODO/QRPGLESRC) SRCMBR(TODOMAIN) BNDDIR(TODO/TODOBND)`
- The running program behaves identically to the original from a user perspective

**Todo List:**
1. Remove file declarations for `TODOLF` and `TODOPF` from `TODOMAIN.RPGLE`
2. Add `/COPY` or inline prototypes for all `TODOBL` exported procedures
3. Replace the file-open/close calls in `Main` with `OpenFiles`/`CloseFiles`
4. Replace the sequential `READ TODOLF` loop in `LoadSubfile` with calls to `ReadFirstTodo`/`ReadNextTodo`
5. Replace the `GetNextId()` call in `AddTodo` with the `TODOBL` version (prototype already matches)
6. Replace the `CHAIN`/`WRITE TODOPF` in `AddTodo` with `AddTodoRecord(w_NextId, DETDESC, DETDUE)`
7. Replace the `CHAIN`/`UPDATE TODOR` in `EditTodo` with `EditTodoRecord(w_SelId, DETDESC, DETDUE)`
8. Replace the `CHAIN`/`UPDATE` in `MarkDone` with `MarkDoneRecord(w_SelId)`
9. Replace the `CHAIN`/`DELETE` in `DeleteTodo` with `DeleteTodoRecord(w_SelId)` (the data part only; keep the `EXFMT TODODEL` confirmation screen)
10. Replace the inline blank-check with `ValidateDescription(DETDESC)` in both `AddTodo` and `EditTodo`
11. Compile and confirm behaviour is unchanged

**Relevant Context:**
- `TODOMAIN.RPGLE` lines 67–124: `Main` procedure — remove file opens/closes
- `TODOMAIN.RPGLE` lines 130–173: `LoadSubfile` — replace inner READ loop
- `TODOMAIN.RPGLE` lines 201–235: `AddTodo` — replace CHAIN + WRITE + blank-check
- `TODOMAIN.RPGLE` lines 241–279: `EditTodo` — replace CHAIN + UPDATE + blank-check
- `TODOMAIN.RPGLE` lines 285–293: `MarkDone` — replace CHAIN + UPDATE
- `TODOMAIN.RPGLE` lines 299–321: `DeleteTodo` — replace data portion only

---

### Sub-Task 3 — Create `TODOBND` binding directory

**Status:** [x] done

**Intent:**
A binding directory is an IBM i object that lists service programs to bind to. Both `TODOMAIN` and `TODOTEST` need to find `TODOBL` at compile time. Creating `TODOBND` now makes both compile steps identical and avoids hardcoding the bind list in each compile command.

**Expected Outcomes:**
- `TODO/TODOBND` binding directory exists on IBM i
- It contains one entry: `TODO/TODOBL`
- `TODOMAIN` recompiles cleanly using `BNDDIR(TODO/TODOBND)`

**Todo List:**
1. Run: `CRTBNDDIR BNDDIR(TODO/TODOBND)`
2. Run: `ADDBNDDIRE BNDDIR(TODO/TODOBND) OBJ((TODO/TODOBL *SRVPGM))`
3. Recompile `TODOMAIN` with `BNDDIR(TODO/TODOBND)` to confirm linkage works
4. Document the `TODOBND` commands in `AGENTS.md` compile section

**Relevant Context:**
- `AGENTS.md` compile commands section — add the two new CL commands before the `CRTBNDRPG` step

---

### Sub-Task 4 — Write `TODOTEST.RPGLE` RPGUnit test suite

**Status:** [x] done

**Intent:**
Write the RPGUnit test service program that exercises the four agreed behaviours using the `ASSERT*` macros from RPGUnit's `RUTESTCASE` copy member. Each test is self-contained: it sets up whatever records it needs, calls the `TODOBL` procedure under test, asserts the result, and cleans up any inserted records.

**Expected Outcomes:**
- `QRPGLESRC/TODOTEST.RPGLE` exists
- The following test procedures are present and correctly named (prefix `test`):
  - `testGetNextId_EmptyFile` — clears file, calls `GetNextId`, asserts result = 1, restores state
  - `testGetNextId_WithRecords` — inserts a known record with ID 77, calls `GetNextId`, asserts result = 78, deletes record
  - `testValidateDescription_Blank` — calls `ValidateDescription('')`, asserts returns `*OFF`
  - `testValidateDescription_Spaces` — calls `ValidateDescription('   ')`, asserts returns `*OFF`
  - `testValidateDescription_Valid` — calls `ValidateDescription('Buy milk')`, asserts returns `*ON`
  - `testAddTodoRecord` — calls `AddTodoRecord`, reads back the record, asserts all fields match, then deletes the record
  - `testMarkDoneRecord` — inserts a record with `TDDONE='0'`, calls `MarkDoneRecord`, reads back, asserts `TDDONE='1'`, deletes record
- All tests pass when run via `RUCALLTST TSTPGM(TODO/TODOTEST)`

**Todo List:**
1. Create `QRPGLESRC/TODOTEST.RPGLE` starting with `**FREE`
2. Add `/COPY QRPGLESRC,RUTESTCASE` (or RPGUnit's standard copy member path on pub400.com) for `ASSERT*` macros
3. Add prototypes for `TODOBL` exported procedures
4. Write a `setUp` procedure (called automatically by RPGUnit before each test) that calls `OpenFiles`
5. Write a `tearDown` procedure (called automatically after each test) that calls `CloseFiles`
6. Implement each of the seven test procedures listed above; each test cleans up its own data
7. Compile: `CRTSRVPGM SRVPGM(TODO/TODOTEST) MODULE(TODO/TODOTEST) BNDDIR(TODO/TODOBND) BNDSRVPGM(RPGUNIT/RUTESTCASE)`
8. Run: `RUCALLTST TSTPGM(TODO/TODOTEST)` and confirm all tests pass

**Relevant Context:**
- RPGUnit copy member is typically at `RPGUNIT/QRPGLESRC,RUTESTCASE` on pub400.com — verify the exact path before coding
- `setUp`/`tearDown` are RPGUnit reserved procedure names called before/after each `test*` procedure
- For `testGetNextId_EmptyFile`: note that deleting all records from `TODOPF` is destructive; a safer approach is to write a high-watermark record, call `GetNextId`, then delete only that record, and instead directly test `GetNextId` against a known last ID
- `TODOPF` is opened for `*UPDATE:*OUTPUT:*DELETE` — tests that insert records must use WRITE through `TODOBL`'s `AddTodoRecord` or via a direct WRITE if a test-helper procedure is added

---

### Sub-Task 5 — Update documentation

**Status:** [x] done

**Intent:**
Keep `AGENTS.md` and any docs accurate so future agents and developers understand the new two-module architecture without reading source code.

**Expected Outcomes:**
- `AGENTS.md` compile commands updated with the full ordered sequence including `TODOBL` and `TODOBND`
- Architecture section added (or updated) explaining the `TODOBL` / `TODOMAIN` split and the `TODOTEST` test suite
- `AGENTS.md` critical conventions section updated: note that file declarations now live only in `TODOBL`, not `TODOMAIN`

**Todo List:**
1. Update the "Compile Commands" section in `AGENTS.md` to include:
   - `CRTSRVPGM` for `TODOBL` (after DDS objects, before `CRTBNDRPG`)
   - `CRTBNDDIR` and `ADDBNDDIRE` for `TODOBND`
   - `CRTSRVPGM` for `TODOTEST` (at the end)
2. Add a note that `TODOMAIN` now requires `BNDDIR(TODO/TODOBND)` in `CRTBNDRPG`
3. Add an architecture note explaining the service program split and that all file I/O is in `TODOBL`
4. Update the indicator map note if any indicators are affected (they are not — screens are unchanged)

**Relevant Context:**
- `AGENTS.md` "Compile Commands" section
- `AGENTS.md` "Critical Conventions" section — the `USROPN` and `TODOPF`/`TODOLF` notes need to reference `TODOBL` not `TODOMAIN`
