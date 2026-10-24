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
| `scripts/setup.sh` | Converging provisioning (packages → server settings → queue). Only changes what differs. `--dry-run`, `--force`. |
| `scripts/verify.sh` | Executable Definition of Done, and **the source of truth for the check list**. `--json` for machine-readable output. |
| `scripts/lib.sh` | Shared config loader (allow-listed `KEY=VALUE`, validated, never `source`d) and logging. |
| `scripts/check-dod-sync.sh` | CI guard: the checks in `verify.sh` and `docs/DEFINITION_OF_DONE.md` must match. |
| `config/printserver.env.example` | Tunables (`PRINTER_NAME`, `DEVICE_URI`, `PRINTER_MODEL`, `PAPER_SIZE`, `NETWORK_ACCESS`, `REMOTE_ADMIN`). |
| `docs/DEFINITION_OF_DONE.md` | The acceptance checklist, with IDs `DOD-1…DOD-11` and `DOD-M1…M3`. |
| `.claude/agents/` | Claude Code subagents: `printserver-provisioner`, `printserver-verifier` (read-only, enforced by a hook). |
| `.claude/hooks/verifier-readonly.sh` | PreToolUse hook that blocks state-changing commands for the verifier. |
| `.claude/skills/provision-printserver/` | `/provision-printserver` skill that runs the whole workflow end to end. |

## Workflow (follow in order)

Every phase has an exit gate. Don't start the next phase until the gate passes.

### 0. Recon (read-only)
Establish where you are running and what's attached. **Don't change anything yet.**

```bash
ssh <user>@<host> 'uname -a; head -3 /etc/os-release; lsusb; ip -4 addr show | grep inet; command -v lpstat && lpstat -t'
```

- Running on the developer's Mac rather than the Pi? Everything below goes through `ssh <user>@<host>`. Ask for the host and user if they aren't given. Don't guess.
- Don't run `lpinfo -v` here. It needs CUPS installed and admin rights. `setup.sh` handles detection.
- Gate: you can SSH in, the OS is Debian/Raspberry Pi OS, and `lsusb` shows the printer (or the user confirms it's a network printer).

### 1. Configure
- Copy `config/printserver.env.example` to `config/printserver.env` on the Pi, uncomment only what differs from defaults, and `chmod 600` it.
- Gate: `sudo ./scripts/setup.sh --dry-run` gets past config validation. Invalid values or unknown keys stop it with an error.

### 2. Provision
```bash
sudo -n true || echo "sudo needs a password, so hand the commands to the user"
sudo ./scripts/setup.sh --dry-run   # review the plan (works before CUPS is installed)
sudo ./scripts/setup.sh
```
- Gate: the script exits `0`. Re-running it should report "Already in the desired state".

### 3. Verify
```bash
./scripts/verify.sh --json   # run once, attach to your report
```
- Gate: exit `0`, `"failed":0`.
- `PRINT_TEST_PAGE=1` (DOD-11) prints a real page. It's environment-only and needs the user's consent each time.
- On failure, use the troubleshooting table in `readme.md`, fix, and **re-run the full verify**. Don't cherry-pick checks.

### 4. Client check (human-in-the-loop)
An agent can't tap "Print" on an iPhone. Ask the user to print from an Apple device (Share → Print) and confirm the printer shows up as `<PRINTER_NAME> @ <hostname>`. Record their answer.

### 5. Report
Finish with a short report: host, queue name, device URI, model/driver, the `verify.sh --json` output, the client-check result, and any deviations from defaults along with why.

## Guardrails

- **Idempotency first.** Prefer extending `setup.sh` over running ad-hoc commands. If you had to run something by hand, fold it back into the script.
- **One `cupsctl` call** for all server settings. Separate calls can silently reset earlier flags (documented in `readme.md` §3).
- **Secure defaults:** `NETWORK_ACCESS=local` and `REMOTE_ADMIN=no`. Only change them when the user explicitly asks, and spell out the exposure (admin pages use the Pi login password over Basic auth).
- **Ask before** changing Wi-Fi/network config, rebooting, editing `/etc/cups/cupsd.conf` by hand, deleting or `--force`-recreating existing queues, or printing a real page (`PRINT_TEST_PAGE=1` uses paper).
  Subagents can't ask anyone, so they **stop and return** the exact command for the caller to get approved.
- **Credentials:** never modify sudoers (`NOPASSWD`), never pipe, store, log or echo a password, and never install SSH keys on the Pi without asking. If `sudo` needs a password, hand the command to the user, e.g. `! ssh -t pi@host 'sudo …'`.
- **Reviewed code only runs as root.** A change to `scripts/` must be shown to the user as a diff before it's run with `sudo`. Don't hot-patch the Pi.
- **Never** disable the firewall, commit `config/printserver.env` or other secrets, or `curl | bash` from the internet.
- Don't claim success without a passing `verify.sh`. If something can't be verified (e.g. no printer attached), say so in the report.

## Changing this repo

- Shell scripts must pass `shellcheck` (CI enforces this) and stay idempotent.
- `verify.sh` is the source of truth for the DoD. A new check needs a `check DOD-n "…"` line there and a row in `docs/DEFINITION_OF_DONE.md` (`scripts/check-dod-sync.sh` enforces this in CI). Also update the DoD summary in `readme.md`, and the troubleshooting table if the check adds a new failure mode. The verify GIF reads its check list from `verify.sh`.
- Keep `readme.md` (the narrative) and the scripts (the automation) in sync. A step that exists in one should exist in the other.
- Regenerate the README GIFs with `pip install -r assets/src/requirements.txt && python3 assets/src/make_gifs.py` whenever the workflow or the checks change.
