"""Checks over the VM SOE script set (Nic Henstridge's Aug-2026 spec):

- rhs-vm-config/AUSetup_RHS_SOE_VM_Config_2022.ps1 v2.00 - builds the SOE VM and
  places the C:\\certeq package into the mounted VHDs before first boot.
- vm-soe-files/NZ_VM_SOE_Clean_Up.ps1 - run manually on the staged SOE; does the
  installs (Maxtel, PLS, Java, generatekvs, printer driver) and desktop cleanup.
- lab-soe-scripts/*.vbs - Lab SOE edits (backup v12 drops the DTR copy; GSC02
  build v3 pushes the VM_SOE_Files package to RHS02 c$\\certeq).

These files deploy to every Lab SOE / RHS02 and are hand-maintained, so the
checks guard encoding (UTF-8 BOM + CRLF for .ps1, ASCII CRLF for .vbs),
PowerShell 5.1 safety, and the structure the runsheet relies on."""
import pathlib
import re
import shutil
import subprocess

import pytest

KVS1 = pathlib.Path(__file__).parents[2]
AUSETUP = KVS1 / "rhs-vm-config" / "AUSetup_RHS_SOE_VM_Config_2022.ps1"
CLEANUP = KVS1 / "vm-soe-files" / "NZ_VM_SOE_Clean_Up.ps1"
BACKUP_VBS = KVS1 / "lab-soe-scripts" / "2 - SOE Provisioning Files Back Up v12.vbs"
BUILD_VBS = KVS1 / "lab-soe-scripts" / "7 - GSC02 Build Script v3.vbs"
PWSH = shutil.which("pwsh")


def ps_text(path: pathlib.Path) -> str:
    return path.read_bytes().decode("utf-8-sig").replace("\r\n", "\n")


def vbs_text(path: pathlib.Path) -> str:
    return path.read_bytes().decode("ascii").replace("\r\n", "\n")


@pytest.mark.parametrize("path", [AUSETUP, CLEANUP], ids=["ausetup", "cleanup"])
def test_ps1_ascii_bom_crlf(path):
    raw = path.read_bytes()
    assert raw.startswith(b"\xef\xbb\xbf") and b"\r\n" in raw and b"\n" not in raw.replace(b"\r\n", b"")
    assert ps_text(path).isascii()


@pytest.mark.parametrize("path", [BACKUP_VBS, BUILD_VBS], ids=["backup", "build"])
def test_vbs_ascii_crlf(path):
    raw = path.read_bytes()
    assert b"\r\n" in raw and b"\n" not in raw.replace(b"\r\n", b"")
    raw.decode("ascii")


@pytest.mark.parametrize("path", [AUSETUP, CLEANUP], ids=["ausetup", "cleanup"])
def test_ps1_is_51_safe(path):
    t = ps_text(path)
    for bad in (" ?? ", " && ", " || ", "?:"):
        assert bad not in t, bad


def test_ausetup_original_vm_creation_is_intact():
    t = ps_text(AUSETUP)
    for must in ("New-VM -Name $VMName -Generation 2 -SwitchName VLAN1",
                 "Set-VMNetworkAdapterVlan -VMName $VMName -Access -VlanId 10",
                 "Wait-VM -Name $VMName -For Heartbeat -Delay 120",
                 "Write-Log 'VM already exists'", "# v1.02 17/12/2024", "# v2.00 20/08/2026",
                 "C:\\Images\\Virtual\\SOE_2022\\SOE.7z"):
        assert must in t, must


def test_ausetup_places_every_destination():
    t = ps_text(AUSETUP)
    # OS disk (VM C:)
    for must in ("$osDrive\\Helpdesk\\tools\\generatekvs.exe",
                 "$osDrive\\Source\\Scripts\\generatekvs.exe",       # spare for the cleanup script
                 "$osDrive\\Source\\Scripts\\NZ_VM_SOE_Clean_Up.ps1",
                 "$osDrive\\Temp\\Printer Drivers"):
        assert must in t, must
    # Data disk (VM E: - Waystation)
    assert '$way = "$dataDrive\\Ghost Images\\Waystation"' in t
    for must in ("$way\\Tools\\SOE_Reboot_eOPS.exe", "$way\\AppStore\\Maxtel.ps1",
                 "$way\\AppStore\\Maxtel", "$way\\AppStore\\PLS\\jre-7u1-windows-x64.exe"):
        assert must in t, must
    # generatekvs goes to Helpdesk first with the source kept, then the spare consumes it
    assert t.index("Helpdesk\\tools\\generatekvs.exe\" -KeepSource") < t.index("$osDrive\\Source\\Scripts\\generatekvs.exe")


def test_ausetup_placement_gates_the_vm_start():
    t = ps_text(AUSETUP)
    fresh = t[t.index("# Extract VHDs"):t.index("'VM already exists'")]
    assert fresh.index("Place-Package") < fresh.index("Start-VM -Name $VMName")
    assert "the VM was NOT started" in t
    # a mounted VHD is always released, even on failure
    assert t.count("Dismount-VHD") >= 3       # two Finally blocks + the no-volume bail-out
    assert t.count("} Finally {") >= 2
    # preflight names each missing item and the script that provides it
    assert "'SOE_Reboot_eOPS.exe', 'jre-7u1-windows-x64.exe', 'Maxtel.ps1', 'Maxtel', 'generatekvs.exe', 'NZ_VM_SOE_Clean_Up.ps1'" in t
    assert "7 - GSC02 Build Script" in t
    # sanity: the OS vhd really is the OS disk
    assert 'Test-Path "$osDrive\\Windows"' in t


