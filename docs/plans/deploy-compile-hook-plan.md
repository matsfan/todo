# Deploy & Compile Hook Plan

> **Update (2026-09-08):** the scripts evolved past what this plan describes once the
> hook was actually exercised end-to-end for the first time. `.env` now also requires
> `IBMI_CURLIB` (DSPUSRPRF and other screen-oriented Display commands kill a
> non-interactive SSH session outright, so the current library can't be looked up at
> build time -- see `scripts/ibmi-compile.sh`), the scripts no longer take
> user/identity as positional args (everything comes from `.env`), and
> `scripts/ibmi-compile.sh` now also explicitly builds `TODOBL.SRVPGM`/`TODOBND.BNDDIR`
> and binds `TODOMAIN.PGM` against `TODOBND` itself -- TOBi's Rules.mk-driven build
> cannot do either on this pub400 install. This doc is kept as-is below for the
> original design history; treat the scripts themselves as the source of truth.

## Overview

Mandate that Bob always uses `scripts/ibmi-deploy.sh` and `scripts/ibmi-compile.sh` for every
deploy and compile operation against pub400.com — both as a rule Bob follows when doing
implementation work, and as an automatic post-session action via a Bob `Stop` hook. This keeps
both scripts as the single source of truth for how the application is deployed and built; as the
team learns more about the IBM i environment the scripts evolve in place, and those improvements
automatically feed the future CI/CD pipeline.

**Scope:**
- Update AGENTS.md (root) and `.bob/rules-agent/AGENTS.md` to make the scripts mandatory.
- Add a `.env`-based credential file (git-ignored) for the pub400 username and SSH identity.
- Add a `.bob/hooks/ibmi-post-stop.sh` shell script that reads `.env`, runs deploy then compile,
  and appends output to a log file without interrupting Bob's session.
- Register the hook as a `Stop` event in `.bob/settings.json`.

**Non-goals:**
- No changes to the scripts themselves.
- No CI/CD workflow YAML (that is Sub-Task 4 of `cicd-pipeline-plan.md`).
- No RPGUnit test invocation (Sub-Task 3 of `cicd-pipeline-plan.md`).

---

## Sub-Tasks

---

### Sub-Task 1 — Create `.env` credential file and git-ignore it

**Intent**
Give the hook a consistent, non-secret-in-config place to find the pub400 username and SSH
identity path. The file must never be committed.

**Expected Outcomes**
- `.env` file exists at the repo root with `IBMI_USER` and `IBMI_IDENTITY` variables.
- `.env` is listed in `.gitignore` (create `.gitignore` if it does not exist).
- `.env.example` exists at the repo root documenting the two required variables (safe to commit).

**Todo List**
1. Check whether `.gitignore` exists; if not, create it.
2. Add `.env` to `.gitignore` (only if not already present).
3. Create `.env.example` with placeholder values:
   ```
   IBMI_USER=your-pub400-username
   IBMI_IDENTITY=~/.ssh/ci-key
   ```
4. Create `.env` with actual values (do NOT commit — it is git-ignored):
   ```
   IBMI_USER=mbprice1
   IBMI_IDENTITY=~/.ssh/ci-key
   ```

**Relevant Context**
- `scripts/ibmi-deploy.sh` takes `<username>` as `$1` and an optional identity file as `$3`.
- `scripts/ibmi-compile.sh` takes `<username>` as `$1` and an optional identity file as `$2`.
- `IBMI_SSH_PORT` is already read from the environment by both scripts (defaults to `2222`).

**Status:** [x] done

---

### Sub-Task 2 — Write the post-Stop hook script

**Intent**
Create a shell script at `.bob/hooks/ibmi-post-stop.sh` that the Bob `Stop` hook will invoke.
It reads credentials from `.env`, runs deploy then compile, and appends all output to
`.bob/logs/ibmi-build.log` without blocking or interrupting the Bob session.

**Expected Outcomes**
- `.bob/hooks/ibmi-post-stop.sh` exists and is executable.
- When run, it:
  1. Sources `.env` from the repo root (fails silently if the file is absent so other users'
     sessions are not broken).
  2. Skips execution if `IBMI_USER` is unset (print a one-line warning to the log).
  3. Appends a timestamped header, then runs `scripts/ibmi-deploy.sh` and
     `scripts/ibmi-compile.sh`, capturing combined stdout+stderr to
     `.bob/logs/ibmi-build.log`.
  4. Appends a `PASS` or `FAIL` footer with the exit code.
- `.bob/logs/` is git-ignored (logs are local artifacts, not source).
- The script itself exits 0 always — the `Stop` hook must not block Bob regardless of build result.

**Todo List**
1. Create `.bob/logs/` directory placeholder (e.g. `.bob/logs/.gitkeep`).
2. Add `.bob/logs/` to `.gitignore`.
3. Write `.bob/hooks/ibmi-post-stop.sh`:
   - `#!/usr/bin/env bash`
   - Source `.env` relative to the `cwd` from stdin JSON, or fall back to `__dirname`-relative lookup.
   - Guard on `IBMI_USER` being set.
   - Run deploy: `scripts/ibmi-deploy.sh "$IBMI_USER" "$IBMI_GIT_REF" "$IBMI_IDENTITY"` where
     `IBMI_GIT_REF` defaults to the current local branch (`git rev-parse --abbrev-ref HEAD`)
     when not set in `.env`.
   - Run compile: `scripts/ibmi-compile.sh "$IBMI_USER" "$IBMI_IDENTITY"`.
   - Append all output and final status to the log file.
   - Exit 0 unconditionally.
