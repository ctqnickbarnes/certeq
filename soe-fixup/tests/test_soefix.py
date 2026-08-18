import pathlib
import re
import sys

import pytest

sys.path.insert(0, str(pathlib.Path(__file__).parents[1]))
import soefix  # noqa: E402


@pytest.fixture(autouse=True)
def _isolated_sites(tmp_path, monkeypatch):
    """Never let a test touch the real sites.json."""
    monkeypatch.setattr(soefix, "SITES", tmp_path / "sites.json")
    monkeypatch.setattr(soefix, "IP_OVERRIDE", None)


def test_derive():
    assert soefix.derive(27) == {"site": 27, "ip_rhs": "10.56.27.93", "ip_soe": "10.56.27.1"}


def test_derive_ip_override(monkeypatch, tmp_path):
    monkeypatch.setattr(soefix, "SITES", tmp_path / "sites.json")
    monkeypatch.setattr(soefix, "IP_OVERRIDE", "10.56.55.1")
    assert soefix.derive(310) == {"site": 310, "ip_rhs": "10.56.55.93", "ip_soe": "10.56.55.1"}
    # remembered: later commands without --ip still resolve
    monkeypatch.setattr(soefix, "IP_OVERRIDE", None)
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
    assert soefix.store_info(202, None) == {
        "site": 202, "name": "site 202", "ref": "", "days": None, "done": False, "backlog": False,
    }
    assert soefix.store_info(202, "Greenlane")["name"] == "Greenlane"


def test_store_info_uses_sheet_when_present(monkeypatch):
    row = {"ref": "R1", "site": 25, "name": "Gisborne", "done": True, "days": 44}
    monkeypatch.setattr(soefix, "load_stores", lambda: ([row], 0))
    info = soefix.store_info(25, None)
    assert info == {"site": 25, "name": "Gisborne", "ref": "R1", "days": 44, "done": True, "backlog": False}
    # explicit --name wins over the sheet
    assert soefix.store_info(25, "Gizzy")["name"] == "Gizzy"


def test_name_is_remembered_per_site(monkeypatch):
    monkeypatch.setattr(soefix, "load_stores", lambda: ([], 0))
    assert soefix.store_info(443, "Ferry Road")["name"] == "Ferry Road"
    assert soefix.store_info(443, None)["name"] == "Ferry Road"      # later commands without --name
    assert soefix.store_info(444, None)["name"] == "site 444"


def test_ps_quote():
    assert soefix.ps_quote("O'Neil") == "O''Neil"


# ---------------------------------------------------------------- RHS02 payloads
def first_code_line(p: str) -> str:
    return next(l for l in p.splitlines() if l.strip() and not l.startswith("#"))


def test_bake_restore():
    p = soefix.bake_restore(27)
    assert first_code_line(p) == "& {"
    assert "10.56.27.1" in p and "SOE_Server2022_Restore.exe" in p and "X:\\Certeq" in p
    assert "Read-Host" not in p
    assert "{{" not in p


def test_bake_verify():
    p = soefix.bake_verify(27, "O'Neil Store")
    assert first_code_line(p) == "& {"
    assert "10.56.27.1" in p and "\\c$" in p
    assert "soefix-logs\\27.txt" in p
    assert "'DT Ranking Reboot*'" in p and "SOE_Reboot_eOPS.exe" in p   # not 'DT Ranking*' (DTBrowser shortcut)
    assert "O''Neil Store" in p
    assert "Read-Host" not in p


# ---------------------------------------------------------------- SOE scripts
INFO = {"site": 27, "name": "Test's Store", "ref": "REF-1", "days": 44, "done": False}


def test_bake_soe_convert():
    s = soefix.bake_soe("convert", INFO, "Epson TM", "10.56.27.93")
    assert "{{" not in s
    assert "Read-Host" in s and "Restart-Computer" in s
    assert "Maxtel.ps1" in s and "printui" in s and "pnputil" in s
    assert "'Epson TM'" in s and "Test''s Store" in s
    assert "/auto" not in s  # never recollect on a conversion
    soefix.check_embeddable(s)
    assert "Which to run?" in s   # multiple self-extracting packages -> pick
    # without --driver the step is still there, just manual - same pause
    s2 = soefix.bake_soe("convert", INFO, "", "10.56.27.93")
    assert "done by hand" in s2 and "[SKIP] Driver" not in s2
    # printui + the pause happen unconditionally, after the driver block
    for script in (s, s2):
        assert script.count("Start-Process -FilePath 'printui.exe'") == 1
        assert script.index("printui.exe") < script.index("Press Enter here once the driver is listed") < script.index("# --- 3.")


