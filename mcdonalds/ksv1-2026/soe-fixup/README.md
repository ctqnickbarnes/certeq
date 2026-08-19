# soe-fixup

Mac/Windows helper for the **cleanup pass** on already-converted VM SOEs (recollect with the
2025 `generatekvs.exe`), plus verify / tidy / log. Driven through a CyberArk PSM RDP session
to the store's RHS02. Everything is derived from the **site number N**: RHS02 = `10.56.N.93`,
VM SOE = `10.56.N.1` (`--ip` once for sites whose third octet isn't the site number).

**Conversions of new stores are not done from here any more** - the SME runs
[`../rhs-vm-config/AUSetup_RHS_SOE_VM_Config_2022.ps1` (v1.03)](../rhs-vm-config/README.md) on RHS02 from the
Provisioning Tool and it does the whole thing in one run.

VMConnect *types* pasted text into the SOE, so the SOE never receives a script by paste:
the RHS02 payload (real clipboard) writes the SOE script into `\\10.56.N.1\c$\Temp\soefix\`
and on the SOE you type one line.

## One-time setup

- `soefix.toml` (next to `soefix.py`) holds the machine-specific paths: `sheet` (the tracking
  workbook), `static_dir` (local folder with `generatekvs.exe` 2025 build +
  `jre-7u1-windows-x64.exe`), `static_unc` (how RHS02 sees that folder through RDP drive
  redirection - check with `Get-ChildItem \\tsclient` inside the session; through PSM it is a
  drive letter like `\\tsclient\Z`) and optionally `results_log`. `~` is expanded. See
  `soefix.example.toml`.
- Mac: `psm` (in `~/.zshrc`) redirects `static_dir` into the session; `soefix` alias -> `soefix.py`.
- Windows: see *Running from Windows* below.

## Cleanup pass (already-converted sites, incl. the 2015-generatekvs backlog)

```
soefix push 25                        # paste on RHS02 (normal PowerShell)
#   drops cleanup.ps1 + go.cmd on the SOE, pushes the 2025 generatekvs.exe (old kept as
#   .2015.bak) and the JRE if missing. Pings the SOE; reaches it by IP, hostname or the
#   SOE Administrator password if your session's creds aren't accepted.
# on the SOE:  Win+R  ->  C:\Temp\soefix\go
#   cleanup.ps1: desktop exe, PLS (click Close program), Java, generatekvs 2025 check +
#   recollect generatekvs.exe /auto <days from the sheet>. No restart.
soefix verify 25                      # paste on RHS02: checks + pulls the summary back
soefix log 25                         # Mac: append it to results.log
soefix tidy 25                        # paste on RHS02: removes C:\Temp\soefix, the summary
                                      # file and the .bak from the SOE
```

`soefix list` shows pending stores and the recollect backlog (Done rows whose *Errors / Checks*
says the recollect wasn't run); those accept `push` without `--force`. Every payload shows the
progress panel (mug) at the bottom of the console; the log scrolls above it.

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
4. Run `soefix.cmd push 25` etc. (put the folder on PATH to drop the
   `.cmd`); it uses `uv run --script soefix.py`. Clipboard is handled by
   pyperclip on both platforms.

## Files

- `soefix.py` - generator / logger (uv script); `soefix.cmd` Windows launcher
- `soefix.example.toml` - config template; copy to `soefix.toml` and edit
- `templates/push.ps1`, `verify.ps1`, `tidy.ps1` - RHS02 payloads (`& { }`, paste); `_connect.ps1`, `_beer.ps1` shared partials
- `templates/cleanup.ps1`, `go.cmd` - written onto the SOE by push
- `tests/` - `uv run pytest` (generator tests, real PowerShell parse check of every baked
  payload and of `../rhs-vm-config/AUSetup_RHS_SOE_VM_Config_2022.ps1` via `pwsh`: `brew install powershell` /
  `winget install Microsoft.PowerShell`)
- `pyproject.toml` / `uv.lock` - dev deps for the tests

Created locally, not part of the repo (git-ignored): `soefix.toml` (your
paths), `results.log` (one summary per store, or wherever `results_log`
points), and the `soefix-logs/` folder inside your `static_dir`.

Templates are ASCII-only, PowerShell 5.1-safe, and the SOE scripts must never
contain a line starting with `'@` (they travel inside a here-string).
