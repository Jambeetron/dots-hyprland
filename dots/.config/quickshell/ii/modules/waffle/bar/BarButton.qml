import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.functions
import qs.modules.waffle.looks

AcrylicButton {
    id: root

    property var altAction: () => {}
    property var middleClickAction: () => {}

    Layout.fillHeight: true
    topInset: 4
    bottomInset: 4
    leftInset: 0
    rightInset: 0
    horizontalPadding: 8

    colBackground: ColorUtils.transparentize(Looks.colors.bg1)

    // Optional left-button drag (used by the taskbar to reorder apps). Press
    // coordinates are in this button's local space; moves report the cursor
    // in the same space. A drag swallows the click it would otherwise end in.
    property bool dragEnabled: false
    readonly property bool dragging: mouseArea.dragging
    signal dragStarted(real pressX, real pressY)
    signal dragMoved(real x, real y)
    signal dragFinished(bool commit)

    MouseArea {
        id: mouseArea
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
        property bool dragging: false
        property bool suppressClick: false
        property real pressX: 0
        property real pressY: 0

        function finishDrag(commit) {
            if (!dragging)
                return;
            dragging = false;
            root.dragFinished(commit);
        }

        onPressed: (event) => {
            root.down = true;
            if (event.button === Qt.LeftButton) {
                pressX = event.x;
                pressY = event.y;
                suppressClick = false;
            }
        }
        onPositionChanged: (event) => {
            if (!root.dragEnabled || !(pressedButtons & Qt.LeftButton))
                return;
            if (!dragging && (Math.abs(event.x - pressX) > 8 || Math.abs(event.y - pressY) > 8)) {
                dragging = true;
                root.down = false;
                root.dragStarted(pressX, pressY);
            }
            if (dragging)
                root.dragMoved(event.x, event.y);
        }
        onReleased: (event) => {
            root.down = false;
            if (event.button === Qt.LeftButton && dragging) {
                suppressClick = true;
                finishDrag(true);
            }
        }
        onCanceled: {
            root.down = false;
            finishDrag(false);
        }
        Component.onDestruction: finishDrag(false)
        onClicked: (event) => {
            if (event.button === Qt.LeftButton && suppressClick) {
                suppressClick = false;
                return;
            }
            if (dragging)
                return;
            if (event.button === Qt.LeftButton) root.clicked();
            if (event.button === Qt.RightButton) root.altAction();
            if (event.button === Qt.MiddleButton) root.middleClickAction();
        }
    }

}
