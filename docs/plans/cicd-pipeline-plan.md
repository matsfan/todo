# Open Source CI/CD Pipeline for the Todo App — Plan

## Overview

Turn the current **manual** VS Code task workflow (deploy → compile → test, run by hand
against pub400.com) into an **automated** GitHub Actions pipeline, using only free/open-source
tooling — no Eradani, ARCAD, or similar commercial IBM i DevOps suite.

**Baseline already in place** (nothing here needs to be built from scratch):
- RPG source already lives as IFS-friendly files in git (`QDDSSRC/`, `QRPGLESRC/`), not source
  physical file members — the hard "get RPG into git" problem is already solved.
- The program is already split into a testable architecture: `TODOBL` (`*SRVPGM`, all file I/O
  and business logic) + `TODOMAIN` (thin UI shell) + `TODOTEST` (RPGUnit suite), per
  [rpgunit-testable-plan.md](../rpgunit-testable-plan.md).
- `scripts/ibmi-deploy.sh` (scp source to the IFS) and `scripts/ibmi-compile.sh` (SSH + ordered
  `CRT*` commands) already exist and work, wired into `.vscode/tasks.json`.
- `docs/DEPLOY.md` documents the manual first-time setup on pub400.com.
- **Confirmed: git is installed on pub400.com at `/QOpenSys/pkgs/bin/git`** (PASE Open Source
  package), **and a manual `git clone` of `github.com/matsfan/todo` from pub400 has succeeded.**
  This closes out the last open question for the deploy redesign in Sub-Task 2: pub400 has both
  git and outbound internet access, and the repo is publicly reachable, so pub400 can clone/pull
  it directly with no stored GitHub credentials.

**What's missing** — and what this plan builds:
1. Non-interactive auth (today's scripts prompt for a username each run and rely on
   password-based SSH).
2. An automated trigger (GitHub Actions), since today someone has to remember to run the VS
   Code tasks.
3. A machine-readable pass/fail signal from RPGUnit (today `RUCALLTST` output just streams to a
   terminal panel — nothing fails the build).
4. A safe convention for running compiles/tests against a **shared, public, free** system
   (pub400.com) without one developer's push clobbering another's.
5. A deploy step that tracks git commits directly (via `git pull`/`checkout` on pub400) instead
   of blindly `scp`-ing whatever is on the local disk — see Sub-Task 2.

**Team context**: I (the author of this plan) have CI/CD and DevOps experience but no RPG or
IBM i background. I'm leaning on RPG-experienced teammates to review any generated CL command
changes, and on AI agents to draft scripts/workflows — but agent-drafted CL parameter choices
should be treated as a draft for teammate review, not as final, especially anywhere this plan
flags "domain review needed."

---

## Research To Do

Do these before, or in parallel with, the sub-tasks below — several of them determine how a
sub-task should be implemented.

1. **pub400.com automation policy** — confirm scripted/CI SSH access is acceptable under
   pub400's usage terms. It's a free community system with per-user disk quotas; find pub400's
   FAQ/terms and, if unclear, ask in the pub400 community channels before pointing a CI trigger
   at it on every push.
2. **SSH key-based auth on IBM i** — how to add a public key to a pub400 user profile so CI
   doesn't need a stored password. This is standard OpenSSH (`~/.ssh/authorized_keys` under the
   PASE home directory) but needs to be done once by hand and verified.
3. **RPGUnit machine-readable results** — how `RUCALLTST` communicates pass/fail today (job log
   messages vs. a spooled report) and whether it supports an output option (`OUTPUT`/`DTAOUT`
   parameters, or RPGUnit's XML report mode) that a script can parse for a real exit code,
   instead of a human reading the panel.
4. **Network reachability, both directions**:
   - Confirm a standard GitHub-hosted Ubuntu runner can reach pub400.com over SSH (port 23/22
     as applicable) from GitHub's IP ranges; if pub400 firewalls that, a self-hosted runner
     would be needed instead. *(Still open.)*
   - ~~Confirm pub400.com itself has outbound HTTPS access to `github.com`~~ — **confirmed**: a
     manual `git clone` of this repo from pub400 succeeded.
5. **Secrets handling** — how to store the pub400 username and CI private key as GitHub Actions
   repository secrets, and how/when to rotate them.
6. **Shared-system concurrency** — pub400 hosts one `TODO` library today. Decide whether the
   team wants a single shared library (simplest, but a second push mid-test can collide) or
   some isolation scheme (e.g., only auto-deploy on merge to `main`, keep feature branches
   compiled manually to a personal library). This is a team/process decision, not just a
   technical one — see Sub-Task 5.
7. **BOB / `makei` availability** — `.vscode/actions.json` already has actions that shell out to
   `/QOpenSys/pkgs/bin/makei build`, which is the CLI for IBM's open-source **Bob** (Better
   Object Builder). That implies the `bob` PASE package may already be installed on this
   profile. Confirm this — if so, it's a lower-effort path to dependency-driven incremental
   builds than hand-maintaining the delete-everything-and-recompile-all logic in
   `ibmi-compile.sh`. Worth investigating now even though adopting it is deferred (Sub-Task 7).
