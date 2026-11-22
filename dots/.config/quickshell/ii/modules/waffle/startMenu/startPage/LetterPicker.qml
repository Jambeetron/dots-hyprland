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

MouseArea {
    id: root

    required property var availableLetters
    signal picked(string letter)
    signal dismissed

    onClicked: root.dismissed()
    onWheel: event => event.accepted = true

    GridLayout {
        anchors.centerIn: parent
        columns: 7
        rowSpacing: 8
        columnSpacing: 8

        Repeater {
            model: "#ABCDEFGHIJKLMNOPQRSTUVWXYZ".split("")
            delegate: WBorderlessButton {
                id: letterButton
                required property string modelData
                implicitWidth: 64
                implicitHeight: 64
                enabled: root.availableLetters.includes(letterButton.modelData)
                onClicked: root.picked(letterButton.modelData)
                contentItem: WText {
                    horizontalAlignment: Text.AlignHCenter
                    text: letterButton.modelData
                    opacity: letterButton.enabled ? 1 : 0.3
                    font.pixelSize: Looks.font.pixelSize.xlarger
                    font.weight: Looks.font.weight.stronger
                }
            }
        }
    }
}
