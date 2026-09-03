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

**What's missing** — and what this plan builds:
1. Non-interactive auth (today's scripts prompt for a username each run and rely on
   password-based SSH).
2. An automated trigger (GitHub Actions), since today someone has to remember to run the VS
   Code tasks.
3. A machine-readable pass/fail signal from RPGUnit (today `RUCALLTST` output just streams to a
   terminal panel — nothing fails the build).
4. A safe convention for running compiles/tests against a **shared, public, free** system
   (pub400.com) without one developer's push clobbering another's.

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
4. **GitHub-hosted runner reachability** — confirm a standard GitHub-hosted Ubuntu runner can
   reach pub400.com over SSH (port 23/22 as applicable) from GitHub's IP ranges; if pub400
   firewalls that, a self-hosted runner would be needed instead.
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
1. Generate a dedicated keypair (`ssh-keygen -t ed25519 -f ci-key -C "todo-ci"`, no passphrase
   since it must run unattended).
2. Install the public key on the pub400 profile (via an existing authenticated session —
   append to `~/.ssh/authorized_keys` on the IFS home directory).
3. Verify manual key-only login works before touching CI.
4. Add `IBMI_SSH_KEY` (private key contents) and `IBMI_USER` as GitHub repo secrets.

**Relevant Context**
- Current scripts already parameterize the username as `$1` — see
  [scripts/ibmi-deploy.sh](../../scripts/ibmi-deploy.sh) and
  [scripts/ibmi-compile.sh](../../scripts/ibmi-compile.sh).
- Research item 2 above covers the exact IBM i-side key setup.

**Status:** [ ] not started

---

### Sub-Task 2 — Make the scripts CI-safe

**Intent**
`ibmi-deploy.sh` and `ibmi-compile.sh` were written for an interactive developer session. CI
needs explicit key auth and no interactive host-key prompts.

**Expected Outcomes**
- Both scripts accept an SSH identity file (env var or flag) instead of assuming the default
  key/agent.
- Host key checking is handled deliberately (e.g. `StrictHostKeyChecking=accept-new` with a
  pinned `known_hosts`, not blind `StrictHostKeyChecking=no`).
- Scripts still work unchanged for local interactive use (don't break the existing VS Code
  tasks).

**Todo List**
1. Add identity-file support to both scripts (e.g. `ssh -i "${IBMI_SSH_KEY_PATH}" ...`).
2. Decide and implement a host-key verification approach for first connection from a fresh CI
   runner.
3. **Flag for RPG-teammate/DevOps pairing review**: `ibmi-compile.sh`'s `chk_del` helper
   (lines 16–18) combines the existence check and delete in one `&&`/`||` chain with a trailing
   `|| true` — today that also silently swallows a *failed delete* (for any reason other than
   "object doesn't exist"), not just a missing object. Worth tightening before this runs
   unattended in CI, since a silently-failed `DLTF`/`DLTPGM` would make the next `CRT*` step
   fail with a confusing "object already exists" error instead.
4. Re-run both scripts manually against pub400.com to confirm no regression.

**Relevant Context**
- [scripts/ibmi-compile.sh:16-18](../../scripts/ibmi-compile.sh) — the `chk_del` function.
- This script already deletes and recompiles every object on every run (documented in
  [deploy-scripts-plan.md](../../deploy-scripts-plan.md)) — fine for 3 objects today; revisit if
  Sub-Task 7 (Bob) is adopted later.

**Status:** [ ] not started

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
- On push/PR (scope decided in Sub-Task 5), it: checks out the repo, sets up the SSH key from
  secrets, runs `ibmi-deploy.sh`, then `ibmi-compile.sh`, then the new test stage from
  Sub-Task 3, and fails the check if any step fails.
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

### Sub-Task 7 (optional / future) — Adopt Bob (`makei`) for incremental builds

**Intent**
Replace the hand-maintained delete-everything-and-recompile-all logic in `ibmi-compile.sh` with
IBM's open-source Bob build tool, once the program has enough objects that manually keeping the
compile order correct becomes a maintenance burden. Not needed for today's 3-object program.

**Expected Outcomes**
- Confirmation of whether `bob`/`makei` is actually installed on the target profile (research
  item 7).
- If adopted: `makei build` (or `makei compile -f <file>`) replaces the ordered `CRT*` sequence
  in `ibmi-compile.sh`, driven by a Bob `Rules.mk` / `iproj.json`.

**Todo List**
1. Confirm `/QOpenSys/pkgs/bin/makei` is present and working on pub400 (it's already referenced
   in [`.vscode/actions.json:106,119`](../../.vscode/actions.json), suggesting it may already be
   available).
2. If available, prototype `makei build` against a throwaway library and compare output/behavior
   to the current script.
3. Defer actually switching CI over to it until there's a concrete pain point (e.g. adding more
   RPG objects makes `AGENTS.md`'s manually-documented compile order hard to keep correct).

**Relevant Context**
- [github.com/IBM/sourceorbit](https://github.com/IBM/sourceorbit) pairs with Bob for dependency
  discovery, if/when this is revisited.

**Status:** [ ] not started

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
