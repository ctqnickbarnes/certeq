"""The standalone RHS02 conversion script (rhs-vm-config/SOE_Convert_2022.ps1): deployed to
every RHS02 and run by the Provisioning Tool - hand-maintained, so these checks guard it."""
import pathlib
import re
import shutil
import subprocess

import pytest

HERE = pathlib.Path(__file__).parents[1]
SCRIPT = HERE.parent / "rhs-vm-config" / "SOE_Convert_2022.ps1"
BEER = HERE / "templates" / "_beer.ps1"
PWSH = shutil.which("pwsh")


def text() -> str:
    return SCRIPT.read_text()


def test_exists_and_ascii():
    assert SCRIPT.exists()
    assert text().isascii()


def test_beer_block_is_verbatim_copy_of_the_template():
    t = text()
    m = re.search(r"# ---- begin: verbatim copy of soe-fixup/templates/_beer.ps1.*?\n(.*?)\n# ---- end: _beer.ps1 ----", t, re.S)
    assert m, "beer block markers missing"
    assert m.group(1) == BEER.read_text().rstrip("\n"), "SOE_Convert_2022.ps1 beer block differs from templates/_beer.ps1 - copy it over"


def test_phase_structure():
    t = text()
    steps = re.findall(r"^Show-Beer '([^']+)'", t, re.M)
    assert steps == ["Preflight", "Restore", "VM + wizard", "Push files", "Driver (manual)", "SOE steps", "Restart + GP", "Tidy + summary"], steps
    assert "Init-Beer 'SOE convert' $beerTotal" in t and "$beerTotal = 8" in t
    # the three human pauses, and only those
    pauses = re.findall(r"^\s*Read-Pause ", t, re.M)
    assert len(pauses) == 4  # screenshot, wizard-timeout fallback, driver, no-transport fallback
    for must in ("Invoke-Command -VMName", "Copy-Item", "-ToSession", "DontShowUI", "Restart-Computer -Force",
                 "DT Ranking Reboot*", "SOE_Reboot_eOPS.exe", "generatekvs.exe.2015.bak", "vmconnect.exe",
                 "NZ-R$($Site.ToString('D4'))", "SOEFIX_ELEVATED", "SOE_Server2022_Restore.exe"):
        assert must in t, must
    # never a recollect on a conversion
    assert "/auto" not in t
    # no PS7-only syntax
    for bad in (" ?? ", " && ", " || "):
        assert bad not in t


@pytest.mark.skipif(PWSH is None, reason="pwsh not installed")
def test_parses_with_powershell():
    path = str(SCRIPT).replace("'", "''")   # the folder name has an apostrophe
    cmd = (f"$e = $null; [void][System.Management.Automation.Language.Parser]::ParseFile('{path}', [ref]$null, [ref]$e); "
           "if ($e) { $e | ForEach-Object { $_.Extent.StartLineNumber.ToString() + ': ' + $_.Message }; exit 1 }")
    r = subprocess.run([PWSH, "-NoProfile", "-NonInteractive", "-Command", cmd], capture_output=True, text=True)
    assert r.returncode == 0, r.stdout + r.stderr
