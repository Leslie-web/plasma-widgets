import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts

import org.kde.kirigami as Kirigami

// Root is a ColumnLayout rather than a bare Item so the page has a real
// implicit size and is never collapsed to 0x0 inside the config dialog.
ColumnLayout {
    id: page

    spacing: Kirigami.Units.smallSpacing

    property alias cfg_showTrack: showTrack.checked
    property alias cfg_showWaveform: showWaveform.checked
    property alias cfg_textMode: textMode.currentIndex
    property alias cfg_smoothFrames: smoothFrames.checked
    property alias cfg_waveformPoints: waveformPoints.value
    property alias cfg_helperPort: helperPort.value

    Kirigami.FormLayout {
        Layout.fillWidth: true
        Layout.margins: Kirigami.Units.gridUnit

        QQC2.CheckBox {
            id: showTrack
            Kirigami.FormData.label: i18n("Sections:")
            text: i18n("Current track")
        }

        QQC2.CheckBox {
            id: showWaveform
            text: i18n("Waveform")
        }

        QQC2.ComboBox {
            id: textMode
            Kirigami.FormData.label: i18n("Text colour:")
            model: [i18n("Follow the wallpaper"), i18n("Always light"), i18n("Always dark")]
        }

        QQC2.CheckBox {
            id: smoothFrames
            Kirigami.FormData.label: i18n("Spectrum:")
            text: i18n("Smooth between frames")
        }

        QQC2.SpinBox {
            id: waveformPoints
            Kirigami.FormData.label: i18n("Detail:")
            from: 0
            to: 256
            stepSize: 16
            editable: true
            textFromValue: function (value) {
                return value === 0 ? i18n("Follow source") : value
            }
            valueFromText: function (text) {
                const parsed = parseInt(text, 10)
                return isNaN(parsed) ? 0 : Math.min(256, Math.max(0, parsed))
            }
        }

        QQC2.SpinBox {
            id: helperPort
            Kirigami.FormData.label: i18n("Helper port:")
            from: 1024
            to: 65535
            editable: true
        }

        QQC2.Label {
            Kirigami.FormData.label: i18n("Hint:")
            Layout.maximumWidth: Kirigami.Units.gridUnit * 22
            wrapMode: Text.WordWrap
            opacity: 0.75
            font: Kirigami.Theme.smallFont
            text: i18n("The waveform needs cava. The helper starts on its own and picks the next free port if this one is taken.")
        }
    }
}
