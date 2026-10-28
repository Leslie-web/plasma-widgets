#!/usr/bin/env bash
# Capture store screenshots: the same two widgets against five stock wallpapers.
#
# The point of the listing images is the one thing a still can show well: the
# text colour follows the wallpaper behind each block. So each shot changes the
# wallpaper and nothing else.
#
# The wallpaper is switched by writing the containment config with the shell
# stopped. Doing it through evaluateScript() while the shell runs rewrote the
# *slideshow* group's Image key (currentConfigGroup is applied asynchronously),
# which silently destroyed the user's setting. Do not "simplify" this back.
#
# Restores the slideshow on exit, including on failure.
set -euo pipefail

cd "$(dirname "$0")"
OUT="screenshots"
mkdir -p "$OUT"

CONF="$HOME/.config/plasma-org.kde.plasma.desktop-appletsrc"
GROUP_ARGS=(--file plasma-org.kde.plasma.desktop-appletsrc --group Containments --group 28)

SAVED_IMAGE=$(awk '/^\[Containments\]\[28\]\[Wallpaper\]\[org.kde.slideshow\]\[General\]/{f=1;next} f&&/^\[/{f=0} f&&/^Image=/{sub("Image=","");print;exit}' "$CONF")
echo "saved slideshow image: $SAVED_IMAGE"
[ -n "$SAVED_IMAGE" ] || { echo "could not read the current wallpaper; refusing to touch it" >&2; exit 1; }

restore() {
    set +e
    systemctl --user stop plasma-plasmashell
    kwriteconfig6 "${GROUP_ARGS[@]}" --key wallpaperplugin org.kde.slideshow
    kwriteconfig6 "${GROUP_ARGS[@]}" --group Wallpaper --group org.kde.slideshow --group General \
        --key Image "$SAVED_IMAGE"
    # five restarts in a row trips StartLimitBurst; clear the counter
    systemctl --user reset-failed plasma-plasmashell 2>/dev/null || true
    systemctl --user start plasma-plasmashell
    sleep 6
    echo "restored slideshow wallpaper"
}
trap restore EXIT

use_wallpaper() {
    systemctl --user stop plasma-plasmashell
    kwriteconfig6 "${GROUP_ARGS[@]}" --key wallpaperplugin org.kde.image
    kwriteconfig6 "${GROUP_ARGS[@]}" --group Wallpaper --group org.kde.image --group General \
        --key Image "file://$1"
    systemctl --user reset-failed plasma-plasmashell 2>/dev/null || true
    systemctl --user start plasma-plasmashell
    # the applet's probe re-reads the wallpaper once per cycle; let it settle
    sleep 10
}

minimise() {
    cat > /tmp/_kshot_min.js <<'JS'
const list = workspace.windowList();
for (const w of list) { try { if (w.normalWindow) w.minimized = true; } catch (e) {} }
JS
    qdbus org.kde.KWin /Scripting org.kde.kwin.Scripting.loadScript /tmp/_kshot_min.js >/dev/null
    qdbus org.kde.KWin /Scripting org.kde.kwin.Scripting.start >/dev/null
}

unminimise() {
    cat > /tmp/_kshot_restore.js <<'JS'
const list = workspace.windowList();
for (const w of list) { try { if (w.normalWindow) w.minimized = false; } catch (e) {} }
JS
    qdbus org.kde.KWin /Scripting org.kde.kwin.Scripting.loadScript /tmp/_kshot_restore.js >/dev/null
    qdbus org.kde.KWin /Scripting org.kde.kwin.Scripting.start >/dev/null
}

# Crops are derived from the live applet geometry. Hardcoding them is what made
# the first pass capture the wrong widget after the layout moved.
geometry_of() {
    qdbus org.kde.plasmashell /PlasmaShell org.kde.PlasmaShell.evaluateScript "
      var ds = desktops();
      for (var i = 0; i < ds.length; ++i) {
        var ws = ds[i].widgetIds;
        for (var j = 0; j < ws.length; ++j) {
          var w = ds[i].widgetById(ws[j]);
          if (w && String(w.type) === 'org.leslie.$1') {
            var g = w.geometry;
            print(g.x + ',' + g.y + ',' + g.width + ',' + g.height);
          }
        }
      }"
}

# "x,y,w,h" -> spectacle crop geometry with margin, clamped to the 1920x1080 screen
crop_for() {
    local margin=80
    awk -F, -v m="$margin" '{
        x = $1 - m; y = $2 - m; w = $3 + 2 * m; h = $4 + 2 * m
        if (x < 0) { w += x; x = 0 }
        if (y < 0) { h += y; y = 0 }
        if (x + w > 1920) w = 1920 - x
        if (y + h > 1080) h = 1080 - y
        printf "%dx%d+%d+%d", w, h, x, y
    }' <<< "$1"
}

shot() {
    local tag="$1" geometry="$2"
    minimise; sleep 1.2
    spectacle -b -n -o "/tmp/_kshot_full.png" >/dev/null 2>&1
    unminimise
    magick "/tmp/_kshot_full.png" -crop "$geometry" +repage "$OUT/$tag.png"
    echo "  $OUT/$tag.png ($geometry)"
}

WALLS=(
  "01-autumn:/usr/share/wallpapers/Autumn/contents/images/2560x1600.jpg"
  "02-cluster:/usr/share/wallpapers/Cluster/contents/images/3840x2160.png"
  "03-altai:/usr/share/wallpapers/Altai/contents/images/5120x2880.png"
  "04-by-the-water:/usr/share/wallpapers/BytheWater/contents/images/2560x1600.jpg"
  "05-coast:/usr/share/wallpapers/Coast/contents/images/7680x2160.png"
)

for entry in "${WALLS[@]}"; do
    name="${entry%%:*}"; path="${entry#*:}"
    # ONLY=03 lets a single wallpaper be re-shot without redoing the rest
    if [[ -n "${ONLY:-}" && "$name" != *"$ONLY"* ]]; then continue; fi
    echo "$name"
    use_wallpaper "$path"
    CLOCK_CROP=$(crop_for "$(geometry_of clock)")
    MUSIC_CROP=$(crop_for "$(geometry_of nowplaying)")
    shot "clock-$name"      "$CLOCK_CROP"
    shot "nowplaying-$name" "$MUSIC_CROP"
done
