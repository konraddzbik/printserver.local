# Raspberry Pi AirPrint Server for Brother Printers (CUPS + Avahi)

Turn a Raspberry Pi 3 (or newer) into an AirPrint server for a USB Brother printer, so you can print from macOS, iPadOS, and iOS without installing any drivers on Apple devices.

Tested with: **Raspberry Pi 3 Model B**, **Raspberry Pi OS Lite (64-bit)**, **Brother HL-1110** (USB), CUPS 2.4.x.

---

## How it works

```
iPhone / iPad / Mac
        │  (AirPrint = IPP + Bonjour/mDNS)
        ▼
Raspberry Pi
 ├── avahi-daemon  → broadcasts the shared printer via Bonjour
 ├── CUPS          → print server, queue, filters
 └── brlaser       → open-source driver for host-based Brother printers
        │  (USB)
        ▼
Brother printer
```

Modern CUPS (2.x) advertises **shared** queues via DNS-SD automatically. No `airprint-generate`, no manual Avahi service files — those guides are outdated.

---

## 1. Flash the OS (headless)

Use [Raspberry Pi Imager](https://www.raspberrypi.com/software/):

1. **Choose OS** → *Raspberry Pi OS (other)* → **Raspberry Pi OS Lite (64-bit)** — no desktop needed for a print server, and the Pi 3's 1 GB RAM will thank you.
2. Open the **settings (gear icon)** before writing and set:
   - hostname (e.g. `printserver`)
   - enable SSH
   - username + password
   - Wi-Fi SSID, password, **and country code**
3. Write the card, boot the Pi, wait 2–3 minutes on first boot.

```bash
ssh <user>@printserver.local
```

> **Headless troubleshooting ("host unavailable"):**
> - First boot takes 2–3 min (filesystem resize) — be patient.
> - `.local` not resolving → find the IP in your router's DHCP list, or `arp -a` from your Mac.
> - Pi 3 is **2.4 GHz only**. A 5 GHz-only SSID (or aggressive band steering) means the Pi never joins.
> - Verify the Imager settings saved: the `bootfs` partition should contain `firstrun.sh` / `custom.toml`.
> - Fastest diagnostic: plug in Ethernet. If it appears, it's a Wi-Fi config problem.

Give the Pi a **static IP or DHCP reservation** — a print server that changes address is a print server that "randomly stops working".

## 2. Install CUPS, Avahi, and the Brother driver

```bash
sudo apt update
sudo apt install cups avahi-daemon printer-driver-brlaser
sudo usermod -aG lpadmin $USER
```

`brlaser` is the open-source driver covering most host-based Brother lasers (HL-1110, HL-L2300 series, DCP-1510/7030/7040, and more). If your Brother supports **IPP Everywhere / AirPrint natively** (most network models after ~2013), you won't need it — see step 4.

## 3. Open CUPS to the network

CUPS ships locked to localhost. Enable everything in **one** command — separate `cupsctl` invocations can silently reset earlier flags (I learned this the fun way when the web UI reported *"The web interface is currently disabled"*):

```bash
sudo cupsctl --remote-any --remote-admin --share-printers WebInterface=yes
sudo systemctl restart cups
```

Verify it actually listens on the network:

```bash
sudo ss -tlnp | grep 631
```

You want `*:631` or `0.0.0.0:631`. If you only see `127.0.0.1:631`, the config didn't take.

> **Security note:** `--remote-any` allows access from any network the Pi can see. On a home LAN behind NAT that's fine. On anything shared, restrict access in `/etc/cups/cupsd.conf` with `Allow @LOCAL` instead.

## 4. Add the printer

### Option A — web UI

1. Go to `https://<pi-ip>:631` (accept the self-signed cert warning; `http://` returns *426 Upgrade Required*).
2. **Administration → Add Printer** — log in with your SSH user (must be in `lpadmin`).
3. Your USB printer should be listed under *Local Printers*, e.g.
   `Brother HL-1110 series (Brother HL-1110 series)`.
4. Name it (no spaces or `/` `#`), and — **critical — check "Share This Printer"**. Unshared printers are invisible to AirPrint.
5. Pick the driver:
   - Host-based models (HL-1110 etc.): **Brother HL-1110 series, using brlaser**
   - Modern IPP-capable printers: **IPP Everywhere** (driverless — prefer this when available)
6. Set defaults (A4, duplex if applicable) and finish.

### Option B — command line

```bash
lpinfo -v                      # list detected device URIs
sudo lpadmin -p Brother -E \
  -v "usb://Brother/HL-1110%20series?serial=XXXXXXX" \
  -m drv:///brlaser.drv/br1110.ppd \
  -o printer-is-shared=true
sudo lpadmin -d Brother        # set as default
```

For driverless printers, replace `-m drv:///...` with `-m everywhere`.

> If the web UI's Add Printer page skips straight to a manual *Connection:* URI field (sometimes with garbage pre-filled), CUPS detected nothing. Check `lpinfo -v` and `lsusb` — printer off, sleeping, or a bad cable are the usual suspects.

## 5. Verify

```bash
# Services up?
systemctl status cups avahi-daemon

# Queue healthy?
lpstat -t                      # want: "printer Brother is idle. enabled"

# AirPrint actually broadcast?
avahi-browse -rt _ipp._tcp     # your printer must appear here

# Test print from the Pi
echo "Hello from CUPS" | lp -d Brother
```

Then grab your iPhone → any app → Share → Print. The printer appears within seconds as `Brother @ printserver`.

## Troubleshooting

| Symptom | Cause / fix |
|---|---|
| iOS doesn't list the printer | Printer not **shared**; or client (AP) isolation on Wi-Fi blocks mDNS — common on guest networks and some mesh setups |
| Printer listed but jobs fail | Wrong driver; for Brother host-based models use `brlaser`, not the generic PCL ones |
| Worked yesterday, gone today | Pi got a new IP — set a DHCP reservation; or restart `avahi-daemon` |
| `lpstat` shows `disabled`/`paused` | `sudo cupsenable Brother && sudo cupsaccept Brother` |
| Web UI: "Web interface is currently disabled" | `sudo cupsctl WebInterface=yes && sudo systemctl restart cups` |
| 403 on Administration pages | Missing `--remote-admin`, or user not in `lpadmin` |
| Nothing in `lpinfo -v` | Check `lsusb`; wake the printer; try another cable/port |

## Optional hardening & maintenance

```bash
# Keep the queue from silently accumulating dead jobs
sudo cupsctl PreserveJobHistory=no

# Unattended security updates
sudo apt install unattended-upgrades
```

CUPS logs live in `/var/log/cups/error_log` — bump `LogLevel debug` in `cupsd.conf` when debugging, and turn it back off after (SD cards don't love verbose logging).

## License

MIT — use, share, adapt.
