# Definition of Done — AirPrint print server

The server is **done** when every *required* item below holds. Items `DOD-1…DOD-10` (and `DOD-11` when enabled) are checked automatically by [`scripts/verify.sh`](../scripts/verify.sh). The rest need a human.

## Automated (`scripts/verify.sh`)

| ID | Requirement | How it's checked | If it fails |
|---|---|---|---|
| DOD-1 | CUPS is running | `systemctl is-active cups` | `sudo systemctl enable --now cups` |
| DOD-2 | Avahi is running | `systemctl is-active avahi-daemon` | `sudo systemctl enable --now avahi-daemon` |
| DOD-3 | CUPS listens on the LAN | `ss -tln` shows `*:631` / `0.0.0.0:631` | Re-run `setup.sh`. Only `127.0.0.1:631` means `cupsctl` didn't apply |
| DOD-4 | Web UI reachable | `curl -k https://localhost:631/` → `200` | `sudo cupsctl WebInterface=yes` |
| DOD-5 | Queue exists and is enabled | `lpstat -p $PRINTER_NAME` | `sudo cupsenable $PRINTER_NAME` |
| DOD-6 | Queue accepts jobs | `lpstat -a $PRINTER_NAME` | `sudo cupsaccept $PRINTER_NAME` |
| DOD-7 | Queue is shared | `lpoptions -p` → `printer-is-shared=true` | `sudo lpadmin -p $PRINTER_NAME -o printer-is-shared=true` |
| DOD-8 | Queue is the default | `lpstat -d` | `sudo lpadmin -d $PRINTER_NAME` |
| DOD-9 | Advertised via Bonjour | `avahi-browse -rt _ipp._tcp` lists the queue | Check sharing (DOD-7), then `sudo systemctl restart avahi-daemon` |
| DOD-10 | AirPrint-compatible TXT record | `_ipp._tcp` record contains `URF=` | Wrong/old driver. Use `brlaser` or `everywhere` |
| DOD-11 | *(opt-in)* Test page completes | `lp` job reaches `completed` within 60 s | Check `/var/log/cups/error_log`, driver, paper, cable |

## Manual

| ID | Requirement | Who |
|---|---|---|
| DOD-M1 | Pi has a static IP or DHCP reservation | User confirms in router |
| DOD-M2 | An iPhone/iPad/Mac lists `<PRINTER_NAME> @ <hostname>` and a page prints | User |
| DOD-M3 | No secrets or `config/printserver.env` committed | Agent (`git status`) |

## Evidence the agent must report

1. `./scripts/verify.sh --json` output, with `"failed":0`
2. Queue name, device URI, driver/model
3. DOD-M1…M3 status (confirmed / not confirmed / not applicable, with the reason)
