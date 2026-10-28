# Plasma widgets

Two Plasma 6 applets. Both sit straight on the wallpaper (no background panel)
and pick their text colour from the wallpaper behind each block, so they stay
readable across a slideshow instead of assuming a light or dark desktop.

| Package | Name | What it does |
|---|---|---|
| `org.leslie.clock` | Day & Date | Weekday, date and clock |
| `org.leslie.nowplaying` | Now Playing | Track, artist, transport controls, live cava spectrum |

## Requirements

- Plasma 6
- **Now Playing only:** `cava` for the waveform. The helper that bridges cava to
  the applet is bundled in `contents/code/` and starts by itself on first
  playback; it needs `python3` (standard library only, no pip packages).
  Without cava the widget still shows track and transport, and the waveform
  strip says so.

## Install

```bash
kpackagetool6 --type Plasma/Applet --install org.leslie.clock.tar.gz
```

Build an archive from a package directory (a top-level directory inside the
archive, or the `.plasmoid` extension, both fail to install on KF6):

```bash
tar -czf org.leslie.clock.tar.gz -C org.leslie.clock metadata.json LICENSE contents
```

Restart the shell after changing an installed applet:

```bash
systemctl --user restart plasma-plasmashell
```

## Licence

MIT, see `LICENSE` in each package.
