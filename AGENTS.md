# AGENTS.md — instructions for coding agents

This repo turns a Raspberry Pi into an AirPrint server for a USB Brother printer (CUPS + Avahi + brlaser).
Any agent (Claude Code, Codex, Cursor, Copilot, Gemini CLI, …) working here should follow this file.
The human-oriented guide is [`readme.md`](readme.md); this file is the operational contract.

## Mission

Provision a Pi so that an iPhone, iPad, or Mac on the same LAN can print to the attached printer with **no driver installed on the client**.
You're done when every item in the [Definition of Done](docs/DEFINITION_OF_DONE.md) passes, and `scripts/verify.sh` exits `0` is the proof.

## Repo map

| Path | Purpose |
|---|---|
| `readme.md` | Manual step-by-step guide and troubleshooting table. **Source of truth for *why*.** |
| `scripts/setup.sh` | Idempotent provisioning (packages → network → queue → hygiene). Supports `--dry-run`. |
| `scripts/verify.sh` | Executable Definition of Done. `--json` for machine-readable output. |
| `config/printserver.env.example` | Tunables (`PRINTER_NAME`, `DEVICE_URI`, `PRINTER_MODEL`, `PAPER_SIZE`, `NETWORK_ACCESS`, `PRINT_TEST_PAGE`). |
| `docs/DEFINITION_OF_DONE.md` | The acceptance checklist, with IDs `DOD-1…DOD-11`. |
| `.claude/agents/` | Claude Code subagents: `printserver-provisioner`, `printserver-verifier`. |
| `.claude/skills/provision-printserver/` | `/provision-printserver` skill that runs the whole workflow end to end. |

## Workflow (follow in order)

Every phase has an exit gate. Don't start the next phase until the gate passes.

### 0. Recon (read-only)
Establish where you are running and what's attached. **Don't change anything yet.**

```bash
ssh <user>@<host> 'uname -a; cat /etc/os-release | head -3; lsusb; ip -4 addr show | grep inet'
```

- Running on the developer's Mac rather than the Pi? Everything below goes through `ssh <user>@<host>`. Ask for the host and user if they aren't given. Don't guess.
- Gate: you can SSH in, the OS is Debian/Raspberry Pi OS, and `lsusb` shows the printer (or the user confirms it's a network printer).

### 1. Configure
- Copy `config/printserver.env.example` to `config/printserver.env` on the Pi and set only what differs from defaults.
- Gate: `PRINTER_NAME` matches `^[A-Za-z0-9_.-]+$`.

### 2. Provision
```bash
sudo ./scripts/setup.sh --dry-run   # review the plan first
sudo ./scripts/setup.sh
```
- Gate: the script exits `0`.

### 3. Verify
```bash
./scripts/verify.sh          # human output
./scripts/verify.sh --json   # attach this to your report
```
- Gate: exit `0`, all checks ✓.
- On failure, use the troubleshooting table in `readme.md`, fix, and **re-run the full verify**. Don't cherry-pick checks.

### 4. Client check (human-in-the-loop)
An agent can't tap "Print" on an iPhone. Ask the user to print from an Apple device (Share → Print) and confirm the printer shows up as `<PRINTER_NAME> @ <hostname>`. Record their answer.

### 5. Report
Finish with a short report: host, queue name, device URI, model/driver, the `verify.sh --json` output, the client-check result, and any deviations from defaults along with why.

## Guardrails

- **Idempotency first.** Prefer extending `setup.sh` over running ad-hoc commands. If you had to run something by hand, fold it back into the script.
- **One `cupsctl` call** for the network flags. Separate calls can silently reset earlier flags (documented in `readme.md` §3).
- **`NETWORK_ACCESS=local` is the default.** Only use `any` when the user explicitly asks, and point out the exposure.
- **Ask before** changing Wi-Fi/network config, rebooting, editing `/etc/cups/cupsd.conf` by hand, deleting existing queues, or printing a real page (`PRINT_TEST_PAGE=1` uses paper).
- **Never** disable the firewall, commit `config/printserver.env` or other secrets, or `curl | bash` from the internet.
- Don't claim success without a passing `verify.sh`. If something can't be verified (e.g. no printer attached), say so in the report.

## Changing this repo

- Shell scripts must pass `shellcheck` (CI enforces this) and stay idempotent.
- A new DoD check needs all three: a `check DOD-n …` line in `verify.sh`, a row in `docs/DEFINITION_OF_DONE.md`, and an entry in the README troubleshooting table if it adds a new failure mode.
- Keep `readme.md` (the narrative) and the scripts (the automation) in sync. A step that exists in one should exist in the other.
- Regenerate the README GIFs with `python3 assets/src/make_gifs.py` (needs Pillow) whenever the workflow or the checks change.
