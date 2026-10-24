"""Render the README GIFs. Usage: pip install -r assets/src/requirements.txt && python3 assets/src/make_gifs.py"""
import re
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

OUT = Path(__file__).resolve().parent.parent
W, H = 880, 440
BG, CARD, LINE = "#0d1117", "#161b22", "#30363d"
FG, DIM = "#e6edf3", "#7d8590"
CYAN, GREEN, RED, AMBER, VIOLET = "#39c5cf", "#3fb950", "#f85149", "#d29922", "#a371f7"


def font(size, mono=False):
    candidates = (
        ["/System/Library/Fonts/Menlo.ttc", "/usr/share/fonts/truetype/dejavu/DejaVuSansMono.ttf"]
        if mono
        else ["/System/Library/Fonts/SFNS.ttf", "/System/Library/Fonts/Helvetica.ttc",
              "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf"]
    )
    for path in candidates:
        try:
            return ImageFont.truetype(path, size)
        except OSError:
            continue
    return ImageFont.load_default(size)


def canvas():
    img = Image.new("RGB", (W, H), BG)
    return img, ImageDraw.Draw(img)


def save(frames, durations, name):
    frames = [f.convert("P", palette=Image.Palette.ADAPTIVE, colors=64) for f in frames]
    frames[0].save(OUT / name, save_all=True, append_images=frames[1:], duration=durations,
                   loop=0, optimize=True, disposal=2)
    print(f"wrote {OUT / name} ({(OUT / name).stat().st_size // 1024} KB, {len(frames)} frames)")


def box(d, xy, title, sub, color, active):
    x0, y0, x1, y1 = xy
    d.rounded_rectangle(xy, 14, fill=CARD, outline=color if active else LINE, width=3 if active else 2)
    d.text(((x0 + x1) / 2, y0 + 30), title, font=font(20), fill=FG if active else DIM, anchor="mm")
    for i, line in enumerate(sub):
        d.text(((x0 + x1) / 2, y0 + 58 + i * 20), line, font=font(13, True), fill=color if active else DIM,
               anchor="mm")


# 1. Architecture: a print job travels iPhone → Pi → printer -------------------
def architecture():
    nodes = [
        ((40, 150, 230, 290), "iPhone / Mac", ["Share → Print", "no drivers"], CYAN),
        ((345, 110, 595, 330), "Raspberry Pi", ["avahi  · Bonjour", "CUPS   · queue", "brlaser · driver"],
         VIOLET),
        ((710, 150, 850, 290), "Brother", ["USB laser"], GREEN),
    ]
    legs = [((230, 220), (345, 220), "IPP + mDNS"), ((595, 220), (710, 220), "USB")]
    frames, durs = [], []
    steps = 48
    for t in range(steps + 14):
        img, d = canvas()
        d.text((W / 2, 40), "How a page gets printed", font=font(26), fill=FG, anchor="mm")
        phase = min(t / steps, 1.0)
        active = 0 if phase < 0.25 else 1 if phase < 0.75 else 2
        for i, (xy, title, sub, col) in enumerate(nodes):
            box(d, xy, title, sub, col, i == active or t >= steps)
        for (a, b, label) in legs:
            d.line([a, b], fill=LINE, width=3)
            d.text(((a[0] + b[0]) / 2, a[1] - 34), label, font=font(12, True), fill=DIM, anchor="mm")
        # the travelling packet
        if t < steps:
            if phase < 0.5:
                (a, b, _), p = legs[0], phase / 0.5
            else:
                (a, b, _), p = legs[1], (phase - 0.5) / 0.5
            x = a[0] + (b[0] - a[0]) * p
            d.rounded_rectangle((x - 12, 206, x + 12, 234), 3, fill=FG)
            for k in range(3):
                d.line((x - 7, 213 + k * 6, x + 7, 213 + k * 6), fill=BG, width=2)
        else:  # page comes out of the printer
            rise = min((t - steps) * 6, 60)
            d.rounded_rectangle((760, 290 + 60 - rise, 800, 350 + 60 - rise), 3, fill=FG)
            d.text((W / 2, 395), "printed: no client drivers, no cloud", font=font(18), fill=GREEN,
                   anchor="mm")
        frames.append(img)
        durs.append(60)
    durs[-1] = 1800
    save(frames, durs, "architecture.gif")


# 2. Agent workflow: phases with exit gates -----------------------------------
PHASES = [
    ("0", "Recon", "ssh · lsusb · lpinfo -v"),
    ("1", "Configure", "printserver.env"),
    ("2", "Provision", "setup.sh (idempotent)"),
    ("3", "Verify", "verify.sh → DoD"),
    ("4", "Client check", "human prints from iOS"),
    ("5", "Report", "evidence + JSON"),
]


