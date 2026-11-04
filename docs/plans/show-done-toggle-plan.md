# Show/Hide Completed Todos Feature Plan

## Overview

Add an F5 toggle to the list screen that lets the user switch between showing only
incomplete todos (the current behaviour) and showing all todos including completed
ones. When showing all, a `*` marker in the Done column visually distinguishes
completed items.

No database schema changes are required — `TDDONE` already stores the done flag.

Completed todos will display `*` in the Done column (replacing the raw `1` value).
All options (2=Edit, 4=Delete, 5=Mark Done) remain available on completed items;
option 5 on an already-done item will silently re-mark it done (no-op in effect).

---

## Architecture

The `TDDONE='1'` filter currently lives inside `ReadNextTodo` in `TODOBL.RPGLE`
(line 292). Adding a parameter to the existing procedures would change the
`TODOBL.BND` export signatures and could break callers. Instead:

- Add two new exported procedures to `TODOBL`: `ReadFirstTodoAll` / `ReadNextTodoAll`
  that read all records regardless of `TDDONE`.
- Add those two symbols to `QBNDSRC/TODOBL.BND`.
- In `TODOMAIN`, track toggle state in a new `w_ShowDone` indicator and call the
  appropriate pair of read procedures in `LoadSubfile`.
- Add F5 to `TODODSPPF` on `TODOCTL`, add a second footer format `TODOFTR2` that
  shows the "Hide Done" label, and conditionally write the right footer.

---

## Sub-Task 1 — Add ReadFirstTodoAll / ReadNextTodoAll to TODOBL

**Status:** [ ] pending

**Intent:**
Add two new procedures to `TODOBL.RPGLE` that behave identically to
`ReadFirstTodo`/`ReadNextTodo` but skip the `TDDONE <> '1'` filter. This keeps the
existing procedures unchanged (no risk of breaking `TODOTEST`) and gives `TODOMAIN`
a clean API to call when the toggle is in "show all" mode.

**Expected Outcomes:**
- `TODOBL.RPGLE` contains `ReadFirstTodoAll` and `ReadNextTodoAll` procedures,
  both flagged `EXPORT`.
- Both procedures have matching `DCL-PR` prototypes in `TODOBL.RPGLE`.
- `QBNDSRC/TODOBL.BND` has `EXPORT SYMBOL('READFIRSTTODOALL')` and
  `EXPORT SYMBOL('READNEXTTODOALL')` entries.
- `TODOBL.RPGLE`'s header comment export list is updated to include both new
  procedures.
- In `TODOSFL` the `TDDONE` field display is updated so `*` shows for done items.

**Todo List:**
1. In `QRPGLESRC/TODOBL.RPGLE`:
   - Add `DCL-PR` prototypes for `ReadFirstTodoAll` and `ReadNextTodoAll` (same
     signatures as `ReadFirstTodo`/`ReadNextTodo`).
   - Add `DCL-PROC ReadFirstTodoAll EXPORT` — identical to `ReadFirstTodo` but
     calls `ReadNextTodoAll` instead of `ReadNextTodo`.
   - Add `DCL-PROC ReadNextTodoAll EXPORT` — identical to `ReadNextTodo` but
     without the `IF TDDONE <> '1'` guard (reads every record).
   - Update the header comment export list to include the two new procedures.
2. In `QBNDSRC/TODOBL.BND`:
   - Add `EXPORT SYMBOL('READFIRSTTODOALL')` and `EXPORT SYMBOL('READNEXTTODOALL')`
     after the existing `ReadNextTodo` entry.

**Relevant Context:**
- `ReadNextTodo` is at line 280–304 of `QRPGLESRC/TODOBL.RPGLE` — the only change
  for the "all" variant is removing the `IF TDDONE <> '1'` guard.
- `EXTPROC` names must be uppercase strings — `EXTPROC('READFIRSTTODOALL')` and
  `EXTPROC('READNEXTTODOALL')`.
- `QBNDSRC/TODOBL.BND` uses `STRPGMEXP`/`EXPORT SYMBOL`/`ENDPGMEXP` — add the two
  new symbols inside the existing `STRPGMEXP` block.

---

## Sub-Task 2 — Update TODODSPPF display file

**Status:** [ ] pending

**Intent:**
Add F5 to `TODOCTL` as the show/hide toggle key, and add a second footer record
format `TODOFTR2` that shows the "Hide Done" label when completed todos are
visible. `TODOMAIN` will conditionally write either `TODOFTR` or `TODOFTR2`.

**Expected Outcomes:**
- `TODOCTL` has `CA05(05 'F5=Show Done')` keyword.
- The existing `TODOFTR` footer constant changes from:
  `'Valid options: 2=Edit  4=Delete  5=Mark Done'`
  to include `F5=Show Done` at the end.
- A new `TODOFTR2` record format exists with `OVERLAY`, identical to `TODOFTR`
  except the F5 label reads `F5=Hide Done`.
- `*IN05` is added to the indicator map comment at the top of the file.
- The instruction line at row 3 of `TODOCTL` is updated to include `F5=Show Done`.

**Todo List:**
1. In `QDDSSRC/TODODSPPF.DSPF`:
   - Add `CA05(05 'F5=Show Done')` to `TODOCTL` after the existing `CA06` line.
   - Update the `*IN05` comment in the indicator map section at the top.
   - Update the row 3 instruction constant in `TODOCTL` to include `F5`.
   - Rename or update `TODOFTR` footer constant to append `  F5=Show Done`.
   - Add a new `TODOFTR2` record format (with `OVERLAY`) whose footer reads
     `  F5=Hide Done` instead of `  F5=Show Done`.
   - In `TODOSFL`, change the `TDDONE` field from a plain output field to display
     `*` when done. The cleanest DDS approach: add a second overlay constant
     conditioned on an indicator (e.g. `*IN54`) that writes `*` at the same
     row/col as `TDDONE`, and in `TODOMAIN` set `*IN54 = (TDDONE = '1')` before
     each `WRITE TODOSFL`. Alternatively, set `TDDONE = '*'` in `LoadSubfile`
     before writing the subfile row when `l_Rec.tdDone = '1'` — simpler and
     requires no new indicator.