def test_convert_driver_uses_leaf_name():
    for given in (r"Printer Drivers\Epson TM", r"X:\Certeq\Printer Drivers\Epson TM", "Printer Drivers/Epson TM/", "Epson TM"):
        s = soefix.bake_soe("convert", INFO, given, "10.56.27.93")
        assert "$driver   = 'Epson TM'" in s, given


def test_soe_scripts_cannot_elevation_loop():
    for mode in ("convert", "cleanup"):
        s = soefix.bake_soe(mode, INFO, "X", "10.56.27.93")
        assert "SOEFIX_ELEVATED" in s and s.count("-Verb RunAs") == 1
        assert s.index("$env:SOEFIX_ELEVATED -eq '1'") < s.index("-Verb RunAs")


def test_bake_soe_cleanup():
    s = soefix.bake_soe("cleanup", INFO, "", "10.56.27.93")
    assert "{{" not in s
    assert "/auto $days" in s and "$days     = 44" in s
    assert "Restart-Computer" not in s
    soefix.check_embeddable(s)


def test_bake_soe_cleanup_needs_days():
    with pytest.raises(ValueError):
        soefix.bake_soe("cleanup", {**INFO, "days": None}, "", "10.56.27.93")


def test_check_embeddable_rejects_terminator():
    with pytest.raises(ValueError):
        soefix.check_embeddable("ok\n'@\nmore")


def test_templates_are_ascii_and_51_safe():
    for f in sorted(soefix.TEMPLATES.iterdir()):
        text = f.read_text()
        assert text.isascii(), f"{f.name} contains non-ASCII"
        for bad in (" ?? ", " && ", " || ", "param("):
            assert bad not in text, f"{f.name} uses {bad!r}"


# ---------------------------------------------------------------- push payload
def test_bake_push_convert(monkeypatch):
    monkeypatch.setattr(soefix, "load_stores", lambda: ([], 0))
    p = soefix.bake_push(202, "Epson TM", False, "Greenlane", False)
    assert "{{" not in p
    assert first_code_line(p) == "& {"
    assert "10.56.202.1" in p and "convert.ps1" in p and "Maxtel" in p
    assert "Greenlane" in p and "'Epson TM'" in p
    assert f"$stat     = '{soefix.STATIC_UNC}'" in p   # whatever soefix.toml says
    assert "Read-Host" in p          # inside the embedded SOE script only
    assert p.count("@'") == 2 and p.count("\n'@") == 2   # two here-strings, cleanly closed
    # embedded go.cmd targets the right script
    assert 'File "%~dp0convert.ps1"' in p


def test_bake_push_cleanup_uses_sheet_days(monkeypatch):
    row = {"ref": "R1", "site": 25, "name": "Gisborne", "done": False, "days": 44}
    monkeypatch.setattr(soefix, "load_stores", lambda: ([row], 0))
    p = soefix.bake_push(25, "", True, None, False)
    assert "cleanup.ps1" in p and "$days     = 44" in p and "Gisborne" in p
    assert "$mode     = 'cleanup'" in p


def test_bake_push_refuses_done(monkeypatch):
    row = {"ref": "R1", "site": 25, "name": "Gisborne", "done": True, "days": 44}
    monkeypatch.setattr(soefix, "load_stores", lambda: ([row], 0))
    with pytest.raises(SystemExit):
        soefix.bake_push(25, "", True, None, False)
    assert "cleanup.ps1" in soefix.bake_push(25, "", True, None, True)


# ---------------------------------------------------------------- log ingest
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
    # second ingest warns about the duplicate but still appends
    soefix.cmd_log(["27"])
    assert "already in" in capsys.readouterr().out


def test_backlog_cleanup_allowed_without_force(monkeypatch):
    row = {"ref": "R1", "site": 4, "name": "Backlog", "done": True, "days": 50, "backlog": True}
    monkeypatch.setattr(soefix, "load_stores", lambda: ([row], 0))
    assert "$days     = 50" in soefix.bake_push(4, "", True, None, False)
    with pytest.raises(SystemExit):  # convert on a Done row still needs --force
        soefix.bake_push(4, "X", False, None, False)


