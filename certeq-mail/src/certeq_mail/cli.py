"""certeq — KVS1 deployment emails from the terminal.

Mac port of the Outlook VBA suite (KVS1_2026.bas + Certeq_Menu_KVS1 form).
Every command fetches the same Certeq custom report as its VBA counterpart and
opens the email as a draft in Outlook for review — nothing is auto-sent.
"""

import argparse
import sys

from . import api, outlook, templates

COMMANDS = {
    "soe-au": ("SOE VM Recovery email (AU)", 220),
    "soe-nz": ("SOE VM Recovery email (NZ)", 3613),
    "dmaas-au": ("DMaaS / RSM staging email (AU)", 1320),
    "dmaas-nz": ("DMaaS / RSM staging email (NZ)", 3609),
    "maxtel": ("Maxtel VM SOE upgrade checks email (NZ)", 3613),
    "completion": ("KVS1 conversion completion email (NZ)", 3612),
    "issues": ("Completion email with open-issues list (NZ)", 3612),
    "issues-update": ("Issues update email (NZ)", 3612),
    "report": ("Daily KVS1 conversions report (NZ & PI)", 3614),
    "login": ("Log in to the Certeq portal API", None),
}

SOE_FIELDS = ("Store", "Store Name", "IP", "State", "Status")
DMAAS_FIELDS = ("Store", "Store Name", "Owner", "Network_LanAddress", "RHS01 MAC", "RHS02 MAC", "State")
COMPLETION_FIELDS = ("Ref_ID", "Site_ID", "Site_Name", "whatsapp_hypersupport", "support_date", "email_dl", "email_cc")


def build_email(command: str, site_id: str | None) -> tuple:
    report_id = COMMANDS[command][1]

    if command == "report":
        return templates.daily_report(api.rows(api.query(report_id)))

    if not site_id:
        site_id = input("Site ID: ").strip()
    if not site_id:
        raise SystemExit("A Site ID is required.")
    payload = api.query(report_id, Site_ID=site_id)

    match command:
        case "soe-au":
            return templates.soe_recovery(api.first_row(payload, *SOE_FIELDS), "AU")
        case "soe-nz":
            return templates.soe_recovery(api.first_row(payload, *SOE_FIELDS), "NZ")
        case "dmaas-au":
            return templates.dmaas(api.first_row(payload, *DMAAS_FIELDS), "AU")
        case "dmaas-nz":
            return templates.dmaas(api.first_row(payload, *DMAAS_FIELDS), "NZ")
        case "maxtel":
            return templates.maxtel_recovery(api.first_row(payload, *SOE_FIELDS))
        case "completion":
            return templates.kvs1_nz_completion(api.first_row(payload, *COMPLETION_FIELDS))
        case "issues":
            return templates.kvs_nz_completion_issues(api.first_row(payload, *COMPLETION_FIELDS))
        case "issues-update":
            return templates.kvs_nz_completion_issues_update(api.first_row(payload, *COMPLETION_FIELDS))
    raise SystemExit(f"Unknown command: {command}")


def run(command: str, site_id: str | None) -> None:
    if command == "login":
        data = api.login()
        name = data.get("display_name") or "OK"
        print(f"Logged in: {name} (token stored in Keychain)")
        return

    subject, to, cc, html, wants_signature = build_email(command, site_id)
    if wants_signature:
        html += outlook.signature()
    outlook.open_draft(subject, html, to, cc)
    print(f"Draft opened in Outlook: {subject}")


def menu() -> None:
    """Interactive replacement for the Certeq_Menu_KVS1 UserForm."""
    names = list(COMMANDS)
    print("Certeq Console")
    for i, name in enumerate(names, 1):
        print(f"  {i}. {name:14} {COMMANDS[name][0]}")
    choice = input("Choose [1-{}]: ".format(len(names))).strip()
    if not choice.isdigit() or not 1 <= int(choice) <= len(names):
        raise SystemExit("No valid selection.")
    run(names[int(choice) - 1], None)


def main() -> None:
    parser = argparse.ArgumentParser(
        prog="certeq",
        description=__doc__,
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    sub = parser.add_subparsers(dest="command")
    for name, (help_text, _) in COMMANDS.items():
        p = sub.add_parser(name, help=help_text)
        if name not in ("login", "report"):
            p.add_argument("site_id", nargs="?", help="Site ID (prompted if omitted)")

    args = parser.parse_args()
    if not args.command:
        menu()
        return
    try:
        run(args.command, getattr(args, "site_id", None))
    except KeyboardInterrupt:
        sys.exit(130)