**Relevant Context:**
- DDS uses fixed-column layout (cols 1–80). Do NOT reformat.
- `TODOFTR` is at lines 87–91 of `QDDSSRC/TODODSPPF.DSPF`. It is a `+` continuation
  constant — the total length including the new text must stay within 80 columns
  on each physical line.
- The current footer text is 43 characters. Adding `  F5=Show Done` (14 chars)
  brings it to 57 — fits on one continuation line. `TODOFTR2` swaps that label.
- Row 3 instruction line currently reads `'F3=Exit   F6=Add New Todo'` (col 2).
  Update to `'F3=Exit   F5=Show Done   F6=Add New Todo'`.
  Total length = 41 chars — fits within 80 cols.
- For the `*` display: the simpler approach (no new indicator) is to remap the
  value in RPG before `WRITE TODOSFL`: set `TDDONE = '*'` when `tdDone = '1'`,
  `TDDONE = ' '` otherwise. The `TDDONE` subfile field stays `1A O` in DDS.
  No DDS change needed for this field.

---

## Sub-Task 3 — Update TODOMAIN to wire up the toggle

**Status:** [ ] pending

**Intent:**
Add the `w_ShowDone` toggle indicator to `TODOMAIN`, handle F5 in the main loop,
pass the correct read procedure pair to `LoadSubfile`, and conditionally write
`TODOFTR` or `TODOFTR2`.

**Expected Outcomes:**
- A module-level indicator `w_ShowDone` is declared (default `*OFF` = hide done).
- `*IN05` is added to the indicator map comment at the top of `TODOMAIN.RPGLE`.
- `LoadSubfile` accepts an indicator parameter and calls `ReadFirstTodoAll`/
  `ReadNextTodoAll` when it is `*ON`, or the existing pair when `*OFF`.
- `Main` toggles `w_ShowDone` when `*IN05` is set, then `ITER`s (same pattern as F6).
- `Main` writes `TODOFTR2` instead of `TODOFTR` when `w_ShowDone` is `*ON`.
- Prototypes for `ReadFirstTodoAll` and `ReadNextTodoAll` are added in the prototype
  section.

**Todo List:**
1. In `QRPGLESRC/TODOMAIN.RPGLE`:
   - Add `DCL-PR` prototypes for `ReadFirstTodoAll` and `ReadNextTodoAll`.
   - Add `DCL-S w_ShowDone IND INZ(*OFF);` to the variables section.
   - Update the indicator map comment to include `*IN05  F5=Toggle show done`.
   - Update `LoadSubfile` signature to accept `i_ShowDone IND CONST` parameter.
   - In `LoadSubfile`, call `ReadFirstTodoAll(l_Rec)` / `ReadNextTodoAll(l_Rec)`
     when `i_ShowDone = *ON`, existing calls otherwise.
   - In `Main`, add F5 handling after F6: toggle `w_ShowDone`, then `ITER`.
   - In `Main`, replace `WRITE TODOFTR` with a conditional:
     `IF w_ShowDone; WRITE TODOFTR2; ELSE; WRITE TODOFTR; ENDIF;`
   - Update the `LoadSubfile()` call in `Main` to pass `w_ShowDone`.

**Relevant Context:**
- `LoadSubfile` is at lines 198–238 of `TODOMAIN.RPGLE`. It currently takes no
  parameters — add `DCL-PI *N; i_ShowDone IND CONST; END-PI;`.
- F6 handling pattern (lines 152–156) is the model for F5: check indicator, take
  action, `ITER`.
- `w_ShowDone` must be `*OFF` at program start so the default view hides done items
  (preserving existing behaviour).
- `WRITE TODOFTR;` is at line 142 in `Main`.
- For the `*` display: in `LoadSubfile`, when writing each subfile row set
  `TDDONE = '*'` if `l_Rec.tdDone = '1'`, else `TDDONE = ' '`. The existing
  `TDDONE = l_Rec.tdDone;` line (line 219) is replaced by this conditional.
  Note: `TDDONE` is used as a display-only output field in `TODOSFL`; it is never
  read back by RPG logic, so remapping its value for display is safe.

---

## Sub-Task 4 — Create feature branch and verify CI build

**Status:** [ ] pending

**Intent:**
Commit all changes to a feature branch so the `deploy-dev.yml` CI workflow
compiles them into `MBPRICE1` for interactive testing.

**Expected Outcomes:**
- All changed files are committed on a branch named `feature/show-done-toggle`.
- The push triggers `deploy-dev.yml` and the build completes with no new errors
  (`TODOMAIN.PGM` and `TODOBL.SRVPGM` both rebuilt successfully).

**Todo List:**
1. Create and switch to branch `feature/show-done-toggle`.
2. Stage and commit all changed files (`TODODSPPF.DSPF`, `TODOBL.RPGLE`,
   `TODOBL.BND`, `TODOMAIN.RPGLE`) with a descriptive commit message.
3. Push the branch — this triggers `deploy-dev.yml`.
4. After CI completes, verify the objects were updated by checking
   `QSYS2.OBJECT_STATISTICS` for `MBPRICE1/TODOMAIN` and `MBPRICE1/TODOBL`
   `OBJCREATED` timestamps.
