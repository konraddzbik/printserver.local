#!/usr/bin/env bash
# CI guard: every DoD check defined in verify.sh (the source of truth) must be
# documented in docs/DEFINITION_OF_DONE.md, and nothing may be documented that
# verify.sh doesn't check.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."

code="$(grep -oE '^[[:space:]]*check DOD-[0-9]+' scripts/verify.sh | grep -oE 'DOD-[0-9]+' | sort -u)"
docs="$(grep -oE '^\| DOD-[0-9]+ ' docs/DEFINITION_OF_DONE.md | grep -oE 'DOD-[0-9]+' | sort -u)"

if [[ "$code" != "$docs" ]]; then
  echo "DoD drift between scripts/verify.sh and docs/DEFINITION_OF_DONE.md:" >&2
  diff <(echo "$code") <(echo "$docs") >&2 || true
  exit 1
fi
echo "DoD in sync: $(wc -l <<<"$code" | tr -d ' ') checks"
