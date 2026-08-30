# Tutorial: Add a Priority Field

A hands-on exercise for learning RPG by extending the real `TODO` app. You
write all the code yourself; this document tells you *what* to build, *where*
each change goes, and *why*, and gives you a way to check your work at the
end. Read [`docs/rpg-primer-for-dotnet-devs.md`](rpg-primer-for-dotnet-devs.md)
first if you haven't — this tutorial assumes you know the vocabulary it
introduces (DDS, indicators, subfiles, `*SRVPGM`, `LIKEDS`, etc.) and links
back to it instead of re-explaining.

## What you'll build

A `Priority` field on every todo, with values `1`=High, `2`=Medium,
`3`=Low:

- Stored as a new column on `TODOPF`.
- Shown as a new column in the `TODOCTL` subfile list.
- Editable on the `TODODET` add/edit screen, defaulting to `2` (Medium) for
  new todos.
- Validated — only `1`, `2`, or `3` are accepted, with an error message on
  bad input, the same pattern `TODODET` already uses for blank descriptions.
- Covered by new RPGUnit tests in `TODOTEST`.

This exercise deliberately touches every layer of the app — DDS table, DDS
screens, the `TODOBL` service program, the `TODOMAIN` UI program, and the
test suite — because that's the same shape as almost every real change
you'll make in this codebase. By the end you'll have done, once yourself,
everything the [primer's §12 walkthrough](rpg-primer-for-dotnet-devs.md#12-walking-the-whole-request-end-to-end)
only described.

**Time estimate:** 1–3 hours, depending on how much DDS column-counting
trips you up (it will — that's normal, see the primer's §7 note about it).

## Before you start

- Make sure you can already compile and run the app as it stands today —
  work through [`AGENTS.md`](../AGENTS.md)'s compile commands and `CALL
  TODO/TODOMAIN` once first if you haven't, so you know a failed compile
  during this tutorial is *your* change and not a pre-existing problem.
- Decide how you'll edit source: either directly against the server's
  `TODO/QRPGLESRC` and `TODO/QDDSSRC` source files (e.g. via RDi or VS Code
  with the Code for IBM i extension), or in this repo's local mirror
  followed by an upload step — whatever your existing workflow is for this
  project.
- You do not need to do the steps in one sitting. Each checkpoint below
  compiles and (mostly) runs on its own, so stop and resume freely.

---

## Checkpoint 0 — Decide on the field, then move on

Value: `TDPRI`, `CHAR(1)`, allowed values `'1'`, `'2'`, `'3'`. This mirrors
`TDDONE` exactly (single-character code, not a real boolean/enum type) —
see the primer's [§3 table](rpg-primer-for-dotnet-devs.md#1-todopf--the-table)
if you want a refresher on why RPG/DDS leans on this pattern instead of a
richer type.

---

## Checkpoint 1 — Add the column to `TODOPF`

Open [`QDDSSRC/TODOPF.PF`](../QDDSSRC/TODOPF.PF) and add a `TDPRI` field
after `TDDUE`, following the exact style of the existing fields (name in
its column, type in its column, `TEXT()` describing it). Use a `TEXT()`
value that spells out the code meanings, the same way `TDDONE`'s does.

**Gotcha to know about before you compile:** unlike `ALTER TABLE` in
SQL Server, `CRTPF` recompiling over an *existing* file object on IBM i
will not silently add a column and keep your data — you generally need
one of:

- **No real data yet / a throwaway learning table:** just delete and
  recreate it — `DLTF FILE(TODO/TODOPF)` then `CRTPF ...` again from the
  updated source.
- **You want to keep existing rows:** use SQL instead of the `CRTPF`/DDS
  path for just this one change — from `STRSQL` or "Run SQL Scripts":
  ```sql
  ALTER TABLE TODO/TODOPF ADD COLUMN TDPRI CHAR(1) DEFAULT '2'
  ```
  This is a genuinely useful thing to know: IBM i tables described by DDS
  are still real SQL tables, and `ALTER TABLE` works on them. It won't,
  however, update your `TODOPF.PF` *source* — keep that in sync by hand so
  the DDS and the live table don't drift apart, since the next `CRTPF` from
  source would otherwise revert your `ALTER`.

Either way, once `TODOPF` has the new column: **recompile `TODOLF` too**,
even though you won't change its source. `TODOLF` carries a "level check"
against `TODOPF`'s record format at the byte layout level; if you leave the
old `TODOLF` object in place after changing `TODOPF`, you'll get a level
check runtime error the next time something opens both files. `CRTLF
FILE(TODO/TODOLF) SRCFILE(TODO/QDDSSRC) SRCMBR(TODOLF)` again is enough — no
source edit needed, since `TODOLF` inherits all fields from `TODOPF`
implicitly (see the primer's [§3 section on `TODOLF`](rpg-primer-for-dotnet-devs.md#todolf--a-keyed-view)).

**Checkpoint done when:** `TODOPF` and `TODOLF` both recompile clean.

---

## Checkpoint 2 — Teach `TODOBL` about priority

All of this is in [`QRPGLESRC/TODOBL.RPGLE`](../QRPGLESRC/TODOBL.RPGLE).

1. Add `tdPri CHAR(1);` to the `todoRec_t` data structure.
2. Write a new exported procedure `ValidatePriority`, same shape as the
   existing `ValidateDescription`
   ([`TODOBL.RPGLE:168-176`](../QRPGLESRC/TODOBL.RPGLE)): takes
   `i_Pri CHAR(1) CONST`, returns an `IND` that's `*ON` only when the value
   is `'1'`, `'2'`, or `'3'`. Add its `DCL-PR ... EXTPROC('VALIDATEPRIORITY')`
   prototype alongside the others near the top of the file.
3. Extend `AddTodoRecord` and `EditTodoRecord` — both the prototypes and the
   procedure bodies — to accept a new `i_Pri CHAR(1) CONST` parameter and
   assign it to `TDPRI` before the `WRITE`/`UPDATE`.
4. Extend `ReadNextTodo` and `GetTodoById` to copy `TDPRI` into
   `o_Rec.tdPri`, the same way they already copy `TDDONE` into
   `o_Rec.tdDone`.

**Why this file first:** `TODOBL` owns the data and the validation rule —
nothing about *how priority is entered on screen* belongs here, only *what
counts as a valid priority* and *how it's persisted*. That split is the
whole point of the `TODOBL`/`TODOMAIN` architecture (primer §6); if you
catch yourself wanting to reference a screen field name inside `TODOBL.RPGLE`,
that's a sign the logic belongs in `TODOMAIN` instead.

**Checkpoint done when:** `TODOBL` compiles into a module and re-links into
the `*SRVPGM` clean. (`TODOMAIN` and `TODOTEST` will now fail to compile
until you update them too — that's expected, move on.)

---

## Checkpoint 3 — Add priority to the screens

Open [`QDDSSRC/TODODSPPF.DSPF`](../QDDSSRC/TODODSPPF.DSPF).

### `TODOSFL` / `TODOCTL` (the list)

Add a display-only `TDPRI` field to the `TODOSFL` row format, and a matching
column heading + dashed underline to `TODOCTL`. You'll need to find free
column space — `TDDUE` currently runs from column 63 for 10 characters
(ending at 72), and `TDDONE` sits at column 75, so you have a narrow gap.
Two reasonable options:

- Squeeze a 1-character `Pri` column into the gap (e.g. column 74).
- Push `TDDONE` a few columns further right and put a slightly wider
  `Pri` column where `TDDONE` used to be.

Either is fine — this is exactly the fixed-column-counting exercise the
primer warns you about in [§7's closing note](rpg-primer-for-dotnet-devs.md#14-where-to-go-from-here).
Budget extra time here; getting DDS column math right by trial and error the
first few times is completely normal.

### `TODODET` (add/edit)

Add a priority prompt and an editable `DETPRI` field below the existing
`Due Date` line, following the same pattern as `DETDUE` — a label literal,
then a `1A B` (both input/output) field, plus a short hint literal like
`(1=High 2=Med 3=Low)` the way `DETDUE` has a `(YYYY-MM-DD)` hint next to
it.

You'll need to **move the existing error-message literal down a row or two**
to make room (it currently sits right below where `Due Date` is). While
you're there, add a **second** conditioned message literal for a bad
priority value — reuse the existing `*IN60` for the description error, and
introduce a **new** indicator (e.g. `*IN61`) for the priority error. Add
`*IN61` to the indicator-map comment block at the top of this file, matching
the existing entries — and to the equivalent comment block in
`TODOMAIN.RPGLE`. Both files' comments are documented as required to stay in
sync (see [`AGENTS.md`](../AGENTS.md#critical-conventions)); this is a small,
real taste of keeping two files' comments consistent by discipline rather
than by compiler enforcement.

**Checkpoint done when:** `TODODSPPF` recompiles clean. (You can't fully
verify it looks right until `TODOMAIN` drives it again — next checkpoint.)

---

## Checkpoint 4 — Wire it up in `TODOMAIN`

All of this is in [`QRPGLESRC/TODOMAIN.RPGLE`](../QRPGLESRC/TODOMAIN.RPGLE).

1. Update the `todoRec_t` DS and the `DCL-PR` prototypes for
   `ValidatePriority`, `AddTodoRecord`, and `EditTodoRecord` to match what
   you changed in `TODOBL` — remember these are hand-copied, not shared, so
   the compiler won't catch a mismatch for you until bind time (primer §5).
2. In `AddTodo`: initialize `DETPRI = '2'` alongside the other field resets
   at the top, add a `ValidatePriority(DETPRI)` check next to the existing
   `ValidateDescription` check (turning on your new `*IN61` and `ITER`-ing on
   failure, the same way the description check does with `*IN60`), and pass
   `DETPRI` through to `AddTodoRecord`.
3. In `EditTodo`: initialize `DETPRI = l_Rec.tdPri` after the `GetTodoById`
   call, add the same validation, and pass `DETPRI` through to
   `EditTodoRecord`.
4. In `LoadSubfile`: set `TDPRI = l_Rec.tdPri` alongside the other subfile
   field assignments before each `WRITE TODOSFL`.
5. Don't forget to reset `*IN61 = *OFF` wherever `*IN60` is reset (screen
   entry, and after a successful validation pass) — an indicator that's
   never turned back off will make the error message "stick" on screens
   where it shouldn't appear.

**Checkpoint done when:** `TODOMAIN` compiles and binds against the updated
`TODOBL`. Run it (`CALL TODO/TODOMAIN`) and manually test:

- Add a todo, leave priority at the default — should save as Medium.
- Add a todo with priority `1` — list should show it.
- Try an invalid priority (e.g. `9` or blank) — should re-show the screen
  with your new error message, without losing the description you typed.
- Edit an existing todo's priority — should persist and show correctly back
  on the list.
- Confirm the list column lines up under its heading for a few different
  rows (this is where column-math mistakes usually show up first).

---

## Checkpoint 5 — Update `TODOTEST`

Open [`QRPGLESRC/TODOTEST.RPGLE`](../QRPGLESRC/TODOTEST.RPGLE).

1. Update the copied `todoRec_t` DS and the copied prototypes
   (`ValidatePriority`, `AddTodoRecord`, `EditTodoRecord`) to match.
2. Every *existing* call to `AddTodoRecord` in this file now needs a fourth
   argument — pick a valid priority (e.g. `'2'`) for the existing tests so
   they keep compiling and keep testing what they were already testing.
3. Add new test procedures, following the `test*` naming convention so
   RPGUnit discovers them automatically (primer §9):
   - `testValidatePriority_Valid` — asserts `'1'`, `'2'`, and `'3'` all pass
     (three `assert()` calls, or three small test procedures if you'd rather
     keep each test to one assertion — either is a defensible style choice).
   - `testValidatePriority_Invalid` — asserts a bad value (e.g. `'9'` or a
     blank) fails.
   - Extend `testAddTodoRecord` (or add a new test) to assert the priority
     you passed in comes back correctly from `GetTodoById`, the same way it
     already asserts `tdDesc` and `tdDone`.

Reuse the existing sentinel-ID convention documented at the top of the file
(IDs chosen to avoid colliding with real data) for any new record you
insert, and make sure every test that inserts a row also deletes it —
match the existing `testAddTodoRecord`/`testMarkDoneRecord` pattern.

**Checkpoint done when:** `RUCALLTST TSTPGM(TODO/TODOTEST)` runs and every
test passes, old and new.

---

## Checkpoint 6 — Recompile everything, in order

Once all the source changes above are done, recompile from scratch in
dependency order — this is a good opportunity to internalize the compile
order in [`AGENTS.md`](../AGENTS.md#compile-commands-must-run-in-this-exact-order)
rather than just copy-pasting it:

1. `TODOPF` (recreate or `ALTER TABLE`, per Checkpoint 1)
2. `TODOLF` (recompile — level check)
3. `TODODSPPF`
4. `TODOBL` module → `*SRVPGM`
5. `TODOMAIN` (`CRTBNDRPG` against `TODOBND`)
6. `TODOTEST` module → `*SRVPGM` (bound against `TODOBND` + RPGUnit)

If step 4 or 5 fails with an unresolved reference, it almost always means a
prototype in `TODOMAIN`/`TODOTEST` doesn't exactly match what `TODOBL`
actually exports (parameter count, order, or type) — that's the "no shared
header" tradeoff from primer §5 biting you, and confirming that by
re-diffing the two `DCL-PR` blocks by eye is a normal, expected part of this
exercise.

---

## Stretch goals

Once the base feature works end-to-end, optional extensions that reuse
everything you just learned:

- **Color-code the list by priority.** DDS `COLOR()` keywords can be
  conditioned on indicators, the same way `TODODET`'s error message is
  conditioned on `*IN60`. You'd need to set an indicator per subfile row
  based on `l_Rec.tdPri` in `LoadSubfile` before each `WRITE TODOSFL` — but
  note indicators are shared per *screen*, not per *row*, so look into
  DDS's per-record indicator handling for subfiles (conditioning on a field
  value directly, via `COLOR(*BLU 1)`-style value-based conditioning,
  rather than a program-set indicator) before assuming you need 14 rows'
  worth of indicators.
- **Sort the list by priority.** Add a new logical file, `TODOLF2` or
  similar, keyed on `TDPRI` then `TDID`, the same way `TODOLF` is keyed on
  `TDID` alone (primer §3) — then give `TODOMAIN` a function key that
  switches which logical file `LoadSubfile` reads from.
- **Filter to a single priority.** Add a prompt field on `TODOCTL` and use
  it to skip records in `ReadNextTodo` (or write a `ReadNextTodoByPriority`
  variant in `TODOBL`) — mirrors how `ReadNextTodo` already skips done
  records.

---

## Answer key

Attempt the checkpoints above yourself first — that's where the learning
happens. Use this only to check your work or get unstuck. It's one valid
implementation, not the only correct one (your column choices in Checkpoint
3 will likely differ, and that's fine).

<details>
<summary><strong>Reveal the full solution</strong> (click to expand)</summary>

### `QDDSSRC/TODOPF.PF`

```
     A            TDPRI          1A         TEXT('Priority: 1=High 2=Medium 3=Low')
```
Add this line right after the `TDDUE`/`DATFMT(*ISO)` lines, before the `K TDID` key section.

### `QDDSSRC/TODODSPPF.DSPF`

Indicator map comment block — add:
```
     A*   *IN61  - ERRMSG   : invalid priority message overlay on TODODET
```

`TODOSFL` — add after the `TDDUE` line:
```
     A            TDPRI          1A  O  8 74
```
(This narrows the gap before `TDDONE` at column 75 to a single space —
tight but valid. If your DDS compiler complains about overlap, move `TDDONE`
to column 77 in both `TODOSFL` and the `TODOCTL` heading/dash lines below.)

`TODOCTL` — heading row, add after the `Due Date` heading:
```
     A                                       6 74'Pri'
     A                                          COLOR(WHT)
```
and in the dashed underline row, add:
```
     A                                       7 74'---'
     A                                          COLOR(WHT)
```

`TODODET` — replace the due-date-hint-through-error-message section with:
```
     A                                       9  2'Due Date   :'
     A            DETDUE         L   B  9 15DATFMT(*ISO)
     A                                          COLOR(GRN)
     A                                       9 30'(YYYY-MM-DD)'
     A                                          COLOR(BLU)
     A                                      11  2'Priority   :'
     A            DETPRI         1A  B 11 15
     A                                          COLOR(GRN)
     A                                      11 30'(1=High 2=Med 3=Low)'
     A                                          COLOR(BLU)
     A                                 60   13  2'Description cannot be blank.  +
     A                                          Press Enter to continue.'
     A                                          COLOR(RED)
     A                                 61   14  2'Priority must be 1, 2, or 3.  +
     A                                          Press Enter to continue.'
     A                                          COLOR(RED)
```

### `QRPGLESRC/TODOBL.RPGLE`

`todoRec_t`:
```rpgle
DCL-DS todoRec_t        QUALIFIED TEMPLATE;
  tdId    PACKED(5:0);
  tdDesc  CHAR(50);
  tdDone  CHAR(1);
  tdDue   DATE(*ISO);
  tdPri   CHAR(1);
END-DS;
```

New prototype, alongside `ValidateDescription`'s:
```rpgle
DCL-PR ValidatePriority    IND
                           EXTPROC('VALIDATEPRIORITY');
  i_Pri     CHAR(1) CONST;
END-PR;
```

`AddTodoRecord` / `EditTodoRecord` prototypes — add the new parameter:
```rpgle
DCL-PR AddTodoRecord       EXTPROC('ADDTODORECORD');
  i_Id      PACKED(5:0) CONST;
  i_Desc    CHAR(50)    CONST;
  i_Due     DATE(*ISO)  CONST;
  i_Pri     CHAR(1)     CONST;
END-PR;

DCL-PR EditTodoRecord      EXTPROC('EDITTODORECORD');
  i_Id      PACKED(5:0) CONST;
  i_Desc    CHAR(50)    CONST;
  i_Due     DATE(*ISO)  CONST;
  i_Pri     CHAR(1)     CONST;
END-PR;
```

New procedure implementation:
```rpgle
DCL-PROC ValidatePriority   EXPORT;
  DCL-PI *N IND;
    i_Pri     CHAR(1) CONST;
  END-PI;

  RETURN (i_Pri = '1' OR i_Pri = '2' OR i_Pri = '3');
END-PROC;
```

`AddTodoRecord` body:
```rpgle
DCL-PROC AddTodoRecord      EXPORT;
  DCL-PI *N;
    i_Id      PACKED(5:0) CONST;
    i_Desc    CHAR(50)    CONST;
    i_Due     DATE(*ISO)  CONST;
    i_Pri     CHAR(1)     CONST;
  END-PI;

  TDID   = i_Id;
  TDDESC = i_Desc;
  TDDONE = '0';
  TDDUE  = i_Due;
  TDPRI  = i_Pri;
  WRITE TODOR TODOPF;
END-PROC;
```

`EditTodoRecord` body — add `i_Pri` to the `DCL-PI` and `TDPRI = i_Pri;`
right after `TDDUE = i_Due;`.

`ReadNextTodo` — add `o_Rec.tdPri = TDPRI;` next to the other `o_Rec.*`
assignments.

`GetTodoById` — add `o_Rec.tdPri = TDPRI;` next to its other `o_Rec.*`
assignments.

### `QRPGLESRC/TODOMAIN.RPGLE`

Header indicator comment — add:
```
// *IN61  Error message on TODODET (invalid priority)
```

Mirror the `todoRec_t` DS and all four changed prototypes
(`ValidatePriority`, `AddTodoRecord`, `EditTodoRecord`) exactly as in
`TODOBL.RPGLE` above.

`AddTodo`:
```rpgle
DCL-PROC AddTodo;

  DETMODE  = 'Add     ';
  DETID    = 0;
  DETDESC  = *BLANKS;
  DETDUE   = w_Today;
  DETPRI   = '2';
  *IN60    = *OFF;
  *IN61    = *OFF;

  DOU NOT *IN03 AND NOT *IN12;

    EXFMT TODODET;

    IF *IN03 OR *IN12;
      LEAVE;
    END-IF;

    IF NOT ValidateDescription(DETDESC);
      *IN60 = *ON;
      *IN61 = *OFF;
      ITER;
    END-IF;

    IF NOT ValidatePriority(DETPRI);
      *IN60 = *OFF;
      *IN61 = *ON;
      ITER;
    END-IF;

    *IN60 = *OFF;
    *IN61 = *OFF;

    w_NextId = GetNextId();
    AddTodoRecord(w_NextId: DETDESC: DETDUE: DETPRI);

    LEAVE;

  END-DO;

END-PROC;
```

`EditTodo` — same shape: set `DETPRI = l_Rec.tdPri;` after the
`GetTodoById` call, reset `*IN60`/`*IN61` to `*OFF` alongside the existing
reset, add the `ValidatePriority` check the same way as above, and change
the call to `EditTodoRecord(w_SelId: DETDESC: DETDUE: DETPRI);`.

`LoadSubfile` — add `TDPRI = l_Rec.tdPri;` alongside the other subfile
field assignments before `WRITE TODOSFL;`.

### `QRPGLESRC/TODOTEST.RPGLE`

Mirror the `todoRec_t` DS and the `ValidatePriority`/`AddTodoRecord`
prototypes as above (this file doesn't call `EditTodoRecord`, so that
prototype isn't needed here).

Update every existing `AddTodoRecord(...)` call to pass a priority, e.g.:
```rpgle
AddTodoRecord(77: 'Watermark record': %date(*SYS): '2');
AddTodoRecord(9999: 'High watermark sentinel': %date(*SYS): '2');
AddTodoRecord(8001: 'Test add record': %date(*SYS): '1');
AddTodoRecord(8002: 'Test mark done': %date(*SYS): '2');
```

New tests:
```rpgle
DCL-PROC testValidatePriority_Valid EXPORT;
  DCL-PI *N END-PI;

  assert(ValidatePriority('1'): 'Priority 1 should pass');
  assert(ValidatePriority('2'): 'Priority 2 should pass');
  assert(ValidatePriority('3'): 'Priority 3 should pass');

END-PROC;

DCL-PROC testValidatePriority_Invalid EXPORT;
  DCL-PI *N END-PI;

  assert(NOT ValidatePriority('9'): 'Priority 9 should fail');
  assert(NOT ValidatePriority(' '): 'Blank priority should fail');

END-PROC;
```

Extend `testAddTodoRecord` with one more assertion after the existing
`aEqual` calls:
```rpgle
aEqual('1': l_Rec.tdPri);
```
(matching the `'1'` priority used in the updated `AddTodoRecord(8001: ...)`
call above).

</details>

---

## Where to go from here

Once this lands and passes its tests, you've now made a real, full-stack
change to an IBM i application by hand — table, screens, service layer, UI
program, and tests. The next good exercise is picking one of this
tutorial's [stretch goals](#stretch-goals), or inventing your own similar
one (a `Notes` free-text field, a `Category` field, an "archive" flag
separate from "done") and doing the same six checkpoints without this
document's hand-holding.
