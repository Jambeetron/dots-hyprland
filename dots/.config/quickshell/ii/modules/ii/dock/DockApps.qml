pragma ComponentBehavior: Bound
import Qt5Compat.GraphicalEffects
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Widgets
import Quickshell.Wayland
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions

Item {
    id: root
    property real maxWindowPreviewHeight: 200
    property real maxWindowPreviewWidth: 300
    property real windowControlsHeight: 30
    property real buttonPadding: 5

    property Item lastHoveredButton: null
    property bool buttonHovered: false
    property bool requestDockShow: previewPopup.show || appMenu.visible
    readonly property bool menuOpen: appMenu.visible

    // Right-click menu for any dock icon (pin / grouping).
    function openAppMenu(button, x, y, appId) {
        root.buttonHovered = false;
        appMenu.popup(button, x, y, AppMenuEntries.dockEntries(appId));
        menuKeys.forceActiveFocus();
    }

    // Keyboard navigation for the menu (arrows, Enter, Esc). Dock.qml gives
    // the dock surface exclusive keyboard focus only while the menu is
    // open, so keys land here (or in the menu's own popup, whichever
    // the compositor focuses -- both route through handleKey()).
    Item {
        id: menuKeys
        focus: true
        Keys.onPressed: event => event.accepted = appMenu.handleKey(event.key)
    }

    AppContextMenu {
        id: appMenu
        preferUp: true
    }

    // Drag-to-reorder state, shared across DockAppButton delegates: the
    // entry key of the icon currently being dragged, or "" when nothing is.
    // Works within a section: pinned icons reorder among pinned ones,
    // running icons among running ones (the separator is the boundary).
    property string draggingKey: ""
    property bool dragPinned: false

    // The model is NEVER touched while a drag is in progress. Instead the
    // dragged icon follows the cursor through a Translate transform, and its
    // neighbors slide aside by exactly one slot (also via Translate, which
    // doesn't feed back into the ListView layout or into indexAt()). The
    // target slot is a pure function of the cursor offset from the press
    // point, so there's no geometry to go stale and nothing to oscillate.
    // The reorder is committed exactly once, on release.
    property int dragFromIndex: -1
    property int dragToIndex: -1
    // Model-index range [dragSectionStart, dragSectionEnd] the drag may move in.
    property int dragSectionStart: 0
    property int dragSectionEnd: 0
    property real dragSlotWidth: 1
    property real dragOffsetX: 0

    // Cursor during a drag: press point in content space, latest position
    // in viewport (listView) space. Kept separately so the target can be
    // recomputed when the list scrolls under a still cursor (auto-scroll).
    property real dragPressContentX: 0
    property real dragViewX: 0

    // Drag ghost: the dragged icon is drawn by `dragGhost` below, outside the
    // ListView. The real delegate is hidden while dragging -- ListView culls
    // (stops drawing) any delegate whose layout slot has scrolled out of the
    // viewport, so a delegate that's merely Translate'd toward the cursor
    // vanished mid-drag once edge auto-scroll carried its slot off-screen.
    property string dragAppId: ""
    property real dragItemContentX: 0   // dragged delegate's slot x (content space)
    property real dragItemWidth: 0
    property real dragIconCenterY: 0    // in this item's coordinates
    property real dragIconSize: 0

    function beginDrag(entry, fromIndex, delegate, pressContentX, iconCenterY, iconSize) {
        const itemWidth = delegate.width;
        root.dragPressContentX = pressContentX;
        root.dragAppId = entry.appId;
        root.dragItemContentX = delegate.x;
        root.dragItemWidth = itemWidth;
        root.dragIconCenterY = iconCenterY;
        root.dragIconSize = iconSize;
        const apps = TaskbarApps.apps;
        const pinnedCount = apps.filter(a => a.pinned).length;
        if (entry.pinned) {
            root.dragSectionStart = 0;
            root.dragSectionEnd = pinnedCount - 1;
        } else {
            root.dragSectionStart = pinnedCount > 0 ? pinnedCount + 1 : 0; // skip separator
            root.dragSectionEnd = apps.length - 1;
        }
        root.dragPinned = entry.pinned;
        root.dragSlotWidth = Math.max(1, itemWidth + listView.spacing);
        root.dragFromIndex = fromIndex;
        root.dragToIndex = fromIndex;
        root.dragOffsetX = 0;
        root.draggingKey = entry.key;
    }

    function trackDragCursor(item, x, y) {
        root.dragViewX = item.mapToItem(listView, x, y).x;
        root.refreshDrag();
    }

    function refreshDrag() {
        const contentX = listView.mapToItem(listView.contentItem, root.dragViewX, 0).x;
        root.updateDrag(contentX - root.dragPressContentX);
    }

    function updateDrag(offsetX) {
        if (root.draggingKey === "")
            return;
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
        if (commit && to !== from) {
            if (root.dragPinned)
                TaskbarApps.reorder(key, to);
            else
                TaskbarApps.reorderRunning(key, to - root.dragSectionStart);
            // Lay out synchronously while draggingKey is still set, so the
            // x Behavior stays disabled and the new x lands in the same
            // frame the Translate offsets below drop back to 0 -- no jump.
            listView.forceLayout();
        }
        root.dragOffsetX = 0;
        root.dragFromIndex = -1;
        root.dragToIndex = -1;
        root.draggingKey = "";
    }

    Layout.fillHeight: true
    Layout.topMargin: Appearance.sizes.hyprlandGapsOut
    // Set by Dock.qml to the room left on screen; past it the list scrolls.
    property real maxWidth: Infinity
    implicitWidth: Math.min(listView.implicitWidth, root.maxWidth)
    Layout.preferredWidth: implicitWidth
    Layout.maximumWidth: implicitWidth

    // ---- Horizontal scrolling (only does anything when the list overflows)
    readonly property real minContentX: listView.originX
    readonly property real maxContentX: listView.originX + Math.max(0, listView.contentWidth - listView.width)
    property real scrollTargetX: 0

    function clampContentX(x) {
        return Math.max(root.minContentX, Math.min(x, root.maxContentX));
    }

    function scrollBy(dx, animated) {
        const base = scrollAnimX.running ? root.scrollTargetX : listView.contentX;
        root.scrollTargetX = root.clampContentX(base + dx);
        if (animated) {
            scrollAnimX.to = root.scrollTargetX;
            scrollAnimX.restart();
        } else {
            scrollAnimX.stop();
            listView.contentX = root.scrollTargetX;
        }
    }

    // Keep the view in range when apps open/close or the dock resizes.
    onMaxContentXChanged: if (!scrollAnimX.running && listView.contentX > root.maxContentX) listView.contentX = root.maxContentX
    onMinContentXChanged: if (!scrollAnimX.running && listView.contentX < root.minContentX) listView.contentX = root.minContentX

    NumberAnimation {
        id: scrollAnimX
        target: listView
        property: "contentX"
        duration: Appearance.animation.scroll.duration
        easing.type: Appearance.animation.scroll.type
        easing.bezierCurve: Appearance.animation.scroll.bezierCurve
    }

    // Edge auto-scroll for an overflowing dock: while the cursor sits near
    // either end -- just hovering, or dragging an icon -- keep scrolling that
    // way, faster the closer it is to the edge. Hover scrolls gentler than a
    // drag; nothing scrolls while the right-click menu is open.
    readonly property bool canScroll: root.maxContentX > root.minContentX
    readonly property bool edgeHoverActive: listHover.hovered && root.draggingKey === "" && !root.menuOpen && !root.pressActive
    // Set by DockAppButton while a mouse button is held on an icon.
    property bool pressActive: false
    Timer {
        interval: 16
        repeat: true
        running: root.canScroll && (root.draggingKey !== "" || root.edgeHoverActive)
        onTriggered: {
            const dragging = root.draggingKey !== "";
            const x = dragging ? root.dragViewX : listHover.point.position.x;
            const edge = dragging ? 48 : 40;
            const maxSpeed = dragging ? 14 : 8;
            let v = 0;
            if (x < edge)
                v = -maxSpeed * Math.min(1, (edge - x) / edge);
            else if (x > listView.width - edge)
                v = maxSpeed * Math.min(1, (x - (listView.width - edge)) / edge);
            if (v === 0)
                return;
            const before = listView.contentX;
            root.scrollBy(v, false);
            if (dragging && listView.contentX !== before)
                root.refreshDrag();
        }
    }

    function popupCenterXForButton(button) {
        if (!button || !root.QsWindow)
            return 0;
        return root.QsWindow.mapFromItem(button, button.width / 2, 0).x;
    }

    // Converts a point in fromItem's local coordinates (typically the
    // dragged delegate's own MouseArea, at the moment of a real mouse
    // event) into the list's content coordinates. Deliberately split from
    // indexAtContentPos below: the dragged delegate itself snaps to a new
    // x each time it's reordered, so re-deriving content coordinates from
    // its *current* position on every timer tick (instead of once, right
    // when the mouse actually moved) would silently drift -- the stored
    // content-space point stays correct regardless of how many times the
    // delegate has since moved.
    function mapToContent(fromItem, x, y) {
        return fromItem.mapToItem(listView.contentItem, x, y);
    }

    // Hit-tests an already-content-space point (see mapToContent above)
    // against the list.
    function indexAtContentPos(x, y) {
        return listView.indexAt(x, y);
    }

    StyledListView {
        id: listView
        spacing: 2
        orientation: ListView.Horizontal
        anchors {
            top: parent.top
            bottom: parent.bottom
            left: parent.left
            right: parent.right
        }
        implicitWidth: contentWidth
        clip: true
        // Keep EVERY delegate instantiated, even when scrolled far out of
        // view. By default ListView destroys delegates beyond the visible
        // area + a small cache; when edge auto-scroll carried the dragged
        // icon's slot that far, its MouseArea was destroyed mid-drag, which
        // cancelled the drag and snapped the app back. A dock holds a few
        // dozen icons at most, so keeping them all alive is cheap.
        cacheBuffer: 100000
        // Scrolling is wheel-only (see the MouseArea below); dragging on the
        // list is reserved for reordering icons.
        interactive: false

        Behavior on implicitWidth {
            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
        }

        model: ScriptModel {
            objectProp: "key"
            values: TaskbarApps.apps
        }
        delegate: DockAppButton {
            required property var modelData
            required property int index
            appToplevel: modelData
            listIndex: index
            appListRoot: root

            topInset: Appearance.sizes.hyprlandGapsOut + root.buttonPadding
            bottomInset: Appearance.sizes.hyprlandGapsOut + root.buttonPadding
        }
    }

    Item {
        id: dragGhost
        visible: root.draggingKey !== ""
        z: 100
        width: root.dragItemWidth
        height: root.dragIconSize
        // Slot position + drag offset, converted from content to view space
        // (tracks scrolling too), kept inside the list's visible area.
        // (content -> view is just "- contentX"; written out explicitly so
        // the binding re-evaluates on every scroll step.)
        x: Math.max(listView.x, Math.min(
            listView.x + root.dragItemContentX + root.dragOffsetX - listView.contentX,
            listView.x + listView.width - width))
        y: root.dragIconCenterY - height / 2 - ((Config.options?.dock.raiseOnHover ?? true) ? 8 : 0)

        IconImage {
            id: ghostIcon
            anchors.centerIn: parent
            visible: !(Config.options?.dock?.monochromeIcons ?? false)
            source: root.dragAppId === "" ? "" : Quickshell.iconPath(AppSearch.guessIcon(root.dragAppId), "image-missing")
            implicitSize: root.dragIconSize
        }
        Loader {
            active: Config.options?.dock?.monochromeIcons ?? false
            anchors.fill: ghostIcon
            sourceComponent: Item {
                Desaturate {
                    id: ghostDesaturated
                    visible: false
                    anchors.fill: parent
                    source: ghostIcon
                    desaturation: 0.8
                }
                ColorOverlay {
                    anchors.fill: ghostDesaturated
                    source: ghostDesaturated
                    color: ColorUtils.transparentize(Appearance.colors.colPrimary, 0.9)
                }
            }
        }
    }

    // Wheel up -> apps slide left (reveal the right end), wheel down -> apps
    // slide right. Horizontal touchpad swipes follow the fingers.
    // Pointer handlers on this container (the ListView's parent), NOT an
    // overlay item on top of the icons: handlers here never take part in
    // press delivery, so clicks and drag-to-reorder on the icons are
    // untouched, and the HoverHandler stays hovered over the children too.
    WheelHandler {
        acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
        orientation: Qt.Vertical | Qt.Horizontal
        target: null
        onWheel: event => {
            const slot = (Config.options?.dock.height ?? 60) - 25;
            const useY = Math.abs(event.angleDelta.y) >= Math.abs(event.angleDelta.x);
            const delta = useY ? event.angleDelta.y : -event.angleDelta.x;
            root.scrollBy(delta / 120 * slot, true);
        }
    }

    // Tracks the cursor for edge auto-scroll (x is the same in listView
    // space: the list spans this item's full width).
    HoverHandler {
        id: listHover
    }

    PopupWindow {
        id: previewPopup
        property var appTopLevel: root.lastHoveredButton?.appToplevel

        property bool shouldShow: (popupMouseArea.containsMouse || root.buttonHovered) && appTopLevel && appTopLevel.toplevels && appTopLevel.toplevels.length > 0

        property bool show: false
        property real cachedCenterX: 0

        Connections {
            target: root
            function onLastHoveredButtonChanged() {
                if (root.lastHoveredButton && root.QsWindow)
                    previewPopup.cachedCenterX = root.popupCenterXForButton(root.lastHoveredButton);
            }
            function onButtonHoveredChanged() {
                if (root.buttonHovered && root.lastHoveredButton && root.QsWindow)
                    previewPopup.cachedCenterX = root.popupCenterXForButton(root.lastHoveredButton);
                updateTimer.restart();
            }
        }

        onShouldShowChanged: {
            updateTimer.restart();
        }

        Timer {
            id: updateTimer
            interval: 100
            onTriggered: {
                previewPopup.show = previewPopup.shouldShow;
            }
        }

        anchor {
            window: root.QsWindow.window
            adjustment: PopupAdjustment.None
            gravity: Edges.Top | Edges.Right
            edges: Edges.Top | Edges.Left
        }

        visible: popupBackground.opacity > 0
        color: "transparent"
        implicitWidth: root.QsWindow.window?.width ?? 1
        implicitHeight: popupMouseArea.implicitHeight + root.windowControlsHeight + Appearance.sizes.elevationMargin * 2

        MouseArea {
            id: popupMouseArea
            anchors.bottom: parent.bottom
            implicitWidth: popupBackground.implicitWidth + Appearance.sizes.elevationMargin * 2
            implicitHeight: root.maxWindowPreviewHeight + root.windowControlsHeight + Appearance.sizes.elevationMargin * 2
            hoverEnabled: true
            x: previewPopup.cachedCenterX - width / 2

            StyledRectangularShadow {
                target: popupBackground
                opacity: previewPopup.show ? 1 : 0
                visible: opacity > 0
                Behavior on opacity {
                    animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                }
            }

            Rectangle {
                id: popupBackground
                property real padding: 5
                opacity: previewPopup.show ? 1 : 0
                visible: opacity > 0
                Behavior on opacity {
                    animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                }
                clip: true
                color: Appearance.m3colors.m3surfaceContainer
                radius: Appearance.rounding.normal
                anchors.bottom: parent.bottom
                anchors.bottomMargin: Appearance.sizes.elevationMargin
                anchors.horizontalCenter: parent.horizontalCenter
                implicitHeight: previewRowLayout.implicitHeight + padding * 2
                implicitWidth: previewRowLayout.implicitWidth + padding * 2
                Behavior on implicitWidth {
                    animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                }
                Behavior on implicitHeight {
                    animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                }

                RowLayout {
                    id: previewRowLayout
                    anchors.centerIn: parent
                    Repeater {
                        model: ScriptModel {
                            values: previewPopup.appTopLevel?.toplevels ?? []
                        }
                        RippleButton {
                            id: windowButton
                            Layout.fillHeight: true
                            required property var modelData
                            padding: 0
                            middleClickAction: () => {
                                windowButton.modelData?.close();
                            }
                            onClicked: {
                                windowButton.modelData?.activate();
                            }
                            contentItem: ColumnLayout {
                                implicitWidth: screencopyView.implicitWidth
                                implicitHeight: screencopyView.implicitHeight

                                ButtonGroup {
                                    contentWidth: parent.width - anchors.margins * 2
                                    StyledText {
                                        Layout.margins: 5
                                        Layout.fillWidth: true
                                        font.pixelSize: Appearance.font.pixelSize.small
                                        text: windowButton.modelData?.title
                                        elide: Text.ElideRight
                                        color: Appearance.m3colors.m3onSurface
                                    }
                                    GroupButton {
                                        id: closeButton
                                        colBackground: ColorUtils.transparentize(Appearance.colors.colSurfaceContainer)
                                        baseWidth: root.windowControlsHeight
                                        baseHeight: root.windowControlsHeight
                                        buttonRadius: Appearance.rounding.full
                                        contentItem: MaterialSymbol {
                                            anchors.centerIn: parent
                                            horizontalAlignment: Text.AlignHCenter
                                            text: "close"
                                            iconSize: Appearance.font.pixelSize.normal
                                            color: Appearance.m3colors.m3onSurface
                                        }
                                        onClicked: {
                                            windowButton.modelData?.close();
                                        }
                                    }
                                }
                                Item {
                                    Layout.fillWidth: true
                                    Layout.fillHeight: true
                                    implicitHeight: screencopyView.height
                                    implicitWidth: screencopyView.width
                                    ScreencopyView {
                                        id: screencopyView
                                        anchors.centerIn: parent
                                        captureSource: windowButton.modelData
                                        live: true
                                        paintCursor: true
                                        constraintSize: Qt.size(root.maxWindowPreviewWidth, root.maxWindowPreviewHeight)
                                        layer.enabled: true
                                        layer.effect: OpacityMask {
                                            maskSource: Rectangle {
                                                width: screencopyView.width
                                                height: screencopyView.height
                                                radius: Appearance.rounding.small
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
