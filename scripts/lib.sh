# shellcheck shell=bash
# Shared helpers for setup.sh and verify.sh. Source it, don't execute it.
#
# Config precedence (highest first): variables already set in the environment,
# then config/printserver.env, then the defaults below. The file is parsed as
# plain KEY=VALUE lines from an allow-list. It's never `source`d, because
# setup.sh runs as root.

export LC_ALL=C   # every check parses CUPS/Avahi output; keep it untranslated

LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_KEYS=(PRINTER_NAME DEVICE_URI PRINTER_MODEL PAPER_SIZE NETWORK_ACCESS REMOTE_ADMIN)
# shellcheck disable=SC2034  # used by setup.sh
JOB_HISTORY_SECONDS=3600   # long enough for DOD-11, short enough not to pile up

log()  { printf '\033[1;36m==>\033[0m %s\n' "$*"; }
ok()   { printf '\033[1;32m  ✓\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m  !\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31m  ✗\033[0m %s\n' "$*" >&2; exit 1; }

load_config() {
  local file="${ENV_FILE:-$LIB_DIR/../config/printserver.env}" key value n=0
  declare -A from_env=()
  for key in "${CONFIG_KEYS[@]}"; do [[ -v $key ]] && from_env[$key]=1; done

  if [[ -f "$file" ]]; then
    # Refuse a file anyone but its owner can modify: setup.sh runs as root.
    [[ -z "$(find "$file" \( -perm -g+w -o -perm -o+w \) -print 2>/dev/null)" ]] \
      || die "$file is group/world-writable. Run: chmod 600 $file"
    while IFS= read -r line || [[ -n $line ]]; do
      n=$((n + 1))
      [[ $line =~ ^[[:space:]]*(#|$) ]] && continue
      [[ $line =~ ^([A-Z_]+)=(.*)$ ]] || die "$file:$n: expected KEY=VALUE"
      key="${BASH_REMATCH[1]}" value="${BASH_REMATCH[2]}"
      [[ " ${CONFIG_KEYS[*]} " == *" $key "* ]] || die "$file:$n: unknown key '$key'"
      [[ $value =~ ^\"(.*)\"$ || $value =~ ^\'(.*)\'$ ]] && value="${BASH_REMATCH[1]}"
      [[ -n ${from_env[$key]:-} ]] || printf -v "$key" '%s' "$value"
    done <"$file"
  fi

  PRINTER_NAME="${PRINTER_NAME:-Brother}"
  DEVICE_URI="${DEVICE_URI:-}"
  PRINTER_MODEL="${PRINTER_MODEL:-auto}"
  PAPER_SIZE="${PAPER_SIZE:-A4}"
  NETWORK_ACCESS="${NETWORK_ACCESS:-local}"
  REMOTE_ADMIN="${REMOTE_ADMIN:-no}"

  [[ $PRINTER_NAME =~ ^[A-Za-z0-9_.-]{1,127}$ ]] || die "PRINTER_NAME '$PRINTER_NAME': use letters, digits, '_', '.', '-' only"
  [[ -z $DEVICE_URI || $DEVICE_URI =~ ^[a-z]+://[^[:space:]\'\"\;\`\$]+$ ]] || die "DEVICE_URI '$DEVICE_URI' is not a valid device URI"
  [[ $PRINTER_MODEL =~ ^(auto|everywhere|[A-Za-z0-9_.:/-]+)$ ]] || die "PRINTER_MODEL '$PRINTER_MODEL' is not a valid model"
  [[ $PAPER_SIZE =~ ^[A-Za-z0-9_.-]+$ ]] || die "PAPER_SIZE '$PAPER_SIZE' is not a valid media name"
  [[ $NETWORK_ACCESS =~ ^(local|any)$ ]] || die "NETWORK_ACCESS must be 'local' or 'any'"
  [[ $REMOTE_ADMIN =~ ^(yes|no)$ ]] || die "REMOTE_ADMIN must be 'yes' or 'no'"
}
