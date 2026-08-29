# Reorganise Source Repo to Standard IBM i Layout — Plan

## Overview

Restructure the flat root directory into the standard IBM i source Physical File folder
convention used by IBM i tooling (Code for IBM i, Bob build tool, iProj). This makes the
repo immediately recognisable to IBM i developers and compatible with those tools out of the box.

**Target layout:**
```
todo/
├── QDDSSRC/
│   ├── TODOPF.PF
│   ├── TODOLF.LF
│   └── TODODSPPF.DSPF
├── QRPGLESRC/
│   └── TODOMAIN.RPGLE
└── docs/
    ├── DEPLOY.md
    └── todo-rpg-plan.md
```

**Non-goals:** No code changes, no logic changes, no new features.

---

## Sub-Tasks

---

### Sub-Task 1 — Move DDS source files into `QDDSSRC/` and rename extensions

**Intent**
The three DDS files (physical file, logical file, display file) all belong in a folder named
`QDDSSRC` — mirroring the Source Physical File of the same name that is created on the IBM i
server. The file extension should be the member type (`PF`, `LF`, `DSPF`) rather than the
generic `.dds`, which is the convention expected by Code for IBM i's member browser.

**Expected Outcomes**
- `QDDSSRC/TODOPF.PF` exists with the same content as the old `TODOPF.dds`
- `QDDSSRC/TODOLF.LF` exists with the same content as the old `TODOLF.dds`
- `QDDSSRC/TODODSPPF.DSPF` exists with the same content as the old `TODODSPPF.dds`
- Old root-level `.dds` files are removed

**Todo List**
1. Create the `QDDSSRC/` directory
2. Move and rename `TODOPF.dds`    → `QDDSSRC/TODOPF.PF`
3. Move and rename `TODOLF.dds`    → `QDDSSRC/TODOLF.LF`
4. Move and rename `TODODSPPF.dds` → `QDDSSRC/TODODSPPF.DSPF`
5. Delete the old `.dds` files from the root

**Relevant Context**
- Files: `TODOPF.dds`, `TODOLF.dds`, `TODODSPPF.dds`
- Content is unchanged — this is a rename + move only

**Status:** [x] done

---

### Sub-Task 2 — Move RPG source into `QRPGLESRC/` and rename extension

**Intent**
Free-form RPGLE source belongs in `QRPGLESRC/`, again mirroring the IBM i Source Physical
File. The extension should be `.RPGLE` (uppercase) to match the member type.

**Expected Outcomes**
- `QRPGLESRC/TODOMAIN.RPGLE` exists with the same content as the old `TODOMAIN.rpgle`
- Old root-level `TODOMAIN.rpgle` is removed

**Todo List**
1. Create the `QRPGLESRC/` directory
2. Move and rename `TODOMAIN.rpgle` → `QRPGLESRC/TODOMAIN.RPGLE`
3. Delete the old `TODOMAIN.rpgle` from the root

**Relevant Context**
- File: `TODOMAIN.rpgle`
- Content is unchanged — rename + move only

**Status:** [x] done

---

### Sub-Task 3 — Move documentation into `docs/`

**Intent**
Separate human-readable docs from compilable source so the two source folders contain only
files that land on the IBM i server. This is a clean convention that all IBM i project
templates follow.

**Expected Outcomes**
- `docs/DEPLOY.md` exists with the same content as the old `DEPLOY.md`
- `docs/todo-rpg-plan.md` exists with the same content as the old `todo-rpg-plan.md`
- Old root-level `DEPLOY.md` and `todo-rpg-plan.md` are removed

**Todo List**
1. Create the `docs/` directory
2. Move `DEPLOY.md`         → `docs/DEPLOY.md`
3. Move `todo-rpg-plan.md`  → `docs/todo-rpg-plan.md`
4. Delete the old files from the root

**Relevant Context**
- Files: `DEPLOY.md`, `todo-rpg-plan.md`
- Content is unchanged — move only

**Status:** [x] done

---

### Sub-Task 4 — Update `DEPLOY.md` upload paths to reflect new layout

**Intent**
The upload instructions in `DEPLOY.md` (Step 5) reference the old filenames with `.dds` and
`.rpgle` extensions. After the rename they will be wrong. Update those references so the guide
stays accurate for anyone following it from the new repo structure.

**Expected Outcomes**
- All filename references in `docs/DEPLOY.md` use the new names (`TODOPF.PF`, `TODOLF.LF`,
  `TODODSPPF.DSPF`, `TODOMAIN.RPGLE`) and correct folder paths

**Todo List**
1. Open `docs/DEPLOY.md`
2. In Step 5 (Option A), replace every `filename.dds` / `filename.rpgle` reference with the
   new `FILENAME.EXT` names inside `QDDSSRC/` and `QRPGLESRC/`
3. In Step 5 (Option C), update the `FROMSTMF` paths to point to the new folder locations

**Relevant Context**
- File: `docs/DEPLOY.md` (after Sub-Task 3 moves it)
- Only Step 5 content needs updating — compile commands and everything else are unchanged

**Status:** [x] done
