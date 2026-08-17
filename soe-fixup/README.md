# soe-fixup

Per-store SOE conversion / cleanup payloads, driven from the Mac through a
CyberArk PSM RDP session. Everything is derived from the **site number N**:
RHS02 = `10.56.N.93` (where the PSM session lands), VM SOE = `10.56.N.1`
(Hyper-V guest on RHS02).

The trick: VMConnect *types* pasted text into the SOE, so the SOE never
receives a script by paste. RHS02 payloads (real clipboard) write the SOE
script into `\\10.56.N.1\c$\Temp\soefix\`, and on the SOE you type one line.

## One-time setup

- `soefix.toml` (next to `soefix.py`) holds the machine-specific paths:
  `sheet` (the tracking workbook), `static_dir` (local folder with
  `generatekvs.exe` 2025 build + `jre-7u1-windows-x64.exe`), `static_unc`
  (how RHS02 sees that folder through RDP drive redirection) and optionally
  `results_log`. `~` is expanded. See `soefix.example.toml`.
- Mac: `psm` (in `~/.zshrc`) redirects `static_dir` into the session as
  `\\tsclient\SOE_Static_Files`; `soefix` alias -> `soefix.py` (uv script).
- Windows: see *Running from Windows* below.

## Conversion flow (new store), e.g. site 202 Greenlane

Mac: `soefix ...` and `psm` (drive redirected by the alias). Windows: `soefix.cmd ...`
and open the PSM `.rdp` in mstsc with *Local Resources > Drives* ticked.

| # | Where | Do | What happens |
|---|---|---|---|
| 1 | Mac / Win | `soefix restore 202` / `soefix.cmd restore 202` | payload on clipboard |
| 2 | RHS02 | connect (`psm` / mstsc), normal PowerShell, paste | `X:\SOE_Backup` -> `C:\SOE_Backup`; runs `SOE_Server2022_Restore.exe` (UAC Yes, ~10 min, don't interrupt); lists `X:\Certeq` driver folders |
| 3 | RHS02 | manual | screenshot the restore result. Hyper-V: start SOE VM > Connect > country, 4-digit ID, `10.56.202.1`, timezone; both restarts (~15 min); sign out store user, log in as **Administrator** |
| 4 | Mac / Win | `soefix push 202 --driver "<folder>" --name Greenlane` (Win: `soefix.cmd push ...`) | payload on clipboard |
| 5 | RHS02 | paste | ping + `c$` / `e$` share checks; writes `convert.ps1` + `go.cmd` to SOE `C:\Temp\soefix`; Maxtel.ps1 + Maxtel\ -> SOE `E:\...\AppStore`; driver folder `X:\Certeq\<folder>` -> SOE `C:\Temp\<folder>` (only with `--driver`); replaces missing/2015 `generatekvs.exe`; JRE installer only if the SOE lacks it |
| 6 | VM SOE | `Win+R` -> `C:\Temp\soefix\go` | Maxtel -> driver: `printui /s /t2` opens and the script **pauses** (with `--driver` the folder is already in `C:\Temp` and the first `.inf` staged; without it, copy it yourself first - see below). Add > x64 > Have Disk > `.inf` > model, driver only, Enter -> `SOE_Reboot_eOPS.exe` into Tools, off desktops -> PLS (click **Close program**) -> Java silent -> generatekvs is 2025 (no recollect) -> summary -> 15 s -> restart |
| 7 | Mac / Win | `soefix verify 202` / `soefix.cmd verify 202` | payload on clipboard |
| 8 | RHS02 | paste, after the reboot | ping; `DT Ranking Reboot` shortcut present, targets `E:\...\Tools\SOE_Reboot_eOPS.exe`, no real exe; copies the SOE summary back to `<static_dir>/soefix-logs/202.txt`. Shortcut missing = GP hasn't run: restart the VM (line printed), verify again |
| 9 | Mac / Win | `soefix log 202` / `soefix.cmd log 202` | summary -> `results.log` |
| 10 | thin client | manual | USB printer, Have Disk from `\\10.56.202.1\c$\Temp\<folder>`, test page; then normal RDP to the SOE: printer shows `(redirected #)`, test page; SME sign-off |

Two pastes to wait on (2, 5), one typed line on the SOE (6); every step prints
`[PASS]/[FAIL]` and never aborts, so read the summary before moving on.

`--driver` takes a folder name under `X:\Certeq` (e.g. `"Printer Drivers\Epson TM-T88V"`),
a path under `X:\`, or a full `X:\...` / UNC path; the SOE gets it as `C:\Temp\<last folder>`.
`soefix restore` prints the folder list two levels deep so you can copy the name.

Driver by hand (step 6 without `--driver`): when the script pauses, browse
`\\10.56.N.93\x$\Certeq` from the SOE and copy the printer's driver folder to
`C:\Temp` (extract if needed); in the printui window it opened: Drivers > Add >
x64 > Have Disk > the `.inf` in `C:\Temp\<folder>` > model; install the driver
only (no printer, no port), confirm it's listed, then press Enter in the script.

## Cleanup (already-converted sites, incl. the 2015-generatekvs backlog)

```
soefix push 25 --cleanup              # paste on RHS02 (SOE reachable at 10.56.25.1)
#   drops cleanup.ps1 (desktop exe, PLS, Java, generatekvs check + recollect
#   generatekvs.exe /auto <days from the sheet>) and pushes the 2025 generatekvs.exe
# on the SOE:  Win+R  ->  C:\Temp\soefix\go        (no restart)
soefix verify 25 ; soefix log 25      # verify's desktop checks may FAIL harmlessly on
                                      # an old-style site; the summary pull is what matters
```

Stores marked **Done** in the sheet are refused (`--force` to override).
`soefix list` shows pending stores with corrected day counts.

## Logging fallbacks

`soefix log N` reads `SOE_Static_Files/soefix-logs/N.txt` if present; otherwise
`soefix log N <note>` records a manual line, and bare `soefix log` reads a
summary from the clipboard. Every SOE script also appends its summary to
`C:\Helpdesk\soe_fixup_summary.txt` on the box and keeps a transcript in
`C:\Temp\soefix\transcript.txt` (verify pulls that back too).

## Day counts

From the *Days Since Completion* column of
`~/Documents/Certeq/KSV1/VM SOE/VM SOE Clean Up.xlsx` (`Site #` is the key,
headers on row 4). It is an XLOOKUP into an external Report workbook, so Excel
only stores the value cached at last save - `soefix` adds the days elapsed
since the file was modified. The sheet is only ever read.

