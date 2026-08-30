# RPG for C#/.NET Developers — A Primer Using This Repo

This is a guided tour of IBM i / RPG concepts, taught entirely through the actual
`TODO` application in this repository. Every concept is anchored to a real line
of code you can go look at, and mapped to the closest C#/.NET equivalent you
already know. The mapping is never exact — that's the point where the real
learning happens — but it'll get you oriented fast.

Read this top to bottom once, then keep it open as a reference while you read
the source files in this order:

1. [`QDDSSRC/TODOPF.PF`](../QDDSSRC/TODOPF.PF) — the table
2. [`QDDSSRC/TODOLF.LF`](../QDDSSRC/TODOLF.LF) — an index/view over it
3. [`QDDSSRC/TODODSPPF.DSPF`](../QDDSSRC/TODODSPPF.DSPF) — the screens
4. [`QRPGLESRC/TODOBL.RPGLE`](../QRPGLESRC/TODOBL.RPGLE) — the "service layer"
5. [`QRPGLESRC/TODOMAIN.RPGLE`](../QRPGLESRC/TODOMAIN.RPGLE) — the UI controller
6. [`QRPGLESRC/TODOTEST.RPGLE`](../QRPGLESRC/TODOTEST.RPGLE) — the tests

---

## 1. The big mental shift: there is no filesystem, and no build output folder

In .NET, source is `.cs` files on disk, and `dotnet build` produces `.dll`/`.exe`
files elsewhere. On IBM i, almost nothing is a plain file:

| .NET world | IBM i world |
|---|---|
| Folder | **Library** (e.g. `TODO`) |
| `.cs`, `.sql` files on disk | **Source physical file member** — a "file" that is really a database table of source lines, living inside a library |
| Solution/project structure | This repo's `QRPGLESRC/` and `QDDSSRC/` folders are a *local mirror* of two source files, `TODO/QRPGLESRC` and `TODO/QDDSSRC`, that actually live on the IBM i server |
| `.dll` / `.exe` | **`*PGM`** (program object) or **`*SRVPGM`** (service program object) |
| `dotnet build` | A `CRT*` ("Create") CL command — `CRTPF`, `CRTDSPF`, `CRTSRVPGM`, `CRTBNDRPG`, etc. |
| `dotnet run` | `CALL TODO/TODOMAIN` |

