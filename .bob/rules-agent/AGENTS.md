# Project Coding Rules (Non-Obvious Only)

- `TODOPF` is opened `USAGE(*UPDATE:*OUTPUT:*DELETE)` — writing/updating/deleting must always go through `TODOPF`, never `TODOLF`.
- Subfile clear is order-dependent: `*IN52=*ON` → `WRITE TODOCTL` → `*IN52=*OFF` immediately. Rows written before clearing, or with `*IN52` left on, corrupt the subfile.
- `*IN50` (SFLDSP) must be `*OFF` when zero rows exist — attempting to display an empty subfile abends the program.
- `DeleteTodo` must re-chain to `TODOPF` after `EXFMT TODODEL` before issuing `DELETE` — the record lock is dropped across a screen I/O.
- `GetNextId` uses `SETLL *END` + `READPE` on `TODOLF` to find the highest existing ID; it returns `1` when the file is empty.
- `w_Found` is always assigned as `NOT %EOF(...)` immediately after `CHAIN` — do not introduce `%FOUND` checks; the pattern would be inconsistent.
- DDS source uses fixed-column layout — never run a general code formatter on `.PF`, `.LF`, `.DSPF` files; columns 1–80 are significant.
- The library name `TODO` is hardcoded in `PFILE(TODO/TODOPF)` inside `QDDSSRC/TODOLF.LF` and in every compile command — update both if the library changes.
