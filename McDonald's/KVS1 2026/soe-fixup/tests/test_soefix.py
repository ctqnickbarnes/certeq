import pathlib
import re
import sys

import pytest

sys.path.insert(0, str(pathlib.Path(__file__).parents[1]))
import soefix  # noqa: E402

INFO = {"site": 27, "name": "Test's Store", "ref": "REF-1", "days": 44, "done": False, "backlog": False}
ROW = {"ref": "R1", "site": 25, "name": "Gisborne", "done": False, "days": 44, "backlog": False}


@pytest.fixture(autouse=True)
def _isolated_sites(tmp_path, monkeypatch):
    """Never let a test touch the real sites.json."""
    monkeypatch.setattr(soefix, "SITES", tmp_path / "sites.json")
    monkeypatch.setattr(soefix, "IP_OVERRIDE", None)


def first_code_line(p: str) -> str:
    return next(l for l in p.splitlines() if l.strip() and not l.startswith("#"))


def read_host_calls(p: str) -> list[str]:
    """Read-Host uses outside the Read-Beer helper (RHS02 pastes must have none)."""
    return [l for l in p.splitlines()
            if "Read-Host" in l and not l.strip().startswith("#") and "$ans = Read-Host $prompt" not in l]


# ---------------------------------------------------------------- core
def test_derive():
    assert soefix.derive(27) == {"site": 27, "ip_rhs": "10.56.27.93", "ip_soe": "10.56.27.1"}


def test_derive_ip_override(monkeypatch, tmp_path):
    monkeypatch.setattr(soefix, "IP_OVERRIDE", "10.56.55.1")
    assert soefix.derive(310) == {"site": 310, "ip_rhs": "10.56.55.93", "ip_soe": "10.56.55.1"}
    monkeypatch.setattr(soefix, "IP_OVERRIDE", None)   # remembered
    assert soefix.derive(310)["ip_soe"] == "10.56.55.1"
    (tmp_path / "sites.json").unlink()
    with pytest.raises(SystemExit):
        soefix.derive(310)
    monkeypatch.setattr(soefix, "IP_OVERRIDE", "10.56.55")
    with pytest.raises(SystemExit):
        soefix.derive(310)


def test_render_substitutes_and_rejects_leftovers(tmp_path, monkeypatch):
    (tmp_path / "t.ps1").write_text("a {{X}} b {{Y}}")
    monkeypatch.setattr(soefix, "TEMPLATES", tmp_path)
    assert soefix.render("t.ps1", X="1", Y="2") == "a 1 b 2"
    with pytest.raises(ValueError):
        soefix.render("t.ps1", X="1")


def test_store_info_falls_back_when_not_in_sheet(monkeypatch):
    monkeypatch.setattr(soefix, "load_stores", lambda: ([], 0))
    assert soefix.store_info(202, None) == {"site": 202, "name": "site 202", "ref": "", "days": None, "done": False, "backlog": False}
    assert soefix.store_info(202, "Greenlane")["name"] == "Greenlane"


def test_store_info_uses_sheet_when_present(monkeypatch):
    row = {"ref": "R1", "site": 25, "name": "Gisborne", "done": True, "days": 44}
    monkeypatch.setattr(soefix, "load_stores", lambda: ([row], 0))
    assert soefix.store_info(25, None) == {"site": 25, "name": "Gisborne", "ref": "R1", "days": 44, "done": True, "backlog": False}
    assert soefix.store_info(25, "Gizzy")["name"] == "Gizzy"


def test_name_is_remembered_per_site(monkeypatch):
    monkeypatch.setattr(soefix, "load_stores", lambda: ([], 0))
    assert soefix.store_info(443, "Ferry Road")["name"] == "Ferry Road"
    assert soefix.store_info(443, None)["name"] == "Ferry Road"
    assert soefix.store_info(444, None)["name"] == "site 444"


