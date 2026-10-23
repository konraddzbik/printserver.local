---
name: provision-printserver
description: End-to-end provisioning of a Raspberry Pi AirPrint print server from this repo — recon, configure, run setup.sh, verify against the Definition of Done, client check, report. Use when asked to set up, rebuild, or repair the print server.
---

Follow `AGENTS.md` phases 0–5 exactly.

1. **Inputs.** You need the SSH target (`user@host`, default `printserver.local`). Ask for anything that's missing, plus any non-default printer settings.
2. **Phases 0–2.** Delegate to the `printserver-provisioner` subagent. Pass it the SSH target and settings.
3. **Phase 3.** Delegate to the `printserver-verifier` subagent. If it reports `NOT DONE`, hand the failures back to the provisioner. Stop after 3 rounds and escalate to the user with the evidence.
4. **Phase 4.** Ask the user to print from an Apple device and confirm (DOD-M2). Also ask about the DHCP reservation (DOD-M1).
5. **Phase 5.** Report using the "Evidence the agent must report" section of `docs/DEFINITION_OF_DONE.md`.

Arguments, if given: `$ARGUMENTS` (e.g. `pi@192.168.1.50 PRINTER_NAME=Office`).