def workflow():
    frames, durs = [], []
    cw, gap, top = 128, 12, 150
    left = (W - (cw * 6 + gap * 5)) / 2
    for step in range(len(PHASES) * 3 + 2):
        current = step // 3
        img, d = canvas()
        d.text((W / 2, 45), "Agent workflow, gated by a Definition of Done", font=font(24), fill=FG,
               anchor="mm")
        d.text((W / 2, 78), "AGENTS.md  ·  provisioner → verifier subagents  ·  /provision-printserver",
               font=font(13, True), fill=DIM, anchor="mm")
        for i, (num, name, sub) in enumerate(PHASES):
            x0 = left + i * (cw + gap)
            done, now = i < current, i == current
            col = GREEN if done else CYAN if now else LINE
            d.rounded_rectangle((x0, top, x0 + cw, top + 150), 12, fill=CARD, outline=col,
                                width=3 if (done or now) else 2)
            d.ellipse((x0 + cw / 2 - 18, top + 18, x0 + cw / 2 + 18, top + 54), fill=col if (done or now) else CARD,
                      outline=col, width=2)
            d.text((x0 + cw / 2, top + 36), "✓" if done else num, font=font(18, True),
                   fill=BG if (done or now) else DIM, anchor="mm")
            d.text((x0 + cw / 2, top + 80), name, font=font(16), fill=FG if (done or now) else DIM, anchor="mm")
            words, lines, cur = sub.split(), [], ""
            for w in words:
                if len(cur + " " + w) > 15:
                    lines.append(cur)
                    cur = w
                else:
                    cur = (cur + " " + w).strip()
            lines.append(cur)
            for j, ln in enumerate(lines):
                d.text((x0 + cw / 2, top + 106 + j * 16), ln, font=font(11, True), fill=DIM, anchor="mm")
            if i < 5:
                d.text((x0 + cw + gap / 2, top + 75), "›", font=font(20), fill=GREEN if done else LINE, anchor="mm")
        if current >= len(PHASES):
            d.text((W / 2, 370), f"VERDICT: DONE   {len(CHECKS)}/{len(CHECKS)} automated · client confirmed", font=font(18, True),
                   fill=GREEN, anchor="mm")
        elif step % 3 == 2:
            d.text((W / 2, 370), f"gate {PHASES[current][0]} passed ✓", font=font(16, True), fill=GREEN, anchor="mm")
        else:
            d.text((W / 2, 370), f"running phase {PHASES[current][0]}: {PHASES[current][1].lower()}…",
                   font=font(16, True), fill=CYAN, anchor="mm")
        frames.append(img)
        durs.append(450)
    durs[-1] = 2500
    save(frames, durs, "agent-workflow.gif")


# 3. verify.sh in a terminal --------------------------------------------------
def load_checks():
    """Read the always-on checks from scripts/verify.sh, the source of truth."""
    src = (OUT.parent / "scripts" / "verify.sh").read_text()
    return re.findall(r'^check (DOD-\d+) "([^"]+)"', src, flags=re.M)


CHECKS = load_checks()


def terminal():
    mono, lh = font(15, True), 24
    cmd = "./scripts/verify.sh"
    frames, durs = [], []

    def frame(typed, shown, summary=False, cursor=True):
        img, d = canvas()
        d.rounded_rectangle((20, 20, W - 20, H - 20), 12, fill=CARD, outline=LINE, width=2)
        for i, c in enumerate((RED, AMBER, GREEN)):
            d.ellipse((40 + i * 22, 36, 54 + i * 22, 50), fill=c)
        d.text((W / 2, 43), "pi@printserver: ~/printserver.local", font=font(13, True), fill=DIM, anchor="mm")
        y = 70
        d.text((40, y), "$ ", font=mono, fill=GREEN)
        d.text((60, y), typed, font=mono, fill=FG)
        if cursor and not shown:
            d.rectangle((60 + d.textlength(typed, font=mono), y + 2, 69 + d.textlength(typed, font=mono), y + 18),
                        fill=FG)
        if shown or summary:
            y += lh
            d.text((40, y), "==> Verifying print server (queue: Brother)", font=mono, fill=CYAN)
        for cid, desc in CHECKS[:shown]:
            y += lh
            d.text((48, y), "✓", font=mono, fill=GREEN)
            d.text((72, y), f"{cid:<7}{desc}", font=mono, fill=FG)
        if summary:
            y += lh * 1.5
            d.text((48, y), f"{len(CHECKS)} passed, 0 failed", font=mono, fill=GREEN)
        d.text((W - 36, H - 34), "illustrative output", font=font(11, True), fill=DIM, anchor="rm")
        return img

    for blink in range(3):
        frames.append(frame("", 0, cursor=blink % 2 == 0))
        durs.append(350)
    for i in range(1, len(cmd) + 1):
        frames.append(frame(cmd[:i], 0))
        durs.append(55)
    for n in range(1, len(CHECKS) + 1):
        frames.append(frame(cmd, n))
        durs.append(220)
    frames.append(frame(cmd, len(CHECKS), summary=True))
    durs.append(3000)
    save(frames, durs, "verify.gif")


if __name__ == "__main__":
    architecture()
    workflow()
    terminal()
