# certeq

Tooling for Certeq field / KVS1 work. Each folder is a self-contained project
with its own README and `uv` environment.

| Project | What it does |
|---|---|
| [`McDonald's/KVS1 2026/rhs-vm-config/`](McDonald's/KVS1%202026/rhs-vm-config/) | PowerShell run on a store's RHS02 by the Provisioning Tool: the AUSetup VM-config scripts; the SOE one (v1.03) creates the VM and then does the whole conversion in one run. |
| [`McDonald's/KVS1 2026/soe-fixup/`](McDonald's/KVS1%202026/soe-fixup/) | Mac/Windows helper for the cleanup pass on already-converted VM SOEs (recollect with the 2025 generatekvs) via CyberArk PSM: bakes the RHS02 payloads, verify/tidy, pulls summaries back. |
| [`certeq-mail/`](certeq-mail/) | Mac port of the Outlook VBA macro suite: pulls site data from the Certeq portal API and opens the templated KVS1 deployment emails as drafts in Outlook. |

## Conventions

- Python via [`uv`](https://docs.astral.sh/uv/) - `uv sync` / `uv run` inside a project; no global installs.
- Machine-specific paths and credentials never go in the repo: `soefix.toml` and
  `sites.json` (soe-fixup) and the Keychain / `~/.config/certeq-mail/` (certeq-mail) are
  local; each project ships an example or a `login` command instead.
- Store data (spreadsheets, `SOE_Static_Files`, run logs) stays out of git.
- Not touched by this repo: CyberArk PSM access itself - you still get the
  one-time `.rdp` from PVWA.
