# rhs-vm-config

PowerShell run on the store's RHS02 (Hyper-V host) by the McDonald's Provisioning Tool.

| Script | Who runs it | What it does |
|---|---|---|
| `AUSetup_RHS_VM_Config_2022.ps1` | SME (Provisioning Tool) | Creates the "Server 2022 GSC" VM from the image (store controller). Untouched reference - its mount-the-VHDX-and-copy approach is what v2.00 below follows. |
| `AUSetup_RHS_SOE_VM_Config_2022.ps1` | SME (Provisioning Tool) | v2.00: creates the "Server 2022 SOE" VM from the image, **places the VM SOE package into the VHDs before first boot**, then starts it. |

## AUSetup_RHS_SOE_VM_Config_2022.ps1 v2.00

Per Nic Henstridge's Aug-2026 spec (Flow 36 for file locations). The v1.02 VM-creation
code is unchanged. Before `Start-VM`, the script:

1. **Preflight** - checks every package item is in `C:\certeq` (pushed there by Lab SOE
   script `7 - GSC02 Build Script v3`). Any missing item is named in the log and nothing
   is touched.
2. **OS disk** (`SOEOS.vhdx`, the VM's C:) - mounts it, sanity-checks `\Windows` is there,
   then places `Helpdesk\tools\generatekvs.exe`, a spare `Source\Scripts\generatekvs.exe`
   (staging can revert the Helpdesk copy - the cleanup script restores from the spare),
   `Source\Scripts\NZ_VM_SOE_Clean_Up.ps1`, and `Temp\Printer Drivers\` when the package
   carries it.
3. **Data disk** (`SOEData.vhdx`, the VM's E:) - places `Ghost Images\Waystation\Tools\SOE_Reboot_eOPS.exe`,
   `...\AppStore\Maxtel.ps1`, `...\AppStore\Maxtel\`, `...\AppStore\PLS\jre-7u1-windows-x64.exe`.

Destination folders are created as needed, every item is confirmed at its destination
(a move - sources are consumed), and the VHDs are always dismounted. Any failure names
the source and intended destination and **stops the script before the VM ever boots**;
fix and re-run (a re-run with the VM off places the package and then starts the VM).
No installers run here - that is `NZ_VM_SOE_Clean_Up.ps1` on the staged SOE
(see `../vm-soe-files/`).

Logs to the Provisioning Tool `Logs\SOE_VM_Config.log` as before.

Deploy: replaces the v1.02 file in `C:\Configuration\Provisioning\Appstore` on each RHS02.
Test on one store first. File stays UTF-8 BOM + CRLF like the other AUSetup scripts;
`soe-fixup`'s tests (`test_vm_soe_scripts.py`) guard the structure.
