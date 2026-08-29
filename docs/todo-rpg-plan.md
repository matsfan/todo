# IBM i RPG Todo Application — Plan

## Overview

Build a simple 5250 green-screen todo application for IBM i (pub400.com) using:
- **Free-form RPGLE** for the main program
- **DDS Physical File** for data storage
- **DDS Logical File** for a keyed view used by the subfile
- **DDS Display File** for all 5250 screens

All objects compile into the user's default library (`YOURLIB` placeholder throughout).

### Fields stored per todo
| Field | Type | Notes |
|---|---|---|
| TDID | Packed(5,0) | Unique sequential numeric ID |
| TDDESC | Char(50) | Description |
| TDDONE | Char(1) | Done flag: '0'=pending, '1'=done |
| TDDUE | Date (ISO) | Due date |

### Screen flow
- **LIST screen** — subfile showing only incomplete todos; option column: `2`=Edit, `4`=Delete, `5`=Mark Done
- **ADD/EDIT screen** — enter/change description and due date
- **DELETE CONFIRM screen** — confirm before removing a record
- F6 on list = Add new todo
- After any action, return to refreshed list

---

## Sub-Tasks

---

### Sub-Task 1 — Physical File (TODOPF)

**Intent**  
Define the database table that stores all todo records. This is the foundation everything else builds on.

**Expected Outcomes**
- `TODOPF.dds` source member exists and is ready to compile as a Physical File
- Contains all four fields: TDID, TDDESC, TDDONE, TDDUE
- TDID is the unique key

**Todo List**
1. Create `TODOPF.dds` with DDS column layout
2. Define record format `TODOR`
3. Define fields: TDID (5P 0), TDDESC (50A), TDDONE (1A), TDDUE (date in ISO format L field)
4. Set TDID as the unique key field
5. Add compile instructions as a comment header (CRTPF command for YOURLIB)

**Relevant Context**
- DDS physical files use `K` in column 17 to define key fields
- Date field in DDS: type `L`, date format keyword `DATFMT(*ISO)`
- Compile command: `CRTPF FILE(YOURLIB/TODOPF) SRCFILE(YOURLIB/QDDSSRC)`

**Status:** [x] done

---

### Sub-Task 2 — Logical File (TODOLF)

**Intent**  
Define a keyed logical file over TODOPF. The RPG subfile loader will read through TODOLF in ID order. A logical file also lets us add a select/omit rule to filter done records at the file level, though filtering will be done in RPG for clarity.

**Expected Outcomes**
- `TODOLF.dds` source member exists and is ready to compile as a Logical File over TODOPF
- Keyed by TDID in ascending order
- No select/omit (filtering handled in RPG)

**Todo List**
1. Create `TODOLF.dds` with DDS column layout
2. Reference base file `TODOPF` using `PFILE` keyword
3. Define same record format name `TODOR` (or use `JFILE`-free single-format approach)
4. Specify TDID as the key field
5. Add compile instructions as a comment header (CRTLF command for YOURLIB)

**Relevant Context**
- DDS logical file: `PFILE(YOURLIB/TODOPF)` on the record format line (column 45+)
- Compile command: `CRTLF FILE(YOURLIB/TODOLF) SRCFILE(YOURLIB/QDDSSRC)`

**Status:** [x] done

---

### Sub-Task 3 — Display File (TODODSPPF)

**Intent**  
Define all 5250 screen layouts in a single DDS Display File. Three record formats are needed: the subfile itself, the subfile control (list screen), and the add/edit detail screen. A fourth minimal format handles the delete confirmation.

**Expected Outcomes**
- `TODODSPPF.dds` source exists and is ready to compile as a Display File
- Record formats:
  - `TODOSFL` — subfile record (one row per todo: option, ID, description, due date, done indicator)
  - `TODOCTL` — subfile control (F3=Exit, F6=Add, page keys, column headings)
  - `TODODET` — add/edit detail screen (description input, due date input)
  - `TODODEL` — delete confirmation screen (shows description, Confirm/Cancel)
- Indicator map documented in comments (which `*IN` indicators control SFL/CTL behaviour)

**Todo List**
1. Create `TODODSPPF.dds`
2. Define `TODOSFL` subfile record format with option field, display-only ID, description, due date, done flag
3. Define `TODOCTL` subfile control record — `SFLCTL(TODOSFL)`, `SFLSIZ`, `SFLDSP`, `SFLDSPCTL`, `SFLCLR`, `SFLEND`; add function key indicators F3, F6; column headings
4. Define `TODODET` record — input fields for description (50A) and due date, plus F3=Cancel, F12=Cancel indicators; display-only ID field for edit mode
5. Define `TODODEL` record — display-only description, Enter=confirm, F12=cancel
6. Document indicator assignments in a comment block at the top of the file
7. Add compile instructions (CRTDSPF command for YOURLIB)

**Relevant Context**
- Suggested indicator assignments:
  - `*IN50` — SFLDSP (show subfile records)
  - `*IN51` — SFLDSPCTL (show subfile control)
  - `*IN52` — SFLCLR (clear subfile)
  - `*IN53` — SFLEND (end of subfile / "More..." indicator)
  - `*IN03` — F3 exit
  - `*IN06` — F6 add
  - `*IN12` — F12 cancel
