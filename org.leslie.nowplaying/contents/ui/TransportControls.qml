import QtQuick
import QtQuick.Layouts

import org.kde.kirigami as Kirigami

RowLayout {
    id: root

    property real scaleFactor: 1
    property color iconColor: Kirigami.Theme.textColor
    property bool playing: false
    property bool canPrev: true
    property bool canNext: true

    signal previousPressed()
    signal playPausePressed()
    signal nextPressed()

    spacing: Math.round(Kirigami.Units.gridUnit * 0.5 * scaleFactor)
    Layout.alignment: Qt.AlignHCenter

    TransportButton {
        iconName: "media-skip-backward"
        enabled: root.canPrev
        onClicked: root.previousPressed()
    }

    TransportButton {
        iconName: root.playing ? "media-playback-pause" : "media-playback-start"
        onClicked: root.playPausePressed()
    }

    TransportButton {
        iconName: "media-skip-forward"
        enabled: root.canNext
        onClicked: root.nextPressed()
    }

    component TransportButton: Item {
        id: button

        property string iconName

        signal clicked()

        implicitWidth: Math.round(Kirigami.Units.gridUnit * 1.2 * root.scaleFactor)
        implicitHeight: implicitWidth
        opacity: enabled ? 1 : 0.35

        Kirigami.Icon {
            anchors.fill: parent
            source: button.iconName
            isMask: true
            color: root.iconColor
        }

        MouseArea {
            anchors.fill: parent
            enabled: button.enabled
            cursorShape: Qt.PointingHandCursor
            onClicked: button.clicked()
        }
    }
}
