import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.waffle.looks
import qs.modules.waffle.bar.tasks
import qs.modules.waffle.bar.tray

Rectangle {
    id: root

    color: Looks.colors.bg0
    implicitHeight: 48
    
    Rectangle {
        id: border
        anchors {
            left: parent.left
            right: parent.right
            top: Config.options.waffles.bar.bottom ? parent.top : undefined
            bottom: Config.options.waffles.bar.bottom ? undefined : parent.bottom
        }
        color: Looks.colors.bg0Border
        implicitHeight: 1
    }

    BarGroupRow {
        id: bloatRow
        anchors.left: parent.left
        opacity: Config.options.waffles.bar.leftAlignApps ? 0 : 1
        visible: opacity > 0
        Behavior on opacity {
            animation: Looks.transition.opacity.createObject(this)
        }

        WidgetsButton {}
    }

    BarGroupRow {
        id: appsRow
        anchors.left: undefined
        anchors.horizontalCenter: parent.horizontalCenter
        // Centered while it fits; when the centered spot would overlap a side
        // row, slide just enough to clear it (uses the space on both sides).
        readonly property real sideMargin: 8
        readonly property real leftEdge: (bloatRow.visible ? bloatRow.width : 0) + sideMargin
        readonly property real rightEdge: root.width - systemRow.width - sideMargin
        readonly property real centeredX: (root.width - width) / 2
        anchors.horizontalCenterOffset: Math.min(Math.max(0, leftEdge - centeredX), rightEdge - width - centeredX)

        states: State {
            name: "left"
            when: Config.options.waffles.bar.leftAlignApps
            AnchorChanges {
                target: appsRow
                anchors.left: parent.left
                anchors.horizontalCenter: undefined
            }
        }

        transitions: Transition {
            animations: Looks.transition.anchor.createObject(this)
        }

        StartButton { id: startButton }
        SearchButton { id: searchButton }
        TaskViewButton { id: taskViewButton }
        Tasks {
            // Room left for the app list: the whole gap between the side rows
            // (appsRow slides off-center when needed, see horizontalCenterOffset).
            readonly property real fixedButtonsWidth: startButton.width + searchButton.width + taskViewButton.width
            readonly property real rowRoom: Config.options.waffles.bar.leftAlignApps
                ? root.width - systemRow.width - appsRow.sideMargin
                : appsRow.rightEdge - appsRow.leftEdge
            maxWidth: Math.max(0, rowRoom - fixedButtonsWidth)
        }
    }

    BarGroupRow {
        id: systemRow
        anchors.right: parent.right
        FadeLoader {
            Layout.fillHeight: true
            shown: Config.options.waffles.bar.leftAlignApps
            sourceComponent: WidgetsButton {}
        }
        Tray {}
        UpdatesButton {}
        SystemButton {}
        TimeButton {}
    }

    component BarGroupRow: RowLayout {
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        spacing: 0
    }
}
