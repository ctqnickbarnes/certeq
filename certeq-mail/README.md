# certeq-mail

Mac port of the Outlook VBA macro suite (`Outlook Macros v7.zip` — `KVS1_2026.bas`,
`API_Login` and `Certeq_Menu_KVS1` forms). Fetches site data from the Certeq
portal API and opens templated KVS1 deployment emails as **drafts** in Outlook
for Mac — nothing is sent automatically, same as the VBA `.Display` behaviour.

## Setup

```sh
cd ~/dev/certeq-mail
uv sync
uv run certeq login          # credentials + token go to the macOS Keychain
```

Optional but recommended — your email signature (the VBA read the Windows
signature folder, which doesn't exist on Mac). Save your signature's HTML to:

```
~/.config/certeq-mail/signature.html
```

Tip: send yourself an email from Outlook with just your signature, view the
message source, and paste the HTML into that file.

## Usage

```sh
uv run certeq                     # interactive menu (the old Certeq Console form)
uv run certeq soe-au 1234         # SOE VM Recovery email (AU, report 220)
uv run certeq soe-nz 1234         # SOE VM Recovery email (NZ, report 3613)
uv run certeq dmaas-au 1234       # DMaaS / RSM staging email (AU, report 1320)
uv run certeq dmaas-nz 1234       # DMaaS / RSM staging email (NZ, report 3609)
uv run certeq maxtel 1234         # Maxtel upgrade-checks email (report 3613)
uv run certeq completion 1234     # KVS1 completion email (report 3612)
uv run certeq issues 1234         # completion email with open-issues list
uv run certeq issues-update 1234  # issues update email
uv run certeq report              # daily conversions report (report 3614)
```

Omit the site ID to be prompted, matching the VBA `InputBox`.

## GUI

```sh
uv run certeq-gui
```

Opens the "Certeq Console" window (Tkinter port of the `Certeq_Menu_KVS1`
form): Site ID field, one button per email, Daily Report, and a Login… dialog
replacing the `API_Login` form. The status line mirrors the old Active/Inactive
token indicator. Buttons disable while a request is in flight; errors surface
in a dialog with the API response snippet.

## VBA → Mac mapping

| VBA | Here |
|---|---|
| `MSXML2.ServerXMLHTTP` | `httpx` |
| `GetSetting`/`SaveSetting` (registry) | macOS Keychain via `keyring` + `~/.config/certeq-mail/config.json` |
| Hand-rolled JSON parser (~150 lines/macro) | `response.json()` |
| `%APPDATA%\Microsoft\Signatures\*.htm` | `~/.config/certeq-mail/signature.html` |
| `OutMail.Display` | AppleScript draft in Outlook (works with New Outlook) |
| `API_Login` / `Certeq_Menu_KVS1` forms | `certeq login` / bare `certeq` menu |

Token handling is slightly improved: when the token expires the CLI re-logs-in
automatically using the Keychain-stored password (the VBA needed the login form
run again each day).

## Notes

- Body text and recipient lists are copied verbatim from the VBA, including the
  placeholder "Issue Description" lists you edit before sending. One encoding
  artifact was fixed ("Service Caf�" → "Service Café").
- The daily report's duplicate CC (`sme@certeq.com.au` twice in the VBA) was
  deduplicated.
