# ksv1-calendar-fix

On a KVS1 conversion night the store must close early in eBOS (e.g. 21:00, not 24 h) so the
day-close can run before the conversion. The manager sets it in MyRestaurant, but since
17 Aug 2026 the change has been taking ~2 h to reach the SOE (MCD: the cloud triggers run
on a daily schedule, not on save). `KVS1_Calendar_Fix.ps1` forces it through on the **live
SOE** (the store's current eBOS server - not the new VM):

- **wake** (default, MCD's recommended method - Kyle Barton, 19 Aug 2026): restart the
  `myRestaurant Client` service, create `C:\myRestaurantClientService\data\wakemeup.txt`
  (skips the up-to-5-min startup delay), wait for `calendar_*.xml` + `.done` to land in
  `C:\myRt\From`, run `C:\IM_Bin\APP_SA_AS400.exe`.
- **inject** (`-Inject`, or offered when wake times out - Certeq's method, trialled at
  2074 Spearwood II 19 Aug 2026): write the `calendar_*.xml` + `.done` pair ourselves,
  then run the importer.

Either way the script finishes by telling you to do **eBOS > Help Desk Utilities > AS400
Import** and check System Calendar shows `00:00 - HH:MM` for today. Design:
`docs/2026-08-19-calendar-fix-design.md`.

## Run it (on the SOE)

1. Copy `KVS1_Calendar_Fix.ps1` to `C:\Temp\calfix\` on the SOE (it ships in `SOE_Static_Files`).
2. **Right-click it > Run with PowerShell**, accept the UAC prompt. It prompts for the close
   time; the store number comes from the hostname. The window stays open until you press
   Enter at the end.

With switches, from any PowerShell or cmd prompt:

```
powershell -ExecutionPolicy Bypass -File C:\Temp\calfix\KVS1_Calendar_Fix.ps1 -CloseTime 21:00            # no prompts
powershell -ExecutionPolicy Bypass -File C:\Temp\calfix\KVS1_Calendar_Fix.ps1 -CloseTime 21:00 -Inject    # straight to the Certeq method
powershell -ExecutionPolicy Bypass -File C:\Temp\calfix\KVS1_Calendar_Fix.ps1 -Store 2074 -Date 20260819 -CloseTime 21:00 -TimeoutMin 15
powershell -ExecutionPolicy Bypass -File C:\Temp\calfix\KVS1_Calendar_Fix.ps1 -CloseTime 21:00 -NoImport  # stop once the file is in C:\myRt\From
```

(Double-clicking a `.ps1` opens Notepad - use right-click > Run with PowerShell, or the
command line above.)

Every phase prints `[PASS]`/`[WARN]`/`[FAIL]`; a FAIL stops and says why. Transcript:
`C:\Temp\calfix\transcript.txt`. Summary: `C:\Temp\calfix\summary.txt` and appended to
`C:\Helpdesk\calendar_fix_summary.txt`.

## Conversion-night checklist (first few sites - we are proving both paths)

1. Manager has saved the close time in MyRestaurant (still required - wake only pulls
   what is pending in the cloud).
2. Run the script (right-click > Run with PowerShell, or `-CloseTime HH:MM`). Note how long **Wait** takes (`wait=NNs` in the one-line
   summary) and whether the file that arrived contained today's date + close time.
3. If it times out (10 min) answer `Y` to inject, or `N` and hand to L2 (VISDATA).
4. Do the eBOS AS400 Import, check System Calendar, retry the eBOS close.
5. Send SME the one-line summary (`... method=wake wait=42s import=0 result=PASS`). If
   something looks wrong, attach `C:\Temp\calfix\transcript.txt`.

## Tests (Mac)

`uv run pytest` - parses the script with the real PowerShell parser (`brew install
powershell`), and dot-sources it with `CALFIX_NO_RUN=1` to unit-test the helpers: the
XML/`.done` generator is compared byte-for-byte with `original/calendar_20260819133759.xml`/`.done`
(the pair used at 2074). Wake/Wait/Import only run on Windows - the checklist above is
their test.

## Files

- `KVS1_Calendar_Fix.ps1` - the script (ASCII, PowerShell 5.1-safe, self-elevating)
- `original/` - the source material as received: the email thread (`.eml`, git-ignored) and the
  `calendar_20260819133759.xml` / `.done` pair used at 2074 (test fixtures)
- `tests/` - pytest (`pshelp.py` runs snippets under pwsh)
- `docs/` - design + plan (local only, git-ignored like soe-fixup)
