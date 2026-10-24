#!/usr/bin/env bash
# PreToolUse hook for the printserver-verifier subagent: blocks Bash commands
# that change state on the Pi or locally. A deny-list is a guard rail, not a
# sandbox. It stops accidental "fixes"; it won't stop a determined adversary.
# Exit 2 = block, with stderr fed back to the agent.
set -uo pipefail

input="$(cat)"
if command -v jq >/dev/null; then
  cmd="$(jq -r '.tool_input.command // empty' <<<"$input")"
else
  cmd="$(python3 -c 'import json,sys; print(json.load(sys.stdin).get("tool_input",{}).get("command",""))' <<<"$input")"
fi

deny='(^|[^[:alnum:]_-])(sudo|su|doas|lpadmin|cupsctl|cupsenable|cupsdisable|cupsaccept|cupsreject|cancel|lp|lpr|lpoptions[^|;&]*[[:space:]]-[od]|apt|apt-get|dpkg|usermod|rm|mv|tee|chmod|chown|scp|rsync|reboot|shutdown|systemctl[[:space:]]+(start|stop|restart|reload|enable|disable|mask)|sed[[:space:]]+-i|PRINT_TEST_PAGE=1)([^[:alnum:]_-]|$)'

if grep -Eq -- "$deny" <<<"$cmd"; then
  echo "printserver-verifier is read-only: '$cmd' would change state or use paper. Report the finding instead of fixing it." >&2
  exit 2
fi
# Writing redirections, except to /dev/null
if grep -Eq -- '(^|[^0-9&])>>?[[:space:]]*[^&[:space:]]' <<<"${cmd//\/dev\/null/}"; then
  echo "printserver-verifier is read-only: output redirection to a file is blocked." >&2
  exit 2
fi
exit 0
