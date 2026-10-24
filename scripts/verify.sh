#!/usr/bin/env bash
# Executable Definition of Done for the print server (see docs/DEFINITION_OF_DONE.md).
# This file is the source of truth for the check list: CI and the README GIF read
# the `check DOD-n "…"` lines below. Exit 0 only when every check passes.
#
# Usage (on the Pi):  ./scripts/verify.sh [--json]
#   PRINT_TEST_PAGE=1 ./scripts/verify.sh   also prints a real page (DOD-11).
#   Environment only, never read from the config file, so paper is never used implicitly.
set -uo pipefail

# shellcheck source-path=SCRIPTDIR source=lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

JSON=0
for arg in "$@"; do
  case "$arg" in
    --json)    JSON=1 ;;
    -h|--help) printf 'usage: %s [--json]\n' "$0"; exit 0 ;;
    *)         die "unknown argument: $arg (usage: $0 [--json])" ;;
  esac
done
PRINT_TEST_PAGE="${PRINT_TEST_PAGE:-0}"
DOD11_TIMEOUT="${DOD11_TIMEOUT:-60}"   # seconds to wait for the test page
[[ $DOD11_TIMEOUT =~ ^[0-9]+$ ]] || die "DOD11_TIMEOUT must be a number of seconds"
load_config   # validates PRINTER_NAME, so it's safe in regexes and JSON below

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
# The disabled web UI still answers 200, with an explanatory page, so check the body.
webui_up()        { local body; body="$(curl -sfk https://localhost:631/printers/)" && [[ $body != *"web interface is currently disabled"* ]]; }
queue_enabled()   { lpstat -p "$PRINTER_NAME" | awk -v p="$PRINTER_NAME" '$1=="printer" && $2==p && /enabled since/ {f=1} END{exit !f}'; }
# "not accepting requests" contains "accepting requests", so match the field, not a substring.
queue_accepting() { lpstat -a "$PRINTER_NAME" | awk -v p="$PRINTER_NAME" '$1==p && $2=="accepting" {f=1} END{exit !f}'; }
queue_shared()    { lpoptions -p "$PRINTER_NAME" | tr ' ' '\n' | grep -qx 'printer-is-shared=true'; }
is_default()      { lpstat -d | awk -F': ' -v p="$PRINTER_NAME" '$2==p {f=1} END{exit !f}'; }
# Only this host's records (by address), and only this queue (by CUPS's rp= TXT key).
# Other Bonjour printers on the LAN, e.g. a networked Brother, must not count.
own_ipp_records() {
  avahi-browse -rtp _ipp._tcp \
    | awk -F';' -v ips=" $(hostname -I) " '$1=="=" && index(ips, " " $8 " ")' \
    | grep -F "\"rp=printers/$PRINTER_NAME\""
}
advertised()      { own_ipp_records | grep -q .; }
airprint_txt()    { own_ipp_records | grep -q '"URF='; }
# Relies on setup.sh keeping completed jobs for JOB_HISTORY_SECONDS.
test_page()       {
  local id
  id="$(echo "printserver.local DoD $(date -Is)" | lp -d "$PRINTER_NAME" | awk '{print $4}')"
  [[ ${id%-*} == "$PRINTER_NAME" && ${id##*-} =~ ^[0-9]+$ ]] || return 1   # e.g. Brother-42
  for _ in $(seq $(( (DOD11_TIMEOUT + 1) / 2 ))); do
    lpstat -W completed -o "$PRINTER_NAME" | awk -v id="$id" '$1==id {f=1} END{exit !f}' && return 0
    sleep 2
  done
  return 1
}

(( JSON )) || log "Verifying print server (queue: $PRINTER_NAME)"
check DOD-1 "cups service active"                 systemctl is-active --quiet cups
check DOD-2 "avahi-daemon service active"         systemctl is-active --quiet avahi-daemon
check DOD-3 "CUPS listens on the LAN (:631)"      listens_on_lan
check DOD-4 "web UI enabled on https://:631"      webui_up
check DOD-5 "queue exists and is enabled"         queue_enabled
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
