import QtQuick
import QtQuick.Shapes
import QtQuick.Layouts

import org.kde.kirigami as Kirigami

// Live waveform for the Now Playing widget.
//
// cava runs in spectrum mode and plasma-waveform-helper serves its frames. The
// bars are eased with a fast attack and a slow decay, then drawn as one
// mirrored band around the middle line, so it reads as a wave rather than as a
// bar graph.
//
// The band is a single Shape polygon rather than a Canvas: a Canvas pipeline
// with a few hundred segments a frame cost ~30% of a core here, which showed up
// as mouse stutter elsewhere in the shell. One polygon is uploaded to the scene
// graph instead.
//
// The two rates differ on purpose: painting runs at ~30 fps from cached
// samples, while the helper is polled ten times a second, because an
// XMLHttpRequest costs the shell far more than a repaint does.
Item {
    id: root

    // The helper is started on this port when it can have it, and scans upward
    // when it cannot, so this is a hint rather than the truth.
    property int portHint: 8765
    property bool active: false
    property int points: 0
    property bool smoothFrames: true
    property color lineColor: Kirigami.Theme.highlightColor
    property bool helperUp: false

    // -1 until /status has identified a helper; empty once one is usable.
    property int port: -1
    // "", "no-helper" or "no-cava" - drives the message in the strip.
    property string problem: ""
    property bool discovering: false
    property int probeOffset: 0
    property var probeRequest: null
    readonly property int portSpan: 10
    readonly property string endpoint: port > 0 ? "http://127.0.0.1:" + port + "/frames" : ""

    readonly property int pollInterval: 100
    readonly property int frameInterval: 40
    readonly property int staleAfter: 700

    property var samples: []
    property var targetSamples: []
    property double lastStamp: 0
    property var request: null

    // 1 while frames arrive, eased to 0 when they stop.
    property real level: 0
    // Slow breath for the idle rule.
    property real breath: 0
    property int idleTicks: 0
    // Auto-gain, so quietly mastered tracks still fill the band.
    property real gain: 1
    // The polygon handed to the Shape, top edge then bottom edge.
    property var bandPoints: []

    Layout.fillWidth: true
    Layout.fillHeight: true
    Layout.minimumWidth: Math.round(Kirigami.Units.gridUnit * 3)
    Layout.minimumHeight: Math.round(Kirigami.Units.gridUnit * 1.2)
    Layout.preferredWidth: Math.round(Kirigami.Units.gridUnit * 6)

    Component.onCompleted: {
        if (active)
            root.discover()
    }

    Component.onDestruction: root.abort()

    onActiveChanged: {
        if (active) {
            // Reuse a port that worked before: each probe costs the shell a
            // request, so only scan when there is nothing to reuse.
            if (port > 0)
                pollTimer.restart()
            else
                discover()
        } else {
            root.abort()
            helperUp = false
        }
    }

    onWidthChanged: root.refreshBand()
    onHeightChanged: root.refreshBand()
    onLineColorChanged: root.refreshBand()

    Timer {
        id: pollTimer

        interval: root.pollInterval
        repeat: false
        onTriggered: root.poll()
    }

    // Nothing has answered yet: the applet launches the helper on first play,
    // so give it a moment and keep looking rather than showing a dead strip.
    Timer {
        id: discoverTimer

        interval: 2000
        repeat: true
        running: root.active && root.port < 0
        onTriggered: root.discover()
    }

    Timer {
        id: frameTimer

        interval: root.frameInterval
        repeat: true
        running: true
        onTriggered: root.step()
    }

    Shape {
        id: band

        anchors.fill: parent
        antialiasing: true
        visible: root.bandPoints.length > 2

        ShapePath {
            fillColor: Qt.rgba(root.lineColor.r, root.lineColor.g, root.lineColor.b, 0.30)
            strokeColor: Qt.rgba(root.lineColor.r, root.lineColor.g, root.lineColor.b, 0.95)
            strokeWidth: 1.6
            joinStyle: ShapePath.RoundJoin
            capStyle: ShapePath.RoundCap

            PathPolyline {
                path: root.bandPoints
            }
        }
    }

    Rectangle {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        height: 1
        visible: !band.visible
        color: root.lineColor
        opacity: 0.10 + 0.10 * root.breath
    }

    // A quiet flat line with no explanation reads as broken. Say which half of
    // the chain is missing: this is the first thing a new user sees.
    Text {
        anchors.centerIn: parent
        width: parent.width
        visible: root.active && root.problem.length > 0 && !band.visible
        text: root.problem === "no-cava"
              ? i18n("Install cava to see the waveform")
              : i18n("Waveform helper is not running")
        color: root.lineColor
        opacity: 0.65
        font: Kirigami.Theme.smallFont
        elide: Text.ElideRight
        horizontalAlignment: Text.AlignHCenter
    }

    // Linear read of the eased samples, so the band can be drawn at finer
    // intervals than the bar count.
    function sampleAt(t) {
        const values = samples
        const count = values.length
        if (count < 2)
            return 0
        const position = Math.max(0, Math.min(1, t)) * (count - 1)
        const lower = Math.floor(position)
        const upper = Math.min(count - 1, lower + 1)
        const blend = position - lower
        return values[lower] * (1 - blend) + values[upper] * blend
    }

    function heightAt(t, amplitude) {
        return Math.min(1, root.sampleAt(t) * root.gain) * amplitude
    }

    function refreshBand() {
        const count = samples.length
        const width = root.width
        const height = root.height

        if (count < 2 || level <= 0.02 || width < 8 || height < 8) {
            if (bandPoints.length > 0)
                bandPoints = []
            return
        }

        const middle = height / 2
        const amplitude = middle * 0.88 * level
        const steps = Math.max(48, Math.min(240, count * 2))
        const result = []

        for (let index = 0; index <= steps; ++index) {
            const t = index / steps
            result.push(Qt.point(t * width, middle - root.heightAt(t, amplitude)))
        }
        for (let index = steps; index >= 0; --index) {
            const t = index / steps
            result.push(Qt.point(t * width, middle + root.heightAt(t, amplitude)))
        }

        bandPoints = result
    }

    function step() {
        const target = targetSamples
        let repaint = false

        if (target.length >= 2) {
            if (samples.length !== target.length) {
                samples = target.slice(0)
                repaint = true
            } else {
                const attack = smoothFrames ? 0.62 : 1.0
                const decay = smoothFrames ? 0.2 : 1.0
                const next = new Array(target.length)
                let moved = 0

                for (let index = 0; index < target.length; ++index) {
                    const here = samples[index]
                    const goal = target[index]
                    const rate = goal > here ? attack : decay
                    const value = here + (goal - here) * rate
                    next[index] = value
                    if (Math.abs(value - here) > moved)
                        moved = Math.abs(value - here)
                }

                samples = next
                repaint = moved > 0.002
            }
        }

        const fresh = helperUp && (Date.now() - lastStamp) < staleAfter

        if (fresh && level < 1) {
            level = Math.min(1, level + 0.2)
            repaint = true
        } else if (!fresh && level > 0) {
            level = Math.max(0, level - 0.08)
            repaint = true
        }

        if (level < 0.05) {
            breath = 0.5 + 0.5 * Math.sin(Date.now() / 900)
            idleTicks = (idleTicks + 1) % 60
            if (idleTicks === 0)
                refreshBand()
        }

        if (level === 0 && samples.length > 0) {
            samples = []
            targetSamples = []
            repaint = true
        }

        if (repaint)
            root.refreshBand()
    }

    function poll() {
        if (!active)
            return

        if (port < 0) {
            discover()
            return
        }

        if (request === null) {
            request = new XMLHttpRequest()
            request.timeout = 500
            request.onreadystatechange = function () {
                const current = root.request
                if (!current || current.readyState !== XMLHttpRequest.DONE)
                    return
                if (current.status === 200) {
                    let handled = false
                    try {
                        const payload = JSON.parse(current.responseText)
                        if (payload && payload.f && payload.f.length > 0) {
                            root.helperUp = true
                            root.lastStamp = payload.t || 0
                            root.setTarget(payload.f[payload.f.length - 1])
                            handled = true
                        }
                    } catch (error) {
                        handled = false
                    }
                    if (!handled)
                        root.helperUp = false
                } else {
                    // Nothing is listening any more: the helper died, or it
                    // bound a different port. Rescan on the next tick.
                    root.helperUp = false
                    root.problem = "no-helper"
                    root.port = -1
                }

                if (root.active)
                    pollTimer.restart()
            }
        }

        request.open("GET", String(root.endpoint) + "?n=1")
        request.send()
    }

    // Ask each port in the window whether it is our helper. Something else may
    // already own the default port, so a reply has to identify itself before it
    // is trusted.
    function discover() {
        if (discovering || !active)
            return
        discovering = true
        probeOffset = 0
        probeNext()
    }

    function probeNext() {
        if (!active) {
            discovering = false
            return
        }
        if (probeOffset >= portSpan) {
            discovering = false
            problem = "no-helper"
            port = -1
            return
        }

        const candidate = portHint + probeOffset
        const probe = new XMLHttpRequest()
        probeRequest = probe
        probe.timeout = 400
        probe.onreadystatechange = function () {
            if (probe.readyState !== XMLHttpRequest.DONE)
                return
            if (root.probeRequest !== probe)
                return
            root.probeRequest = null

            let identified = false
            let hasCava = false
            if (probe.status === 200) {
                try {
                    const status = JSON.parse(probe.responseText)
                    // Older copies of the helper predate the identity field;
                    // their /status shape is still distinctive enough.
                    if (status && (status.app === "plasma-waveform"
                                   || (status.cava !== undefined && status.port !== undefined))) {
                        identified = true
                        hasCava = !!status.binary
                    }
                } catch (error) {
                    identified = false
                }
            }

            if (identified) {
                root.port = candidate
                root.problem = hasCava ? "" : "no-cava"
                root.discovering = false
                if (root.request === null)
                    pollTimer.restart()
            } else {
                root.probeOffset += 1
                root.probeNext()
            }
        }
        probe.open("GET", "http://127.0.0.1:" + candidate + "/status")
        probe.send()
    }

    function abort() {
        const pending = request
        request = null
        if (pending)
            pending.abort()

        const probing = probeRequest
        probeRequest = null
        discovering = false
        if (probing)
            probing.abort()
    }

    function setTarget(raw) {
        const source = resampleTo(raw, points)
        const count = source.length
        if (count < 2)
            return

        const heights = new Array(count)
        let peak = 0

        for (let index = 0; index < count; ++index) {
            const value = Math.max(0, Math.min(100, source[index])) / 100
            heights[index] = value
            if (value > peak)
                peak = value
        }

        const wantedGain = peak > 0.06 ? Math.min(2.4, 0.92 / peak) : 1.0
        gain = gain + (wantedGain - gain) * 0.1

        const shaped = new Array(count)
        for (let index = 0; index < count; ++index) {
            const before = heights[Math.max(0, index - 1)]
            const here = heights[index]
            const after = heights[Math.min(count - 1, index + 1)]
            shaped[index] = (before + 2 * here + after) / 4
        }

        targetSamples = shaped
    }

    function resampleTo(values, wanted) {
        const count = values.length
        if (wanted <= 0 || wanted === count || count < 2)
            return values

        const result = new Array(wanted)
        for (let index = 0; index < wanted; ++index) {
            const position = (index / (wanted - 1)) * (count - 1)
            const lower = Math.floor(position)
            const upper = Math.min(count - 1, lower + 1)
            const blend = position - lower
            result[index] = values[lower] * (1 - blend) + values[upper] * blend
        }
        return result
    }
}
