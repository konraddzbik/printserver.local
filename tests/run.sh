#!/usr/bin/env bash
# Hermetic tests for scripts/: every CUPS/Avahi/systemd command is a stub that
# reads its output from FX_* fixture variables and logs state-changing calls.
# Runs in CI (bash 5). Real-mode setup.sh scenarios need passwordless sudo and
# are skipped without it.
#
# Usage: tests/run.sh
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
pass=0 fail=0 skip=0

# --- hermetic PATH: stubs + only the real tools the scripts need -------------
REAL="$WORK/real"; mkdir -p "$REAL"
for t in bash awk grep sed find tr seq sort cat dirname env printf date mktemp rm diff wc head sleep basename touch chmod; do
  p="$(command -v "$t")" && ln -s "$p" "$REAL/$t"
done

make_stubs() {  # make_stubs <dir> [command-to-omit…]
  local dir="$1"; shift
  mkdir -p "$dir"
  cat >"$dir/_stub" <<'STUB'
#!/usr/bin/env bash
name="$(basename "$0")"
log() { printf '%s %s\n' "$name" "$*" >>"$FX_CALLS"; }
case "$name" in
  systemctl)
    case "$1" in is-active|is-enabled) exit "${FX_SVC_RC:-0}" ;; *) log "$@" ;; esac ;;
  dpkg-query)   printf '%s' "${FX_PKG_STATUS:-installed}" ;;
  cupsctl)      if (( $# )); then log "$@"; else printf '%b' "${FX_CUPSCTL:-}"; fi ;;
  lpinfo)       [[ $1 == -v ]] && printf '%b' "${FX_LPINFO_V:-}"; [[ $1 == -m ]] && printf '%b' "${FX_LPINFO_M:-}"; true ;;
  lpstat)
    case "$1" in
      -v) printf '%b' "${FX_LPSTAT_V:-}" ;; -p) printf '%b' "${FX_LPSTAT_P:-}" ;;
      -a) printf '%b' "${FX_LPSTAT_A:-}" ;; -d) printf '%b' "${FX_LPSTAT_D:-}" ;;
      -W) printf '%b' "${FX_LPSTAT_W:-}" ;;
    esac ;;
  lpoptions)    printf '%b' "${FX_LPOPTIONS:-}" ;;
  avahi-browse) printf '%b' "${FX_AVAHI:-}" ;;
  hostname)     printf '%s\n' "${FX_IPS:-192.168.1.10}" ;;
  ss)           printf '%b' "${FX_SS:-}" ;;
  curl)         printf '%b' "${FX_CURL_BODY:-}"; exit "${FX_CURL_RC:-0}" ;;
  id)           printf '%s\n' "${FX_GROUPS:-pi lpadmin}" ;;
  lp)           log "$@"; printf 'request id is %s (1 file(s))\n' "${FX_LP_ID:-}" ;;
  *)            log "$@" ;;   # lpadmin, cupsenable, cupsaccept, usermod, apt-get
esac
STUB
  chmod +x "$dir/_stub"
  local c
  for c in systemctl dpkg-query cupsctl lpinfo lpstat lpoptions avahi-browse hostname ss curl id lp \
           lpadmin cupsenable cupsaccept usermod apt-get; do
    [[ " $* " == *" $c "* ]] || ln -s _stub "$dir/$c"
  done
}
STUBS="$WORK/stubs";        make_stubs "$STUBS"
STUBS_NOCUPS="$WORK/nocups"; make_stubs "$STUBS_NOCUPS" lpinfo lpstat lpoptions cupsctl lpadmin cupsenable cupsaccept

