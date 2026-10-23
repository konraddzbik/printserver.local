#!/usr/bin/env bash
# Executable Definition of Done for the print server (see docs/DEFINITION_OF_DONE.md).
# Exit 0 only when every required check passes.
#
# Usage (on the Pi):  ./scripts/verify.sh [--json]
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="${ENV_FILE:-$SCRIPT_DIR/../config/printserver.env}"
# shellcheck source=/dev/null
[[ -f "$ENV_FILE" ]] && source "$ENV_FILE"
PRINTER_NAME="${PRINTER_NAME:-Brother}"
PRINT_TEST_PAGE="${PRINT_TEST_PAGE:-0}"
JSON=0
[[ "${1:-}" == "--json" ]] && JSON=1

pass=0 fail=0
results=()

check() {  # check <id> <description> <command...>
  local id="$1" desc="$2"; shift 2
  if "$@" &>/dev/null; then
    pass=$((pass + 1)); results+=("{\"id\":\"$id\",\"ok\":true}")
    (( JSON )) || printf '\033[1;32m  ✓\033[0m %-6s %s\n' "$id" "$desc"
  else
    fail=$((fail + 1)); results+=("{\"id\":\"$id\",\"ok\":false}")
    (( JSON )) || printf '\033[1;31m  ✗\033[0m %-6s %s\n' "$id" "$desc"
  fi
}

listens_on_lan()  { ss -tln | awk '{print $4}' | grep -Eq '^(\*|0\.0\.0\.0|\[::\]):631$'; }
queue_idle()      { lpstat -p "$PRINTER_NAME" | grep -q 'enabled'; }
queue_accepting() { lpstat -a "$PRINTER_NAME" | grep -q 'accepting requests'; }
queue_shared()    { lpoptions -p "$PRINTER_NAME" | grep -q 'printer-is-shared=true'; }
is_default()      { lpstat -d | grep -q ": $PRINTER_NAME\$"; }
advertised()      { avahi-browse -rtp _ipp._tcp | grep -q "$PRINTER_NAME"; }
airprint_txt()    { avahi-browse -rtp _ipp._tcp | grep "$PRINTER_NAME" | grep -q 'URF='; }
webui_up()        { curl -sk -o /dev/null -w '%{http_code}' https://localhost:631/ | grep -q '^200$'; }
test_page()       { local id; id="$(echo "printserver.local DoD $(date -Is)" | lp -d "$PRINTER_NAME" | awk '{print $4}')";
                    for _ in $(seq 30); do lpstat -W completed -o "$PRINTER_NAME" | grep -q "^$id" && return 0; sleep 2; done; return 1; }

(( JSON )) || printf '\033[1;36m==>\033[0m Verifying print server (queue: %s)\n' "$PRINTER_NAME"
check DOD-1 "cups service active"                 systemctl is-active --quiet cups
check DOD-2 "avahi-daemon service active"         systemctl is-active --quiet avahi-daemon
check DOD-3 "CUPS listens on the LAN (:631)"      listens_on_lan
check DOD-4 "web UI answers on https://:631"      webui_up
check DOD-5 "queue exists and is enabled"         queue_idle
check DOD-6 "queue accepts jobs"                  queue_accepting
check DOD-7 "queue is shared"                     queue_shared
check DOD-8 "queue is the system default"         is_default
check DOD-9 "advertised via Bonjour (_ipp._tcp)"  advertised
check DOD-10 "AirPrint TXT record (URF) present"  airprint_txt
if [[ "$PRINT_TEST_PAGE" == 1 ]]; then
  check DOD-11 "test page completed"              test_page
fi

if (( JSON )); then
  printf '{"printer":"%s","passed":%d,"failed":%d,"checks":[%s]}\n' \
    "$PRINTER_NAME" "$pass" "$fail" "$(IFS=,; echo "${results[*]}")"
else
  printf '\n  %d passed, %d failed\n' "$pass" "$fail"
fi
(( fail == 0 ))
