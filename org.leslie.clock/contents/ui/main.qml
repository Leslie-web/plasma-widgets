import QtQuick
import QtQuick.Layouts

import org.kde.plasma.core as PlasmaCore
import org.kde.plasma.plasmoid
import org.kde.kirigami as Kirigami

// Day of week, date and clock on their own, so they can be placed apart from
// the music widget.
PlasmoidItem {
    id: root

    readonly property real unit: Kirigami.Units.gridUnit
    readonly property int textMode: Plasmoid.configuration.textMode

    readonly property int appletIdentifier: Plasmoid.id

    // Samples the wallpaper under the widget so the palette can follow it.
    LuminanceProbe {
        id: luminanceProbe
        target: root
        appletId: root.appletIdentifier
        // This applet is text end to end, so the whole box is one band.
        bandRanges: [[0.0, 1.0]]
    }

    // 0 = auto (follow the wallpaper), 1 = always light, 2 = always dark.
    //
    // Under a slideshow no fixed colour survives, so the choice is made from
    // contrast rather than from brightness. The family that leaves fewer pixels
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

    readonly property var clockStats: {
        const bands = luminanceProbe.bands
        return bands.length > 0 && bands[0] ? bands[0] : null
    }

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
            // Nothing measured: light survives the median wallpaper better than
            // dark does, and the settings offer an override. The tooltip says
            // when this guess is in use.
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

    readonly property int clockOffset: offsetFor(clockStats)
    readonly property color primaryColor: toneFor(clockStats, clockOffset, 6.0, 0.03)
    readonly property color secondaryColor: toneFor(clockStats, clockOffset + 1, 4.0, 0.08)
    readonly property color tertiaryColor: toneFor(clockStats, clockOffset + 2, 3.0, 0.20)

    // Sits straight on the wallpaper like the reference layout.
    Plasmoid.backgroundHints: PlasmaCore.Types.NoBackground
    Plasmoid.title: i18n("Day & Date")

    preferredRepresentation: fullRepresentation

    toolTipMainText: Qt.formatDate(new Date(), Qt.locale().dateFormat(Locale.LongFormat))
    toolTipSubText: {
        const time = Qt.formatTime(new Date(), "HH:mm:ss")
        const state = luminanceProbe.probeState
        if (state === "waiting" || state === "ok")
            return time
        // The probe gave up, so the colour is a guess rather than a measurement.
        return time + "\n" + i18n("The wallpaper could not be measured, so the text colour is a guess. Set it in the widget's settings.")
    }

    fullRepresentation: ColumnLayout {
        id: layout

        // Desktop applets are sized from the implicit size on first placement;
        // after that the user drags the handles and everything scales with it.
        implicitWidth: Math.round(root.unit * 20)
        implicitHeight: Math.round(root.unit * 4.6)

        readonly property real uiScale: Math.max(0.6, Math.min(3.0, layout.width / (root.unit * 20)))

        spacing: Math.round(root.unit * 0.3 * layout.uiScale)

        ClockBlock {
            id: clockBlock

            Layout.fillWidth: true
            // Centre the block itself: fillWidth alone left it hugging its
            // content at the left edge.
            Layout.alignment: Qt.AlignHCenter
            scaleFactor: layout.uiScale
            fontFamily: Plasmoid.configuration.weekdayFont
            primaryColor: root.primaryColor
            secondaryColor: root.secondaryColor
            tertiaryColor: root.tertiaryColor
        }
    }
}
