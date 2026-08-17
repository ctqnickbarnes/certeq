# certeq

Tooling for Certeq field / KVS1 work. Each folder is a self-contained project
with its own README and `uv` environment.

| Project | What it does |
|---|---|
| [`soe-fixup/`](soe-fixup/) | Bakes the per-store PowerShell payloads for the VM SOE conversion runbook (restore / push / verify on RHS02, one typed line on the SOE) and the cleanup/recollect pass for already-converted sites. Mac + Windows. |
| [`certeq-mail/`](certeq-mail/) | Mac port of the Outlook VBA macro suite: pulls site data from the Certeq portal API and opens the templated KVS1 deployment emails as drafts in Outlook. |

## Conventions

- Python via [`uv`](https://docs.astral.sh/uv/) - `uv sync` / `uv run` inside a project; no global installs.
- Machine-specific paths and credentials never go in the repo: `soefix.toml`
  (soe-fixup) and the Keychain / `~/.config/certeq-mail/` (certeq-mail) are
  local; each project ships an example or a `login` command instead.
- Store data (spreadsheets, `SOE_Static_Files`, run logs) stays out of git.
- Not touched by this repo: CyberArk PSM access itself - you still get the
  one-time `.rdp` from PVWA.
