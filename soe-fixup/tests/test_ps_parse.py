"""Parse every baked payload with the real PowerShell parser (pwsh on the Mac).
Catches quoting/brace/here-string mistakes; behaviour is only proven on Windows."""
import pathlib
import shutil
import subprocess
import sys

import pytest

sys.path.insert(0, str(pathlib.Path(__file__).parents[1]))
import soefix  # noqa: E402

PWSH = shutil.which("pwsh")


@pytest.fixture(autouse=True)
def _isolated_sites(tmp_path, monkeypatch):
    monkeypatch.setattr(soefix, "SITES", tmp_path / "sites.json")
    monkeypatch.setattr(soefix, "IP_OVERRIDE", None)
INFO = {"site": 27, "name": "Test's Store", "ref": "REF-1", "days": 44, "done": False}


def parse_errors(path: pathlib.Path) -> str:
    cmd = (
        "$e = $null; $t = $null; "
        f"[void][System.Management.Automation.Language.Parser]::ParseFile('{path}', [ref]$t, [ref]$e); "
        "if ($e) { $e | ForEach-Object { $_.Extent.StartLineNumber.ToString() + ': ' + $_.Message }; exit 1 }"
    )
    r = subprocess.run([PWSH, "-NoProfile", "-NonInteractive", "-Command", cmd], capture_output=True, text=True)
    return "" if r.returncode == 0 else (r.stdout + r.stderr)


def payloads(monkeypatch):
    monkeypatch.setattr(soefix, "load_stores", lambda: ([{"ref": "R1", "site": 25, "name": "Gisborne", "done": False, "days": 44}], 0))
    return {
        "restore": soefix.bake_restore(27),
        "verify": soefix.bake_verify(27, "Test's Store"),
        "tidy": soefix.bake_tidy(27, "Test's Store"),
        "push-convert": soefix.bake_push(202, "Epson TM-T88", False, "Greenlane", False),
        "push-cleanup": soefix.bake_push(25, "", True, None, False),
        "soe-convert": soefix.bake_soe("convert", INFO, "Epson TM-T88", "10.56.27.93"),
        "soe-cleanup": soefix.bake_soe("cleanup", INFO, "", "10.56.27.93"),
    }


@pytest.mark.skipif(PWSH is None, reason="pwsh not installed (brew install --cask powershell)")
@pytest.mark.parametrize("name", ["restore", "verify", "tidy", "push-convert", "push-cleanup", "soe-convert", "soe-cleanup"])
def test_payload_parses(name, tmp_path, monkeypatch):
    text = payloads(monkeypatch)[name]
    f = tmp_path / f"{name}.ps1"
    f.write_text(text)
    errs = parse_errors(f)
    assert errs == "", f"{name}:\n{errs}"


@pytest.mark.skipif(PWSH is None, reason="pwsh not installed")
def test_embedded_soe_script_roundtrips(tmp_path, monkeypatch):
    """The here-string inside push.ps1 must yield the SOE script byte-for-byte."""
    monkeypatch.setattr(soefix, "load_stores", lambda: ([], 0))
    p = soefix.bake_push(202, "Epson TM-T88", False, "Greenlane", False)
    expected = soefix.bake_soe("convert", soefix.store_info(202, "Greenlane"), "Epson TM-T88", "10.56.202.93")
    f = tmp_path / "push.ps1"
    f.write_text(p)
    # extract $soeScript by evaluating just the here-string assignment
    cmd = (
        f"$ast = [System.Management.Automation.Language.Parser]::ParseFile('{f}', [ref]$null, [ref]$null); "
        "$hs = $ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.StringConstantExpressionAst] -and $n.StringConstantType -eq 'SingleQuotedHereString' }, $true); "
        "[IO.File]::WriteAllText('" + str(tmp_path / "out.txt") + "', $hs[0].Value)"
    )
    subprocess.run([PWSH, "-NoProfile", "-NonInteractive", "-Command", cmd], check=True)
    assert (tmp_path / "out.txt").read_text() == expected