# --- fixtures for a healthy, fully converged server --------------------------
healthy() {
  export FX_CUPSCTL='_remote_admin=0\n_remote_any=0\n_share_printers=1\nWebInterface=Yes\nPreserveJobHistory=3600\n'
  export FX_LPINFO_V='direct usb://Brother/HL-1110%20series?serial=ABC123\nnetwork socket\n'
  export FX_LPINFO_M='drv:///brlaser.drv/br1110.ppd Brother HL-1110 series, using brlaser v6\n'
  export FX_LPSTAT_V='device for Brother: usb://Brother/HL-1110%20series?serial=ABC123\n'
  export FX_LPSTAT_P='printer Brother is idle.  enabled since Fri Oct 24 10:00:00 2026\n'
  export FX_LPSTAT_A='Brother accepting requests since Fri Oct 24 10:00:00 2026\n'
  export FX_LPSTAT_D='system default destination: Brother\n'
  export FX_LPOPTIONS='copies=1 printer-is-accepting-jobs=true printer-is-shared=true printer-state=3\n'
  export FX_SS='State Recv-Q Send-Q Local Address:Port Peer Address:Port\nLISTEN 0 128 0.0.0.0:631 0.0.0.0:*\n'
  export FX_CURL_BODY='<html>Printers</html>'
  export FX_IPS='192.168.1.10 fd00::10'
  export FX_AVAHI='+;eth0;IPv4;Brother @ printserver;_ipp._tcp;local\n=;eth0;IPv4;Brother @ printserver;_ipp._tcp;local;printserver.local;192.168.1.10;631;"rp=printers/Brother" "ty=Brother HL-1110 series" "URF=W8,SRGB24,RS600"\n'
  unset FX_SVC_RC FX_PKG_STATUS FX_CURL_RC FX_LP_ID FX_LPSTAT_W
}

# --- runner -----------------------------------------------------------------
OUT="$WORK/out"
export FX_CALLS="$WORK/calls" DOD11_TIMEOUT=2
runit() {  # runit <stubdir> <script> [args…]   (no sudo)
  local stubs="$1"; shift
  : >"$FX_CALLS"
  ENV_FILE="${ENV_FILE:-$WORK/none.env}" PATH="$stubs:$REAL" bash "$ROOT/scripts/$1" "${@:2}" >"$OUT" 2>&1
}
runroot() {  # same, as root
  local stubs="$1"; shift
  : >"$FX_CALLS"
  # shellcheck disable=SC2024  # output files belong to the unprivileged runner on purpose
  sudo --preserve-env env ENV_FILE="${ENV_FILE:-$WORK/none.env}" PATH="$stubs:$REAL" \
    bash "$ROOT/scripts/$1" "${@:2}" >"$OUT" 2>&1
}
HAVE_SUDO=0; sudo -n true 2>/dev/null && HAVE_SUDO=1

t() {  # t <name> <expected-rc> <command…>
  local name="$1" want="$2"; shift 2
  "$@"; local rc=$?
  if [[ $want == "$rc" || ($want == nonzero && $rc != 0) ]]; then pass=$((pass + 1)); printf '  ok   %s\n' "$name"
  else fail=$((fail + 1)); printf '  FAIL %s (rc=%s, want %s)\n' "$name" "$rc" "$want"; sed 's/^/       | /' "$OUT"; fi
}
expect_out()    { grep -qF -- "$1" "$OUT"; }
expect_call()   { grep -qF -- "$1" "$FX_CALLS"; }
expect_nocall() { ! grep -q . "$FX_CALLS"; }
both() { "$@"; }
sudo_t() { if (( HAVE_SUDO )); then t "$@"; else skip=$((skip + 1)); printf '  skip %s (no passwordless sudo)\n' "$1"; fi; }

echo "verify.sh"
healthy
t "healthy server passes all checks"            0 runit "$STUBS" verify.sh --json
t "  … JSON reports 0 failed"                    0 expect_out '"passed":10,"failed":0'
t "unknown argument is rejected"                 nonzero runit "$STUBS" verify.sh --jsn
FX_LPSTAT_A='Brother not accepting requests since Fri Oct 24 10:00:00 2026 -\n\tRejecting Jobs\n' \
  t "DOD-6 fails when queue rejects jobs"        nonzero runit "$STUBS" verify.sh --json
FX_LPSTAT_A='Brother not accepting requests since x -\n' runit "$STUBS" verify.sh --json
t "  … and only DOD-6"                           0 expect_out '{"id":"DOD-6","ok":false}'
FX_LPSTAT_P='printer Brother disabled since Fri Oct 24 -\n\tPaused\n' \
  t "DOD-5 fails when queue disabled"            nonzero runit "$STUBS" verify.sh
