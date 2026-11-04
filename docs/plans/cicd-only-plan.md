# CI/CD-Only Deploy Plan

## Overview

Move all deploy+compile activity for MBPRICE1 (dev) and MBPRICE2 (test) into
GitHub Actions, removing the dependency on the local Bob Stop hook. The existing
`deploy-test.yml` workflow already handles MBPRICE2 on every push to `main`. This
plan adds a symmetric `deploy-dev.yml` workflow for MBPRICE1 on every push to any
branch except `main`, disables the local Stop hook, and updates supporting docs.

**Not in scope:** MBPRICEB (production) — it remains manually deployed by separate
instruction and is not touched here.

---

## Sub-Task 1 — Add deploy-dev.yml workflow for MBPRICE1

**Status:** [x] done

**Intent:**
Create a new GitHub Actions workflow that deploys and compiles into MBPRICE1 (the
dev library) whenever code is pushed to any branch other than `main`. This mirrors
the structure of the existing `deploy-test.yml` but targets `MBPRICE1` and a
separate IFS checkout directory (`todo-dev`) so it never clobbers the `todo-test`
checkout used by the MBPRICE2 pipeline.

**Expected Outcomes:**
- A file `.github/workflows/deploy-dev.yml` exists.
- Pushing to any branch except `main` triggers this workflow.
- The workflow deploys the pushed commit to `/home/mbprice/source/todo-dev` on
  pub400 and compiles all objects into `MBPRICE1`.
- The workflow uses the same `IBMI_USER` and `IBMI_SSH_KEY` repository secrets as
  the existing test workflow.
- A `workflow_dispatch` trigger is included so the workflow can be re-run manually.
- Concurrency is configured so concurrent runs on the same branch queue rather than
  cancel (matching the `cancel-in-progress: false` policy of `deploy-test.yml`).

**Todo List:**
1. Create `.github/workflows/deploy-dev.yml` modelled on `deploy-test.yml` with:
   - `on.push.branches-ignore: [main]` trigger plus `workflow_dispatch`
   - `env.IBMI_CURLIB: MBPRICE1`
   - `env.IBMI_IFS_DIR: todo-dev`
   - `env.IBMI_USER: ${{ secrets.IBMI_USER }}`
   - Same three steps as `deploy-test.yml` (checkout, write SSH key, deploy, compile)
   - Concurrency group keyed on `ibmi-dev-deploy-${{ github.ref }}` (per-branch
     queuing) with `cancel-in-progress: false`

**Relevant Context:**
- Model file: `.github/workflows/deploy-test.yml`
- Scripts called: `scripts/ibmi-deploy.sh "${{ github.sha }}"` and
  `scripts/ibmi-compile.sh` — both already read `IBMI_CURLIB` and `IBMI_IFS_DIR`
  from the environment, no script changes needed.
- Secrets already in the repo: `IBMI_USER`, `IBMI_SSH_KEY`.

---

## Sub-Task 2 — Disable the Bob Stop hook

**Status:** [x] done

**Intent:**
The local Stop hook (`.bob/hooks/ibmi-post-stop.sh`) currently deploys and compiles
to MBPRICE1 automatically after each Bob session. With CI handling MBPRICE1, this
hook is redundant and should be disabled to avoid confusion (or accidental deploys
from a stale local branch). Replace its body with a no-op stub that prints a clear
message directing developers to push to a branch instead.

**Expected Outcomes:**
- Running `.bob/hooks/ibmi-post-stop.sh` (or having Bob trigger it at session end)
  does nothing on pub400 — no SSH connections are made.
- The script prints a message explaining that deploys are now handled by CI.
- The script exits 0 (not an error) so Bob's session end is not disrupted.

**Todo List:**
1. Replace the body of `.bob/hooks/ibmi-post-stop.sh` with a stub that:
   - Prints a message such as: `Deploy+compile is now handled by GitHub Actions CI.
     Push your branch to trigger a build into MBPRICE1 (feature branches) or
     MBPRICE2 (main).`
   - Exits 0.
   - Retains the shebang and a brief comment explaining what changed and why.

**Relevant Context:**
- Current file: `.bob/hooks/ibmi-post-stop.sh`

---

## Sub-Task 3 — Update .env.example

**Status:** [x] done

**Intent:**
The local `.env` file is no longer needed for deploy/compile (CI handles it), but
`.env.example` is the committed template that documents the variables. Update it to
reflect the current reality: the file is only needed if a developer wants to run
the scripts locally, and `IBMI_IFS_DIR` (now important for understanding the
naming convention) should be documented.

**Expected Outcomes:**
- `.env.example` documents all four variables: `IBMI_USER`, `IBMI_IDENTITY`,
  `IBMI_CURLIB`, and `IBMI_IFS_DIR`.
- A comment explains that CI now handles deploys and this file is only needed for
  running scripts manually.
- The placeholder values make the purpose of each variable obvious.

**Todo List:**
1. Update `.env.example` to add `IBMI_IFS_DIR` with a comment, and add a header
   comment noting this file is for local manual use only — CI uses repository
   secrets.

**Relevant Context:**
- Current file: `.env.example`

---

## Sub-Task 4 — Update AGENTS.md

**Status:** [x] done

**Intent:**
The root `AGENTS.md` and `.bob/rules-plan/AGENTS.md` both document the deploy+compile
approach. Update them to reflect that CI is now the single source of truth for
deploys, the Stop hook is a no-op, and the `todo-dev` / `todo-test` IFS directory
naming convention now applies to both pipelines.

**Expected Outcomes:**
- `AGENTS.md`'s "Deploy & Compile (triggering)" section accurately describes the
  two GitHub Actions workflows and the disabled Stop hook.
- `.bob/rules-plan/AGENTS.md`'s note about the Stop hook being automatic is
  updated: plans should reference pushing to a branch rather than the hook.
- No references to the Stop hook doing live deploys remain.

**Todo List:**
1. Update the "Deploy & Compile (triggering)" section of `AGENTS.md` to describe
   the two workflows, their triggers, IFS directories, and target libraries.
2. Update `.bob/rules-plan/AGENTS.md`'s last bullet (about the Stop hook) to say
   plans should focus on source changes and push to the appropriate branch; CI
   handles the rest.

**Relevant Context:**
- Files: `AGENTS.md`, `.bob/rules-plan/AGENTS.md`
- IFS layout: `todo-dev` → MBPRICE1 (feature branches), `todo-test` → MBPRICE2 (main)
