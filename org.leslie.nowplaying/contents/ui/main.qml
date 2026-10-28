import QtQuick
import QtQuick.Layouts

import org.kde.plasma.core as PlasmaCore
import org.kde.plasma.plasmoid
import org.kde.plasma.plasma5support as P5Support
import org.kde.kirigami as Kirigami

import org.kde.plasma.private.mpris as Mpris

PlasmoidItem {
    id: root

    readonly property real unit: Kirigami.Units.gridUnit
    readonly property int helperPort: Plasmoid.configuration.helperPort
    readonly property bool showTrack: Plasmoid.configuration.showTrack
    readonly property bool showWaveform: Plasmoid.configuration.showWaveform
    readonly property int textMode: Plasmoid.configuration.textMode

    // Mirror of WaveformLine.helperUp, kept here so the tooltip can read it
    // without touching the representation, which may not be instantiated yet.
    property bool waveformActive: false
    property string waveformProblem: ""

    // The helper ships inside the package, so a fresh install has the whole
    // chain except cava itself. Started on demand; the helper holds a lock, so
    // launching it when one already runs (including a systemd unit's copy) is
    // harmless.
    readonly property string helperPath: Qt.resolvedUrl("../code/plasma-waveform-helper")
        .toString().replace(/^file:\/\//, "")
    readonly property string helperCommand: "setsid nohup python3 '" + helperPath
        + "' >/dev/null 2>&1 < /dev/null &"
    property int launchSeq: 0

    P5Support.DataSource {
        id: helperLauncher
        engine: "executable"
        connectedSources: []
    }

    function ensureHelper() {
        // The sequence number makes each command distinct; the data engine
        // ignores a source it has already seen.
        launchSeq += 1
        helperLauncher.connectedSources = [helperCommand + " echo " + launchSeq]
    }

    onIsPlayingChanged: if (isPlaying) ensureHelper()

    // The shell may restore this applet while something is already playing, in
    // which case no status change ever arrives to trigger the start.
    Component.onCompleted: {
        if (isPlaying)
            ensureHelper()
    }

    // Samples the wallpaper under the widget so the palette can follow it.
    LuminanceProbe {
        id: luminanceProbe
        target: root
        appletId: root.appletIdentifier
    }

    readonly property int appletIdentifier: Plasmoid.id

    // 0 = auto (follow the wallpaper), 1 = always light, 2 = always dark.
    //
    // Under a slideshow no fixed colour survives, so the choice is made from
    // contrast rather than from brightness. Each text block measures the band
    // of wallpaper behind itself: on one wall the track line sat on dark red
    // while the transport row sat on bright cream, so a single colour had to be
    // unreadable somewhere. Inside a block the family that leaves fewer pixels
    // below 3:1 wins, and each level takes the softest tone that still keeps
    // its contrast over most of the band.
    readonly property var darkRamp: ["#0f1115", "#252a32", "#3d434d", "#585f6a"]
    readonly property var lightRamp: ["#fcfdff", "#e9edf2", "#cfd4dc", "#adb4bf"]

    function channelLinear(value) {
        return value <= 0.04045 ? value / 12.92 : Math.pow((value + 0.055) / 1.055, 2.4)
    }

    function toneLuminance(hex) {
        const red = channelLinear(parseInt(hex.substring(1, 3), 16) / 255)
        const green = channelLinear(parseInt(hex.substring(3, 5), 16) / 255)
        const blue = channelLinear(parseInt(hex.substring(5, 7), 16) / 255)
        return 0.2126 * red + 0.7152 * green + 0.0722 * blue
    }

    function contrast(first, second) {
        const lighter = Math.max(first, second)
        const darker = Math.min(first, second)
        return (lighter + 0.05) / (darker + 0.05)
    }

    // Bands: 0 = track, 1 = transport.
    function statsAt(index) {
        const bands = luminanceProbe.bands
        if (index < bands.length && bands[index])
            return bands[index]
        // A band can be empty if the layout changes; borrow a neighbour rather
        // than leaving the text at the default colour.
        for (let scan = 0; scan < bands.length; ++scan) {
            if (bands[scan])
                return bands[scan]
        }
        return null
    }

    readonly property var trackStats: statsAt(0)
    readonly property var transportStats: statsAt(1)

    // Share of the band this family cannot bring to 3:1, using its strongest
    // tone. Lower is better; the winner is the more readable one.
    function uncoveredShare(stats, ramp) {
        if (!stats)
            return 1

        const tone = toneLuminance(ramp[0])
        let total = 0
        let failed = 0

        for (let index = 0; index < stats.histogram.length; ++index) {
            const share = stats.histogram[index]
            if (share <= 0)
                continue
            total += share
            if (contrast(tone, (index + 0.5) / stats.histogram.length) < 3.0)
                failed += share
        }

        return total > 0 ? failed / total : 1
    }

    function usesDarkFor(stats) {
        if (textMode === 2)
            return true
        if (textMode === 1)
            return false
        if (!stats)
            return false

        const dark = uncoveredShare(stats, darkRamp)
        const light = uncoveredShare(stats, lightRamp)
        if (Math.abs(dark - light) > 0.02)
            return dark < light

        // A genuinely mixed band: fall back to which side reads better at its
        // median luminance.
        return contrast(toneLuminance(darkRamp[0]), stats.p50)
            > contrast(toneLuminance(lightRamp[0]), stats.p50)
    }

    function rampFor(stats) {
        return usesDarkFor(stats) ? darkRamp : lightRamp
    }

    // A mixed band needs the strongest tones; a calm one can stay softer.
    function offsetFor(stats) {
        if (!stats)
            return 1
        return (1 - Math.abs(stats.dark - 0.5) * 2) > 0.45 ? 0 : 1
    }

    // Share of the band where this tone cannot hold the requested contrast.
    // Percentiles were too blunt: one bright highlight covering a tenth of the
    // area dragged every tone down to the strongest one.
    function gapFor(stats, ramp, hex, floorRatio) {
        if (!stats)
            return 1

        const tone = toneLuminance(hex)
        let total = 0
        let failed = 0

        for (let index = 0; index < stats.histogram.length; ++index) {
            const share = stats.histogram[index]
            if (share <= 0)
                continue
            total += share
            if (contrast(tone, (index + 0.5) / stats.histogram.length) < floorRatio)
                failed += share
        }

        return total > 0 ? failed / total : 1
    }

    // Start from the preferred tone for a level and step toward the strongest
    // end only while too much of the band fails it, so the tonal hierarchy
    // survives wherever the background allows it.
    function toneFor(stats, preferred, floorRatio, tolerance) {
        const ramp = rampFor(stats)
        let index = Math.max(0, Math.min(ramp.length - 1, preferred))
        while (index > 0 && gapFor(stats, ramp, ramp[index], floorRatio) > tolerance)
            --index
        return ramp[index]
    }

    // Tolerances were tuned over the whole wallpaper folder (803 walls): these
    // keep a second tone on 348 of them, where (0.03/0.06/0.10) collapsed to
    // one, without changing the amount of area left below 3:1.
    readonly property int trackOffset: offsetFor(trackStats)
    readonly property int transportOffset: offsetFor(transportStats)

    Mpris.Mpris2Model {
        id: mprisModel
    }

    // Mpris2Model picks the "active" player, and Electron/Chromium apps keep a
    // media session registered at all times: VS Code was being chosen as the
    // current player, which has no track, no length and no transport, so the
    // widget showed "Nothing playing" and the buttons did nothing. Watch the
    // selection and move it to a player that can actually be used.
    Timer {
        id: playerWatch

        interval: 1500
        repeat: true
        running: true
        onTriggered: root.ensureUsablePlayer()
    }

    function ensureUsablePlayer() {
        // Score every player every time. Bailing out as soon as the current one
        // looked usable kept a paused browser media session selected while a
        // real player was playing: the widget showed the wrong track, the
        // transport stayed on "play" and the waveform never started.
        let best = -1
        let bestPlaying = false
        let bestHasTrack = false

        for (let index = 0; index < 8; ++index) {
            mprisModel.currentIndex = index
            const candidate = mprisModel.currentPlayer
            if (!candidate)
                continue

            const playing = candidate.playbackStatus === Mpris.PlaybackStatus.Playing
            const hasTrack = (candidate.track || "").length > 0
            if (!playing && !hasTrack)
                continue

            const better = best < 0
                || (playing && !bestPlaying)
                || (playing === bestPlaying && hasTrack && !bestHasTrack)
            if (better) {
                best = index
                bestPlaying = playing
                bestHasTrack = hasTrack
            }
        }

        const target = best >= 0 ? best : mprisModel.currentIndex
        if (target !== mprisModel.currentIndex)
            mprisModel.currentIndex = target
    }

    readonly property var player: mprisModel.currentPlayer ?? null
    readonly property bool hasPlayer: player !== null && player !== undefined
    readonly property bool isPlaying: hasPlayer && player.playbackStatus === Mpris.PlaybackStatus.Playing

    // Sits straight on the wallpaper like the reference layout.
    Plasmoid.backgroundHints: PlasmaCore.Types.NoBackground
    Plasmoid.title: i18n("Now Playing")

    preferredRepresentation: fullRepresentation

    toolTipMainText: hasPlayer ? (player.track || i18n("Unknown track")) : i18n("Now Playing")
    toolTipSubText: {
        const lines = []
        if (hasPlayer && player.artist)
            lines.push(player.artist)
        if (hasPlayer && player.album)
            lines.push(player.album)
        if (showWaveform && waveformProblem === "no-cava")
            lines.push(i18n("The waveform needs cava, which is not installed"))
        else if (showWaveform && waveformProblem === "no-helper")
            lines.push(i18n("The waveform helper did not start (python3 is required)"))
        return lines.join("\n")
    }

    fullRepresentation: ColumnLayout {
        id: layout

        // Desktop applets are sized from the implicit size on first placement;
        // after that the user drags the handles and everything scales with it.
        implicitWidth: Math.round(root.unit * 20)
        implicitHeight: Math.round(root.unit * 6)

        readonly property real uiScale: Math.max(0.6, Math.min(3.0, layout.width / (root.unit * 20)))

        spacing: Math.round(root.unit * 0.3 * layout.uiScale)

        // Hand the probe the real text rows. Fractions of the widget height
        // were guesses: the layout decides where the blocks actually sit, and
        // a guess landed the transport band on the waveform strip.
        Binding {
            target: luminanceProbe
            property: "bandRanges"
            value: [trackBlock, transportBlock].map(function (item) {
                const total = layout.height > 0 ? layout.height : 1
                return [Math.max(0, item.y / total),
                        Math.min(1, (item.y + item.height) / total)]
            })
            when: layout.height > 0
            restoreMode: Binding.RestoreNone
        }

        TrackInfo {
            id: trackBlock

            Layout.fillWidth: true
            visible: root.showTrack
            scaleFactor: layout.uiScale
            trackColor: root.toneFor(root.trackStats, root.trackOffset, 4.5, 0.08)
            artistColor: root.toneFor(root.trackStats, root.trackOffset + 1, 3.0, 0.20)
            trackText: root.hasPlayer ? (root.player.track || "") : ""
            artistText: root.hasPlayer ? (root.player.artist || "") : ""
        }

        WaveformLine {
            id: waveform
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.minimumHeight: Math.round(root.unit * 1.8 * layout.uiScale)
            Layout.maximumHeight: Math.round(root.unit * 3 * layout.uiScale)
            visible: root.showWaveform
            // Polling costs a request per tick and cava would only deliver
            // silence while paused, so it runs only during playback.
            active: root.isPlaying && root.showWaveform
            portHint: root.helperPort
            points: Plasmoid.configuration.waveformPoints
            smoothFrames: Plasmoid.configuration.smoothFrames
            lineColor: Kirigami.Theme.highlightColor
            onHelperUpChanged: root.waveformActive = helperUp
            onProblemChanged: root.waveformProblem = problem
        }

        TransportControls {
            id: transportBlock

            Layout.alignment: Qt.AlignHCenter
            visible: root.showTrack && root.hasPlayer
            scaleFactor: layout.uiScale
            iconColor: root.toneFor(root.transportStats, root.transportOffset, 4.5, 0.10)
            playing: root.isPlaying
            canPrev: root.hasPlayer && root.player.canGoPrevious
            canNext: root.hasPlayer && root.player.canGoNext
            onPreviousPressed: if (root.hasPlayer) root.player.Previous()
            onPlayPausePressed: if (root.hasPlayer) root.player.PlayPause()
            onNextPressed: if (root.hasPlayer) root.player.Next()
        }
    }
}
