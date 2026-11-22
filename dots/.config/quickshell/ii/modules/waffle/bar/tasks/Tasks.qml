import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.services
import qs.modules.common
import qs.modules.waffle.looks

MouseArea {
    id: root

    // Set by WaffleBarContent to the room left on the bar; past it the
    // list scrolls instead of overflowing (icons keep their size).
    property real maxWidth: Infinity

    Layout.fillHeight: true
    implicitHeight: appRow.implicitHeight
    implicitWidth: Math.max(0, Math.min(appRow.contentWidth, root.maxWidth))
    Layout.preferredWidth: implicitWidth
    Layout.maximumWidth: implicitWidth
    hoverEnabled: true

    function showPreviewPopup(appEntry, button) {
        previewPopup.show(appEntry, button);
    }

    readonly property var modelApps: TaskbarApps.apps.filter(app => app.appId !== "SEPARATOR")

    // ---- Drag-to-reorder (same rules as the dock: pinned icons reorder
    // among pinned ones, running among running). The model is never touched
    // mid-drag; neighbors slide via Translate and the move is committed once,
    // on release, through TaskbarApps (so the dock gets the same order).
    property string draggingKey: ""
    // True while a drop is being committed: neighbor offsets must snap, as
    // the layout itself moves them by that same slot.
    property bool dropping: false
    property bool dragPinned: false
    property int dragFromIndex: -1
    property int dragToIndex: -1
    property int dragSectionStart: 0
    property int dragSectionEnd: 0
    property real dragSlotWidth: 1
    property real dragOffsetX: 0
    property real dragPressContentX: 0
    property real dragViewX: 0
    property string dragIconName: ""
    property real dragItemContentX: 0
    property real dragItemWidth: 0

    function beginDrag(entry, fromIndex, delegate, pressX, pressY) {
        previewPopup.close();
        root.dragPressContentX = delegate.mapToItem(appRow.contentItem, pressX, pressY).x;
        root.dragViewX = delegate.mapToItem(appRow, pressX, pressY).x;
        root.dragIconName = delegate.iconName;
        root.dragItemContentX = delegate.x;
        root.dragItemWidth = delegate.width;
        const pinnedCount = root.modelApps.filter(a => a.pinned).length;
        if (entry.pinned) {
            root.dragSectionStart = 0;
            root.dragSectionEnd = pinnedCount - 1;
        } else {
            root.dragSectionStart = pinnedCount;
            root.dragSectionEnd = root.modelApps.length - 1;
        }
        root.dragPinned = entry.pinned;
        root.dragSlotWidth = Math.max(1, delegate.width + appRow.spacing);
        root.dragFromIndex = fromIndex;
        root.dragToIndex = fromIndex;
        root.dragOffsetX = 0;
        root.draggingKey = entry.key;
    }

    function trackDragCursor(item, x, y) {
        root.dragViewX = item.mapToItem(appRow, x, y).x;
        root.refreshDrag();
    }

    function refreshDrag() {
        if (root.draggingKey === "")
            return;
        const contentX = appRow.mapToItem(appRow.contentItem, root.dragViewX, 0).x;
        const offsetX = contentX - root.dragPressContentX;
        const minOff = (root.dragSectionStart - root.dragFromIndex) * root.dragSlotWidth;
        const maxOff = (root.dragSectionEnd - root.dragFromIndex) * root.dragSlotWidth;
        root.dragOffsetX = Math.max(minOff, Math.min(offsetX, maxOff));
        root.dragToIndex = root.dragFromIndex + Math.round(root.dragOffsetX / root.dragSlotWidth);
    }

    function endDrag(commit) {
        if (root.draggingKey === "")
            return;
        const key = root.draggingKey;
        const from = root.dragFromIndex;
        const to = root.dragToIndex;
        root.dropping = true;
        if (commit && to !== from) {
            if (root.dragPinned)
                TaskbarApps.reorder(key, to);
            else
                TaskbarApps.reorderRunning(key, to - root.dragSectionStart);
            appRow.forceLayout();
        }
        // Key first: resetting the indices while it's set shifts other icons.
        root.draggingKey = "";
        root.dragOffsetX = 0;
        root.dragFromIndex = -1;
        root.dragToIndex = -1;
        root.dropping = false;
    }

    Behavior on implicitWidth {
        animation: Looks.transition.move.createObject(this)
    }

    // ---- Horizontal scrolling (only does anything when the list overflows)
    readonly property real minContentX: appRow.originX
    readonly property real maxContentX: appRow.originX + Math.max(0, appRow.contentWidth - appRow.width)
    readonly property bool canScroll: root.maxContentX > root.minContentX
    property real scrollTargetX: 0

    function clampContentX(x) {
        return Math.max(root.minContentX, Math.min(x, root.maxContentX));
    }

    function scrollBy(dx, animated) {
        const base = scrollAnim.running ? root.scrollTargetX : appRow.contentX;
        root.scrollTargetX = root.clampContentX(base + dx);
        if (animated) {
            scrollAnim.to = root.scrollTargetX;
            scrollAnim.restart();
        } else {
            scrollAnim.stop();
            appRow.contentX = root.scrollTargetX;
        }
    }

    // Keep the view in range when apps open/close or the bar resizes.
    onMaxContentXChanged: if (!scrollAnim.running && appRow.contentX > root.maxContentX) appRow.contentX = root.maxContentX
    onMinContentXChanged: if (!scrollAnim.running && appRow.contentX < root.minContentX) appRow.contentX = root.minContentX

    NumberAnimation {
        id: scrollAnim
        target: appRow
        property: "contentX"
        duration: 200
        easing.type: Easing.OutCubic
    }

    // Edge auto-scroll: hovering near either end -- or dragging an icon
    // there -- keeps scrolling that way, faster the closer to the edge.
    Timer {
        interval: 16
        repeat: true
        running: root.canScroll && (root.draggingKey !== "" || (listHover.hovered && !root.pressed))
        onTriggered: {
            const dragging = root.draggingKey !== "";
            const x = dragging ? root.dragViewX : listHover.point.position.x;
            const edge = dragging ? 48 : 40;
            const maxSpeed = dragging ? 14 : 8;
            let v = 0;
            if (x < edge)
                v = -maxSpeed * Math.min(1, (edge - x) / edge);
            else if (x > appRow.width - edge)
                v = maxSpeed * Math.min(1, (x - (appRow.width - edge)) / edge);
            if (v === 0)
                return;
            const before = appRow.contentX;
            root.scrollBy(v, false);
            if (dragging && appRow.contentX !== before)
                root.refreshDrag();
        }
    }

    WListView {
        id: appRow
        anchors.fill: parent
        orientation: Qt.Horizontal
        spacing: 0
        clip: true
        interactive: false
        // Keep every delegate alive while scrolled out of view.
        cacheBuffer: 100000
        // TODO: Include only apps (and windows) in current workspace only | wait, does that even make sense in a Hyprland workflow?
        model: ScriptModel {
            objectProp: "key"
            values: root.modelApps
        }
        delegate: TaskAppButton {
            required property var modelData
            required property int index
            appEntry: modelData
            listIndex: index
            tasksRoot: root

            onHoverPreviewRequested: {
                root.showPreviewPopup(appEntry, this);
            }
            onHoverPreviewDismissed: {
                previewPopup.close();
            }
        }
    }

    // Drag ghost: drawn outside the ListView so it stays visible even when
    // auto-scroll carries the dragged slot out of the viewport.
    Item {
        id: dragGhost
        visible: root.draggingKey !== ""
        z: 100
        width: root.dragItemWidth
        height: root.height
        x: Math.max(0, Math.min(
            appRow.x + root.dragItemContentX + root.dragOffsetX - appRow.contentX,
            root.width - width))
        y: 0

        WAppIcon {
            anchors.centerIn: parent
            iconName: root.dragIconName
            tryCustomIcon: false
            scale: 1.15
        }
    }

    // Wheel up/down and horizontal touchpad swipes scroll the list.
    WheelHandler {
        acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
        orientation: Qt.Vertical | Qt.Horizontal
        target: null
        onWheel: event => {
            if (!root.canScroll)
                return;
            const slot = root.height;
            const useY = Math.abs(event.angleDelta.y) >= Math.abs(event.angleDelta.x);
            const delta = useY ? event.angleDelta.y : -event.angleDelta.x;
            root.scrollBy(delta / 120 * slot, true);
        }
    }

    HoverHandler {
        id: listHover
    }

    // Previews popup
    TaskPreview {
        id: previewPopup
        tasksHovered: root.containsMouse
        anchor.window: root.QsWindow.window
    }
}
