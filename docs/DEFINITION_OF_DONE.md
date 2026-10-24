# Definition of Done — AirPrint print server

The server is **done** when every *required* item below holds. Items `DOD-1…DOD-10` (and `DOD-11` when enabled) are checked automatically by [`scripts/verify.sh`](../scripts/verify.sh), which is the source of truth: CI (`scripts/check-dod-sync.sh`) fails if this table and the script disagree. The rest need a human.

## Automated (`scripts/verify.sh`)

| ID | Requirement | How it's checked | If it fails |
|---|---|---|---|
| DOD-1 | CUPS is running | `systemctl is-active cups` | `sudo systemctl enable --now cups` |
| DOD-2 | Avahi is running | `systemctl is-active avahi-daemon` | `sudo systemctl enable --now avahi-daemon` |
| DOD-3 | CUPS listens on the LAN | `ss -tln` shows `*:631` / `0.0.0.0:631` / `[::]:631` | Re-run `setup.sh`. Only `127.0.0.1:631` means `cupsctl` didn't apply |
| DOD-4 | Web UI enabled | `https://localhost:631/printers/` answers and isn't the "web interface is currently disabled" page (that page is also HTTP 200) | Re-run `setup.sh` (sets `WebInterface=Yes`) |
| DOD-5 | Queue exists and is enabled | `lpstat -p $PRINTER_NAME` shows `enabled since` | `sudo cupsenable $PRINTER_NAME` |
| DOD-6 | Queue accepts jobs | `lpstat -a`: second field is `accepting` (not `not accepting`) | `sudo cupsaccept $PRINTER_NAME` |
| DOD-7 | Queue is shared | `lpoptions -p` → `printer-is-shared=true` | `sudo lpadmin -p $PRINTER_NAME -o printer-is-shared=true` |
| DOD-8 | Queue is the default | `lpstat -d` | `sudo lpadmin -d $PRINTER_NAME` |
| DOD-9 | Advertised via Bonjour | `avahi-browse -rtp _ipp._tcp` has a record from **this host's** address with TXT `rp=printers/$PRINTER_NAME` | Check sharing (DOD-7), then `sudo systemctl restart avahi-daemon` |
| DOD-10 | AirPrint-compatible TXT record | That same record contains `URF=` | Wrong/old driver. Use `brlaser` or `everywhere` |
| DOD-11 | *(opt-in, `PRINT_TEST_PAGE=1` env only, uses paper)* Test page completes | `lp` job appears in `lpstat -W completed` within 60 s (`setup.sh` keeps job history for 1 h) | Check `/var/log/cups/error_log`, driver, paper, cable. `PreserveJobHistory=No` makes this check fail |

## Manual

| ID | Requirement | Who |
|---|---|---|
| DOD-M1 | Pi has a static IP or DHCP reservation | User confirms in router |
| DOD-M2 | An iPhone/iPad/Mac lists `<PRINTER_NAME> @ <hostname>` and a page prints | User |
| DOD-M3 | No secrets or `config/printserver.env` committed | Agent: `git ls-files --error-unmatch config/printserver.env` must fail |

## Evidence the agent must report

1. `./scripts/verify.sh --json` output, with `"failed":0`
2. Queue name, device URI, driver/model
3. DOD-M1…M3 status (confirmed / not confirmed / not applicable, with the reason)