There's no `dotnet build` equivalent that "just knows what to do" — you compile
each object explicitly, in dependency order, with named CL commands. See
[`AGENTS.md`](../AGENTS.md#compile-commands-must-run-in-this-exact-order) for
this project's exact sequence — notice the table has to exist before the
logical file, which has to exist before the service program, which has to
exist before the binding directory is populated, which has to exist before the
main program compiles. That ordering is load-bearing, not stylistic.

The five-character member names (`TODOPF`, `TODOBL`, `TODOMAIN`...) aren't a
style choice either — they're a hard OS limit on object names, which is why
everything in this codebase is terse and abbreviated (`TDID`, `TDDESC`, `w_Rrn`).
There's no Roslyn analyzer nagging you to rename `w_Rrn` to `currentRelativeRecordNumber`;
10 characters is often the ceiling for a field name in DDS.

---

## 2. `**FREE` — RPG has two syntaxes, and you only need to know one

Classic RPG ("fixed-form") required code to sit in specific numbered columns —
a holdover from punch cards. Every file in `QRPGLESRC/` in this repo opens with:

```rpgle
**FREE
```

([`TODOMAIN.RPGLE:1`](../QRPGLESRC/TODOMAIN.RPGLE)) — this switches the whole
member to free-form syntax, which reads much more like a normal structured
language: statements end in `;`, indentation is cosmetic, `//` is a line
comment. You will see old fixed-form RPG (`RPG III`/`RPG IV` without `**FREE`)
in the wild on legacy IBM i systems, but this project is 100% free-form, and
that's the modern default — treat fixed-form as "legacy dialect" the way
you'd treat VB6 next to C#.

DDS (the files in `QDDSSRC/`) is a *different, older* fixed-column language
that free-form RPG did **not** replace — more on that in §4.

---

## 3. Files-as-tables: DDS physical/logical files ≈ a table + a view

### `TODOPF` — the table

[`QDDSSRC/TODOPF.PF`](../QDDSSRC/TODOPF.PF) is DDS (Data Description
Specifications) defining a **physical file** — this is the actual on-disk
table. Roughly:

```
A                                      UNIQUE
A          R TODOR
A            TDID           5P 0       TEXT('Todo ID - unique sequential key')
A            TDDESC        50A         TEXT('Todo description')
A            TDDONE         1A         TEXT('Done flag: 0=Pending 1=Done')
A            TDDUE          L          TEXT('Due date')
A                                      DATFMT(*ISO)
A          K TDID
```

Map it like this:

| DDS | SQL/.NET equivalent |
|---|---|
| The whole `TODOPF` file | A table, `CREATE TABLE TODOPF (...)` |
| `R TODOR` | The **record format** — think of this as the row's *type*, roughly a C# class/`record` describing one row. Every physical file has exactly one. |
| `TDID`, `TDDESC`, `TDDONE`, `TDDUE` | Columns |
| `5P 0` | **Packed decimal**, 5 digits, 0 decimal places — a compact BCD numeric type with no real .NET equivalent; think `int` that's stored 2-digits-per-byte. This is IBM i's favorite numeric storage type. |
| `50A` | `CHAR(50)` — fixed-width, space-padded string, 50 bytes. RPG char fields are **always** fixed-length and blank-padded, unlike C# `string` |
| `1A` | A 1-character flag — `TDDONE` is `'0'` or `'1'`, there's no native `bool` column type here, so single-char-code flags are idiomatic |
| `L` with `DATFMT(*ISO)` | A native `DATE` column formatted as ISO (`YYYY-MM-DD`) |
| `UNIQUE` | Like a unique constraint/primary key on the physical file |
| `K TDID` | **Key field** — declares `TDID` as the (only) key, i.e. the file's index/primary key, ordering records by that key |

There's no separate `CREATE TABLE` vs `CREATE UNIQUE INDEX` step conceptually
— DDS bundles column definitions and the primary key into one artifact, the
`*PF` object.

### `TODOLF` — a keyed view

[`QDDSSRC/TODOLF.LF`](../QDDSSRC/TODOLF.LF) is a **logical file**:

```
A          R TODOR                     PFILE(TODO/TODOPF)
A          K TDID
```

A logical file is IBM i's version of a database **view/index** — it doesn't
store its own data, it's a keyed (or select/omit-filtered) window onto a
physical file. This one is trivial (just re-sorts `TODOPF` by `TDID`
ascending, redundantly since `TODOPF` is already keyed that way) but in a
larger app you'd see logical files that:

- reorder records by a different key (like a SQL `ORDER BY` baked into an object)
- `SELECT`/`OMIT` a subset of rows (like a `WHERE` clause baked into an object)
- join multiple physical files, or expose only some columns

The RPG code opens `TODOLF` for **sequential reads** and `TODOPF` for
**writes/updates/deletes** — see [`TODOBL.RPGLE:34-38`](../QRPGLESRC/TODOBL.RPGLE):

```rpgle
DCL-F TODOLF    DISK    KEYED USROPN;
DCL-F TODOPF    DISK    KEYED USAGE(*UPDATE:*OUTPUT:*DELETE) USROPN;
```

That's a deliberate convention in this codebase (documented in
[`AGENTS.md`](../AGENTS.md#critical-conventions)): read through the logical
file, mutate only through the physical file. Nothing stops you from writing
through a logical file, but the project's rule is "don't."

**Roughly:** `TODOPF` is your `dbo.Todos` table; `TODOLF` is a
`CREATE VIEW ... ORDER BY TdId` sitting on top of it, and RPG opens each as a
separate file handle with different access rights, more like ADO.NET
`DataReader`s over two different queries than like an EF Core `DbContext`.

---

## 4. `DCL-F` and record I/O verbs ≈ your data access layer, minus the ORM

There's no LINQ, no EF Core, no auto-generated SQL here. RPG file I/O is a set
of built-in verbs that operate directly on a declared file, using its **key**
for positioning. From [`TODOBL.RPGLE`](../QRPGLESRC/TODOBL.RPGLE):

| RPG verb | What it does | Closest .NET analogy |
|---|---|---|
| `CHAIN i_Id TODOPF TODOR` | Random-access read by key — "get the row where `TDID = i_Id`" | `dbSet.Find(id)` / `SELECT * WHERE TdId = @id` |
| `READ TODOLF TODOR` | Read the *next* record sequentially from wherever the file is currently positioned | `IEnumerator.MoveNext()` on an ordered query |
| `SETLL *START TODOLF` | Position the file cursor *before* the first record, without reading anything | Resetting an enumerator / `OFFSET 0` |
| `SETLL *END TODOLF` | Position after the last record | Positioning at the end, used with `READPE` (read prior) to find the highest key |
| `READPE TODOR TODOLF` | Read the *previous* record | `MoveNext()` in reverse |
| `WRITE TODOR TODOPF` | Insert a new row | `INSERT` / `dbSet.Add(x); SaveChanges()` |
| `UPDATE TODOR TODOPF` | Update the row currently loaded into the record buffer | `UPDATE` / `SaveChanges()` after mutating a tracked entity |
| `DELETE TODOR TODOPF` | Delete the row currently loaded/chained | `DELETE` / `dbSet.Remove(x)` |
| `%EOF(file)` | "Did the last operation fail to find/read a record?" | `reader.Read() == false`, or a null check after `Find` |

The critical mental model: **there is one implicit record buffer per file**,
made of global-looking variables named after the columns (`TDID`, `TDDESC`,
`TDDONE`, `TDDUE`). `CHAIN`/`READ` populate that buffer; `WRITE`/`UPDATE` push
it back out. This is much closer to raw ADO.NET's `SqlDataReader` fetching into
column ordinals than to an ORM's tracked entity graph — there's no "the object IS
the row," there's a shared buffer that different files' operations read and
write through.

Example, [`TODOBL.RPGLE:210-217`](../QRPGLESRC/TODOBL.RPGLE):

```rpgle
CHAIN i_Id TODOPF TODOR;
w_Found = NOT %EOF(TODOPF);

IF w_Found;
  TDDESC = i_Desc;
  TDDUE  = i_Due;
  UPDATE TODOR TODOPF;
END-IF;
```

Read this as: "look up the row keyed by `i_Id`. If found, overwrite two
columns in the buffer, then push the whole buffer back as an `UPDATE`." Note
`TDID` and `TDDONE` are *not* reassigned — they keep whatever `CHAIN` just
loaded, since `UPDATE` writes the entire current buffer back.

`%EOF` doing double duty as "not found" (after `CHAIN`) as well as "no more
rows" (after `READ`) is very idiomatic RPG and is called out explicitly in
[`AGENTS.md`](../AGENTS.md#critical-conventions) — there's no separate
"not found" exception the way LINQ's `.Single()` throws, or a nullable return
the way `Find()` gives you `null`.

---

## 5. `DCL-PROC` / `DCL-PR` / `EXTPROC` ≈ methods, interfaces, and `extern`

RPG programs used to be one giant global-variable soup with `GOTO`. Modern
free-form RPG has real procedures. In [`TODOBL.RPGLE`](../QRPGLESRC/TODOBL.RPGLE):

```rpgle
DCL-PROC MarkDoneRecord     EXPORT;
  DCL-PI *N;
    i_Id      PACKED(5:0) CONST;
  END-PI;

  CHAIN i_Id TODOPF TODOR;
  IF NOT %EOF(TODOPF);
    TDDONE = '1';
    UPDATE TODOR TODOPF;
  END-IF;
END-PROC;
```

Map the pieces:

| RPG | C# equivalent |
|---|---|
| `DCL-PROC MarkDoneRecord EXPORT;` ... `END-PROC;` | `public void MarkDoneRecord(...)` — a method body |
| `DCL-PI *N; ... END-PI;` | The parameter list / method signature (the "**p**rocedure **i**nterface") |
| `i_Id PACKED(5:0) CONST;` | `int id` passed by value — `CONST` means "read-only, pass efficiently," similar in spirit to a `readonly` / `in` parameter |
| `EXPORT` | `public` — makes this procedure callable from outside this module |
| `DCL-PR MarkDoneRecord EXTPROC('MARKDONERECORD'); ... END-PR;` (seen in `TODOMAIN.RPGLE` and `TODOTEST.RPGLE`) | A **prototype** — like a C header declaration, or a C# `interface` method signature. It tells the *caller's* compiler what the procedure looks like without needing its source. `EXTPROC('MARKDONERECORD')` names the actual external symbol to bind to at link/bind time — conceptually like `[DllImport("...")]` or a `partial` method's real name. |

Notice `TODOMAIN.RPGLE` and `TODOTEST.RPGLE` both **paste in the exact same
`DCL-PR` block** that `TODOBL.RPGLE` defines
([`TODOMAIN.RPGLE:68-117`](../QRPGLESRC/TODOMAIN.RPGLE),
[`TODOTEST.RPGLE:40-73`](../QRPGLESRC/TODOTEST.RPGLE)). There's no `#include`
that both sides share automatically the way a C# interface or an EF Core
`DbContext` reference does — each caller manually re-declares the contract it
expects `TODOBL` to expose. (Larger RPG codebases pull shared prototypes into
a `/COPY` member — see `TODOTEST.RPGLE`'s `/COPY RPGUNIT/QINCLUDE,TESTCASE`
for what that looks like — but this project chose to duplicate the small
prototype block instead. If you rename a `TODOBL` procedure, you must update
all three files by hand; the compiler won't catch a mismatch until bind time,
and even then only loosely.)

`RETURN l_Id;` inside a `DCL-PI *N PACKED(5:0) END-PI;`-typed procedure
([`TODOBL.RPGLE:146-162`](../QRPGLESRC/TODOBL.RPGLE)) is exactly a C# method
returning `decimal`/`int` — the return type is declared right after `DCL-PI`.

---

## 6. `*SRVPGM` vs `*PGM` ≈ class library vs entry-point executable

This project is split into three compiled objects:

- **`TODOBL`** compiles to a **`*SRVPGM`** (service program) — see the header
  comment in [`TODOBL.RPGLE:3-15`](../QRPGLESRC/TODOBL.RPGLE). This is the
  closest thing IBM i has to a `.dll` class library: a bundle of exported
  procedures with no `main`/entry point of its own, meant to be *called into*
  by other programs.
- **`TODOMAIN`** compiles to a **`*PGM`** — the closest thing to a `.exe`. It
  has the `Main()` call at the bottom
  ([`TODOMAIN.RPGLE:342`](../QRPGLESRC/TODOMAIN.RPGLE)) and is what you
  actually `CALL`.
- **`TODOTEST`** also compiles to a `*SRVPGM`, but one designed to be driven
  by a test runner rather than called by application code (§9).

`TODOMAIN` doesn't directly reference `TODOBL`'s object at compile time the
way a C# project references a `.csproj`/`.dll`. Instead:

1. `TODOMAIN.RPGLE` declares prototypes (`DCL-PR ... EXTPROC(...)`) describing
   what it *expects* to be able to call — like coding against an `interface`
   with no implementation reference yet.
2. At compile time, `CRTBNDRPG PGM(TODO/TODOMAIN) ... BNDDIR(TODO/TODOBND)`
   resolves those external symbols using a **binding directory** — see
   [`AGENTS.md:22-30`](../AGENTS.md#compile-commands-must-run-in-this-exact-order):

   ```cl
   CRTBNDDIR BNDDIR(TODO/TODOBND)
   ...
   ADDBNDDIRE BNDDIR(TODO/TODOBND) OBJ((TODO/TODOBL *SRVPGM))
   CRTBNDRPG PGM(TODO/TODOMAIN) SRCFILE(TODO/QRPGLESRC) SRCMBR(TODOMAIN) BNDDIR(TODO/TODOBND)
   ```

A binding directory is a named, reusable *list of service programs to search*
when resolving unresolved external calls — conceptually closer to a
`PackageReference`/NuGet feed pointer than a project reference, since it's a
named, indirect list rather than a direct file path. `TODOTEST` binds against
the same `TODOBND` directory (plus RPGUnit's own service program) so it can
call the exact same `TODOBL` procedures the real UI calls — that's the whole
point of the split (spelled out in
[`AGENTS.md:39-46`](../AGENTS.md#architecture)): **`TODOBL` is testable in
isolation from the 5250 screen**, the RPG equivalent of "put your business
logic in a class library so you can unit test it without spinning up the UI."

---

## 7. Display files (DSPF) ≈ WinForms .resx + code-behind, for a text terminal

This is the part with no close .NET analogue, because green-screen (5250)
terminals predate GUIs. [`QDDSSRC/TODODSPPF.DSPF`](../QDDSSRC/TODODSPPF.DSPF)
is DDS again, but for a **display file** — it defines every screen
("record format") the program can show: exact row/column position of every
label and input field, colors, function-key bindings.

```
A          R TODODET
A                                      CA03(03 'F3=Cancel')
A                                      CA12(12 'F12=Cancel')
A            DETMODE       10A  O  1  2
A                                       5  2'Todo ID :'
A            DETID          5P 0O  5 12EDTCDE(Z)
A                                       7  2'Description:'
A            DETDESC       50A  B  7 15CHECK(LC)
```

| DDS concept | .NET/WinForms-ish analogy |
|---|---|
| A **record format** in a display file (`TODODET`, `TODOCTL`, `TODODEL`) | One screen/form, or one `.razor`/`.xaml` view |
| `1 30'IBM i RPG Todo Application'` (row 1, col 30, literal text) | A hardcoded `<Label>` at an absolute pixel/grid position — DDS screens are laid out by row/column on an 80×24 (or 132×27) character grid, there's no flow layout |
| `DETDESC 50A B 7 15` — the `B` means **B**oth input and output | A two-way bound `<TextBox Text="{Binding ...}">` |
| `O` (as in `DETID ... O`) | Output-only — a read-only `<Label>` bound to a value |
| `CA03(03 'F3=Cancel')` | Wiring the F3 key to set indicator 03 and show "F3=Cancel" in the key-list footer — like binding a `KeyDown` handler, except the binding itself lives in the *view* definition, not code-behind |
| `EDTCDE(Z)` | An edit code — formatting instructions for numeric display, like a `.ToString("format")` or WPF `StringFormat` |
| `CHECK(LC)` | Input validation hint (lowercase allowed etc.) baked into the field definition |

The DDS file is pure layout — it has **zero logic**. All screen behavior
(what happens on F3, how validation errors show, what data populates the
fields) lives in the RPG program that opens it
(`TODOMAIN.RPGLE`) — this is a real separation of view-definition from
view-logic, just split across two *different languages*, not two files of the
same language the way a `.xaml` + `.xaml.cs` pair would be.

### Indicators — the weirdest but most important idea here

DDS communicates with RPG through **indicators**: numbered boolean flags
(`*IN03`, `*IN50`, etc.) that are shared state between the display file and
the program. Think of indicators as a **fixed array of 99 numbered
`bool`s** (`*IN01` .. `*IN99`, plus named ones like `*INLR`) that both DDS and
RPG can read and set — there's no strongly-typed event system, just numbered
flags whose *meaning* is assigned by convention and documented in comments.

This project documents its indicator map in two places that must be kept in
sync ([`AGENTS.md:60`](../AGENTS.md#critical-conventions)) —
[`TODOMAIN.RPGLE:21-29`](../QRPGLESRC/TODOMAIN.RPGLE) and
[`TODODSPPF.DSPF:10-18`](../QDDSSRC/TODODSPPF.DSPF):

| Indicator | Meaning here | .NET-ish equivalent |
|---|---|---|
| `*IN03` | F3 was pressed (Exit) | A `KeyDown` handler setting `exitRequested = true` |
| `*IN06` | F6 was pressed (Add new) | Same idea, different key |
| `*IN12` | F12 was pressed (Cancel) | Same idea |
| `*IN50` | `SFLDSP` — whether to display the subfile's rows at all | `grid.Visible = true/false` |
| `*IN51` | `SFLDSPCTL` — whether to display the subfile control record | Visibility of the "page"/container around the grid |
| `*IN52` | `SFLCLR` — clear the subfile | `grid.Rows.Clear()` |
| `*IN53` | `SFLEND` — show "Bottom"/"More..." | A "you've reached the end" footer on an infinite-scroll list |
| `*IN60` | Custom, program-defined — controls whether an error message shows on `TODODET` | `errorLabel.Visible = hasValidationError` |

`CA03(03 'F3=Cancel')` in the DDS is what wires the physical F3 key to
setting `*IN03` to `*ON`; the RPG code then just reads `*IN03` as a plain
boolean:

```rpgle
DOU *IN03;                    // Loop until F3=Exit
  ...
  EXFMT TODOCTL;              // show screen, wait for user input
  IF *IN03;
    LEAVE;
  END-IF;
```
(from [`TODOMAIN.RPGLE:128-138`](../QRPGLESRC/TODOMAIN.RPGLE))

`EXFMT` itself is the verb that **writes a screen and reads the user's
response in one blocking call** — the closest .NET analogy is something like
`var result = await ShowDialogAsync(view)`, except synchronous and
terminal-based: it paints the format, blocks until Enter/a function key is
pressed, and returns with both the input fields *and* the indicators updated.

---

## 8. Subfiles ≈ a data grid / repeater control

The `TODOCTL`/`TODOSFL` pair in the DDS is a **subfile** — DDS's built-in
scrollable, multi-row list control, the direct ancestor of a WinForms
`DataGridView` or a web `<table>` bound to a collection.

```
A          R TODOSFL                   SFL
A            SFLOPT         1A  B  8  2
A            TDID           5P 0O  8  4EDTCDE(Z)
A            TDDESC        50A  O  8 11
...
A          R TODOCTL                   SFLCTL(TODOSFL)
A                                      SFLSIZ(0099)
A                                      SFLPAG(0014)
```

- `R TODOSFL ... SFL` — the **row template**: one record format describes
  *one row*, reused for every row in the list. Directly analogous to a
  `<Repeater ItemTemplate>` or a grid column definition, not one row per
  format like a normal record.
- `R TODOCTL ... SFLCTL(TODOSFL)` — the **subfile control** record, which
  owns paging (`SFLSIZ`/`SFLPAG` = max rows buffered / rows visible per page),
  the surrounding chrome (headers, footers, function keys), and the
  indicators that turn the grid on/off (`*IN50`/`*IN51`/`*IN52`/`*IN53` from
  the table above).
- `SFLOPT` (a **B**oth field, i.e. user-editable) is the "option" column
  where the user types `2`, `4`, or `5` next to a row — this UI pattern (type
  a number next to a row instead of clicking a button) is *the* classic
  5250 idiom, standing in for a row of `<button>`s in a modern grid.

Populating it, from [`TODOMAIN.RPGLE:186-226`](../QRPGLESRC/TODOMAIN.RPGLE)
(`LoadSubfile`):

```rpgle
*IN52 = *ON;              // SFLCLR on = clear
WRITE TODOCTL;
*IN52 = *OFF;

w_Rrn = 0;
IF ReadFirstTodo(l_Rec);
  DOW *ON;
    w_Rrn  += 1;
    TDID   = l_Rec.tdId;
    TDDESC = l_Rec.tdDesc;
    ...
    WRITE TODOSFL;          // append one row
    IF NOT ReadNextTodo(l_Rec);
      LEAVE;
    END-IF;
  END-DO;
END-IF;
```

This is exactly the shape of `grid.Rows.Clear(); foreach (var item in
items) grid.Rows.Add(item);` — except each `WRITE TODOSFL` needs an explicit
**RRN** (relative record number, `w_Rrn`) telling the subfile which row slot
to write into, since subfiles are directly addressed by row number rather
than append-only. `AGENTS.md` calls out the clear sequence as order-sensitive
(`*IN52=*ON` → `WRITE TODOCTL` → `*IN52=*OFF`, *before* writing any rows) and
warns that displaying a zero-row subfile (`*IN50=*ON` with nothing written)
is a runtime error — there's no framework-level empty-state handling like an
`ItemsControl` gracefully rendering nothing; you must gate `*IN50` yourself
([`TODOMAIN.RPGLE:219-222`](../QRPGLESRC/TODOMAIN.RPGLE)).

Reading back which rows the user edited/flagged is `READC` ("read changed"):

```rpgle
w_Rrn = 1;
DOU w_Rrn > w_MaxRrn;
  READC TODOSFL;                // next row the user typed something into
  IF %EOF(TODODSPPF);
    LEAVE;
  END-IF;
  w_Option = SFLOPT;
  w_SelId  = TDID;
  SELECT;
    WHEN w_Option = '2'; ExSr EditTodo;
    WHEN w_Option = '4'; ExSr DeleteTodo;
    WHEN w_Option = '5'; ExSr MarkDone;
  END-SL;
  SFLOPT = ' ';                 // clear the option so it doesn't fire again
  w_Rrn += 1;
END-DO;
```
([`TODOMAIN.RPGLE:147-170`](../QRPGLESRC/TODOMAIN.RPGLE))

`READC` only returns rows whose input-capable fields (like `SFLOPT`) changed
since the last write — a built-in "dirty row" iterator, saving you from
re-scanning every row on every postback. There's genuinely nothing quite like
this in modern web/desktop frameworks; it's closest in spirit to only firing
change events for edited grid cells rather than re-diffing the whole
collection.

`ExSr` calls a **subroutine** (`BegSr`/`EndSr`, not shown here because this
program uses `DCL-PROC` procedures named the same as the old-style
subroutines it calls — `AddTodo`, `EditTodo`, `MarkDone`, `DeleteTodo` are
actual procedures, called with `()`-less `ExSr` syntax for historical/stylistic
reasons in this file even though they're modern procs). Functionally, just
read `ExSr Foo;` as `Foo();`.

---

## 9. RPGUnit ≈ xUnit/NUnit

[`QRPGLESRC/TODOTEST.RPGLE`](../QRPGLESRC/TODOTEST.RPGLE) is a test suite
using **RPGUnit**, IBM i's xUnit-family test framework.

| RPGUnit | xUnit/NUnit equivalent |
|---|---|
| `/COPY RPGUNIT/QINCLUDE,TESTCASE` | `using Xunit;` |
| Any exported procedure named `test*` | Any `[Fact]`-attributed method — RPGUnit discovers them by **naming convention**, not attributes |
| `setUp` / `tearDown` | Constructor / `IDisposable.Dispose()` (or `[TestInitialize]`/`[TestCleanup]`) — run before/after *every* test |
| `assert(cond: message)` | `Assert.True(cond, message)` |
| `iEqual(expected: actual)` | `Assert.Equal(expected, actual)` for integers |
| `aEqual(expected: actual)` | `Assert.Equal(expected, actual)` for character/alpha data |
| `RUCALLTST TSTPGM(TODO/TODOTEST)` | `dotnet test` |

```rpgle
DCL-PROC testMarkDoneRecord EXPORT;
  DCL-PI *N END-PI;
  DCL-DS l_Rec LIKEDS(todoRec_t);
  DCL-S  l_Found IND;

  AddTodoRecord(8002: 'Test mark done': %date(*SYS));
  MarkDoneRecord(8002);
  l_Found = GetTodoById(8002: l_Rec);

  assert(l_Found: 'Record 8002 should exist after MarkDoneRecord');
  aEqual('1': l_Rec.tdDone);

  DeleteTodoRecord(8002);
END-PROC;
```

Notice these are **integration tests against the real table**, not tests
against a mock/in-memory store — there's no built-in fake `TODOPF`. The
convention this project uses to stay safe (documented in
[`TODOTEST.RPGLE:11-15`](../QRPGLESRC/TODOTEST.RPGLE)) is reserving specific
ID values (`77`, `9999`, `8001`, `8002`) that won't collide with real
application data, and having every test clean up its own row at the end —
the RPG-world equivalent of seeding and tearing down a test database
transaction, done by hand since there's no `TransactionScope`/`WebApplicationFactory`
to do it for you.

`setUp`/`tearDown` here just call the same `OpenFiles`/`CloseFiles` the real
UI calls ([`TODOTEST.RPGLE:79-95`](../QRPGLESRC/TODOTEST.RPGLE)) — this is
only possible because `TODOBL` is a separate service program with no
dependency on the display file, which is the entire reason for the
`TODOBL`/`TODOMAIN` split (§6).

---

## 10. Data structures ≈ structs/records, `LIKEDS` ≈ using a type by reference

```rpgle
DCL-DS todoRec_t        QUALIFIED TEMPLATE;
  tdId    PACKED(5:0);
  tdDesc  CHAR(50);
  tdDone  CHAR(1);
  tdDue   DATE(*ISO);
END-DS;
```
([`TODOBL.RPGLE:46-51`](../QRPGLESRC/TODOBL.RPGLE), duplicated verbatim in
`TODOMAIN.RPGLE` and `TODOTEST.RPGLE` for the same "no shared header" reason
as the prototypes in §5)

- `DCL-DS ... END-DS` — declares a **data structure**, i.e. a `struct`/`record`.
- `QUALIFIED` — members must be accessed as `l_Rec.tdId`, not bare `tdId` —
  this is the RPG equivalent of *not* having `using static`; without
  `QUALIFIED`, DS members act like flat global variables (again, very
  old-school RPG behavior that `QUALIFIED` opts you out of).
- `TEMPLATE` — this declares a *shape only*, no storage — like a C# `struct`
  type declaration with no instance actually allocated. You then instantiate
  it elsewhere with `LIKEDS`:

```rpgle
DCL-DS l_Rec LIKEDS(todoRec_t);
```

`LIKEDS` is "give me a real, storage-backed data structure shaped exactly
like `todoRec_t`" — like writing `TodoRec l_Rec = new();` against a `record`
type. Passing `LIKEDS(todoRec_t)` as a parameter type
([`TODOBL.RPGLE:92-95`](../QRPGLESRC/TODOBL.RPGLE), `ReadNextTodo`'s
`o_Rec` parameter) is how this codebase returns a "row" from a procedure
without a class/object system — it's an out-parameter struct, filled in by
the callee:

```rpgle
DCL-PROC GetTodoById        EXPORT;
  DCL-PI *N IND;
    i_Id      PACKED(5:0) CONST;
    o_Rec     LIKEDS(todoRec_t);
  END-PI;

  CHAIN i_Id TODOPF TODOR;
  w_Found = NOT %EOF(TODOPF);
  IF w_Found;
    o_Rec.tdId   = TDID;
    o_Rec.tdDesc = TDDESC;
    o_Rec.tdDone = TDDONE;
    o_Rec.tdDue  = TDDUE;
  END-IF;
  RETURN w_Found;
END-PROC;
```

Reads exactly like:

```csharp
public bool TryGetTodoById(int id, out TodoRec rec) { ... }
```

— the boolean return is the "found" signal, and `o_Rec` is filled as a side
effect, mirroring .NET's `TryGetValue` pattern almost exactly (minus `out`
being explicit in the signature — in RPG, parameters passed by reference
without `CONST` are just implicitly mutable/"out" by default).

---

## 11. Naming conventions in this codebase (a legend, not a language rule)

RPG itself doesn't enforce any of this — these are this project's own
conventions, spelled out in
[`AGENTS.md:58`](../AGENTS.md#critical-conventions):

| Prefix | Meaning | .NET-ish parallel |
|---|---|---|
| `w_` | Module-level working storage (e.g. `w_Rrn`, `w_Today`) | A private field on the "program class" |
| `l_` | Local to one procedure (e.g. `l_Rec`, `l_Found`) | A local variable |
| `i_` / `o_` | Input / output parameter (e.g. `i_Id`, `o_Rec`) | `in`/`out` parameter naming hint |
| `DET*` | Fields on the `TODODET` screen (`DETMODE`, `DETID`, `DETDESC`, `DETDUE`) | Bound properties of one view/form |
| `DEL*` | Fields on the `TODODEL` screen | Bound properties of another view |
| `SFL*` | Subfile fields (`SFLOPT`) | Grid row-template bound properties |

Because DDS field names are short and shared across screens by *raw name*
(not namespaced), this prefix convention is doing the job that C#'s class/property
scoping does automatically — it's how you avoid two different screens'
"description" fields colliding, since DDS field names are effectively global
symbols within the display file.

---

## 12. Walking the whole request end-to-end

Put it all together by tracing "user edits a todo," which touches every
concept above:

1. `Main()` calls `LoadSubfile` (§8) then `EXFMT TODOCTL` (§7), which paints
   the list screen and blocks for input.
2. User types `2` in the option column next to a row and presses Enter.
   `SFLOPT` for that row now holds `'2'` in the display file's buffer.
3. `EXFMT` returns. The `READC TODOSFL` loop (§8) finds that one changed row,
   reads `w_Option = SFLOPT` and `w_SelId = TDID` out of the row buffer, sees
   `'2'`, and calls `EditTodo` (§5, a real procedure despite the `ExSr` call
   syntax).
4. `EditTodo` calls `GetTodoById(w_SelId: l_Rec)` — a prototyped call
   (§5/§6) that crosses from the `TODOMAIN` `*PGM` into the `TODOBL`
   `*SRVPGM`, resolved at bind time via `TODOBND` (§6). Inside `TODOBL`,
   `GetTodoById` does a `CHAIN` (§4) on `TODOPF` (§3) and fills the `LIKEDS`
   out-parameter (§10).
5. `EditTodo` copies `l_Rec`'s fields into the `TODODET` screen's bound
   fields (`DETID`, `DETDESC`, `DETDUE`) and calls `EXFMT TODODET` — a
   *different* record format in the same display file (§7), painting a
   completely different screen layout.
6. User edits the description, presses Enter. `ValidateDescription` (another
   `TODOBL` call) checks it's non-blank; if blank, `*IN60` (§7's indicator
   table) is turned on, which makes the DDS-defined error message literal
   visible, and the loop re-displays the same screen (`ITER`).
7. Once valid, `EditTodoRecord(w_SelId: DETDESC: DETDUE)` is called into
   `TODOBL`, which does `CHAIN` + field reassignment + `UPDATE` on `TODOPF`
   (§4/§10).
8. Control returns to `Main`'s outer loop, which calls `LoadSubfile` again —
   clearing and repainting the subfile from scratch with the now-updated data
   (§8) — and shows `TODOCTL` again.

Every one of those eight steps is a named concept from a section above; there
is no "magic" framework layer doing anything implicitly the way EF Core's
change tracking or ASP.NET's model binding would in a comparable C# app —
every read, write, and screen paint is an explicit verb in the source.

---

## 13. Quick-reference glossary

| RPG/IBM i term | One-line meaning | Nearest .NET term |
|---|---|---|
| Library | Container for objects (like a namespace + deployment unit) | Assembly / NuGet package, loosely |
| Source physical file member | A "file" holding source lines, stored in the database | `.cs` file |
| `*PF` (physical file) | An actual on-disk table | SQL table |
| `*LF` (logical file) | A keyed/filtered view over a `*PF` | SQL view / index |
| `*DSPF` (display file) | Defines 5250 terminal screens | `.xaml`/`.razor` view, roughly |
| `*PGM` | A callable, executable program object | `.exe` / entry-point assembly |
| `*SRVPGM` | A bundle of callable procedures, no entry point | `.dll` class library |
| Binding directory | Named list of `*SRVPGM`s to resolve external calls against | NuGet feed / project reference list, loosely |
| `DCL-F` | Declare a file the program will use | `DbSet<T>` / `SqlConnection`, loosely |
| `DCL-PROC` / `DCL-PI` | Define a procedure / its signature | `method` / method signature |
| `DCL-PR ... EXTPROC` | Prototype an external procedure | `extern`/interface declaration |
| `DCL-DS` | Declare a data structure | `struct`/`record` |
| `LIKEDS` | Instantiate/parametrize by an existing DS's shape | Using a type by reference |
| `QUALIFIED` | Require dotted access to DS members | Normal C# member access (default, not opt-in) |
| Indicator (`*INxx`) | A numbered shared boolean flag between DDS and RPG | A bound `bool`/event flag, informally |
| `EXFMT` | Write a screen and block for the user's response | Blocking modal dialog call |
| Subfile | Scrollable multi-row list control | Data grid / repeater |
| `RRN` | Relative record number — a subfile row's address | Grid row index |
| `CHAIN` | Random-access read by key | `Find(id)` |
| `SETLL` | Position a file cursor without reading | Reset a cursor/enumerator |
| `READ` / `READPE` | Sequential read, forward / backward | `MoveNext()` |
| `READC` | Read next subfile row with unread changes | Iterate only "dirty" grid rows |
| `%EOF` | True if the last op found nothing / hit end | `null` check / `false` from `Read()` |
| `WRITE` | Insert a record (or a subfile row) | `INSERT` / add a grid row |
| `UPDATE` | Rewrite the current record buffer to disk | `UPDATE` / `SaveChanges()` |
| `DELETE` | Delete the current/chained record | `DELETE` / `Remove()` |
| RPGUnit | RPG's xUnit-family test framework | xUnit/NUnit |
| CL (Control Language) | IBM i's shell/scripting language, used for `CRT*` compile commands | Shell script / MSBuild target |

---

## 14. Where to go from here

- Read [`AGENTS.md`](../AGENTS.md) again now that the terms make sense — it's
  a dense but accurate summary of this exact project's conventions.
- Read [`docs/DEPLOY.md`](DEPLOY.md) for how this gets onto the pub400.com
  server.
- Read [`docs/todo-rpg-plan.md`](todo-rpg-plan.md) and
  [`docs/rpgunit-testable-plan.md`](rpgunit-testable-plan.md) for the design
  history behind why the code is shaped this way (in particular, why
  `TODOBL`/`TODOMAIN` are split at all).
- The biggest remaining gap between this primer and real fluency is DDS's
  fixed-column syntax (§7) — it's the one language here that free-form RPG's
  friendliness doesn't extend to. Spend time cross-referencing
  `TODODSPPF.DSPF`'s column positions against what actually renders on a
  5250 screen (a terminal emulator like IBM ACS or a `tn5250` client against
  pub400.com will show you) until the column-counting becomes automatic.
