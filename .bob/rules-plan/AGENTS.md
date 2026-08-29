# Project Architecture Rules (Non-Obvious Only)

- All CRUD operations use two separate file handles: `TODOLF` for sequential reads (subfile load, ID generation) and `TODOPF` for mutations. They are not interchangeable.
- The subfile (`TODOSFL`) is a full-page subfile with `SFLSIZ(99)` — it is completely cleared and reloaded from scratch on every return to the list screen. There is no incremental update path.
- `TDDONE='1'` records are filtered in RPG (`LoadSubfile`), not at the logical file level — `TODOLF` has no select/omit. Adding a select/omit to the LF would require recompiling both `TODOLF` and `TODOMAIN`.
- `GetNextId` is a max-ID-plus-one scheme, not a sequence object — concurrent users on a multi-user system could generate duplicate IDs. This is acceptable for pub400.com single-user use only.
- Program entry is `Main()` called at the very last line of the source (`line 326`) — the call site is outside any procedure, which is the standard IBM i free-form entry pattern.
- `USROPN` on both database files means the program controls open/close; if a future procedure needs to access the files before `Main()` opens them, it will abend.
