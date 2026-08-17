"""Open a draft email in Outlook for Mac (equivalent of VBA OutMail.Display).

Works with both New and legacy Outlook via AppleScript. The draft opens for
review — nothing is sent automatically, same as the original macros.
"""

import subprocess
from pathlib import Path

CONFIG_DIR = Path.home() / ".config" / "certeq-mail"
SIGNATURE_FILE = CONFIG_DIR / "signature.html"

_SCRIPT = """
on run argv
    set theSubject to item 1 of argv
    set theBody to item 2 of argv
    set toAddrs to my splitAddrs(item 3 of argv)
    set ccAddrs to my splitAddrs(item 4 of argv)
    tell application "Microsoft Outlook"
        set newMsg to make new outgoing message with properties {subject:theSubject, content:theBody}
        repeat with addr in toAddrs
            make new recipient at newMsg with properties {email address:{address:(contents of addr)}}
        end repeat
        repeat with addr in ccAddrs
            make new cc recipient at newMsg with properties {email address:{address:(contents of addr)}}
        end repeat
        open newMsg
        activate
    end tell
end run

on splitAddrs(s)
    set out to {}
    set AppleScript's text item delimiters to ";"
    set parts to text items of s
    set AppleScript's text item delimiters to ""
    repeat with p in parts
        if (contents of p) is not "" then set end of out to contents of p
    end repeat
    return out
end splitAddrs
"""


def open_draft(subject: str, html: str, to: str, cc: str = "") -> None:
    subprocess.run(
        ["osascript", "-e", _SCRIPT, subject, html, to, cc],
        check=True,
        capture_output=True,
    )


def signature() -> str:
    """HTML signature appended where the VBA read the Windows signature file.

    Outlook for Mac doesn't store signatures as .htm files, so drop your
    signature markup into ~/.config/certeq-mail/signature.html once.
    """
    if SIGNATURE_FILE.exists():
        return SIGNATURE_FILE.read_text()
    print(f"note: no signature found at {SIGNATURE_FILE} — draft opens without one")
    return ""
