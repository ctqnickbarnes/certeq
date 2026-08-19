"""Run snippets against KVS1_Calendar_Fix.ps1 under pwsh with the phase flow disabled."""
import pathlib
import shutil
import subprocess

import pytest

ROOT = pathlib.Path(__file__).parents[1]
SCRIPT = ROOT / "KVS1_Calendar_Fix.ps1"
PWSH = shutil.which("pwsh")
needs_pwsh = pytest.mark.skipif(PWSH is None, reason="pwsh not installed (brew install powershell)")


def ps_str(value) -> str:
    """Quote a value as a single-quoted PowerShell string literal (paths with ' in them!)."""
    return "'" + str(value).replace("'", "''") + "'"


def run_ps(snippet: str, check: bool = True) -> subprocess.CompletedProcess:
    """Dot-source the script (CALFIX_NO_RUN=1 so only functions load), then run snippet."""
    cmd = f"$ErrorActionPreference = 'Stop'; $env:CALFIX_NO_RUN = '1'; . {ps_str(SCRIPT)}; {snippet}"
    r = subprocess.run(
        [PWSH, "-NoProfile", "-NonInteractive", "-Command", cmd],
        capture_output=True, text=True,
    )
    if check:
        assert r.returncode == 0, f"pwsh failed ({r.returncode}):\n{r.stdout}\n{r.stderr}"
    return r