## Running from Windows

Nothing in the payloads cares who drives them; only the generator side differs.

1. Install uv (`winget install astral-sh.uv`), copy this folder somewhere.
2. Copy `soefix.example.toml` to `soefix.toml` and set the paths. In particular
   `static_unc`: `mstsc` redirects whole drives, so if `static_dir` is
   `C:\Users\you\Certeq\SOE_Static_Files` then
   `static_unc = "\\\\tsclient\\C\\Users\\you\\Certeq\\SOE_Static_Files"`.
3. Open the PSM `.rdp` with mstsc: *Show Options > Local Resources > More... >
   Drives* (tick C:), then Connect. That is what `psm` does on the Mac.
4. Run `soefix.cmd restore 202` etc. (put the folder on PATH to drop the
   `.cmd`); it uses `uv run --script soefix.py`. Clipboard is handled by
   pyperclip on both platforms.

## Files

- `soefix.py` - generator / logger (uv script); `soefix.cmd` Windows launcher
- `soefix.example.toml` - config template; copy to `soefix.toml` and edit
- `templates/restore.ps1`, `push.ps1`, `verify.ps1` - RHS02 payloads (`& { }`, paste)
- `templates/convert.ps1`, `cleanup.ps1`, `go.cmd` - written onto the SOE by push
- `tests/` - `uv run pytest` (generator tests + real PowerShell parse check of
  every baked payload via `pwsh`: `brew install powershell` / `winget install Microsoft.PowerShell`)
- `pyproject.toml` / `uv.lock` - dev deps for the tests

Created locally, not part of the repo (git-ignored): `soefix.toml` (your
paths), `results.log` (one summary per store, or wherever `results_log`
points), and the `soefix-logs/` folder inside your `static_dir`.

Templates are ASCII-only, PowerShell 5.1-safe, and the SOE scripts must never
contain a line starting with `'@` (they travel inside a here-string).