FX_AVAHI='=;eth0;IPv4;Brother MFC @ office;_ipp._tcp;local;brother-mfc.local;192.168.1.77;631;"rp=printers/Brother" "URF=W8"\n' \
  t "DOD-9/10 ignore another host's Brother"     nonzero runit "$STUBS" verify.sh --json
FX_AVAHI='=;eth0;IPv4;Brother2 @ printserver;_ipp._tcp;local;printserver.local;192.168.1.10;631;"rp=printers/Brother2" "URF=W8"\n' \
  t "DOD-9 doesn't match a prefix queue name"    nonzero runit "$STUBS" verify.sh --json
FX_CURL_BODY='The web interface is currently disabled. Run "cupsctl WebInterface=yes" to enable it.' \
  t "DOD-4 fails on the disabled-web-UI page"    nonzero runit "$STUBS" verify.sh
FX_SS='LISTEN 0 128 127.0.0.1:631 0.0.0.0:*\n' \
  t "DOD-3 fails when bound to localhost only"   nonzero runit "$STUBS" verify.sh
FX_LP_ID='Brother-1' FX_LPSTAT_W='Brother-12 pi 1024 Fri Oct 24\n' PRINT_TEST_PAGE=1 \
  t "DOD-11 doesn't match job-id prefixes"       nonzero runit "$STUBS" verify.sh --json
FX_LP_ID='Brother-12' FX_LPSTAT_W='Brother-12 pi 1024 Fri Oct 24\n' PRINT_TEST_PAGE=1 \
  t "DOD-11 passes on a completed job"           0 runit "$STUBS" verify.sh --json
FX_LP_ID='' PRINT_TEST_PAGE=1 FX_LPSTAT_W='Brother-12 pi 1024\n' \
  t "DOD-11 fails when lp returns no job id"     nonzero runit "$STUBS" verify.sh --json

echo "config loading (lib.sh)"
healthy
cfg="$WORK/cfg.env"
printf 'PRINTER_NAME=Office\n' >"$cfg"; chmod 600 "$cfg"
ENV_FILE="$cfg" FX_AVAHI='' runit "$STUBS" verify.sh
t "file value is used"                           0 expect_out 'queue: Office'
ENV_FILE="$cfg" PRINTER_NAME=Lab FX_AVAHI='' runit "$STUBS" verify.sh
t "environment overrides the file"               0 expect_out 'queue: Lab'
# shellcheck disable=SC2016  # the literal $(…) is the injection payload
printf 'PRINTER_NAME=$(touch %s/pwned)\n' "$WORK" >"$cfg"
ENV_FILE="$cfg" t "shell in config is rejected" nonzero runit "$STUBS" verify.sh
t "  … and never executed"                       nonzero test -e "$WORK/pwned"
printf 'PRINT_TEST_PAGE=1\n' >"$cfg"
ENV_FILE="$cfg" t "keys outside the allow-list are rejected" nonzero runit "$STUBS" verify.sh
printf 'PRINTER_NAME="Quoted"\n# comment\n\n' >"$cfg"
ENV_FILE="$cfg" FX_AVAHI='' runit "$STUBS" verify.sh
t "quotes and comments are handled"              0 expect_out 'queue: Quoted'
printf 'PRINTER_NAME=Office\n' >"$cfg"; chmod 666 "$cfg"
ENV_FILE="$cfg" t "world-writable config is refused" nonzero runit "$STUBS" verify.sh
chmod 600 "$cfg"
NETWORK_ACCESS=everyone t "invalid enum is rejected" nonzero runit "$STUBS" verify.sh

echo "setup.sh"
healthy
t "unknown argument is rejected"                 nonzero runit "$STUBS" setup.sh --dryrun
t "  … before doing anything"                    0 expect_nocall
FX_PKG_STATUS=not-installed \
  t "dry-run works on a fresh Pi (no CUPS yet)"  0 runit "$STUBS_NOCUPS" setup.sh --dry-run
