import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts

import org.kde.kirigami as Kirigami

// Root is a ColumnLayout rather than a bare Item so the page has a real
// implicit size and is never collapsed to 0x0 inside the config dialog.
ColumnLayout {
    id: page

    spacing: Kirigami.Units.smallSpacing

    property alias cfg_weekdayFont: weekdayFont.text
    property alias cfg_textMode: textMode.currentIndex

    Kirigami.FormLayout {
        Layout.fillWidth: true
        Layout.margins: Kirigami.Units.gridUnit

        QQC2.TextField {
            id: weekdayFont
            Kirigami.FormData.label: i18n("Weekday font:")
            placeholderText: i18n("Leave empty for the system font")
        }

        QQC2.ComboBox {
            id: textMode
            Kirigami.FormData.label: i18n("Text colour:")
            model: [i18n("Follow the wallpaper"), i18n("Always light"), i18n("Always dark")]
        }
    }
}
