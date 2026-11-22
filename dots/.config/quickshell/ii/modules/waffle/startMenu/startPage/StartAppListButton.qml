pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import qs
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import qs.modules.waffle.looks

StartAppButton {
    id: root

    implicitHeight: 44
    contentItem: RowLayout {
        spacing: 12
        WAppIcon {
            Layout.leftMargin: 12
            iconName: root.desktopEntry.icon
            implicitSize: 26
            tryCustomIcon: false
        }
        WText {
            Layout.fillWidth: true
            Layout.rightMargin: 12
            text: root.desktopEntry.name
            elide: Text.ElideRight
        }
    }
}
