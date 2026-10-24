@AGENTS.md

## Claude Code specifics

- `/provision-printserver` runs the full workflow (recon → configure → provision → verify → report).
- Delegate to the `printserver-provisioner` subagent for phases 0–2 and the `printserver-verifier` subagent for phase 3. The verifier is read-only, enforced by `.claude/hooks/verifier-readonly.sh`. Don't let it "fix" things.
- Subagents can't ask the user anything. They return proposed commands or diffs, and you get approval for them.
- Phase 4 (client check) and the final DONE always go through you and the user.
