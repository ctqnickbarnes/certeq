"""Parse the script with the real PowerShell parser and check dot-sourcing is side-effect free."""
import pathlib
import subprocess
import sys

sys.path.insert(0, str(pathlib.Path(__file__).parent))
from pshelp import PWSH, SCRIPT, needs_pwsh, run_ps  # noqa: E402


def parse_errors(path: pathlib.Path) -> str:
    p = str(path).replace("'", "''")
    cmd = (
        "$e = $null; $t = $null; "
        f"[void][System.Management.Automation.Language.Parser]::ParseFile('{p}', [ref]$t, [ref]$e); "
        "if ($e) { $e | ForEach-Object { $_.Extent.StartLineNumber.ToString() + ': ' + $_.Message }; exit 1 }"
    )
    r = subprocess.run([PWSH, "-NoProfile", "-NonInteractive", "-Command", cmd], capture_output=True, text=True)
    return "" if r.returncode == 0 else (r.stdout + r.stderr)


@needs_pwsh
def test_script_parses():
    assert SCRIPT.exists(), SCRIPT
    errs = parse_errors(SCRIPT)
    assert errs == "", errs


@needs_pwsh
def test_script_is_ascii():
    data = SCRIPT.read_bytes()
    bad = [i for i, b in enumerate(data) if b > 0x7F]
    assert not bad, f"non-ASCII byte at offset {bad[0]}"


@needs_pwsh
def test_dot_source_is_quiet():
    """With CALFIX_NO_RUN=1 the script defines functions and returns - no prompts, no output."""
    r = run_ps("Write-Output 'loaded'")
    assert r.stdout.strip() == "loaded", r.stdout