t "  … and says it would auto-detect"            0 expect_out 'would auto-detect'
t "  … and changes nothing"                      0 expect_nocall
t "dry-run on a converged Pi changes nothing"    0 runit "$STUBS" setup.sh --dry-run
t "  … and plans nothing"                        nonzero expect_out '[dry-run]'
FX_LPINFO_V='direct usb://Brother/A\ndirect usb://Brother/B\n' FX_LPSTAT_V='' \
  t "several USB printers → refuses to guess"    nonzero runit "$STUBS" setup.sh --dry-run
FX_LPSTAT_V='' FX_LPINFO_V='network socket://10.0.0.5\n' DEVICE_URI='socket://10.0.0.5' \
  t "socket:// without PRINTER_MODEL → asks"     nonzero runit "$STUBS" setup.sh --dry-run
FX_LPSTAT_V='' DEVICE_URI='dnssd://Brother._ipp._tcp.local/' runit "$STUBS" setup.sh --dry-run
t "dnssd:// → IPP Everywhere"                    0 expect_out 'model everywhere'
t "refuses to run for real without root"         nonzero runit "$STUBS" setup.sh

sudo_t "converged Pi: real run"                  0 runroot "$STUBS" setup.sh
sudo_t "  … makes no state-changing calls"       0 expect_nocall
sudo_t "  … reports nothing changed"             0 expect_out 'Already in the desired state'
FX_CUPSCTL='_remote_admin=1\n_remote_any=1\n_share_printers=1\nWebInterface=Yes\n' FX_LPSTAT_V='' FX_LPSTAT_D='no system default destination\n' \
  sudo_t "fresh queue: real run"                 0 runroot "$STUBS" setup.sh
sudo_t "  … one cupsctl call, admin+any off"     0 expect_call 'cupsctl --share-printers WebInterface=Yes PreserveJobHistory=3600 --no-remote-any --no-remote-admin'
sudo_t "  … creates the queue with brlaser"      0 expect_call 'lpadmin -p Brother -E -v usb://Brother/HL-1110%20series?serial=ABC123 -m drv:///brlaser.drv/br1110.ppd'
sudo_t "  … re-announces over Bonjour"           0 expect_call 'systemctl restart avahi-daemon'
FX_LPSTAT_V='device for Brother: usb://Other/printer\n' \
  sudo_t "queue on another URI → refuses without --force" nonzero runroot "$STUBS" setup.sh
sudo_t "  … and doesn't touch the queue"         nonzero expect_call 'lpadmin'
FX_LPSTAT_V='device for Brother: usb://Other/printer\n' \
  sudo_t "--force recreates it"                  0 runroot "$STUBS" setup.sh --force
REMOTE_ADMIN=yes NETWORK_ACCESS=any FX_CUPSCTL='' sudo_t "opt-in remote admin" 0 runroot "$STUBS" setup.sh
sudo_t "  … passes --remote-any --remote-admin"  0 expect_call '--remote-any --remote-admin'

echo "verifier read-only hook"
hook() { printf '{"tool_input":{"command":%s}}' "$(printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g; s/^/"/; s/$/"/')" \
           | bash "$ROOT/.claude/hooks/verifier-readonly.sh" >/dev/null 2>"$OUT"; }
for cmd in "ssh pi@printserver.local './scripts/verify.sh --json'" \
           "ssh pi@host 'lpstat -t; ss -tln; avahi-browse -rt _ipp._tcp'" \
           "ssh pi@host 'tail -n 50 /var/log/cups/error_log 2>/dev/null'" \
           "ssh pi@host 'lpoptions -p Brother'"; do
  t "allows: $cmd" 0 hook "$cmd"
done
for cmd in "ssh pi@host sudo lpadmin -x Brother" "ssh pi@host 'cupsctl --remote-any'" \
           "ssh pi@host 'echo hi | lp -d Brother'" "ssh pi@host 'PRINT_TEST_PAGE=1 ./scripts/verify.sh'" \
           "ssh pi@host 'systemctl restart cups'" "ssh pi@host 'lpoptions -p Brother -o media=A4'" \
           "echo x > config/printserver.env" "ssh pi@host 'cupsenable Brother'"; do
  t "blocks: $cmd" 2 hook "$cmd"
done

printf '\n%d passed, %d failed, %d skipped\n' "$pass" "$fail" "$skip"
(( fail == 0 ))
