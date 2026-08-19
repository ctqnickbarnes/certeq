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
INFO = {"site": 27, "name": "Test's Store", "ref": "REF-1", "days": 44, "done": False, "backlog": False}
ROW = {"ref": "R1", "site": 25, "name": "Gisborne", "done": False, "days": 44, "backlog": False}


@pytest.fixture(autouse=True)
def _isolated_sites(tmp_path, monkeypatch):
    monkeypatch.setattr(soefix, "SITES", tmp_path / "sites.json")
    monkeypatch.setattr(soefix, "IP_OVERRIDE", None)


def parse_errors(path: pathlib.Path) -> str:
    p = str(path).replace("'", "''")
    cmd = (
        "$e = $null; $t = $null; "
        f"[void][System.Management.Automation.Language.Parser]::ParseFile('{p}', [ref]$t, [ref]$e); "
        "if ($e) { $e | ForEach-Object { $_.Extent.StartLineNumber.ToString() + ': ' + $_.Message }; exit 1 }"
    )
    r = subprocess.run([PWSH, "-NoProfile", "-NonInteractive", "-Command", cmd], capture_output=True, text=True)
    return "" if r.returncode == 0 else (r.stdout + r.stderr)


def payloads(monkeypatch):
    monkeypatch.setattr(soefix, "load_stores", lambda: ([ROW], 0))
    return {
        "verify": soefix.bake_verify(27, "Test's Store"),
        "tidy": soefix.bake_tidy(27, "Test's Store"),
        "push-cleanup": soefix.bake_push(25, None, False),
        "soe-cleanup": soefix.bake_soe(INFO),
    }


@pytest.mark.skipif(PWSH is None, reason="pwsh not installed (brew install powershell)")
@pytest.mark.parametrize("name", ["verify", "tidy", "push-cleanup", "soe-cleanup"])
def test_payload_parses(name, tmp_path, monkeypatch):
    f = tmp_path / f"{name}.ps1"
    f.write_text(payloads(monkeypatch)[name])
    errs = parse_errors(f)
    assert errs == "", f"{name}:\n{errs}"


@pytest.mark.skipif(PWSH is None, reason="pwsh not installed")
def test_embedded_soe_script_roundtrips(tmp_path, monkeypatch):
    """The here-string inside push.ps1 must yield cleanup.ps1 byte-for-byte."""
    monkeypatch.setattr(soefix, "load_stores", lambda: ([ROW], 0))
    p = soefix.bake_push(25, None, False)
    expected = soefix.bake_soe(soefix.store_info(25, None))
    f = tmp_path / "push.ps1"
    f.write_text(p)
    cmd = (
        f"$ast = [System.Management.Automation.Language.Parser]::ParseFile('{f}', [ref]$null, [ref]$null); "
        "$hs = $ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.StringConstantExpressionAst] -and $n.StringConstantType -eq 'SingleQuotedHereString' }, $true); "
        "[IO.File]::WriteAllText('" + str(tmp_path / "out.txt") + "', $hs[0].Value)"
    )
    subprocess.run([PWSH, "-NoProfile", "-NonInteractive", "-Command", cmd], check=True)
    assert (tmp_path / "out.txt").read_text() == expected