# ---------------------------------------------------------------- config / portability
def test_static_unc_is_configurable(monkeypatch):
    monkeypatch.setattr(soefix, "STATIC_UNC", r"\\tsclient\C\Users\bob\Certeq\SOE_Static_Files")
    monkeypatch.setattr(soefix, "load_stores", lambda: ([], 0))
    v = soefix.bake_verify(27, "X")
    p = soefix.bake_push(27, "", False, None, False)
    assert r"\\tsclient\C\Users\bob\Certeq\SOE_Static_Files\soefix-logs" in v
    assert r"$stat     = '\\tsclient\C\Users\bob\Certeq\SOE_Static_Files'" in p


def test_templates_have_no_hardcoded_share():
    for tpl in ("push.ps1", "verify.ps1", "convert.ps1", "cleanup.ps1", "restore.ps1"):
        text = (soefix.TEMPLATES / tpl).read_text()
        assert "tsclient\\SOE_Static_Files" not in text, tpl   # only ever via {{STATIC_UNC}}


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


def test_rhs02_payloads_connect_by_ip_name_or_credentials(monkeypatch):
    monkeypatch.setattr(soefix, "load_stores", lambda: ([], 0))
    monkeypatch.setattr(soefix, "IP_OVERRIDE", "10.56.190.1")
    for p in (soefix.bake_push(443, "", False, None, False), soefix.bake_verify(443, "X"), soefix.bake_tidy(443, "X")):
        assert "function Connect-Soe" in p and "NZ{0:D5}SOE01" in p and "Get-Credential" in p
        assert '$soeHost = Connect-Soe $soeIp $site' in p and '"\\\\$soeHost\\c$"' in p
        assert "{{" not in p


def test_soe_scripts_have_beer_progress():
    for mode, total in (("convert", 7), ("cleanup", 5)):
        s = soefix.bake_soe(mode, INFO, "X", "10.56.27.93")
        assert "function Show-Beer" in s and "function Wait-Beer" in s and "Finish-Beer" in s and "function Write-Mug" in s
        assert f'" {total}   #' in s and "Init-Beer" in s
        # every pause goes through Read-Beer (scroll-region safe); the partial itself holds the only Read-Host
        calls = [l for l in s.splitlines() if "Read-Host" in l and not l.strip().startswith("#")]
        assert len(calls) == 1 and "$ans = Read-Host $prompt" in calls[0], calls
        assert s.count("Show-Beer '") == total, mode
        assert "{{" not in s and s.isascii()          # block chars come from [char] codes


# ---------------------------------------------------------------- tidy
def test_bake_tidy(monkeypatch, tmp_path):
    monkeypatch.setattr(soefix, "SITES", tmp_path / "sites.json")
    monkeypatch.setattr(soefix, "IP_OVERRIDE", None)
    monkeypatch.setattr(soefix, "load_stores", lambda: ([], 0))
    soefix.bake_push(27, r"X:\Certeq\Printer Drivers", False, None, False)   # records driver leaf
    assert soefix._site_rec(27) == {"driver": "Printer Drivers"}
    t = soefix.bake_tidy(27, "X")
    assert first_code_line(t) == "& {"
    assert "10.56.27.1" in t
    for must in ("Temp\\soefix", "soe_fixup_summary.txt", "generatekvs.exe.2015.bak"):
        assert must in t
    # only soefix's own files are ever removed: never the driver folder, Maxtel, JRE or RHS02's backup copy
    removed = re.findall(r"Remove-Artefact\s+(\S+)", t)
    assert removed == ['"$c\\Temp\\soefix"', '"$c\\Helpdesk\\soe_fixup_summary.txt"', '"$c\\Helpdesk\\tools\\generatekvs.exe.2015.bak"'], removed
    assert "Read-Host" not in t


def test_sites_json_backcompat(monkeypatch, tmp_path):
    f = tmp_path / "sites.json"
    f.write_text('{"310": "10.56.55.1"}')          # old format: bare ip
    monkeypatch.setattr(soefix, "SITES", f)
    monkeypatch.setattr(soefix, "IP_OVERRIDE", None)
    assert soefix.derive(310)["ip_soe"] == "10.56.55.1"
    soefix.remember(310, driver="Printer Drivers")
    assert soefix._site_rec(310) == {"ip": "10.56.55.1", "driver": "Printer Drivers"}
