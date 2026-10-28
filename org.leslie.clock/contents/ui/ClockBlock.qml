import QtQuick
import QtQuick.Layouts

import org.kde.kirigami as Kirigami

// Big letter-spaced weekday, then "27 OCTOBER, 2026." and the clock, centred.
ColumnLayout {
    id: root

    property real scaleFactor: 1
    property string fontFamily: ""
    property color primaryColor: Kirigami.Theme.textColor
    property color secondaryColor: Kirigami.Theme.textColor
    property color tertiaryColor: Kirigami.Theme.textColor
    property string weekdayText: ""
    property string dateText: ""
    property string timeText: ""

    // Computed once: reading font.pixelSize from inside the same font group
    // (letterSpacing) is a binding loop.
    readonly property int weekdaySize: Math.max(16, Math.round(Kirigami.Units.gridUnit * 2.2 * scaleFactor))
    readonly property int dateSize: Math.max(8, Math.round(Kirigami.Units.gridUnit * 0.62 * scaleFactor))
    readonly property int timeSize: Math.max(9, Math.round(Kirigami.Units.gridUnit * 0.92 * scaleFactor))

    spacing: Math.round(Kirigami.Units.gridUnit * 0.12 * scaleFactor)

    function refresh() {
        const now = new Date()

        const weekday = Qt.locale().standaloneDayName(now.getDay(), Locale.LongFormat)
        if (weekday !== root.weekdayText)
            root.weekdayText = weekday

        // "27 October, 2026." -> uppercased by the label, matches the
        // reference layout which ends the date with a full stop.
        const date = Qt.formatDate(now, "dd MMMM, yyyy") + "."
        if (date !== root.dateText)
            root.dateText = date

        const time = Qt.formatTime(now, "HH:mm:ss")
        if (time !== root.timeText)
            root.timeText = time
    }

    Component.onCompleted: refresh()

    // Short interval, but the strings are only reassigned when they actually
    // change: no per-tick relayout and no drift like a plain 1000 ms timer.
    Timer {
        interval: 200
        repeat: true
        running: true
        onTriggered: root.refresh()
    }

    Text {
        Layout.alignment: Qt.AlignHCenter
        // letterSpacing also pads after the last glyph, which pushes the
        // glyphs left of centre; pull that whole half-space back on the right.
        Layout.rightMargin: -Math.round(root.weekdaySize * 0.2)
        text: root.weekdayText
        color: root.primaryColor
        font.family: root.fontFamily
        font.pixelSize: root.weekdaySize
        font.weight: Font.Normal
        font.capitalization: Font.AllUppercase
        font.letterSpacing: Math.round(root.weekdaySize * 0.2)
    }

    Text {
        Layout.alignment: Qt.AlignHCenter
        text: root.dateText
        color: root.secondaryColor
        font.pixelSize: root.dateSize
        font.weight: Font.DemiBold
        font.capitalization: Font.AllUppercase
        font.letterSpacing: Math.round(root.dateSize * 0.14)
    }

    Text {
        Layout.alignment: Qt.AlignHCenter
        text: root.timeText
        color: root.secondaryColor
        font.pixelSize: root.timeSize
        font.weight: Font.Normal
        font.letterSpacing: Math.round(root.timeSize * 0.08)
    }
}
