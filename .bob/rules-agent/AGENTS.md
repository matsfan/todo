# Project Coding Rules (Non-Obvious Only)

- All file I/O and business logic lives in `TODOBL` (`*SRVPGM`), not `TODOMAIN` — `TODOMAIN` is a thin UI shell that calls `TODOBL`'s exported procedures (`OpenFiles`, `CloseFiles`, `GetNextId`, `ValidateDescription`, `AddTodoRecord`, `EditTodoRecord`, `MarkDoneRecord`, `DeleteTodoRecord`, `ReadFirstTodo`, `ReadNextTodo`, `GetTodoById`).
- `TODOPF` is opened in `TODOBL` `USAGE(*UPDATE:*OUTPUT:*DELETE)` — writing/updating/deleting must always go through `TODOPF`, never `TODOLF`.
- Subfile clear is order-dependent: `*IN52=*ON` → `WRITE TODOCTL` → `*IN52=*OFF` immediately. Rows written before clearing, or with `*IN52` left on, corrupt the subfile.
- `TODOFTR` (list screen footer, row 23) is a separate record format from `TODOCTL` because content at/below the subfile's own row span can't live inside the subfile control record. Both declare `OVERLAY`; `TODOMAIN`'s `Main` does `WRITE TODOFTR;` before `EXFMT TODOCTL;` every pass — dropping either breaks the footer or the list.
- `*IN50` (SFLDSP) must be `*OFF` when zero rows exist — attempting to display an empty subfile abends the program.
- `DeleteTodoRecord` (in `TODOBL`) does a single `CHAIN` + `DELETE` — do NOT add a re-chain. The confirmation screen (`EXFMT TODODEL` in `TODOMAIN`'s `DeleteTodo`) happens *before* `DeleteTodoRecord` is called, so there is no intervening screen I/O to lose the lock across.
- `GetNextId` (in `TODOBL`) uses `SETLL *END` + `READP` on `TODOLF` to find the highest existing ID; it returns `1` when the file is empty.
- `w_Found` is always assigned as `NOT %EOF(...)` immediately after `CHAIN` — do not introduce `%FOUND` checks; the pattern would be inconsistent.
- DDS source uses fixed-column layout — never run a general code formatter on `.PF`, `.LF`, `.DSPF` files; columns 1–80 are significant.
- The target library is `*CURLIB`, not a hardcoded name — used in `PFILE(*CURLIB/TODOPF)` inside `QDDSSRC/TODOLF.LF` and in every compile command, since pub400.com doesn't allow arbitrary library creation and each profile has its own pre-provisioned current library.
- After finishing implementation work, deploy and compile are handled automatically by the `Stop` hook (`.bob/hooks/ibmi-post-stop.sh`). Do not hand-craft `CRT*` commands or `scp` calls. If you need to trigger deploy+compile manually mid-session, run `bash .bob/hooks/ibmi-post-stop.sh` directly.