4. `chmod +x .bob/hooks/ibmi-post-stop.sh`.
5. Test the script manually: `echo '{"session_id":"test","cwd":"'$(pwd)'","hook_event_name":"Stop","last_assistant_message":null}' | bash .bob/hooks/ibmi-post-stop.sh` and confirm the log file is created with expected content.

**Relevant Context**
- Bob `Stop` hook: receives `{"session_id":…,"cwd":…,"hook_event_name":"Stop","last_assistant_message":…}` on stdin; exit 2 is logged but ignored (task loop is already done), so exiting 0 always is fine.
- `scripts/ibmi-deploy.sh` signature: `$1=user $2=git-ref $3=identity-file`.
- `scripts/ibmi-compile.sh` signature: `$1=user $2=identity-file $3=make-target`.
- Log file path: `.bob/logs/ibmi-build.log` (appended, not overwritten, so history is preserved).

**Status:** [x] done

---

### Sub-Task 3 — Register the hook in `.bob/settings.json`

**Intent**
Wire `.bob/hooks/ibmi-post-stop.sh` into Bob's `Stop` lifecycle event so it runs automatically
when Bob finishes a task in this workspace.

**Expected Outcomes**
- `.bob/settings.json` exists and contains a valid `Stop` hook pointing at
  `.bob/hooks/ibmi-post-stop.sh`.
- No other existing settings or hooks are overwritten.
- The hook event name, handler type, and command are all valid per Bob's hook schema.

**Todo List**
1. Read `.bob/settings.json` if it exists; create a minimal valid JSON object if it does not.
2. Add the `Stop` hook entry:
   ```json
   {
     "hooks": {
       "Stop": [
         {
           "hooks": [
             {
               "type": "command",
               "command": "bash .bob/hooks/ibmi-post-stop.sh",
               "timeout": 120
             }
           ]
         }
       ]
     }
   }
   ```
3. Read the file back and validate the JSON is syntactically correct.
4. Note: a `timeout` of 120 seconds is set because deploy + compile can take up to a minute or
   two on pub400; the default 10-second timeout would kill the hook before it finishes.

**Relevant Context**
- Bob hook settings schema: `Stop` event has no matcher (omit the `matcher` key).
- Settings file location: `.bob/settings.json` (workspace scope — this hook only applies to this
  repo, which is correct since it's pub400-specific).
- Global settings (`~/.bob/settings/settings.json`) are not modified.

**Status:** [x] done

---

### Sub-Task 4 — Update AGENTS.md to mandate the scripts

**Intent**
Make it explicit in the rules Bob reads that `scripts/ibmi-deploy.sh` and
`scripts/ibmi-compile.sh` are the **only** permitted way to deploy and compile, so no future
agent or contributor hand-rolls `CRT*` commands or `scp` calls.

**Expected Outcomes**
- Root `AGENTS.md` has a clearly labelled section stating the scripts are mandatory, explaining
  the `.env` file and log location, and cross-referencing the scripts.
- `.bob/rules-agent/AGENTS.md` has a concise rule that Bob (in agent mode) must run the hook
  script (or the scripts directly) after implementation work — not hand-roll CL commands.
- `.bob/rules-plan/AGENTS.md` notes that deploy/compile is fully handled by the scripts and Bob
  does not need to plan manual compile steps.

**Todo List**
1. Add a "Deploy & Compile" section to root `AGENTS.md` covering:
   - The two scripts are the canonical deploy/compile path.
   - Credentials come from `.env` (see `.env.example`).
   - After finishing implementation work, Bob runs the hook (or the scripts directly).
   - Build output is appended to `.bob/logs/ibmi-build.log`.
2. Add a rule to `.bob/rules-agent/AGENTS.md`:
   - After implementation, always trigger deploy+compile via `bash .bob/hooks/ibmi-post-stop.sh`
     (or the hook fires automatically on `Stop`); never hand-craft `CRT*` commands.
3. Add a note to `.bob/rules-plan/AGENTS.md`:
   - Deploy and compile steps do not need to be planned as manual tasks — they are handled by
     `scripts/ibmi-deploy.sh` / `scripts/ibmi-compile.sh` and the Bob `Stop` hook.

**Relevant Context**
- Root `AGENTS.md`: [`AGENTS.md`](../../AGENTS.md) — 122 lines, "Compile Commands" section
  already references `makei build` but does not mention Bob's hook.
- `.bob/rules-agent/AGENTS.md`: [`rules-agent/AGENTS.md`](../rules-agent/AGENTS.md) — 11 lines,
  coding conventions only; deploy rule is absent.
- `.bob/rules-plan/AGENTS.md`: [`rules-plan/AGENTS.md`](../rules-plan/AGENTS.md) — 9 lines,
  architecture notes only.

**Status:** [x] done

---

## Sequencing

Sub-Tasks 1 → 2 → 3 → 4, in order. Sub-Task 1 must precede 2 (the hook script sources `.env`).
Sub-Task 2 must precede 3 (the hook script must exist before the settings entry references it).
Sub-Task 4 is independent but logically last (documents what was built).
