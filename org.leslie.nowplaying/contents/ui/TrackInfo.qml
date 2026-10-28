import QtQuick
import QtQuick.Layouts

import org.kde.kirigami as Kirigami

// Track over artist, centred.
ColumnLayout {
    id: root

    property real scaleFactor: 1
    property color trackColor: Kirigami.Theme.textColor
    property color artistColor: Kirigami.Theme.textColor
    property string trackText: ""
    property string artistText: ""

    spacing: 0

    readonly property int trackSize: Math.max(7, Math.round(Kirigami.Units.gridUnit * 0.62 * scaleFactor))
    readonly property int artistSize: Math.max(6, Math.round(Kirigami.Units.gridUnit * 0.46 * scaleFactor))

    Text {
        Layout.fillWidth: true
        Layout.alignment: Qt.AlignHCenter
        text: root.trackText.length > 0 ? root.trackText : i18n("Nothing playing")
        color: root.trackColor
        font.pixelSize: root.trackSize
        font.weight: Font.DemiBold
        font.letterSpacing: 1
        elide: Text.ElideRight
        maximumLineCount: 1
        wrapMode: Text.NoWrap
        horizontalAlignment: Text.AlignHCenter
    }

    Text {
        Layout.fillWidth: true
        Layout.alignment: Qt.AlignHCenter
        visible: text.length > 0
        text: root.artistText
        color: root.artistColor
        font.pixelSize: root.artistSize
        font.letterSpacing: 1
        elide: Text.ElideRight
        maximumLineCount: 1
        wrapMode: Text.NoWrap
        horizontalAlignment: Text.AlignHCenter
    }
}
