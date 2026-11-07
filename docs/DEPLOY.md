# Deploy Guide — IBM i RPG Todo Application

This guide covers the actual deploy/compile/run workflow for this repo as of 2026-11-03:
source lives in git, pub400 pulls it onto its own IFS, and two scripts drive everything. The
scripts run in GitHub Actions, one workflow per environment (dev, test, prod).
There is no library-creation step, no source physical file, and no member upload — if you
remember an older version of this document that had those steps, that workflow no longer
exists and is no longer permitted (see [The two scripts are the only way in](#the-two-scripts-are-the-only-way-in)
below).

For architecture, conventions, and compile-order details beyond what's here, see
[AGENTS.md](../AGENTS.md). For the history of how this pipeline got to its current shape,
see [docs/plans/cicd-pipeline-plan.md](plans/cicd-pipeline-plan.md) and the archived plans
under [docs/plans/archive/](plans/archive/) (`deploy-scripts-plan.md`,
`deploy-compile-hook-plan.md`, `rpgunit-testable-plan.md`, `todo-rpg-plan.md`).

---

## What you need

- A free account on [pub400.com](https://pub400.com) — sign up at the website. Each profile
  comes pre-provisioned with its own current library; you cannot create additional libraries
  on this shared free system (see [No library creation, no source members](#no-library-creation-no-source-members)).
- An SSH key registered with your pub400.com profile, stored as the `IBMI_SSH_KEY` repo secret
  (with your profile name as `IBMI_USER`). The deploy/compile scripts authenticate over SSH
  (port 2222 by default), not Telnet — see [Environments](#environments) below.
- A 5250 terminal emulator, to actually **run** the compiled application — **Mocha TN5250**
  (browser-based, free) or **ACS (IBM Access Client Solutions)** (Java, free download from
  IBM). Connect it to `pub400.com` on the standard 5250 port (23) and sign on with your
  pub400.com username and password; this is unrelated to the SSH-based deploy path and only
  needed to see the green-screen UI (see [Running the app](#running-the-app)).
- Optional but convenient: **VS Code** with the [IBM i extension (Code for IBM i)](https://marketplace.visualstudio.com/items?itemName=HalcyonTechLtd.code-for-ibmi)
  for browsing compiled objects and job logs from your PC. It is not required for deploying
  or compiling — those go through the scripts, not through the extension's upload/build
  features.

---

## Environments

Every deploy and compile runs in GitHub Actions. Each environment is a **GitHub Environment**
(repo **Settings → Environments**), and that's the only place its library and checkout are
defined:

| Environment | `IBMI_CURLIB` | `IBMI_IFS_DIR` | Workflow | Runs when | Protection |
|---|---|---|---|---|---|
| `dev` | `MBPRICE1` | `todo-dev` | [`deploy-dev.yml`](../.github/workflows/deploy-dev.yml) | push to any branch except `main` | — |
| `test` | `MBPRICE2` | `todo-test` | [`deploy-test.yml`](../.github/workflows/deploy-test.yml) | push / merge to `main` | `main` only |
| `prod` | `MBPRICEB` | `todo-prod` | [`deploy-prod.yml`](../.github/workflows/deploy-prod.yml) | manual **Run workflow** only | `main` only, reviewer approval |

Each workflow job declares `environment: <name>`, which gives it that environment's variables,
and passes them to the scripts as environment variables. To change where an environment builds,
edit its variables under Settings → Environments; don't hard-code values in the workflow files.

| Variable | Where it's set | Purpose |
|---|---|---|
| `IBMI_USER` | repo secret (shared) | Your pub400.com profile name. |
| `IBMI_SSH_KEY` → `IBMI_IDENTITY` | repo secret (shared) | SSH private key for that profile; the workflow writes it to a file and sets `IBMI_IDENTITY` to its path. |
| `IBMI_CURLIB` | environment variable | The library this environment builds into. See below for why this can't be auto-detected. |
| `IBMI_IFS_DIR` | environment variable | Leaf directory under `/home/$IBMI_USER/source/` for this environment's checkout — see [Deploying](#deploying). |
| `IBMI_SSH_PORT` | optional | SSH port, default `2222`. |

The scripts have no defaults for the library or checkout: if either is missing, they fail
instead of building somewhere unintended. There is no `.env` file anymore.

### Deploying to production

1. Merge to `main` and let **Deploy to test library** finish. Check the result in MBPRICE2.
2. In the repo's **Actions** tab, choose **Deploy to production library** → **Run workflow**,
   with branch `main`. Leave **sha** blank to deploy the latest `main`, or enter an earlier
   commit to roll back to it.
3. The run waits for approval. Open it, choose **Review deployments**, tick `prod`, and approve.

Before touching pub400, the workflow checks that the commit is on `main` and that **Deploy to
test library** succeeded for that exact commit. So production only ever gets a build that has
already passed in test.

### Running the scripts outside Actions

This isn't normally needed. For one-off debugging, the scripts accept the same variables from
your shell, for example:

```
IBMI_USER=... IBMI_IDENTITY=~/.ssh/key IBMI_CURLIB=MBPRICE1 IBMI_IFS_DIR=todo-dev \
  bash scripts/ibmi-deploy.sh my-branch
```

Never do this against `test` or `prod`. Those libraries should only change through their
workflows.

**Why `IBMI_CURLIB` has to be set by hand:** a non-interactive SSH job has no reliable way to
look up the profile's current library at build time. `DSPUSRPRF` and screen-oriented Display
commands generally kill a non-interactive SSH session outright when run without a pty, so
there's no `DSPUSRPRF`-and-parse trick available to the scripts — you just have to tell them
which library you mean.

---

## No library creation, no source members

There are **no source physical files** in this workflow — no `QDDSSRC`/`QRPGLESRC` members,
no `CRTSRCPF`, no SEU, no `scp`, no `CPYFRMSTMF`, no member upload of any kind. Source lives
in this git repo as plain `.PF`/`.LF`/`.DSPF`/`.RPGLE`/`.BND` files, pub400 pulls it directly
onto the IFS via git (see [Deploying](#deploying)), and every compile command reads straight
from that IFS path with `SRCSTMF(...)` — never `SRCFILE(...)`/`SRCMBR(...)`.

There is also no `CRTLIB` step. pub400.com restricts library creation on its shared free
tier, so each profile is pre-provisioned with its own current library instead (see
[The three libraries](#the-three-libraries-and-the-ci-pipeline) below). Every compile command
targets **`*CURLIB`**, never a hardcoded library name — that's also why
`QDDSSRC/TODOLF.LF` references `PFILE(*CURLIB/TODOPF)` rather than a fixed library.

---

## Deploying

```
bash scripts/ibmi-deploy.sh <git-ref>
```

`<git-ref>` defaults to `main` if omitted. This SSHes to pub400 and has **pub400 itself pull
from GitHub** — nothing is copied from your local working tree:

- If `/home/$IBMI_USER/source/$IBMI_IFS_DIR` already has a git checkout, it runs `git fetch
  origin`; otherwise it clones `https://github.com/matsfan/todo.git` there fresh.
- It then resolves `<git-ref>` (preferring `origin/<git-ref>` if that exists, e.g. for a
  branch name) and does `git checkout --detach` + `git reset --hard` + `git clean -fdx` onto
  it.
- The result is that whatever gets compiled always matches an exact, known commit, and a bad
  deploy can be rolled back by re-running the script against a previous good SHA instead of
  needing a separate backup mechanism.

**That IFS checkout is not scratch space.** `git clean -fdx` wipes anything untracked in it on
every deploy — don't hand-edit files there over an SSH session expecting them to survive.

Each environment has its own checkout (`IBMI_IFS_DIR`: `todo-dev`, `todo-test`, `todo-prod`)
so one environment's `git clean -fdx` never wipes the working tree another is mid-build
against.

---

## Compiling

```
bash scripts/ibmi-compile.sh [target]
```

With no target, this does a full build. The build engine is **TOBi**
(`/QOpenSys/pkgs/bin/makei build`, formerly called "Bob"/"Better Object Builder"), driven by
`iproj.json` plus a root `Rules.mk` and one `Rules.mk` per source directory — not a
hand-maintained CL sequence. The dependency order TOBi builds in (and what matters when
editing `Rules.mk`) is:

```
TODOPF -> TODOLF -> TODODSPPF -> TODOBL.MODULE -> TODOBL.SRVPGM -> TODOBND.BNDDIR -> TODOMAIN.PGM
```
(then `TODOTEST.MODULE -> TODOTEST.SRVPGM`, which currently cannot build — see
[Tests](#tests).)

[`scripts/ibmi-compile.sh`](../scripts/ibmi-compile.sh) is more involved than a single remote
`makei build` call, for three reasons documented in its comments (confirmed live
2026-09-09/2026-09-10) — read the script itself for the full explanation, this is the shape,
not a substitute for it:

1. **A CL wrapper program runs the whole build inside one `CHGCURLIB`.** A bare `CHGCURLIB`
   issued from one PASE `system()` call has no effect on any later, separate `system()` call —
   each is its own isolated unit and doesn't share job-attribute state with the next, the same
   way `QTEMP` doesn't carry across them. That was the root cause of a `CPF4131` level-check
   failure, because the unqualified `DCL-F TODODSPPF WORKSTN` in `TODOMAIN` (and `TODOPF`/
   `TODOLF` in `TODOBL`) resolve at compile time via the job's *real* current library. A `QSH`
   child process — and any `system()` calls nested inside it — does inherit a `CHGCURLIB` done
   earlier in the same CL program, so the script builds a small CL wrapper that does
   `CHGCURLIB` then `QSH`-invokes the actual build body, and runs that wrapper as a single
   `CALL`.
2. **`makei build` runs twice**, around an explicit `CRTSRVPGM`/`CRTBNDDIR`/`ADDBNDDIRE` step.
   TOBi on this pub400 install can't actually build a `*SRVPGM` from binder source or a
   `*BNDDIR` at all — the recipes it references for that (`MODULE_TO_BND_RECIPE`/
   `BND_TO_BNDDIR_RECIPE`) are referenced but never defined, so `make` silently expands them to
   nothing and reports the target "up to date" even though the object doesn't exist. The first
   `makei build` pass is allowed to fail (everything it *can* build — DSPF/PF/LF/MODULE —
   still gets built); the script then creates `TODOBL.SRVPGM` and `TODOBND.BNDDIR` explicitly;
   the second `makei build` pass is what actually determines success.
3. **`TODOMAIN.PGM` is bound explicitly by the script**, via its own `CRTBNDRPG ...
   BNDDIR($CURLIB/TODOBND)`, because makei's own generated `CRTBNDRPG` command never emits a
   `BNDDIR()` parameter at all.

Every CL/`system` call in the script redirects stdin from `/dev/null` — without it, the
command reads from the same stdin stream the rest of the remote script is being fed through
and silently swallows everything after it, with no error. (This is the same root cause behind
an earlier `DSPUSRPRF`-over-SSH mystery: screen-oriented Display commands kill a
non-interactive SSH session outright when run without a pty.)

---

## The three libraries and the CI pipeline

One pub400 profile, three pre-provisioned libraries, one GitHub Environment each (see
[Environments](#environments)):

| Library | Role | How it's updated |
|---|---|---|
| `MBPRICE1` | dev | **Automatically**, on every push to any branch except `main`, by `deploy-dev.yml`. |
| `MBPRICE2` | test | **Automatically**, on every push to `main`, by `deploy-test.yml`. |
| `MBPRICEB` | production | **Manually**, with reviewer approval, by `deploy-prod.yml` — see [Deploying to production](#deploying-to-production). |

Dev and test also have `workflow_dispatch`, for an on-demand retry. All three workflows run the
same two scripts covered above; only the GitHub Environment differs. Bob's `Stop` hook
(`.bob/hooks/ibmi-post-stop.sh`) used to build dev locally and is now a no-op.

---

## The two scripts are the only way in

`scripts/ibmi-deploy.sh` and `scripts/ibmi-compile.sh` are the **only** permitted way to
deploy and compile against pub400.com — this is a hard project rule (see
[CLAUDE.md](../CLAUDE.md), [AGENTS.md](../AGENTS.md)). Never hand-craft `ssh`/`scp`/`CRT*`
commands, and never invoke `makei` or CL over an ad hoc SSH session as a substitute for these
scripts. The reasoning: routing everything through the scripts means bugs in the scripts
themselves get found and fixed as part of the same iteration loop, instead of being silently
worked around by someone typing the "right" command by hand once and moving on.

The one exception: it's fine to open a **read-only** SSH session to inspect build artifacts a
script run already produced — for example, reading an `.evfevent` file for compile
diagnostics (see [Troubleshooting](#troubleshooting--useful-commands)). The rule is about
never substituting ad hoc commands for the deploy/compile *action* itself.

---

## Running the app

```
CALL *CURLIB/TODOMAIN
```

from a 5250 session signed on to pub400.com. You should see the Todo List screen. Use:

| Key / Option | Action |
|---|---|
| **F6** | Add a new todo |
| **2** + Enter | Edit the selected todo |
| **4** + Enter | Delete the selected todo (with confirmation) |
| **5** + Enter | Mark the selected todo as Done (removes from list) |
| **F3** | Exit the application |

> **Qualifying `CALL` with a library does not select which library's data you hit.**
> `TODOBL.RPGLE` declares `TODOPF`/`TODOLF` unqualified, with no `OVRDBF`, so they resolve via
> the job's `*LIBL` — specifically its current-library slot, a job/profile attribute
> independent of which library the `*PGM`/`*SRVPGM` objects were actually loaded from. A
> qualified `CALL MBPRICE2/TODOMAIN` still reads/writes whichever library is your session's
> *actual* current library, not `MBPRICE2`, unless you switch it first. Confirmed 2026-09-09: a
> todo added via `CALL MBPRICE2/TODOMAIN` (without switching current library first) showed up
> under `CALL MBPRICE1/TODOMAIN` — it had been writing to `MBPRICE1/TODOPF` the whole time. To
> actually exercise a given library's data:
> ```
> CHGCURLIB CURLIB(MBPRICE2)
> CALL MBPRICE2/TODOMAIN
> ```
> then `CHGCURLIB CURLIB(MBPRICE1)` (or whichever is your normal dev library) to switch back
> afterward.

---

## Tests

```
RUCALLTST TSTPGM(*CURLIB/TODOTEST)
```

**This is currently blocked and cannot be run.** RPGUnit is not installed on this pub400
instance (confirmed 2026-09-08) — the `RPGUNIT` library doesn't exist on the profile and isn't
available via `yum`/PASE either. As a result:

- `TODOTEST.MODULE`/`TODOTEST.SRVPGM` fail to build: `make: No rule to make target
  '/QSYS.LIB/RPGUNIT.LIB/RUCRTTST.SRVPGM'`.
- `TODOTEST.RPGLE` also needs `/COPY RPGUNIT/QINCLUDE,TESTCASE` at compile time, not just bind
  time, so it can't compile at all without RPGUnit present.

This is expected given the current environment and is not currently a priority to fix — see
[CLAUDE.md](../CLAUDE.md) and [docs/plans/cicd-pipeline-plan.md](plans/cicd-pipeline-plan.md)
Sub-Task 3 for status. Don't treat the `RUCALLTST` command above as something you can run today
— it's documented for when RPGUnit becomes available, not as a current step.

---

## Troubleshooting / useful commands

| Purpose | Command |
|---|---|
| List objects in your current library | `DSPLIB LIB(*CURLIB)` |
| View physical file contents | `DSPPFM FILE(*CURLIB/TODOPF)` |
| Clear all records from the PF | `CLRPFM FILE(*CURLIB/TODOPF)` |
| Check your library list | `DSPLIBL` |
| View the job log after a failure | `DSPJOBLOG` |

Beyond the 5250 commands above:

- **Compile diagnostics** — `makei build` runs with `OPT=*EVENTF`, so each compiled object
  gets an `.evfevent` file alongside its source on the IFS checkout with the real `CPF`/`RNF`
  message IDs and line numbers. It's fine to open a **read-only** SSH session to read one of
  these after a script run (see [The two scripts are the only way in](#the-two-scripts-are-the-only-way-in));
  just don't use that session to run compile commands directly.
- **GitHub Actions** — for any build failure, check that environment's workflow run (**Deploy
  to dev/test/production library**) in the repo's Actions tab rather than SSHing in by hand.

---

## Tips for pub400.com

- **Session timeout:** pub400.com sessions time out after roughly 15 minutes of inactivity in
  a 5250 session. Press any key to prevent it.
- **Case sensitivity:** IBM i object and member names are **upper-case** internally. Commands
  are case-insensitive at the prompt, but object names are stored upper-case.
- **Free disk quota:** pub400.com has a per-user disk quota. Compiled objects are larger than
  source — be aware if you recompile many times.
