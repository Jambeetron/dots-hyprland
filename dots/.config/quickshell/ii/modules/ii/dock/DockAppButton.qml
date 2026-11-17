import qs.services
import qs.modules.common
import qs.modules.common.functions
import Qt5Compat.GraphicalEffects
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Widgets

DockButton {
    id: root
    property var appToplevel
    property var appListRoot
    property int lastFocused: -1
    property real iconSize: (Config.options?.dock.height ?? 60) - 25
    property real countDotWidth: 10
    property real countDotHeight: 4
    property bool appIsActive: appToplevel.toplevels.find(t => (t.activated == true)) !== undefined
    property bool iconHovered: false

    readonly property bool isSeparator: appToplevel.appId === "SEPARATOR"
    property var desktopEntry: DesktopEntries.heuristicLookup(appToplevel.appId)
    enabled: !isSeparator
    implicitWidth: isSeparator ? 1 : implicitHeight - topInset - bottomInset

    // Drag-to-reorder feedback: dim while this is the icon being dragged.
    // Composed with RippleButton's own enabled-based dimming (opacity:
    // root.enabled ? 1 : 0.4) rather than replacing it outright -- a plain
    // override here would have undimmed the disabled separator entry too.
    // The dragged icon itself is drawn by DockApps' drag ghost; the real
    // delegate just leaves its (shifting) slot empty.
    opacity: root.isDragSource ? 0 : (root.enabled ? 1 : 0.4)
    // Disabled for ALL icons while ANY drag is active, not just the one
    // being dragged: indexAtContentPos()/listView.indexAt() hit-tests the
    // LIVE geometry of every delegate, and an animated-but-not-yet-settled
    // neighbor reports its old position for the next several frames. Query
    // that mid-flight and the hit-test sees the pre-swap arrangement, swaps
    // back, sees the post-swap arrangement again next frame, and so on --
    // the rapid "indecisive" back-and-forth this was producing. Snapping
    // instantly during the drag (still animating normally for any other
    // reflow, e.g. after a plain pin/unpin) removes the stale-geometry
    // window entirely.
    Behavior on x {
        enabled: appListRoot.draggingKey === ""
        animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
    }

    // Model index from the ListView (pinned apps always come first in
    // TaskbarApps.apps, so for pinned entries this equals the pinned index).
    property int listIndex: -1
    readonly property bool isDragSource: appListRoot.draggingKey !== "" && appListRoot.draggingKey === appToplevel.key

    // Purely visual drag displacement (see DockApps.beginDrag/updateDrag).
    readonly property real dragShift: {
        if (appListRoot.draggingKey === "")
            return 0;
        if (isDragSource)
            return appListRoot.dragOffsetX;
        const from = appListRoot.dragFromIndex;
        const to = appListRoot.dragToIndex;
        const i = root.listIndex;
        if (i < appListRoot.dragSectionStart || i > appListRoot.dragSectionEnd)
            return 0;
        if (from < to && i > from && i <= to)
            return -appListRoot.dragSlotWidth;
        if (to < from && i >= to && i < from)
            return appListRoot.dragSlotWidth;
        return 0;
    }
    z: isDragSource ? 10 : 0
    transform: Translate {
        x: root.dragShift
        // Neighbors slide smoothly; the dragged icon tracks the cursor 1:1;
        // everything snaps when the drag ends (the commit already moved x).
        Behavior on x {
            enabled: appListRoot.draggingKey !== "" && !appListRoot.dropping && !root.isDragSource
            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
        }
    }

    Connections {
        target: DesktopEntries

        function onApplicationsChanged() {
            root.desktopEntry = DesktopEntries.heuristicLookup(appToplevel.appId);
        }
    }

    Loader {
        active: isSeparator
        anchors {
            fill: parent
            topMargin: dockVisualBackground.margin + dockRow.padding + Appearance.rounding.normal
            bottomMargin: dockVisualBackground.margin + dockRow.padding + Appearance.rounding.normal
        }
        sourceComponent: DockSeparator {}
    }

    // Every app icon (pinned or running): this MouseArea takes over hover, click, right-click pin
    // toggle AND drag-to-reorder itself -- splitting drag detection across a
    // second MouseArea stacked on top of RippleButton's own wouldn't work,
    // since only one MouseArea can grab a given press. The trade-off (no
    // ripple flourish on pinned icons) mirrors the dashboard's Favorites
    // grid, which makes the same call for the same reason.
    Loader {
        anchors.fill: parent
        active: !isSeparator
        sourceComponent: MouseArea {
            id: dragArea
            anchors.fill: parent
            hoverEnabled: true
            acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
            // The enclosing ListView is a Flickable -- without this, a
            // horizontal drag meant for reordering gets stolen as a flick.
            preventStealing: true

            property bool dragging: false
            property real pressX: 0
            property real pressY: 0
            // Press point in content space (listView.contentItem). Local
            // coordinates can't be used for the offset: the delegate itself
            // is translated by that offset, which would cancel it out.
            // mapToItem() accounts for the Translate, so content space stays
            // a fixed frame for the whole gesture.
            property real pressContentX: 0

            onEntered: {
                root.iconHovered = true
                // Same suppression as the unpinned hover tracker above --
                // skip the preview-popup side effect while any drag is in
                // progress, including this icon's own (re-entering its own
                // hit region mid-drag shouldn't reopen the preview either).
                if (appListRoot.draggingKey !== "" || appListRoot.menuOpen) return
                if (appToplevel.toplevels.length === 0) return
                appListRoot.lastHoveredButton = root
                appListRoot.buttonHovered = true
                lastFocused = appToplevel.toplevels.length - 1
            }
            onExited: {
                root.iconHovered = false
                if (appListRoot.lastHoveredButton === root) {
                    appListRoot.buttonHovered = false
                }
            }
            // Shared cleanup for every way a drag can conclude: a normal
            // left-button release, the press getting cancelled (window focus
            // loss, the compositor stealing the grab, ...), or this delegate
            // being destroyed outright mid-drag (unpinned via the right-
            // click action while still holding the left button, say). Without
            // this reachable from onCanceled/Component.onDestruction too, a
            // cancelled press left draggingId stuck non-empty forever --
            // dragStepTimer (repeat: true) would keep re-evaluating and
            // reordering off stale coordinates indefinitely, every other
            // icon's hover-triggered preview popup would stay suppressed
            // dock-wide, and this icon would stay dimmed at opacity 0.4.
            function endDrag(commit) {
                if (!dragging)
                    return;
                dragging = false;
                appListRoot.endDrag(commit);
            }

            // Only the button that actually started the gesture governs it.
            // Right/middle presses arriving while already mid-left-drag must
            // not touch pressX/pressY/dragging -- doing so used to silently
            // end the drag, and the eventual left-button release would then
            // read !dragging and launch/activate the app despite having
            // just been dragged.
            onPressed: mouse => {
                if (mouse.button !== Qt.LeftButton)
                    return;
                pressX = mouse.x;
                pressY = mouse.y;
                pressContentX = appListRoot.mapToContent(dragArea, mouse.x, mouse.y).x;
                dragging = false;
                appListRoot.pressActive = true;
            }
            onPressedChanged: if (!pressed) appListRoot.pressActive = false
            onPositionChanged: mouse => {
                if (!(pressedButtons & Qt.LeftButton))
                    return;
                if (!dragging && (Math.abs(mouse.x - pressX) > 8 || Math.abs(mouse.y - pressY) > 8)) {
                    dragging = true;
                    appListRoot.beginDrag(appToplevel, root.listIndex, root, pressContentX,
                        root.contentItem.mapToItem(appListRoot, 0, root.contentItem.height / 2).y,
                        root.iconSize);
                    // Close any preview popup that was already open before
                    // the drag started.
                    appListRoot.buttonHovered = false;
                }
                if (dragging) {
                    appListRoot.trackDragCursor(dragArea, mouse.x, mouse.y);
                }
            }
            // Right/middle releases run their own action (if this wasn't
            // actually a left-drag in progress) without ever touching
            // dragging/draggingId -- releasing the right button while still
            // holding the left one mid-drag must not end that drag.
            onReleased: mouse => {
                if (mouse.button === Qt.LeftButton) {
                    if (!dragging) {
                        if (appToplevel.toplevels.length === 0) {
                            root.desktopEntry?.execute();
                        } else {
                            lastFocused = (lastFocused + 1) % appToplevel.toplevels.length;
                            appToplevel.toplevels[lastFocused].activate();
                        }
                    }
                    dragArea.endDrag(true);
                    // The cursor never "re-entered" if it's been sitting over
                    // this same icon the whole time (hover was suppressed for
                    // the drag's duration, see onPositionChanged above), so
                    // restore it here instead of waiting on an onEntered that
                    // won't come until the cursor actually leaves and returns.
                    if (dragArea.containsMouse && appToplevel.toplevels.length > 0) {
                        appListRoot.lastHoveredButton = root;
                        appListRoot.buttonHovered = true;
                        lastFocused = appToplevel.toplevels.length - 1;
                    }
                } else if (mouse.button === Qt.RightButton) {
                    if (!dragging)
                        appListRoot.openAppMenu(dragArea, mouse.x, mouse.y, appToplevel.appId);
                } else if (mouse.button === Qt.MiddleButton) {
                    if (!dragging)
                        root.desktopEntry?.execute();
                }
            }
            // Cancelled / destroyed mid-drag: drop the preview, keep the old order.
            onCanceled: dragArea.endDrag(false)
            Component.onDestruction: dragArea.endDrag(false)
        }
    }

    onClicked: {
        if (appToplevel.toplevels.length === 0) {
            root.desktopEntry?.execute();
            return;
        }
        lastFocused = (lastFocused + 1) % appToplevel.toplevels.length
        appToplevel.toplevels[lastFocused].activate()
    }

    middleClickAction: () => {
        root.desktopEntry?.execute();
    }

    altAction: (event) => {
        appListRoot.openAppMenu(root, event.x, event.y, appToplevel.appId);
    }

    contentItem: Loader {
        active: !isSeparator
        sourceComponent: Item {
            anchors.centerIn: parent

            transform: Translate {
                y: (root.iconHovered && (Config.options?.dock.raiseOnHover ?? true)) ? -8 : 0
                Behavior on y {
                    animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                }
            }

            Loader {
                id: iconImageLoader
                anchors {
                    left: parent.left
                    right: parent.right
                    verticalCenter: parent.verticalCenter
                }
                active: !root.isSeparator
                sourceComponent: IconImage {
                    source: Quickshell.iconPath(AppSearch.guessIcon(appToplevel.appId), "image-missing")
                    implicitSize: root.iconSize
                }
            }

            Loader {
                active: Config.options?.dock?.monochromeIcons ?? false
                anchors.fill: iconImageLoader
                sourceComponent: Item {
                    Desaturate {
                        id: desaturatedIcon
                        visible: false // There's already color overlay
                        anchors.fill: parent
                        source: iconImageLoader
                        desaturation: 0.8
                    }
                    ColorOverlay {
                        anchors.fill: desaturatedIcon
                        source: desaturatedIcon
                        color: ColorUtils.transparentize(Appearance.colors.colPrimary, 0.9)
                    }
                }
            }

            RowLayout {
                spacing: 3
                anchors {
                    top: iconImageLoader.bottom
                    topMargin: 2
                    horizontalCenter: parent.horizontalCenter
                }
                Repeater {
                    model: Math.min(appToplevel.toplevels.length, 3)
                    delegate: Rectangle {
                        required property int index
                        radius: Appearance.rounding.full
                        implicitWidth: (appToplevel.toplevels.length <= 3) ? 
                            root.countDotWidth : root.countDotHeight // Circles when too many
                        implicitHeight: root.countDotHeight
                        color: appIsActive ? Appearance.colors.colPrimary : ColorUtils.transparentize(Appearance.colors.colOnLayer0, 0.4)
                    }
                }
            }
        }
    }
}
