# rhs-vm-config

PowerShell run on the store's RHS02 (Hyper-V host) by the McDonald's Provisioning Tool.

| Script | Who runs it | What it does |
|---|---|---|
| `AUSetup_RHS_VM_Config_2022.ps1` | SME (Provisioning Tool) | Creates the "Server 2022 GSC" VM from the image (store controller). |
| `AUSetup_RHS_SOE_VM_Config_2022.ps1` | SME (Provisioning Tool) | Creates the "Server 2022 SOE" VM from the image and starts it. **Step 0 of a conversion.** |
| `SOE_Convert_2022.ps1` | SME clicks Run, tech at RHS02 | The rest of the conversion in one run (below). |

## SOE_Convert_2022.ps1

Derives everything from the RHS02 itself - site from the hostname (`NZ00443RHS02` -> 443),
SOE IP from this box's `10.56.x.93` -> `10.56.x.1`, driver folder `X:\Certeq\Printer Drivers`,
static files from `C:\Configuration\Provisioning\Appstore\SOE_Static_Files` (or
`X:\Certeq\SOE_Static_Files`, or a tech's `\\tsclient` drive). Prompts once for the VM SOE
local Administrator password. Talks to the VM over **PowerShell Direct** (Hyper-V VMBus,
no network/WinRM/c$ needed); network remoting is the fallback.

Phases (a `[PASS]/[FAIL]` line each, mug progress panel, log in the Provisioning Tool `Logs\`):

1. Preflight - elevate, derive, X:, static files, VM exists, credential
2. Restore - `X:\SOE_Backup` -> `C:\SOE_Backup`, `SOE_Server2022_Restore.exe` → **pause: screenshot**
3. VM + wizard - starts the VM, opens VMConnect, prints the wizard values; **you do the wizard**;
   it waits (up to 40 min) until the store user has auto-logged in and the guest has been up 2 min
4. Push - Maxtel.ps1 + Maxtel\, driver folder, 2025 `generatekvs.exe` (old kept as .2015.bak), JRE if missing
5. **Pause: driver** - sign out the store user, log in as Administrator, run the package in
   `C:\Temp\Printer Drivers`, `printui /s /t2` > Drivers > Add > x64 > Have Disk > .inf > model
6. SOE steps, unattended - Maxtel, `SOE_Reboot_eOPS.exe` into Tools / off desktops, PLS install
   (crash dialog suppressed), Java 7u1, generatekvs 2025 check (no recollect)
7. Restart + wait - reboots the VM, waits for it and for the `DT Ranking Reboot` GP shortcut
   (one automatic extra restart if it doesn't appear), checks no real exe on desktops, ping
8. Tidy + summary - removes its own files from the SOE, prints the summary, saves it to
   `X:\Certeq\soefix-logs\<site>.txt` (and the tech's `\\tsclient\...\soefix-logs` if present)

Then by hand: thin-client USB printer (driver from `\\10.56.x.1\c$\Temp\Printer Drivers`), test
pages, SME sign-off. Options: `-Site`, `-SoeIp`, `-VMName`, `-DriverDir`, `-SkipRestore`, `-NoBeer`.

Deploy: this file + `SOE_Static_Files\` (generatekvs.exe 2025, jre-7u1-windows-x64.exe) into
`C:\Configuration\Provisioning\Appstore` on each RHS02. Test on one store first.

The progress-panel block inside the script is a verbatim copy of
`../soe-fixup/templates/_beer.ps1`; `soe-fixup`'s tests fail if the two drift.
