@AGENTS.md

## Claude Code specifics

- `/provision-printserver` runs the full workflow (recon → configure → provision → verify → report).
- Delegate to the `printserver-provisioner` subagent for phases 0–2 and the `printserver-verifier` subagent for phase 3. The verifier is read-only by design. Don't let it "fix" things.
- Phase 4 (client check) always goes back to the user.