def test_sites_json_backcompat(monkeypatch, tmp_path):
    f = tmp_path / "sites.json"
    f.write_text('{"310": "10.56.55.1"}')
    monkeypatch.setattr(soefix, "SITES", f)
    assert soefix.derive(310)["ip_soe"] == "10.56.55.1"
    soefix.remember(310, name="Ti Rakau")
    assert soefix._site_rec(310) == {"ip": "10.56.55.1", "name": "Ti Rakau"}


def test_ps_quote():
    assert soefix.ps_quote("O'Neil") == "O''Neil"


# ---------------------------------------------------------------- SOE script (cleanup)
def test_bake_soe_cleanup():
    s = soefix.bake_soe(INFO)
    assert "{{" not in s and s.isascii()
    assert "/auto $days" in s and "$days     = 44" in s and "Test''s Store" in s
    assert "Restart-Computer" not in s
    assert "SOEFIX_ELEVATED" in s and s.count("-Verb RunAs") == 1
    assert s.index("$env:SOEFIX_ELEVATED -eq '1'") < s.index("-Verb RunAs")
    # beer panel: 5 steps, every pause via Read-Beer
    assert "Init-Beer" in s and s.count("Show-Beer '") == 5 and "Finish-Beer" in s
    calls = [l for l in s.splitlines() if "Read-Host" in l and not l.strip().startswith("#")]
    assert len(calls) == 1 and "$ans = Read-Host $prompt" in calls[0], calls
    soefix.check_embeddable(s)


def test_bake_soe_cleanup_needs_days():
    with pytest.raises(ValueError):
        soefix.bake_soe({**INFO, "days": None})


def test_check_embeddable_rejects_terminator():
    with pytest.raises(ValueError):
        soefix.check_embeddable("ok\n'@\nmore")


def test_templates_are_ascii_and_51_safe():
    for f in sorted(soefix.TEMPLATES.iterdir()):
        text = f.read_text()
        assert text.isascii(), f"{f.name} contains non-ASCII"
        for bad in (" ?? ", " && ", " || ", "param("):
            assert bad not in text, f"{f.name} uses {bad!r}"
        if f.name in ("push.ps1", "verify.ps1", "tidy.ps1", "cleanup.ps1"):
            assert "tsclient\\SOE_Static_Files" not in text, f.name   # only via {{STATIC_UNC}}


# ---------------------------------------------------------------- RHS02 payloads
def test_bake_push_cleanup(monkeypatch):
    monkeypatch.setattr(soefix, "load_stores", lambda: ([ROW], 0))
    p = soefix.bake_push(25, None, False)
    assert "{{" not in p and first_code_line(p) == "& {"
    assert "10.56.25.1" in p and "cleanup.ps1" in p and "$days     = 44" in p and "Gisborne" in p
    assert "$mode     = 'cleanup'" in p and f"$stat     = '{soefix.STATIC_UNC}'" in p
    assert p.count("@'") == 2 and p.count("\n'@") == 2       # two here-strings, cleanly closed
    assert 'File "%~dp0cleanup.ps1"' in p
    assert read_host_calls(p) == []


def test_bake_push_refuses_done_unless_backlog_or_force(monkeypatch):
    done = {**ROW, "done": True}
    monkeypatch.setattr(soefix, "load_stores", lambda: ([done], 0))
    with pytest.raises(SystemExit):
        soefix.bake_push(25, None, False)
    assert "cleanup.ps1" in soefix.bake_push(25, None, True)
    monkeypatch.setattr(soefix, "load_stores", lambda: ([{**done, "backlog": True}], 0))
    assert "$days     = 44" in soefix.bake_push(25, None, False)


def test_bake_verify():
    p = soefix.bake_verify(27, "O'Neil Store")
    assert first_code_line(p) == "& {"
    assert "10.56.27.1" in p and "\\c$" in p and "O''Neil Store" in p
    assert "soefix-logs\\27.txt" in p
    assert "'DT Ranking Reboot*'" in p and "SOE_Reboot_eOPS.exe" in p   # not 'DT Ranking*' (DTBrowser shortcut)
    assert read_host_calls(p) == []


