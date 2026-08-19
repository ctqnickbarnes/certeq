import pathlib
import sys

import pytest

sys.path.insert(0, str(pathlib.Path(__file__).parent))
from pshelp import needs_pwsh, run_ps  # noqa: E402

pytestmark = needs_pwsh


@pytest.mark.parametrize("host,expected", [
    ("AU00193SOE01", "193"),
    ("au02074soe01", "2074"),
    ("NZ00443RHS02", "443"),
])
def test_store_from_host(host, expected):
    r = run_ps(f"Write-Output (Get-StoreFromHost '{host}')")
    assert r.stdout.strip() == expected


def test_store_from_host_no_digits_is_null():
    r = run_ps("if ($null -eq (Get-StoreFromHost 'SOMETHING')) { 'null' } else { 'notnull' }")
    assert r.stdout.strip() == "null"


@pytest.mark.parametrize("value,expected", [
    ("21:00", "True"),
    ("09:30", "True"),
    ("00:00", "True"),
    ("23:59", "True"),
    ("9pm", "False"),
    ("25:00", "False"),
    ("21:60", "False"),
    ("9:30", "False"),
    ("", "False"),
])
def test_clock_time(value, expected):
    r = run_ps(f"Write-Output (Test-ClockTime '{value}')")
    assert r.stdout.strip() == expected