- Compile command: `CRTDSPF FILE(YOURLIB/TODODSPPF) SRCFILE(YOURLIB/QDDSSRC)`

**Status:** [x] done

---

### Sub-Task 4 — Main RPG Program (TODOMAIN)

**Intent**  
Write the free-form RPGLE program that ties everything together: drives the screens, reads/writes the physical file through the logical file, and implements all CRUD operations.

**Expected Outcomes**
- `TODOMAIN.rpgle` source exists and is ready to compile as a bound RPG program (`CRTBNDRPG`)
- Program logic covers:
  - **List / Load subfile** — read TODOLF, skip records where TDDONE = '1', write each to subfile
  - **Add** — display TODODET with blank fields, read input, generate next ID, write new record to TODOPF
  - **Edit (Option 2)** — chain to TODOPF by ID, display TODODET pre-filled, update record on Enter
  - **Mark Done (Option 5)** — chain to TODOPF by ID, set TDDONE='1', update record, refresh list
  - **Delete (Option 4)** — display TODODEL confirm screen; on confirm, delete record from TODOPF
  - **Exit (F3)** — `*INLR = *ON`, return
- Clean program cycle: loop back to refresh/reload list after every action

**Todo List**
1. Create `TODOMAIN.rpgle` with `/FREE` style (fully free-form, no column restrictions)
2. Define file declarations: TODOLF (input, keyed), TODOPF (update/add/delete, keyed), TODODSPPF (workstn CF)
3. Define working variables: current option, selected ID, next ID counter, mode flag (add vs edit)
4. Write `LoadSubfile` subroutine: clear SFL, set SFLCLR on, read all TODOLF records skipping TDDONE='1', write to TODOSFL, set SFLDSP/SFLDSPCTL on
5. Write main loop: EXFMT TODOCTL, evaluate F3/F6/option column
6. Write `AddTodo` logic: blank TODODET fields, EXFMT TODODET, on Enter generate ID and WRITE to TODOPF
7. Write `EditTodo` logic: CHAIN to TODOPF, populate TODODET fields, EXFMT TODODET, on Enter UPDATE TODOPF
8. Write `MarkDone` logic: CHAIN to TODOPF, set TDDONE='1', UPDATE TODOPF
9. Write `DeleteTodo` logic: CHAIN to TODOPF, display TODODEL, on Enter DELETE TODOPF record
10. Write `GetNextId` logic: SETLL *END to TODOLF, READPE (read prior) to get last record, increment TDID by 1
11. Add compile instructions as comment header (CRTBNDRPG command for YOURLIB)

**Relevant Context**
- Free-form RPG file declarations use `DCL-F`
- WORKSTN file with `SFILE(TODOSFL:RRN)` keyword needed for subfile record number tracking
- `EXFMT` both writes and reads a display format in one op
- `CHAIN` does a keyed random read; `WRITE`/`UPDATE`/`DELETE` operate on the last-accessed record
- Compile command: `CRTBNDRPG PGM(YOURLIB/TODOMAIN) SRCFILE(YOURLIB/QRPGLESRC)`

**Status:** [x] done

---

### Sub-Task 5 — Compile & Deploy Instructions

**Intent**  
Provide a step-by-step guide for uploading the source members to pub400.com and compiling all objects in the correct dependency order.

**Expected Outcomes**
- `DEPLOY.md` file with copy-paste IBM i commands in the correct sequence
- Covers: creating source physical files (QDDSSRC, QRPGLESRC), uploading members, compile order
- Notes any pub400.com-specific considerations (5250 emulator setup, IFS vs source members)

**Todo List**
1. Create `DEPLOY.md`
2. Document source file creation commands (`CRTSRCPF`)
3. Document member upload options (SEU, RDi, VS Code with IBM i extension, or `CPYFRMSTMF`)
4. List compile commands in dependency order: TODOPF → TODOLF → TODODSPPF → TODOMAIN
5. Add a "first run" section: how to call the program (`CALL YOURLIB/TODOMAIN`)
6. Add tips for pub400.com: TN5250 emulator recommendation, library list setup (`ADDLIBLE`)

**Status:** [x] done

---

## Compile Order Summary

```
CRTSRCPF FILE(YOURLIB/QDDSSRC)
CRTSRCPF FILE(YOURLIB/QRPGLESRC)

CRTPF    FILE(YOURLIB/TODOPF)    SRCFILE(YOURLIB/QDDSSRC)
CRTLF    FILE(YOURLIB/TODOLF)    SRCFILE(YOURLIB/QDDSSRC)
CRTDSPF  FILE(YOURLIB/TODODSPPF) SRCFILE(YOURLIB/QDDSSRC)
CRTBNDRPG PGM(YOURLIB/TODOMAIN)  SRCFILE(YOURLIB/QRPGLESRC)
```

## Placeholder Reminder
Replace `YOURLIB` everywhere with your actual pub400.com username library before compiling.
