import pathlib
import sys

import pytest

sys.path.insert(0, str(pathlib.Path(__file__).parent))
from pshelp import ROOT, needs_pwsh, ps_str, run_ps  # noqa: E402

pytestmark = needs_pwsh

FIX_XML = ROOT / "original" / "calendar_20260819133759.xml"
FIX_DONE = ROOT / "original" / "calendar_20260819133759.done"
STAMP = "Get-Date -Year 2026 -Month 8 -Day 19 -Hour 13 -Minute 37 -Second 59 -Millisecond 0"


def test_fixtures_present():
    assert FIX_XML.exists() and FIX_DONE.exists()
    assert FIX_DONE.read_bytes() == b"2026_08_19_13_37_59"
    assert b"\r\n" in FIX_XML.read_bytes() and not FIX_XML.read_bytes().endswith(b"\n")


def test_calendar_stamp_and_done():
    r = run_ps(f"$s = {STAMP}; Write-Output (Get-CalendarStamp $s); Write-Output (New-CalendarDone $s)")
    assert r.stdout.split() == ["20260819133759", "2026_08_19_13_37_59"]


def test_new_calendar_xml_matches_fixture(tmp_path):
    out = tmp_path / "x.xml"
    run_ps(f"Write-Utf8NoBom '{out}' (New-CalendarXml 2074 '20260819' '00:00' '21:00')")
    assert out.read_bytes() == FIX_XML.read_bytes()


def test_write_calendar_pair_matches_fixtures(tmp_path):
    r = run_ps(f"Write-Output (Write-CalendarPair '{tmp_path}' 2074 '20260819' '00:00' '21:00' ({STAMP}))")
    assert r.stdout.strip() == str(tmp_path / "calendar_20260819133759.xml")
    assert (tmp_path / "calendar_20260819133759.xml").read_bytes() == FIX_XML.read_bytes()
    assert (tmp_path / "calendar_20260819133759.done").read_bytes() == FIX_DONE.read_bytes()


def test_write_calendar_pair_refuses_existing(tmp_path):
    (tmp_path / "calendar_20260819133759.done").write_bytes(b"x")
    r = run_ps(
        f"try {{ Write-CalendarPair '{tmp_path}' 2074 '20260819' '00:00' '21:00' ({STAMP}); 'wrote' }} "
        "catch { 'threw: ' + $_.Exception.Message }"
    )
    assert r.stdout.strip().startswith("threw: already exists")
    assert not (tmp_path / "calendar_20260819133759.xml").exists()


def test_three_digit_store_is_zero_padded():
    r = run_ps("Write-Output (New-CalendarXml 193 '20260819' '00:00' '21:00')")
    assert 'STORENUMBER="00193"' in r.stdout


TWO_DAY_XML = """<?xml version="1.0" encoding="utf-8"?>
<EBOSDATA xmlns:xsd="http://www.w3.org/2001/XMLSchema" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" TYPE="MYREST" DATE_FORMAT="YYYYMMDD">
  <HEADER COUNTRY="AU" STORENUMBER="01890" />
  <CalendarChange date="20260818">
    <weather />
    <tradinghours StoreOpen="true" is24hours="true" OpenTime="00:00" CloseTime="00:00" />
    <comments />
  </CalendarChange>
  <CalendarChange date="20260819">
    <weather />
    <tradinghours StoreOpen="true" is24hours="false" OpenTime="00:00" CloseTime="21:00" />
    <comments />
  </CalendarChange>
</EBOSDATA>"""


def test_read_calendar_changes_fixture():
    r = run_ps(f"(Read-CalendarChanges {ps_str(FIX_XML)}) | ForEach-Object {{ '{{0}}|{{1}}|{{2}}|{{3}}' -f $_.Date, $_.Is24Hours, $_.OpenTime, $_.CloseTime }}")
    assert r.stdout.strip().splitlines() == ["20260819|false|00:00|21:00"]


def test_read_calendar_changes_two_days(tmp_path):
    p = tmp_path / "calendar_x.xml"
    p.write_text(TWO_DAY_XML)
    r = run_ps(f"(Read-CalendarChanges '{p}') | ForEach-Object {{ '{{0}}|{{1}}|{{3}}' -f $_.Date, $_.Is24Hours, $_.OpenTime, $_.CloseTime }}")
    assert r.stdout.strip().splitlines() == ["20260818|true|00:00", "20260819|false|21:00"]


@pytest.mark.parametrize("date,close,expected", [
    ("20260819", "21:00", "True"),
    ("20260819", "22:00", "False"),   # wrong close time
    ("20260818", "00:00", "False"),   # that day is 24h
    ("20260820", "21:00", "False"),   # not in file
])
def test_calendar_matches(tmp_path, date, close, expected):
    p = tmp_path / "calendar_x.xml"
    p.write_text(TWO_DAY_XML)
    r = run_ps(f"Write-Output (Test-CalendarMatches (Read-CalendarChanges '{p}') '{date}' '{close}')")
    assert r.stdout.strip() == expected


def test_calendar_matches_empty_is_false():
    r = run_ps("Write-Output (Test-CalendarMatches @() '20260819' '21:00')")
    assert r.stdout.strip() == "False"
