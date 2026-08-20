# vm-soe-files

The VM SOE package. Lives on every Lab SOE under `C:\Certeq\VM_SOE_Files\`
(manually maintained - being seeded onto the NZ Lab SOEs); script
`7 - GSC02 Build Script v3` pushes it to RHS02 `c$\certeq`, and
`AUSetup_RHS_SOE_VM_Config_2022.ps1` v2.00 places it into the SOE VHDs.

| Item | In git? | Final location on the VM SOE |
|---|---|---|
| `NZ_VM_SOE_Clean_Up.ps1` | yes (this folder) | `C:\Source\Scripts\` |
| `SOE_Reboot_eOPS.exe` | no (binary) | `E:\Ghost Images\Waystation\Tools\` |
| `Maxtel.ps1` | no (Daniel's) | `E:\Ghost Images\Waystation\AppStore\` |
| `Maxtel\` (folder) | no | `E:\Ghost Images\Waystation\AppStore\Maxtel\` |
| `jre-7u1-windows-x64.exe` | no (binary) | `E:\Ghost Images\Waystation\AppStore\PLS\` |
| `generatekvs.exe` (2025) | no (binary) | `C:\Helpdesk\tools\` + spare in `C:\Source\Scripts\` |
| `Printer Drivers\` (optional) | no | `C:\Temp\Printer Drivers\` |

## NZ_VM_SOE_Clean_Up.ps1

Run **on the staged VM SOE** as Administrator, at the runsheet's cleanup junction:

```
powershell -NoProfile -ExecutionPolicy Bypass -File C:\Source\Scripts\NZ_VM_SOE_Clean_Up.ps1
```

In order: Maxtel.ps1 (waited on) -> `SOE_PLS_Install.exe` (the known PLSCleanStart
crash is handled - WER dialog suppressed and restored, Flow 36) -> Java `/s` ->
overwrite `C:\Helpdesk\tools\generatekvs.exe` from the `C:\Source\Scripts` spare and
confirm it is a 2025+ build -> `pnputil /add-driver "C:\Temp\Printer Drivers\*.inf"
/subdirs /install` (skipped when there is no driver folder) -> remove every
`DT Ranking*` shortcut from the store-user (`NZ-R*`) and Public desktops.

Every action logs to `C:\Source\Scripts\NZ_VM_SOE_Clean_Up_<timestamp>.log`.
Exit code 1 (and a FAIL line) if anything failed - review the log and clear the
failures before continuing with the remaining Flow 36 checks.
