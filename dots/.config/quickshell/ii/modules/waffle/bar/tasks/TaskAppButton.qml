import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.waffle.looks
import qs.modules.waffle.bar
import Quickshell

AppButton {
    id: root

    required property var appEntry
    readonly property bool isSeparator: appEntry.appId === "SEPARATOR"
    property var desktopEntry: DesktopEntries.heuristicLookup(appEntry.appId)

    Timer {
        // Retry looking up the desktop entry if it failed (e.g. database not loaded yet)
        property int retryCount: 5
        interval: 1000
        running: !root.isSeparator && root.desktopEntry === null && retryCount > 0
        repeat: true
        onTriggered: {
            retryCount--;
            root.desktopEntry = DesktopEntries.heuristicLookup(root.appEntry.appId);
        }
    }

    property bool active: root.appEntry.toplevels.some(t => t.activated)
    property bool hasWindows: appEntry.toplevels.length > 0

    signal hoverPreviewRequested()
    signal hoverPreviewDismissed()

    // ---- Drag-to-reorder (state lives in Tasks.qml)
    property Item tasksRoot: null
    property int listIndex: -1
    readonly property bool anyDragActive: tasksRoot !== null && tasksRoot.draggingKey !== ""
    readonly property bool isDragSource: anyDragActive && tasksRoot.draggingKey === appEntry.key
    dragEnabled: tasksRoot !== null

    // The dragged icon is drawn by Tasks' drag ghost; neighbors slide aside.
    opacity: isDragSource ? 0 : 1
    z: isDragSource ? 10 : 0
    readonly property real dragShift: {
        if (!anyDragActive || isDragSource)
            return 0;
        const t = tasksRoot;
        const i = listIndex;
        if (i < t.dragSectionStart || i > t.dragSectionEnd)
            return 0;
        if (t.dragFromIndex < t.dragToIndex && i > t.dragFromIndex && i <= t.dragToIndex)
            return -t.dragSlotWidth;
        if (t.dragFromIndex > t.dragToIndex && i >= t.dragToIndex && i < t.dragFromIndex)
            return t.dragSlotWidth;
        return 0;
    }
    transform: Translate {
        x: root.dragShift
        Behavior on x {
            enabled: root.anyDragActive && !root.tasksRoot.dropping
            NumberAnimation {
                duration: 150
                easing.type: Easing.OutCubic
            }
        }
    }

    onDragStarted: (pressX, pressY) => {
        root.hoverTimer.stop();
        root.hoverPreviewDismissed();
        tasksRoot.beginDrag(root.appEntry, root.listIndex, root, pressX, pressY);
    }
    onDragMoved: (x, y) => tasksRoot.trackDragCursor(root, x, y)
    onDragFinished: commit => tasksRoot.endDrag(commit)

    multiple: appEntry.toplevels.length > 1
    checked: active
    iconName: AppSearch.guessIcon(appEntry.appId)
    tryCustomIcon: false

    onHoverTimedOut: {
        if (!root.anyDragActive)
            root.hoverPreviewRequested()
    }

    onClicked: {
        root.hoverTimer.stop() // Prevents preview showing up when clicking to focus
        if (root.multiple) {
            root.hoverPreviewRequested()
        } else if (root.appEntry.toplevels.length === 1) {
            root.appEntry.toplevels[0].activate()
        } else {
            root.desktopEntry.execute()
        }
    }

    middleClickAction: () => {
        if (root.desktopEntry) {
            desktopEntry.execute()
        }
    }

    altAction: () => {
        root.hoverPreviewDismissed()
        root.hoverTimer.stop()
        contextMenu.active = true;
    }

    // Active indicator
    Rectangle {
        id: activeIndicator
        opacity: root.hasWindows ? 1 : 0
        anchors {
            horizontalCenter: root.background.horizontalCenter
            bottom: root.background.bottom
            bottomMargin: 1
        }

        implicitWidth: root.active ? 16 : 6
        implicitHeight: 3
        radius: height / 2

        color: root.active ? Looks.colors.accent : Looks.colors.accentUnfocused

        Behavior on implicitWidth {
            animation: Looks.transition.enter.createObject(this)
        }
        Behavior on color {
            animation: Looks.transition.color.createObject(this)
        }
        Behavior on opacity {
            animation: Looks.transition.opacity.createObject(this)
        }
    }

    BarToolTip {
        extraVisibleCondition: root.shouldShowTooltip && !root.hasWindows
        text: desktopEntry ? desktopEntry.name : appEntry.appId
    }

    BarMenu {
        id: contextMenu
        noSmoothClosing: false // On the real thing this is always smooth

        model: [
            ...((root.desktopEntry?.actions.length > 0) ? root.desktopEntry.actions.map(action =>({
                iconName: action.icon,
                text: action.name,
                action: () => {
                    action.execute()
                }
            })).concat({ type: "separator" }) : []),
            {
                iconName: root.iconName,
                text: root.desktopEntry ? root.desktopEntry.name : StringUtils.toTitleCase(appEntry.appId),
                monochromeIcon: false,
                action: () => {
                    if (root.desktopEntry) {
                        root.desktopEntry.execute()
                    }
                }
            },
            {
                iconName: root.appEntry.pinned ? "pin-off" : "pin",
                text: root.appEntry.pinned ? Translation.tr("Unpin from taskbar") : Translation.tr("Pin to taskbar"),
                action: () => {
                    TaskbarApps.togglePin(root.appEntry.appId);
                }
            },
            ...(root.appEntry.toplevels.length > 0 ? [{
                iconName: "dismiss",
                text: root.multiple ? Translation.tr("Close all windows") : Translation.tr("Close window"),
                action: () => {
                    for (let toplevel of root.appEntry.toplevels) {
                        toplevel.close();
                    }
                }
            }] : []),
        ]
    }
}
