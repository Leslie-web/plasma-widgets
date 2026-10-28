#!/usr/bin/env python3
"""Generate the two store/applet marks from the widgets' own palette.

Deliberately plain: a dark tile from the widget's dark ramp, one light tone for
the mark, no gradients, no shadows. That is the same rule the applets follow,
so the artwork cannot drift away from what the widget looks like.

Fonts: Inter only (SIL OFL, redistributable). The Anurati font the clock can use
is free for personal use but cannot be committed, so it is not used here.

    python3 artwork/make-logos.py
"""

from __future__ import annotations

import math
import pathlib
import subprocess

OUT = pathlib.Path(__file__).resolve().parent

DARKEST = "#0f1115"   # dark ramp tone 0
LIGHTEST = "#fcfdff"  # light ramp tone 0
MID = "#adb4bf"       # light ramp tone 3
RULE = "#585f6a"      # dark ramp tone 3

SANS = "Inter, 'Inter Display', 'DejaVu Sans'"

HEAD = """<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 512 512" width="512" height="512">
  <rect x="48" y="48" width="416" height="416" rx="104" fill="{dark}"/>
"""


def clock_svg() -> str:
    return HEAD.format(dark=DARKEST) + f"""  <text x="256" y="292" text-anchor="middle"
        font-family="{SANS}" font-weight="800" font-size="184"
        letter-spacing="-6" fill="{LIGHTEST}">27</text>
  <rect x="176" y="330" width="160" height="3" fill="{RULE}"/>
  <text x="256" y="382" text-anchor="middle"
        font-family="{SANS}" font-weight="600" font-size="36"
        letter-spacing="12" fill="{MID}">OCT</text>
</svg>
"""


def band_path() -> str:
    """A mirrored spectrum band: the same shape the applet draws.

    Analytic rather than hand-drawn so the humps stay symmetric about y=256,
    which is what makes it read as the waveform and not as a bar chart.
    """
    middle = 256.0
    left, right = 84.0, 428.0
    steps = 96

    def envelope(x: float) -> float:
        t = (x - left) / (right - left)
        peaks = ((0.10, 0.055, 0.52), (0.30, 0.060, 0.78),
                 (0.50, 0.055, 1.00), (0.70, 0.060, 0.66),
                 (0.90, 0.055, 0.40))
        return sum(weight * math.exp(-((t - centre) / width) ** 2)
                   for centre, width, weight in peaks) + 0.06

    top, bottom = [], []
    for index in range(steps + 1):
        x = left + (right - left) * index / steps
        amplitude = 88.0 * min(1.0, envelope(x) / 1.06)
        top.append((x, middle - amplitude))
        bottom.append((x, middle + amplitude))

    points = [f"M{top[0][0]:.1f},{top[0][1]:.1f}"]
    points += [f"L{x:.1f},{y:.1f}" for x, y in top[1:]]
    points += [f"L{x:.1f},{y:.1f}" for x, y in reversed(bottom)]
    points.append("Z")
    return " ".join(points)


def now_playing_svg() -> str:
    return HEAD.format(dark=DARKEST) + f"""  <path d="{band_path()}"
        fill="{MID}" fill-opacity="0.38"
        stroke="{LIGHTEST}" stroke-width="7" stroke-linejoin="round"/>
</svg>
"""


def rasterise(svg: pathlib.Path) -> None:
    """PNG at the two sizes the store and the widget explorer want."""
    for size in (512, 256):
        target = svg.with_name(f"{svg.stem}-{size}.png")
        subprocess.run(
            ["magick", "-background", "none", str(svg), "-resize", f"{size}x{size}", str(target)],
            check=True,
        )
        print(f"wrote {target.name}")


def main() -> None:
    for name, body in (("logo-clock", clock_svg()), ("logo-nowplaying", now_playing_svg())):
        path = OUT / f"{name}.svg"
        path.write_text(body)
        print(f"wrote {path.name}")
        rasterise(path)


if __name__ == "__main__":
    main()
