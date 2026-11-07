# Project Instructions for Claude Code

This is an IBM i (RPG/5250) TODO application hosted on pub400.com, also worked on by another
coding agent ("Bob") — see `.bob/rules-agent/AGENTS.md`, `.bob/rules-plan/AGENTS.md`, and
`.bob/rules-ask/AGENTS.md` for the rules Bob follows, and `AGENTS.md` at the repo root for the
shared project rules (architecture, compile order, deploy & compile).

## Deploy & Compile — always use the scripts

`scripts/ibmi-deploy.sh` and `scripts/ibmi-compile.sh` are the **only** permitted way to deploy
and compile against pub400.com. Never hand-craft `ssh`/`scp` calls or `CRT*` commands directly,
and never invoke `makei` or CL commands over an ad hoc SSH session as a substitute for these
scripts — the point of routing everything through them is that bugs in the scripts themselves
get found and fixed as part of the same iteration loop, instead of being silently worked around.

- **The scripts run in GitHub Actions, not locally.** Each environment is a GitHub Environment
  (Settings → Environments) holding its `IBMI_CURLIB` and `IBMI_IFS_DIR`; the workflows pass
  those to the scripts. See AGENTS.md and `docs/DEPLOY.md`.
  - dev (`MBPRICE1`): push any branch except `main` → `deploy-dev.yml`.
  - test (`MBPRICE2`): push/merge to `main` → `deploy-test.yml`.
  - prod (`MBPRICEB`): `deploy-prod.yml`, manual "Run workflow" only, held for reviewer
    approval, and only takes a commit on `main` that already passed `deploy-test.yml`.
    Only start it when the user explicitly asks for a production deploy.
- Deploy: `bash scripts/ibmi-deploy.sh [git-ref]` (pulls that ref from GitHub onto pub400 via a
  `git reset --hard` + `git clean -fdx` checkout — never used as ad hoc scratch space).
- Compile: `bash scripts/ibmi-compile.sh [target]` (defaults to a full `makei build`).
- Both scripts read everything from environment variables — `IBMI_USER`, `IBMI_IDENTITY`
  (repo secrets), `IBMI_CURLIB`, `IBMI_IFS_DIR` (GitHub Environment variables) — with no
  defaults for the library or checkout. There is no `.env` file. `IBMI_CURLIB` is required because non-interactive
  SSH jobs have no reliable way to look up the profile's current library at build time — see the
  comment in `scripts/ibmi-compile.sh` for why (`DSPUSRPRF`, and screen-oriented Display commands
  generally, kill the SSH session outright when run without a pty).
- It is fine to open a read-only SSH session to inspect build artifacts already produced by a
  script run (e.g. reading an `.evfevent` file for compile diagnostics) — the rule above is about
  never substituting ad hoc commands for the deploy/compile *action* itself.

## Known limitation

RPGUnit is not installed on this pub400 instance. `TODOTEST.MODULE` fails to compile (it needs
`/COPY RPGUNIT/QINCLUDE,TESTCASE`, which doesn't exist), and `TODOTEST.BND` separately fails
(`make: No rule to make target '/QSYS.LIB/RPGUNIT.LIB/RUCRTTST.SRVPGM'`) — this is expected and
not currently a priority to fix. See [AGENTS.md](AGENTS.md#compile-commands) for the full story.
`TODOTEST.RPGLE` exists as source, targeting `TODOBL`'s exported procedures; `RUCALLTST` is not
something you can run today.
