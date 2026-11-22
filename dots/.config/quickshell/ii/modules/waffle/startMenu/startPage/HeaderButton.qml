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

WBorderlessButton {
    id: root

    property string leadingIcon: ""
    property string trailingIcon: ""

    implicitHeight: 28
    implicitWidth: buttonRow.implicitWidth + 10 * 2

    contentItem: Item {
        RowLayout {
            id: buttonRow
            anchors.centerIn: parent
            spacing: 6
            FluentIcon {
                visible: root.leadingIcon !== ""
                icon: root.leadingIcon
                implicitSize: 14
            }
            WText {
                text: root.text
            }
            FluentIcon {
                visible: root.trailingIcon !== ""
                icon: root.trailingIcon
                implicitSize: 14
            }
        }
    }
}
