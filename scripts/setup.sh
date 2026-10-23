#!/usr/bin/env bash
# Idempotent provisioning of a Raspberry Pi AirPrint server (CUPS + Avahi + brlaser).
# Safe to re-run: every step checks state before changing it.
#
# Usage (on the Pi):  sudo ./scripts/setup.sh [--dry-run]
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="${ENV_FILE:-$SCRIPT_DIR/../config/printserver.env}"
# shellcheck source=/dev/null
[[ -f "$ENV_FILE" ]] && source "$ENV_FILE"

PRINTER_NAME="${PRINTER_NAME:-Brother}"
DEVICE_URI="${DEVICE_URI:-}"
PRINTER_MODEL="${PRINTER_MODEL:-auto}"
PAPER_SIZE="${PAPER_SIZE:-A4}"
NETWORK_ACCESS="${NETWORK_ACCESS:-local}"
DRY_RUN=0
[[ "${1:-}" == "--dry-run" ]] && DRY_RUN=1

log()  { printf '\033[1;36m==>\033[0m %s\n' "$*"; }
ok()   { printf '\033[1;32m  ✓\033[0m %s\n' "$*"; }
die()  { printf '\033[1;31m  ✗\033[0m %s\n' "$*" >&2; exit 1; }
run()  { if (( DRY_RUN )); then printf '    [dry-run] %s\n' "$*"; else "$@"; fi; }

[[ "$PRINTER_NAME" =~ ^[A-Za-z0-9_.-]+$ ]] || die "PRINTER_NAME '$PRINTER_NAME' must not contain spaces, '/' or '#'"
[[ "$NETWORK_ACCESS" =~ ^(local|any)$ ]] || die "NETWORK_ACCESS must be 'local' or 'any'"
(( DRY_RUN )) || [[ $EUID -eq 0 ]] || die "run as root: sudo $0"

# 1. Packages ---------------------------------------------------------------
log "Installing packages"
PKGS=(cups avahi-daemon avahi-utils printer-driver-brlaser)
missing=()
for p in "${PKGS[@]}"; do dpkg -s "$p" &>/dev/null || missing+=("$p"); done
if (( ${#missing[@]} )); then
  run apt-get update
  run env DEBIAN_FRONTEND=noninteractive apt-get install -y "${missing[@]}"
else
  ok "all packages present"
fi

ADMIN_USER="${SUDO_USER:-}"
if [[ -n "$ADMIN_USER" && "$ADMIN_USER" != root ]] && ! id -nG "$ADMIN_USER" | grep -qw lpadmin; then
  run usermod -aG lpadmin "$ADMIN_USER"
fi

run systemctl enable --now cups avahi-daemon

# 2. Network exposure — one cupsctl call, separate calls can reset earlier flags
log "Opening CUPS to the network ($NETWORK_ACCESS)"
if [[ "$NETWORK_ACCESS" == any ]]; then
  run cupsctl --remote-any --remote-admin --share-printers WebInterface=yes
else
  run cupsctl --no-remote-any --remote-admin --share-printers WebInterface=yes
fi
run systemctl restart cups

# 3. Printer queue ----------------------------------------------------------
log "Configuring queue '$PRINTER_NAME'"
if [[ -z "$DEVICE_URI" ]]; then
  DEVICE_URI="$(lpinfo -v 2>/dev/null | awk '$2 ~ /^usb:\/\// {print $2; exit}')" || true
  [[ -n "$DEVICE_URI" ]] || die "no USB printer found by 'lpinfo -v' — is it powered on? check 'lsusb'"
  ok "detected $DEVICE_URI"
fi

if [[ "$PRINTER_MODEL" == auto ]]; then
  if [[ "$DEVICE_URI" =~ ^(ipp|ipps):// ]]; then
    PRINTER_MODEL=everywhere
  else
    # Match the model from the URI (e.g. "HL-1110") against available brlaser PPDs.
    model_hint="$(sed -E 's#^usb://[^/]+/([^?]+).*#\1#; s#%20# #g; s# series##' <<<"$DEVICE_URI")"
    PRINTER_MODEL="$(lpinfo -m 2>/dev/null | grep -i brlaser | grep -iF "$model_hint" | awk '{print $1; exit}')" || true
    [[ -n "$PRINTER_MODEL" ]] || die "no brlaser PPD matches '$model_hint' — set PRINTER_MODEL explicitly (lpinfo -m | grep -i brlaser)"
  fi
  ok "model $PRINTER_MODEL"
fi

run lpadmin -p "$PRINTER_NAME" -E -v "$DEVICE_URI" -m "$PRINTER_MODEL" \
  -o printer-is-shared=true -o media="$PAPER_SIZE"
run lpadmin -d "$PRINTER_NAME"
run cupsenable "$PRINTER_NAME"
run cupsaccept "$PRINTER_NAME"

# 4. Hygiene ------------------------------------------------------------------
log "Housekeeping"
run cupsctl PreserveJobHistory=no
run systemctl restart avahi-daemon

log "Done. Next: ./scripts/verify.sh"
