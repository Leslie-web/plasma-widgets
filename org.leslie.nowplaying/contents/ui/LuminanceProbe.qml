import QtQuick
import QtQuick.Window

import org.kde.plasma.plasma5support as P5Support

// Samples the wallpaper behind the widget and reports the brightness
// distribution of the horizontal bands the text sits in, so each block can pick
// tones that are readable on its own backdrop.
//
// A single average was the wrong tool twice over. It cannot describe a wall that
// is half white and half black, and even a faithful histogram of the whole box
// says nothing about the band the text sits on: on one wallpaper the track line
// sat on dark red while the transport row sat on bright cream, so one colour had
// to fail somewhere. Each block now measures its own band.
Item {
    id: root

    visible: false
    width: 1
    height: 1

    // The item whose on-screen rectangle is sampled.
    property Item target: null

    // The applet this probe belongs to; used to find the wallpaper of *its*
    // containment, which matters when two screens run independent slideshows.
    property int appletId: -1

    // Horizontal slices of the widget, as fractions of its height: the track
    // block and the transport row. The waveform strip between them carries no
    // text and is deliberately skipped. The applet overrides this with the
    // real item positions once the layout has a height.
    property var bandRanges: [[0.0, 0.40], [0.80, 1.0]]

    // One entry per band: { mean, dark, p10, p50, p90, histogram[] }.
    property var bands: []
    property bool ready: bands.length > 0

    // Whole-area values, kept for the tooltip and for debugging.
    property real luminance: -1
    property real darkFraction: -1
    property real ambiguity: 0
    property string probeInfo: ""
    property int attempts: 0

    // "waiting" until the probe has an answer, then "ok", "no-wallpaper" (the
    // command named an image that never loaded) or "command-failed" (nothing
    // came back, e.g. a wallpaper plugin with no file behind it).
    property string probeState: "waiting"
    property bool sawOutput: false

    // The wallpaper currently on screen. Reading `Image=` from appletsrc is not
    // enough: a slideshow advances without writing the new frame back, so the
    // config kept describing an image the desktop had long moved past and the
    // text was coloured for the wrong picture. PlasmaShell.wallpaper(screen)
    // reports the live frame, and the screen index comes from the containment
    // this applet lives in, so a second screen with its own slideshow cannot be
    // sampled by mistake. The config entry stays as a last resort.
    readonly property string imageCommand: {
        const conf = "conf=\"$HOME/.config/plasma-org.kde.plasma.desktop-appletsrc\""
        const containment = "cont=$(awk -v app=" + root.appletId + " -F'[][]' '"
            + "/^\\[Containments\\]\\[[0-9]+\\]$/ { c=$4; next } "
            + "/^\\[Containments\\]\\[[0-9]+\\]\\[Applets\\]\\[[0-9]+\\]/ { if ($8 == app) m=c; next } "
            + "END { print m }' \"$conf\")"
        const screen = "idx=$(qdbus org.kde.plasmashell /PlasmaShell org.kde.PlasmaShell.evaluateScript "
            + "\"var d=desktops();var r=-1;for(var i=0;i<d.length;++i){if(d[i].id==$cont)r=i}print(r)\" 2>/dev/null)"
        const live = "url=$(qdbus org.kde.plasmashell /PlasmaShell org.kde.PlasmaShell.wallpaper ${idx:--1} 2>/dev/null "
            + "| sed -n 's/^Image: //p')"
        const fallback = "[ -n \"$url\" ] || url=$(grep -m1 '^Image=file://' \"$conf\" | cut -d= -f2-)"
        const emit = "; printf '%s' \"$url\""
        return conf + "; " + containment + "; " + screen + "; " + live + "; " + fallback + emit
    }

    P5Support.DataSource {
        id: configSource
        engine: "executable"
        connectedSources: [root.imageCommand]
        // A slideshow changes the image behind our back; re-read often enough
        // that the text cannot stay the wrong colour for long.
        interval: 10000

        onNewData: (sourceName, data) => {
            const found = String(data["stdout"] || "").trim()
            root.sawOutput = found.length > 0
            if (found.length > 0 && found !== String(wallpaper.source)) {
                // The new frame may not be drawable yet; give it the full
                // retry budget again.
                root.attempts = 0
                wallpaper.source = found
                sampler.requestPaint()
            }
        }
    }

    // Kept only for its natural size, which is needed to map screen
    // coordinates onto the image. The canvas draws the URL itself: a hidden
    // Image hands drawImage() no pixels.
    Image {
        id: wallpaper
        visible: false
        asynchronous: true
        cache: false
        onStatusChanged: {
            if (status === Image.Ready)
                sampler.requestPaint()
        }
    }

    readonly property string wallpaperSource: wallpaper.source

    // A canvas is the only way to read pixels back in QML. It paints into an
    // offscreen buffer, so keeping it transparent is enough to hide it.
    Canvas {
        id: sampler

        width: 64
        height: 40
        opacity: 0
        renderStrategy: Canvas.Cooperative

        onPaint: root.measure()
        onImageLoaded: requestPaint()
    }

    Timer {
        interval: 30000
        running: true
        repeat: true
        onTriggered: sampler.requestPaint()
    }

    Timer {
        id: retry
        interval: 400
        repeat: false
        onTriggered: sampler.requestPaint()
    }

    // If nothing has arrived after a few seconds, settle on a verdict. Waiting
    // forever meant the applet kept a light-text guess alive on a machine where
    // the wallpaper cannot be read at all.
    Timer {
        interval: 8000
        running: true
        repeat: false
        onTriggered: {
            if (root.bands.length > 0)
                root.probeState = "ok"
            else
                root.probeState = root.sawOutput ? "no-wallpaper" : "command-failed"
        }
    }

    // The sample is tied to the widget's on-screen rectangle, so a move or a
    // resize invalidates it.
    Timer {
        id: geometryDebounce
        interval: 250
        repeat: false
        onTriggered: sampler.requestPaint()
    }

    Connections {
        target: root.target
        ignoreUnknownSignals: true
        function onXChanged() { geometryDebounce.restart() }
        function onYChanged() { geometryDebounce.restart() }
        function onWidthChanged() { geometryDebounce.restart() }
        function onHeightChanged() { geometryDebounce.restart() }
    }

    function linear(channel) {
        return channel <= 0.04045 ? channel / 12.92 : Math.pow((channel + 0.055) / 1.055, 2.4)
    }

    // Bucket centre of the requested percentile, from a 32-bin histogram.
    function percentile(buckets, total, fraction) {
        const wanted = total * fraction
        let seen = 0
        for (let index = 0; index < buckets.length; ++index) {
            seen += buckets[index]
            if (seen >= wanted)
                return (index + 0.5) / buckets.length
        }
        return 1
    }

    function measure() {
        if (wallpaper.status !== Image.Ready)
            return

        const item = root.target !== null ? root.target : root

        const imageWidth = wallpaper.sourceSize.width
        const imageHeight = wallpaper.sourceSize.height
        if (imageWidth <= 0 || imageHeight <= 0)
            return

        const context = sampler.getContext("2d")
        context.clearRect(0, 0, sampler.width, sampler.height)

        // Where this item sits on its screen (desktop applets live in the
        // screen-sized containment view, so null maps to screen coordinates).
        const origin = item.mapToItem(null, 0, 0)
        const screenWidth = Screen.width
        const screenHeight = Screen.height

        // Plasma draws the wallpaper with "Fill" (cover) and centres it.
        const scale = Math.max(screenWidth / imageWidth, screenHeight / imageHeight)
        const offsetX = (imageWidth * scale - screenWidth) / 2
        const offsetY = (imageHeight * scale - screenHeight) / 2

        const sourceX = Math.max(0, (offsetX + origin.x) / scale)
        const sourceY = Math.max(0, (offsetY + origin.y) / scale)
        const sourceW = Math.min(imageWidth - sourceX, item.width / scale)
        const sourceH = Math.min(imageHeight - sourceY, item.height / scale)

        if (sourceW <= 1 || sourceH <= 1)
            return

        context.drawImage(root.wallpaperSource, sourceX, sourceY, sourceW, sourceH,
                          0, 0, sampler.width, sampler.height)

        const pixels = context.getImageData(0, 0, sampler.width, sampler.height).data
        if (!pixels || pixels.length === 0)
            return

        const bins = 32
        const ranges = root.bandRanges
        const bandCount = ranges.length

        // Which band each canvas row belongs to.
        const rowBand = []
        for (let row = 0; row < sampler.height; ++row) {
            const fraction = (row + 0.5) / sampler.height
            let found = -1
            for (let index = 0; index < bandCount; ++index) {
                if (fraction >= ranges[index][0] && fraction <= ranges[index][1]) {
                    found = index
                    break
                }
            }
            rowBand.push(found)
        }

        const histograms = []
        const counts = []
        const sums = []
        const darks = []
        for (let index = 0; index < bandCount; ++index) {
            const buckets = []
            for (let bin = 0; bin < bins; ++bin)
                buckets.push(0)
            histograms.push(buckets)
            counts.push(0)
            sums.push(0)
            darks.push(0)
        }

        let total = 0
        let count = 0
        let dark = 0

        for (let index = 0; index < pixels.length; index += 4) {
            const value = 0.2126 * root.linear(pixels[index] / 255)
                + 0.7152 * root.linear(pixels[index + 1] / 255)
                + 0.0722 * root.linear(pixels[index + 2] / 255)
            total += value
            if (value <= 0.183)
                dark++
            count++

            const pixel = index / 4
            const band = rowBand[Math.floor(pixel / sampler.width)]
            if (band < 0)
                continue

            histograms[band][Math.min(bins - 1, Math.floor(value * bins))]++
            counts[band]++
            sums[band] += value
            if (value <= 0.183)
                darks[band]++
        }

        if (count === 0)
            return

        const mean = total / count

        // A URL draw lands asynchronously, so an all-black result usually
        // means "not drawn yet" rather than a black wallpaper. Retry a few
        // times before believing it.
        if (mean <= 0 && root.attempts < 8) {
            root.attempts++
            retry.start()
            return
        }

        const result = []
        for (let index = 0; index < bandCount; ++index) {
            const pixelsInBand = counts[index]
            if (pixelsInBand === 0) {
                result.push(null)
                continue
            }
            const shares = []
            for (let bin = 0; bin < bins; ++bin)
                shares.push(histograms[index][bin] / pixelsInBand)
            result.push({
                "mean": sums[index] / pixelsInBand,
                "dark": darks[index] / pixelsInBand,
                "p10": root.percentile(histograms[index], pixelsInBand, 0.10),
                "p50": root.percentile(histograms[index], pixelsInBand, 0.50),
                "p90": root.percentile(histograms[index], pixelsInBand, 0.90),
                "histogram": shares
            })
        }

        root.attempts = 0
        root.probeState = "ok"
        root.luminance = mean
        root.darkFraction = dark / count
        root.ambiguity = 1 - Math.abs(root.darkFraction - 0.5) * 2
        root.bands = result
        root.probeInfo = Math.round(sourceX) + "," + Math.round(sourceY)
            + " " + Math.round(sourceW) + "x" + Math.round(sourceH)
            + " dark " + root.darkFraction.toFixed(2)
            + " bands " + result.length
    }
}