def test_ausetup_no_longer_converts_in_run():
    t = ps_text(AUSETUP)
    for gone in ("Show-Beer", "Init-Beer", "Invoke-Command -VMName", "-ToSession", "vmconnect.exe",
                 "SOE_PLS_Install", "/auto", "SOEFIX_ELEVATED", "Read-Pause", "param("):
        assert gone not in t, gone


def test_cleanup_step_order_and_actions():
    t = ps_text(CLEANUP)
    order = ["# --- 1. Maxtel", "# --- 2. PLS", "# --- 3. Java", "# --- 4. generatekvs",
             "# --- 5. Printer driver", "# --- 6. Desktop cleanup", "# --- Summary"]
    positions = [t.index(m) for m in order]
    assert positions == sorted(positions)
    for must in ("E:\\Ghost Images\\Waystation\\AppStore\\Maxtel.ps1",
                 "C:\\Source\\Scripts\\SOE_PLS_Install.exe",
                 "E:\\Ghost Images\\Waystation\\AppStore\\PLS\\jre-7u1-windows-x64.exe",
                 "C:\\Helpdesk\\tools\\generatekvs.exe", "C:\\Source\\Scripts\\generatekvs.exe",
                 "'/add-driver \"{0}\\*.inf\" /subdirs /install'",
                 "DT Ranking*.lnk", "NZ-R*", "C:\\Users\\Public\\Desktop"):
        assert must in t, must
    # Maxtel is waited on; installers are silent; PLSCleanStart crash is handled
    assert "-Wait -PassThru" in t and "'/s'" in t
    assert "DontShowUI" in t and "PLSCleanStart" in t
    # log lands in C:\Source\Scripts with a timestamp, failures return a failed result
    assert "$LogDir        = 'C:\\Source\\Scripts'" in t
    assert "NZ_VM_SOE_Clean_Up_{0}.log" in t
    assert "Exit 1" in t and "$script:Failed" in t
    # 2025-or-later check on what ends up on disk
    assert "-ge 2025" in t
    # never a recollect here
    assert "/auto" not in t.replace("/add-driver", "")


def test_backup_vbs_v12_drops_dtr_and_updates_sizes():
    t = vbs_text(BACKUP_VBS)
    assert "': Version: 12" in t
    assert "Xdrive_dtr.exe" not in t and "Copy DTR file to SOE Desktop" not in t
    assert "RHS02 DTR Files" not in t
    assert '"Expected Size (FC):" & vbTab & vbTab & "~ 5 GB"' in t
    assert '"Expected Size (FC + DT):" & vbTab & "~ 15 GB"' in t
    assert '"> 15.0 GB"' not in t
    assert '"RTP Backup Size:"' in t                    # the measured size stays
    assert 'Provisioning Files Download - v12' in t
    # the FC / DT backup logic is untouched
    for keeps in ("RTPBackup", "selections.exml", "regdata.gz", "product.specification"):
        assert keeps in t, keeps


def test_build_vbs_v3_pushes_the_package():
    t = vbs_text(BUILD_VBS)
    assert "': Version: 3" in t
    # required items are preflighted before anything copies
    for item in ('"SOE_Reboot_eOPS.exe"', '"jre-7u1-windows-x64.exe"', '"Maxtel.ps1"',
                 '"Maxtel"', '"generatekvs.exe"', '"NZ_VM_SOE_Clean_Up.ps1"'):
        assert item in t, item
    assert t.index("VM SOE Package - Preflight") < t.index("AUSetup_GSC.ps1")
    assert "Nothing was copied. Script cancelled." in t
    # destination per spec, Maxtel.ps1 at the root, folder copied whole
    assert 'pkgSource = "C:\\Certeq\\VM_SOE_Files\\"' in t
    assert 'pkgDest = "\\\\" & ipRHS02 & "\\c$\\certeq\\"' in t
    assert "Function CopyFolder" in t and "Sub StopIfFailed" in t
    # every copy is checked; the optional driver folder never blocks
    assert t.count("StopIfFailed ") == 7                # one call per copied item
    assert '"Not found - skipped"' in t
    # the existing AUSetup_GSC replacement still happens
    assert "AUSetup_GSC.ps1" in t and "l:\\Configuration\\Provisioning\\Appstore" in t
    assert "GSC02 Build Script - v3" in t and "GSC02 Build Script - v2" not in t


@pytest.mark.skipif(PWSH is None, reason="pwsh not installed")
@pytest.mark.parametrize("path", [AUSETUP, CLEANUP], ids=["ausetup", "cleanup"])
def test_ps1_parses_with_powershell(path):
    p = str(path).replace("'", "''")   # the folder name may carry an apostrophe
    cmd = (f"$e = $null; [void][System.Management.Automation.Language.Parser]::ParseFile('{p}', [ref]$null, [ref]$e); "
           "if ($e) { $e | ForEach-Object { $_.Extent.StartLineNumber.ToString() + ': ' + $_.Message }; exit 1 }")
    r = subprocess.run([PWSH, "-NoProfile", "-NonInteractive", "-Command", cmd], capture_output=True, text=True)
    assert r.returncode == 0, r.stdout + r.stderr
