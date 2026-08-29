# Deploy Guide — IBM i RPG Todo Application

## Prerequisites

- A free account on [pub400.com](https://pub400.com) — sign up at the website
- A 5250 terminal emulator — **Mocha TN5250** (browser-based, free) or **ACS (IBM Access Client Solutions)** (Java, free download from IBM)
- Optional but recommended: **VS Code** with the [IBM i extension (Code for IBM i)](https://marketplace.visualstudio.com/items?itemName=HalcyonTechLtd.code-for-ibmi) for uploading source and running commands from your PC

---

## Step 1 — Sign On to pub400.com

Open your 5250 emulator and connect to:

```
Host : pub400.com
Port : 23  (Telnet TN5250)
```

Sign on with your pub400.com username and password.

---

## Step 2 — Create the TODO Library

Run this command once to create the dedicated project library:

```
CRTLIB LIB(TODO) TEXT('RPG Todo Application')
```

---

## Step 3 — Add TODO to Your Library List Permanently

First, add it to your **current session** so you can use it right away:

```
ADDLIBLE LIB(TODO)
```

Then make it **permanent** by adding it to your user profile's initial library list.
Replace `YOURUSERNAME` with your actual pub400.com username:

```
CHGUSRPRF USRPRF(YOURUSERNAME) INLLIBL(QGPL QTEMP TODO)
```

> **Note:** `INLLIBL` sets the full initial library list. The values shown (`QGPL QTEMP TODO`) are the typical defaults — check your current list first with `DSPUSRPRF` before changing it, so you don't accidentally remove a library you need.

---

## Step 4 — Create the Source Physical Files

Run these commands once to create the source file containers inside the TODO library:

```
CRTSRCPF FILE(TODO/QDDSSRC)   RCDLEN(112) TEXT('DDS Source')
CRTSRCPF FILE(TODO/QRPGLESRC) RCDLEN(112) TEXT('RPG Source')
```

> **Note:** `RCDLEN(112)` is the standard for source files. `QDDSSRC` holds DDS members; `QRPGLESRC` holds RPG members.

---

## Step 5 — Upload the Source Members

### Option A — VS Code with Code for IBM i (Recommended)

1. Install the **Code for IBM i** extension in VS Code.
2. Add a connection to `pub400.com` with your credentials.
3. In the **Member Browser**, navigate to `TODO/QDDSSRC`.
4. Upload members (right-click → "Upload member"):
   - `QDDSSRC/TODOPF.PF`       → member `TODOPF`,    type `PF`
   - `QDDSSRC/TODOLF.LF`       → member `TODOLF`,    type `LF`
   - `QDDSSRC/TODODSPPF.DSPF`  → member `TODODSPPF`, type `DSPF`
5. Navigate to `TODO/QRPGLESRC` and upload:
   - `QRPGLESRC/TODOMAIN.RPGLE` → member `TODOMAIN`,  type `RPGLE`

### Option B — SEU (System Editor, green-screen only)

```
STRSEU SRCFILE(TODO/QDDSSRC) SRCMBR(TODOPF) TYPE(PF) OPTION(2)
```

Type or paste the DDS source, then press F3 to save. Repeat for each member.

### Option C — Copy from IFS stream file

If you upload the raw `.dds` / `.rpgle` files to the IFS (e.g. via FTP or VS Code), copy them into source members:

```
CPYFRMSTMF FROMSTMF('/home/YOURUSERNAME/QDDSSRC/TODOPF.PF') +
           TOMBR('/QSYS.LIB/TODO.LIB/QDDSSRC.FILE/TODOPF.MBR') +
           MBROPT(*REPLACE) STMFCCSID(437) DBFCCSID(*FILE)
```

Repeat for each file, adjusting `FROMSTMF` and `TOMBR` paths accordingly:
- `QDDSSRC/TODOLF.LF`      → `TODOLF.MBR`
- `QDDSSRC/TODODSPPF.DSPF` → `TODODSPPF.MBR`
- `QRPGLESRC/TODOMAIN.RPGLE` → `QRPGLESRC.FILE/TODOMAIN.MBR`

---

## Step 6 — Compile in Dependency Order

Run the following commands **in order**. Each command must succeed before running the next.

### 1. Physical File
```
CRTPF FILE(TODO/TODOPF) SRCFILE(TODO/QDDSSRC) SRCMBR(TODOPF)
```

### 2. Logical File
```
CRTLF FILE(TODO/TODOLF) SRCFILE(TODO/QDDSSRC) SRCMBR(TODOLF)
```

### 3. Display File
```
CRTDSPF FILE(TODO/TODODSPPF) SRCFILE(TODO/QDDSSRC) SRCMBR(TODODSPPF)
```

### 4. RPG Program
```
CRTBNDRPG PGM(TODO/TODOMAIN) SRCFILE(TODO/QRPGLESRC) SRCMBR(TODOMAIN)
```

> If a compile fails, check the **spooled job log**:
> ```
> DSPJOBLOG
> ```
> Look for `CPF` or `RNF` message IDs — they describe the exact error and line number.

---

## Step 7 — Run the Program

```
CALL TODO/TODOMAIN
```

You should see the Todo List screen. Use:

| Key / Option | Action |
|---|---|
| **F6** | Add a new todo |
| **2** + Enter | Edit the selected todo |
| **4** + Enter | Delete the selected todo (with confirmation) |
| **5** + Enter | Mark the selected todo as Done (removes from list) |
| **F3** | Exit the application |

---

## Useful Commands for Development

| Purpose | Command |
|---|---|
| List objects in the TODO library | `DSPLIB LIB(TODO)` |
| View physical file contents | `DSPPFM FILE(TODO/TODOPF)` |
| Clear all records from PF | `CLRPFM FILE(TODO/TODOPF)` |
| Delete the RPG program | `DLTPGM PGM(TODO/TODOMAIN)` |
| Delete a database file | `DLTF FILE(TODO/TODOPF)` |
| Check your library list | `DSPLIBL` |
| View compile listing | `DSPJOBLOG` then look for RPGLE spool file |

---

## Tips for pub400.com

- **Session timeout:** pub400.com sessions time out after ~15 minutes of inactivity. Press any key to prevent it.
- **Case sensitivity:** IBM i object and member names are **upper-case** internally. Commands are case-insensitive at the prompt but object names are stored in upper-case.
- **CCSID:** pub400.com uses CCSID 37 (EBCDIC). The `CPYFRMSTMF` command handles conversion automatically if you specify `STMFCCSID(437)` (ASCII) when copying from an IFS stream file.
- **Free disk quota:** pub400.com has a per-user disk quota. Compiled objects are larger than source — be aware if you recompile many times.