8. **Source Orbit** — a dependency-graphing CLI for RPG/CL/DDS
   ([github.com/IBM/sourceorbit](https://github.com/IBM/sourceorbit)) that can generate Bob
   build rules automatically. Not needed for today's 3-compiled-object program where the
   dependency order is fixed and already documented in `AGENTS.md` — re-evaluate once the
   program grows enough that manually keeping `ibmi-compile.sh`'s compile order correct becomes
   error-prone.
9. **CL command review with an RPG teammate** — have someone who knows RPG/CL review the exact
   parameters in `scripts/ibmi-compile.sh` (`TGTCCSID(*JOB)`, `DBGVIEW(*SOURCE)`,
   `OPTION(*EVENTF)`) before CI relies on them unattended. These affect debugging and CCSID/
   encoding correctness in ways that won't be obvious from a DevOps background.

---

## Sub-Tasks

---

### Sub-Task 1 — SSH key-based auth for CI

**Intent**
Eliminate interactive password prompts so the deploy/compile scripts can run unattended from
GitHub Actions.

**Expected Outcomes**
- A dedicated CI SSH keypair exists (separate from any developer's personal key).
- The public key is installed in the pub400 profile's `authorized_keys`.
- A manual `ssh -i <ci-key> <user>@pub400.com` login succeeds with no password prompt.
- The private key and username are stored as GitHub Actions repository secrets
  (`IBMI_SSH_KEY`, `IBMI_USER`).

**Todo List**
1. ~~Generate a dedicated keypair (`ssh-keygen -t ed25519 -f ci-key -C "todo-ci"`, no
   passphrase since it must run unattended)~~ — **done**, kept separate from the personal key
   per the decision above.
2. ~~Install the public key on the pub400 profile~~ — **done**, appended alongside the personal
   key already in `authorized_keys`.
3. ~~Verify `ssh -i ci-key -p 2222 mbprice@pub400.com` logs in with no password/passphrase
   prompt~~ — **confirmed working**, no password required.
4. ~~Add `IBMI_SSH_KEY` (the CI key's private key contents) and `IBMI_USER` as GitHub repo
   secrets~~ — **done**.

> **Progress note**: a personal SSH key was generated and verified first (confirming key-based
> auth works on this system at all), then a separate, dedicated, passphrase-free CI key was
> generated, installed in `authorized_keys` alongside the personal key, and verified to log in
> with zero prompts. Only remaining step in this sub-task is adding it to GitHub as a secret.

**Relevant Context**
- Current scripts already parameterize the username as `$1` — see
  [scripts/ibmi-deploy.sh](../../scripts/ibmi-deploy.sh) and
  [scripts/ibmi-compile.sh](../../scripts/ibmi-compile.sh).
- Research item 2 above covers the exact IBM i-side key setup.

**Status:** [x] done

---

### Sub-Task 2 — Switch deploy from `scp` to a git-based pull, and make both scripts CI-safe

**Intent**
`ibmi-deploy.sh` currently `scp`s whatever is on local disk, which is fine for one interactive
developer but has no notion of *which commit* is on the server, no atomicity (a failed transfer
can leave a half-updated tree), and no cheap rollback. Now that `git` is confirmed installed on
pub400 (`/QOpenSys/pkgs/bin/git`), replace it with a `git clone` (first run) / `git fetch` +
`git checkout <ref>` (subsequent runs) directly on the IFS. `ibmi-compile.sh` also needs CI-safe
auth regardless of this change.

**Expected Outcomes**
- A one-time `git clone https://github.com/matsfan/todo.git <IFS_ROOT>` sets up the working copy
  on pub400 (anonymous HTTPS clone — no GitHub credentials needed on pub400 since the repo is
  public).
- `ibmi-deploy.sh` becomes an SSH call that runs `git fetch && git checkout <ref> && git clean
  -fdx` (or `git reset --hard <ref>`) in that IFS directory, where `<ref>` is the commit SHA
  GitHub Actions is building — so what's compiled on pub400 always matches an exact, known git
  commit, not "whatever files happened to be on someone's laptop."
- Both scripts accept an SSH identity file (env var or flag) instead of assuming the default
  key/agent, for CI use.
- Host key checking is handled deliberately (e.g. `StrictHostKeyChecking=accept-new` with a
  pinned `known_hosts`, not blind `StrictHostKeyChecking=no`).
- Scripts still work for local interactive use (don't break the existing VS Code tasks — the
  local dev flow can still be "run the deploy task," it just now runs `git fetch`/`checkout`
  remotely instead of `scp`).

**Todo List**
1. ~~Manually verify `git clone https://github.com/matsfan/todo.git` works over SSH on
   pub400~~ — **done, confirmed working.**
2. ~~Rewrite `ibmi-deploy.sh` to SSH in and run `git fetch`/`checkout <ref>` against the IFS
   clone instead of `scp -r`~~ — **drafted**. The script auto-detects whether `$IFS_ROOT/.git`
   already exists and clones vs. fetches accordingly, so no separate manual bootstrap step is
   needed — first run clones, every run after that just updates.
3. ~~Add identity-file support to both scripts~~ — **drafted**. Both scripts now take an
   optional identity-file argument (`ibmi-deploy.sh`'s 3rd arg, `ibmi-compile.sh`'s 2nd) and
   default to `ssh-agent`/default keys when omitted, so the existing VS Code tasks keep working
   unchanged.
4. ~~Decide and implement a host-key verification approach~~ — **drafted**: both scripts now use
   `StrictHostKeyChecking=accept-new` plus `BatchMode=yes` (so a real auth failure errors out
   immediately instead of hanging on a prompt). Note this is TOFU-per-run on an ephemeral GitHub
   runner, not true pinning — pinning pub400's host key as a repo variable and writing it to
   `known_hosts` explicitly before connecting would be the more rigorous version if this ever
   needs hardening.
5. **Flag for RPG-teammate/DevOps pairing review — still open, intentionally untouched**:
   `ibmi-compile.sh`'s `chk_del` helper combines the existence check and delete in one `&&`/`||`
   chain with a trailing `|| true` — today that also silently swallows a *failed delete* (for
   any reason other than "object doesn't exist"), not just a missing object. Worth tightening
   before this runs unattended in CI, since a silently-failed `DLTF`/`DLTPGM` would make the
   next `CRT*` step fail with a confusing "object already exists" error instead.
6. ~~Re-run `ibmi-deploy.sh` manually against pub400 to confirm the new git-based deploy and
   added SSH options work end-to-end~~ — **done, confirmed working.** `ibmi-compile.sh` still
   needs its own live test run — it wasn't exercised by this test since it's a separate script.
   (Also found along the way: pub400's SSH port is 2222, not the default 22 — both scripts now
   default to that via `IBMI_SSH_PORT`, overridable via env var.)
7. ~~Deploy target path~~ — **changed**: `IFS_ROOT` in both scripts moved from
   `/home/$USER/todo` to `/home/$USER/source/todo` per request, to fit under a general `source`
   directory on pub400 rather than a `todo`-specific top-level one.
8. ~~Confirm `git`'s path on pub400~~ — **confirmed**: `/QOpenSys/pkgs/bin/git`. Since
   `ibmi-deploy.sh` runs its remote commands via a non-interactive `ssh host <<heredoc>` session
   (which doesn't reliably source `.profile`/`.bashrc`), the script now explicitly does
   `export PATH="/QOpenSys/pkgs/bin:$PATH"` at the top of the remote block rather than assuming
   `git` resolves on its own.

**Relevant Context**
- [scripts/ibmi-deploy.sh](../../scripts/ibmi-deploy.sh) — now git-based; confirmed working
  end-to-end against pub400 (2026-09-08 live run, in addition to the earlier confirmation above).
- Item 5's `chk_del` concern is now moot — Sub-Task 7 replaced `ibmi-compile.sh`'s entire
  CL/`chk_del` sequence with `makei build`, which does its own dependency-aware rebuild instead.
- Side benefit worth calling out to the team: because the IFS copy is now a real git checkout,
  "roll back a bad deploy" becomes `git checkout <previous-good-sha>` + recompile, rather than
  needing a separate `SAVLIB`/`RSTLIB` snapshot strategy.

**Status:** [x] done — deploy script verified working end-to-end against pub400

---

### Sub-Task 3 — Machine-readable RPGUnit results

**Intent**
Give CI an actual pass/fail signal from the test suite, not just streamed terminal output. Today
this only exists as the manual **"IBM i: Run Tests"** VS Code task
([`.vscode/tasks.json:34-43`](../../.vscode/tasks.json)), which isn't wired into either compile
script at all.

**Expected Outcomes**
- A new `scripts/ibmi-test.sh` (or an added stage in `ibmi-compile.sh`) runs
  `RUCALLTST TSTPGM(TODO/TODOTEST)` and exits non-zero if any test fails.
- Failure output is captured somewhere CI can surface it (job log excerpt, spooled file
  contents, or an XML/CSV report — whichever research item 3 turns up as supported).

**Todo List**
1. **RPG-teammate research checkpoint**: confirm how `RUCALLTST` reports failures on this
   IBM i version/RPGUnit install (research item 3) — this determines the parsing approach below.
2. Write the script to invoke `RUCALLTST` over SSH and capture its output.
3. Parse the output for a failure indicator and translate it into the script's exit code
   (`set -e` already used elsewhere in this repo's scripts — follow that convention).
4. Verify locally: intentionally break a `TODOBL` procedure, confirm the script now exits
   non-zero; fix it back, confirm it exits zero.

**Relevant Context**
- [`.vscode/tasks.json:34-43`](../../.vscode/tasks.json) — current manual test invocation.
- [docs/rpgunit-testable-plan.md](../rpgunit-testable-plan.md) — background on the `TODOTEST`
  suite and its 7 test procedures.

**Status:** [ ] not started

---

### Sub-Task 4 — GitHub Actions workflow

**Intent**
Wire deploy → compile → test into `.github/workflows/ci.yml`, triggered automatically instead
of requiring someone to run VS Code tasks by hand.

**Expected Outcomes**
- `.github/workflows/ci.yml` exists.
- On push/PR (scope decided in Sub-Task 5), it: sets up the SSH key from secrets, runs
  `ibmi-deploy.sh $IBMI_USER ${{ github.sha }}` (which now `git fetch`/`checkout`s that exact
  commit on pub400 rather than copying local files — the runner doesn't even need its own
  checkout of the repo for this step, since pub400 pulls directly from GitHub), then
  `ibmi-compile.sh`, then the new test stage from Sub-Task 3, and fails the check if any step
  fails.
- No self-hosted runner needed — a standard GitHub-hosted Ubuntu runner just SSHes out to
  pub400.com (confirm this is reachable per research item 4).

**Todo List**
1. Draft the workflow YAML (good task for an AI agent — mechanical translation of the existing
   scripts into workflow steps).
2. Reference `IBMI_SSH_KEY` / `IBMI_USER` secrets from Sub-Task 1.
3. Run it once manually (`workflow_dispatch`) before enabling automatic triggers, to validate
   end-to-end without spamming pub400 on every push while iterating.
4. Once stable, set the real trigger per the Sub-Task 5 decision.

**Relevant Context**
- Reuses `scripts/ibmi-deploy.sh` / `scripts/ibmi-compile.sh` as-is once Sub-Task 2 makes them
  CI-safe — the workflow itself should be a thin wrapper, not new deploy/compile logic.

**Status:** [ ] not started

---

### Sub-Task 5 — Shared-system safety convention

**Intent**
Decide how the team avoids collisions on the single `TODO` library on a shared public system,
before automation makes collisions more frequent than they are today (manual runs are naturally
rate-limited by a human remembering to run them).

**Expected Outcomes**
- A written, agreed convention in `AGENTS.md` (or a new `docs/CONTRIBUTING.md`) for when
  automated compiles/tests run against the shared pub400 `TODO` library.

**Todo List**
1. Team decision — recommended default: CI only runs full deploy+compile+test **on merge to
   `main`**, not on every feature branch push/PR. Feature work stays on the existing manual VS
   Code tasks (optionally to a personal library) until it's ready to merge.
2. Document the convention.
3. Revisit once the team has felt the actual pain (or lack of it) of the single-library model —
   don't over-engineer per-branch isolation before it's needed.

**Relevant Context**
- `.bob/rules-plan/AGENTS.md` already documents that `GetNextId` is a max-ID-plus-one scheme
  "acceptable for pub400.com single-user use only" — the same shared-system caution applies
  here at the CI/library level, not just inside the RPG logic.

**Status:** [ ] not started

---

### Sub-Task 6 — Branch protection / required status check

**Intent**
Once the workflow has proven reliable, make it actually gate merges instead of being advisory.

**Expected Outcomes**
- The GitHub Actions check from Sub-Task 4 is a required status check on `main`.

**Todo List**
1. Let the workflow run successfully for a trial period first (avoid blocking merges on a
   pipeline still being debugged).
2. Enable "Require status checks to pass before merging" for `main` in GitHub branch protection
   settings, selecting the new workflow's check.

**Relevant Context**
- Straightforward GitHub repo settings change — no RPG knowledge needed for this step.

**Status:** [ ] not started

---

### Sub-Task 7 — Adopt TOBi (`makei`) for incremental builds

**Intent**
Replace the hand-maintained delete-everything-and-recompile-all logic in `ibmi-compile.sh` with
IBM's open-source TOBi build tool (formerly "Bob"/"Better Object Builder"). Originally deferred
as "optional / future" pending a concrete pain point — the team decided to switch now anyway.

**Expected Outcomes**
- Confirmation of whether `makei` is actually installed on the target profile (research item 7).
- `makei build` replaces the ordered `CRT*` sequence in `ibmi-compile.sh`, driven by a TOBi
  `Rules.mk` / `iproj.json`.

**Todo List**
1. ~~Confirm `/QOpenSys/pkgs/bin/makei` is present and working on pub400~~ — **confirmed live
   2026-09-08**: `TOBi version 3.2.1`.
2. ~~Add `iproj.json` and `Rules.mk` (root + `QDDSSRC/`, `QRPGLESRC/`, new `QBNDSRC/`)~~ —
   **drafted**, mirroring the exact dependency order documented in `AGENTS.md`. Required adding
   binder source (`QBNDSRC/TODOBL.BND`, `QBNDSRC/TODOTEST.BND`) since TOBi has no rule for
   building a `*SRVPGM` straight from a module — see `AGENTS.md`'s Compile Commands section for
   why.
3. ~~Rewrite `ibmi-compile.sh` to call `makei build` instead of the `CRT*`/`chk_del` sequence~~ —
   **drafted, then fixed 2026-09-08**: the script passed the literal string `BUILDLIB=*CURLIB`,
   but `makei` needs a real env var named `CURLIB` set to an actual library name (`iproj.json`'s
   `&CURLIB` placeholder resolves from that var, not a CL special value) — it errored out
   immediately with "CURLIB must be defined first in the environment variable" every time. Fixed
   to look up the profile's real current library via `DSPUSRPRF` and export that.
4. ~~Prototype `makei build` against pub400 and compare output/behavior to the old script~~ —
   **done 2026-09-08, with real findings**:
   - `BUILDLIB=*CURLIB` was wrong as noted above — the actual mechanism is the `CURLIB` env var.
   - The `TODOTEST.SRVPGM` rule's `RPGUNIT/RUCRTTST` dependency **cannot resolve — confirmed the
     `RPGUNIT` library does not exist anywhere on this pub400 profile** (research item 3 from the
     top of this doc is now answered, and answered negatively). Worse, `iproj.json`'s
     `preUsrlibl: ["RPGUNIT"]` was blocking **every** RPG compile, not just `TODOTEST` — cleared
     it so `TODOBL`/`TODOMAIN` can build; `TODOTEST` stays blocked pending a Sub-Task 3 strategy
     decision. See `AGENTS.md`'s new RPGUnit note for detail.
   - Along the way, live compiles surfaced that **none of this RPG/DDS source had ever actually
     compiled successfully before** (the compile scripts were drafted and never fully live-run
     until now). Real, independent bugs found and fixed: two DDS bugs in `TODOPF.PF` (a
     `TEXT()` literal overflowing the 80-column line limit; a date field's type code one column
     off), a duplicate DDS record-format name between `TODOPF`/`TODOLF` needing a `RENAME` in
     `TODOBL.RPGLE`, several I/O ops in `TODOBL.RPGLE` using fixed-form-style operand lists
     invalid in `**FREE`, `READPE` used where `READP` was needed, every `END-IF`/`END-DO` in
     `TODOBL.RPGLE`/`TODOMAIN.RPGLE` written with a hyphen (invalid — only `END-PROC`/`END-DS`
     etc. take the hyphen; block-closers are `ENDIF`/`ENDDO`), a missing `CTL-OPT NOMAIN` on
     `TODOBL.RPGLE`, a missing `CTL-OPT DFTACTGRP(*NO) ACTGRP(*NEW)` on `TODOMAIN.RPGLE`, and
     `TODOMAIN.RPGLE`'s `Main();` entry-point call positioned after all subprocedures (RPG
     silently ignores mainline code placed there). `TODOBL.SRVPGM` now compiles clean end to end.
   - `TODODSPPF.DSPF`: 3 of its 4 record formats (`TODOSFL`, `TODOCTL`, `TODODET`) now compile
     clean after fixing a continuation-line column bug, two more date-field column bugs, and an
     indicator placed in the wrong condition columns. The 4th, `TODODEL`, has an unresolved
     compile bug blocking the whole file (and therefore `TODOMAIN.PGM`, since it's a `WORKSTN`
     file) — **flagged in `AGENTS.md` for RPG/DDS-teammate review**, not yet root-caused despite
     extensive live A/B testing against the real compiler.
   - Compiler-option comparison (`TGTCCSID`/`DBGVIEW`/`OPTION`) not separately verified — TOBi's
     own defaults were used as-is and nothing so far suggests a CCSID/encoding problem, but this
     wasn't specifically checked line-by-line against the old script's explicit options.
5. This can move to "done" once `TODODEL` is fixed and a full `makei build` succeeds end to end —
   everything else in this item has been verified against a real run, not just drafted.

**Relevant Context**
- [github.com/IBM/sourceorbit](https://github.com/IBM/sourceorbit) pairs with TOBi for
  dependency discovery — not adopted here since `Rules.mk` was written by hand for this small a
  program; revisit if the object count grows enough to make that tedious.
- The `Rules.mk`/binder-source/`ibmi-compile.sh`/RPG source changes here have now been verified
  against live `makei build` runs on pub400 (not just agent-drafted) — but per this plan's intro,
  still treat the RPG/DDS-specific fixes (the `RENAME`, the free-form operand changes, the DDS
  column fixes) as a draft for RPG-teammate review before CI relies on them unattended, and see
  `AGENTS.md` for the specific items flagged.

**Status:** [~] `TODOBL`/`TODOPF`/`TODOLF` verified working end to end; `TODODSPPF.DSPF`'s
`TODODEL` record format still blocks a full build — see `AGENTS.md` for the write-up.

---

## Sequencing Recommendation

1. Sub-Tasks 1–2 by hand first, with an RPG teammate present for the `chk_del` review — validate
   SSH key auth and the adjusted scripts work exactly as the current manual flow does.
2. Sub-Task 3 next — get one real, trustworthy pass/fail signal before automating anything.
3. Sub-Task 4 — wire it into Actions, run manually via `workflow_dispatch` before enabling auto
   triggers.
4. Sub-Task 5 — lock in the shared-system convention (a process decision, do this before flipping
   on automatic triggers, not after).
5. Sub-Task 6 — turn on branch protection once the pipeline has a track record.
6. Sub-Task 7 — revisit later, only if/when the program outgrows manual compile-order upkeep.

## Roles

- **DevOps (me)**: Sub-Tasks 1, 2 (mechanics), 4, 6 — pipeline plumbing, the part that transfers
  directly from other CI/CD experience.
- **RPG teammate(s)**: review Sub-Task 2's CL/script changes and Sub-Task 3's `RUCALLTST`
  parsing before either goes live in CI; weigh in on Sub-Task 5's library convention.
- **AI agents**: good for drafting the workflow YAML, script diffs, and output-parsing logic —
  but treat any agent-authored CL parameter or compile-option change as a draft for RPG-teammate
  review, not as final, per the review checkpoints called out above.