def test_bake_tidy():
    t = soefix.bake_tidy(27, "X")
    assert first_code_line(t) == "& {" and "10.56.27.1" in t
    removed = re.findall(r"Remove-Artefact\s+(\S+)", t)
    assert removed == ['"$c\\Temp\\soefix"', '"$c\\Helpdesk\\soe_fixup_summary.txt"', '"$c\\Helpdesk\\tools\\generatekvs.exe.2015.bak"'], removed
    assert read_host_calls(t) == []


def test_rhs02_payloads_connect_and_beer(monkeypatch):
    monkeypatch.setattr(soefix, "load_stores", lambda: ([ROW], 0))
    for name, p, total in (("push", soefix.bake_push(25, None, False), 6), ("verify", soefix.bake_verify(25, "X"), 3), ("tidy", soefix.bake_tidy(25, "X"), 3)):
        assert "function Connect-Soe" in p and "NZ{0:D5}SOE01" in p and "Get-Credential" in p, name
        assert '$soeHost = Connect-Soe $soeIp $site' in p and '"\\\\$soeHost\\c$"' in p, name
        assert "function Init-Beer" in p and "Finish-Beer" in p and f'" {total}   #' in p, name


def test_static_unc_is_configurable(monkeypatch):
    monkeypatch.setattr(soefix, "STATIC_UNC", r"\\tsclient\C\Users\bob\Certeq\SOE_Static_Files")
    monkeypatch.setattr(soefix, "load_stores", lambda: ([ROW], 0))
    assert r"\\tsclient\C\Users\bob\Certeq\SOE_Static_Files\soefix-logs" in soefix.bake_verify(25, "X")
    assert r"$stat     = '\\tsclient\C\Users\bob\Certeq\SOE_Static_Files'" in soefix.bake_push(25, None, False)


# ---------------------------------------------------------------- config / log
def test_config_loading(tmp_path, monkeypatch):
    cfg = tmp_path / "soefix.toml"
    cfg.write_text('sheet = "~/x.xlsx"\nstatic_dir = "~/s"\nstatic_unc = "\\\\\\\\tsclient\\\\C\\\\s"\n')
    monkeypatch.setattr(soefix, "CONFIG", cfg)
    c = soefix._load_config()
    assert soefix._path(c, "sheet") == pathlib.Path("~/x.xlsx").expanduser()
    assert c["static_unc"] == r"\\tsclient\C\s"
    monkeypatch.setattr(soefix, "CONFIG", tmp_path / "missing.toml")
    assert soefix._load_config() == {}


def test_missing_sheet_config_dies(monkeypatch):
    monkeypatch.setattr(soefix, "SHEET", None)
    with pytest.raises(SystemExit):
        soefix.load_stores()


def test_cmd_log_file_mode(tmp_path, monkeypatch, capsys):
    logs_in = tmp_path / "soefix-logs"
    logs_in.mkdir()
    summary = "==== SOE CONVERT SUMMARY - site 27 X - NZ00027SOE01 - 2026-08-17 ====\n[PASS] Maxtel: ok\n[FAIL] Driver: nope\n"
    (logs_in / "27.txt").write_text(summary)
    monkeypatch.setattr(soefix, "LOGS_IN", logs_in)
    monkeypatch.setattr(soefix, "LOG", tmp_path / "results.log")
    monkeypatch.setattr(soefix, "load_stores", lambda: pytest.fail("file mode must not touch the sheet"))
    soefix.cmd_log(["27"])
    out = capsys.readouterr().out
    assert "[FAIL] Driver: nope" in out and "logged site 27" in out
    assert (tmp_path / "results.log").read_text() == summary.strip() + "\n\n"
    soefix.cmd_log(["27"])
    assert "already in" in capsys.readouterr().out
