#!/usr/bin/env bash
# Provision a Raspberry Pi AirPrint server (CUPS + Avahi + brlaser).
# Converges to the configured state and is safe to re-run: settings, the queue
# and services are only touched when they differ from what's configured.
#
# Usage (on the Pi):  sudo ./scripts/setup.sh [--dry-run] [--force]
#   --dry-run  print what would change, change nothing
#   --force    recreate an existing queue (resets its driver options)
set -euo pipefail

# shellcheck source-path=SCRIPTDIR source=lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

usage() { printf 'usage: %s [--dry-run] [--force]\n' "$0"; }
DRY_RUN=0 FORCE=0
for arg in "$@"; do
  case "$arg" in
    --dry-run) DRY_RUN=1 ;;
    --force)   FORCE=1 ;;
    -h|--help) usage; exit 0 ;;
    *)         usage >&2; die "unknown argument: $arg" ;;
  esac
done

load_config
(( DRY_RUN )) || [[ $EUID -eq 0 ]] || die "run as root: sudo $0"

CHANGED=0
run() { if (( DRY_RUN )); then printf '    [dry-run] %s\n' "$*"; else "$@"; fi; CHANGED=1; }
have() { command -v "$1" >/dev/null; }

# 1. Packages ---------------------------------------------------------------
log "Packages"
PKGS=(cups avahi-daemon avahi-utils printer-driver-brlaser curl)   # curl: verify.sh DOD-4
missing=()
for p in "${PKGS[@]}"; do
  # dpkg -s also succeeds for removed-but-not-purged ("rc") packages
  [[ "$(dpkg-query -W -f='${db:Status-Status}' "$p" 2>/dev/null)" == installed ]] || missing+=("$p")
done
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

for svc in cups avahi-daemon; do
  if ! systemctl is-enabled --quiet "$svc" 2>/dev/null || ! systemctl is-active --quiet "$svc"; then
    run systemctl enable --now "$svc"
  fi
done

# 2. Server settings: a single cupsctl call, only when something differs --------
log "Server settings (network: $NETWORK_ACCESS, remote admin: $REMOTE_ADMIN)"
want=(_share_printers=1 WebInterface=Yes "PreserveJobHistory=$JOB_HISTORY_SECONDS")
flags=(--share-printers WebInterface=Yes "PreserveJobHistory=$JOB_HISTORY_SECONDS")
if [[ $NETWORK_ACCESS == any ]]; then want+=(_remote_any=1); flags+=(--remote-any)
else                                  want+=(_remote_any=0); flags+=(--no-remote-any); fi
if [[ $REMOTE_ADMIN == yes ]]; then   want+=(_remote_admin=1); flags+=(--remote-admin)
else                                  want+=(_remote_admin=0); flags+=(--no-remote-admin); fi

current="$(have cupsctl && cupsctl 2>/dev/null || true)"
drift=0
for kv in "${want[@]}"; do grep -qixF "$kv" <<<"$current" || drift=1; done
if (( drift )); then
  run cupsctl "${flags[@]}"   # cupsd restarts itself to apply the new cupsd.conf
else
  ok "settings already match"
fi

# 3. Printer queue ----------------------------------------------------------
log "Queue '$PRINTER_NAME'"
DRY_PLACEHOLDER=0
if [[ -z "$DEVICE_URI" ]]; then
  if ! have lpinfo; then
    (( DRY_RUN )) || die "lpinfo not found: CUPS install failed?"
    printf '    [dry-run] would auto-detect the USB printer with lpinfo -v once CUPS is installed\n'
    DEVICE_URI="usb://<detected>" DRY_PLACEHOLDER=1
  else
    mapfile -t usb < <(lpinfo -v 2>/dev/null | awk '$2 ~ /^usb:\/\// {print $2}')
    (( ${#usb[@]} )) || die "no USB printer found by 'lpinfo -v'. Is it powered on? Check 'lsusb'."
    (( ${#usb[@]} == 1 )) || die "several USB printers found; set DEVICE_URI to one of: ${usb[*]}"
    DEVICE_URI="${usb[0]}"
    ok "detected $DEVICE_URI"
  fi
fi

if [[ "$PRINTER_MODEL" == auto ]]; then
  case "$DEVICE_URI" in
    ipp://*|ipps://*|dnssd://*) PRINTER_MODEL=everywhere ;;
    usb://*)
      if (( DRY_PLACEHOLDER )) || ! have lpinfo; then
        (( DRY_RUN )) || die "lpinfo not found: CUPS install failed?"
        PRINTER_MODEL="<brlaser PPD matching the printer>"
      else
        # Match the model in the URI (e.g. "HL-1110") against the available brlaser PPDs.
        model_hint="$(sed -E 's#^usb://[^/]+/([^?]+).*#\1#; s#%20# #g; s# series$##' <<<"$DEVICE_URI")"
        PRINTER_MODEL="$(lpinfo -m 2>/dev/null | grep -i brlaser | grep -iF -- "$model_hint" | awk '{print $1; exit}')" || true
        [[ -n "$PRINTER_MODEL" ]] || die "no brlaser PPD matches '$model_hint'. Set PRINTER_MODEL (see: lpinfo -m | grep -i brlaser)."
      fi ;;
    *) die "can't pick a driver for '$DEVICE_URI'. Set PRINTER_MODEL explicitly." ;;
  esac
  ok "model $PRINTER_MODEL"
fi

existing_uri="$(have lpstat && lpstat -v "$PRINTER_NAME" 2>/dev/null | awk '{print $NF}' || true)"
if [[ -z "$existing_uri" || $FORCE == 1 ]]; then
  run lpadmin -p "$PRINTER_NAME" -E -v "$DEVICE_URI" -m "$PRINTER_MODEL" \
    -o printer-is-shared=true -o media="$PAPER_SIZE"
elif [[ "$existing_uri" != "$DEVICE_URI" ]]; then
  die "queue '$PRINTER_NAME' already points at $existing_uri. Re-run with --force to replace it (resets its driver options)."
else
  ok "queue exists, keeping its driver options (use --force to recreate)"
  lpoptions -p "$PRINTER_NAME" | grep -q 'printer-is-shared=true' \
    || run lpadmin -p "$PRINTER_NAME" -o printer-is-shared=true
  lpstat -p "$PRINTER_NAME" | grep -q 'enabled since' || run cupsenable "$PRINTER_NAME"
  lpstat -a "$PRINTER_NAME" | awk -v p="$PRINTER_NAME" '$1==p && $2=="accepting" {f=1} END{exit !f}' \
    || run cupsaccept "$PRINTER_NAME"
fi
[[ "$(have lpstat && lpstat -d 2>/dev/null)" == *": $PRINTER_NAME" ]] || run lpadmin -d "$PRINTER_NAME"

# 4. Re-announce over Bonjour only if something changed ------------------------
if (( CHANGED && ! DRY_RUN )); then
  systemctl restart avahi-daemon
fi

if (( DRY_RUN )); then log "Dry run complete: nothing was changed."
elif (( CHANGED )); then log "Done. Next: ./scripts/verify.sh"
else log "Already in the desired state, nothing changed."; fi
