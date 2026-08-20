# lab-soe-scripts

VBScript run by the onsite techs on the Lab SOE (numbered runsheet scripts).
Originals by Daniel Phillips; edits per Nic Henstridge's Aug-2026 spec.
ASCII + CRLF - keep them that way.

| Script | Change |
|---|---|
| `2 - SOE Provisioning Files Back Up v12.vbs` | v12: the DTR copy to RHS02 (`SOE_Reboot_eOPS.exe` -> `x$\SOE_Backup\Desktop`) is removed - the exe now travels in the VM SOE package instead. The confirmation box keeps the measured RTP Backup size and now shows `Expected Size (FC): ~ 5 GB` and `Expected Size (FC + DT): ~ 15 GB`. FC and DT backup logic untouched. |
| `7 - GSC02 Build Script v3.vbs` | v3: still replaces `AUSetup_GSC.ps1` on RHS02; now also pushes the VM SOE package from `C:\Certeq\VM_SOE_Files\` to `\\<rhs02>\c$\certeq`. Preflights every required item first (a missing item is named and nothing copies), stops on the first failed copy, `Maxtel\` copied as a folder with `Maxtel.ps1` beside it at the root. `Printer Drivers\` is optional - copied when present, "Not found - skipped" otherwise. |

The package contents that must live on every Lab SOE under `C:\Certeq\VM_SOE_Files\`
are listed in `../vm-soe-files/README.md`.

`git log` holds the unedited v11 / v2 baselines for diffing.
