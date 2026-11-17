pragma ComponentBehavior: Bound

import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Hyprland
import Quickshell.Widgets

/**
 * Generic right-click menu for app icons (dock + dashboard).
 *
 * Call popup(item, x, y, entries) where x/y are in item's local coordinates
 * (usually the click position) and entries is an array of:
 *   { type: "action", text, icon?, symbol?, action: () => {} }
 *   { type: "check",  text, checked, action: () => {} }
 *   { type: "separator" }
 * "icon" is a freedesktop icon name, "symbol" a Material Symbol name.
 * Every entry closes the menu once triggered.
 */
PopupWindow {
    id: root

    property var entries: []
    // Prefer opening upwards (dock at the bottom of the screen).
    property bool preferUp: false
    property real padding: Appearance.sizes.elevationMargin

    signal menuClosed

    readonly property bool hasIcons: entries.some(e => e.type !== "separator" && (e.icon || e.symbol))
    readonly property bool hasChecks: entries.some(e => e.type === "check")

    color: "transparent"
    visible: false
    implicitWidth: popupBackground.implicitWidth + root.padding * 2
    implicitHeight: popupBackground.implicitHeight + root.padding * 2

    anchor {
        adjustment: PopupAdjustment.All
        gravity: (root.preferUp ? Edges.Top : Edges.Bottom) | Edges.Right
        edges: Edges.Top | Edges.Left
    }

    // Window the menu was opened from (dock / dashboard) and its root item.
    property var hostWindow: null
    property Item hostContentItem: null

    // Keyboard selection (index into entries; -1 = none). Opened from the
    // keyboard, the first item starts selected; mouse hover also moves it.
    property int currentIndex: -1

    function isSelectable(i) {
        return i >= 0 && i < root.entries.length && root.entries[i].type !== "separator";
    }

    // Step to the next/previous selectable entry, wrapping around.
    function moveSelection(delta) {
        const n = root.entries.length;
        if (n === 0)
            return;
        let i = root.currentIndex;
        for (let step = 0; step < n; step++) {
            i = i === -1 ? (delta > 0 ? 0 : n - 1) : (i + delta + n) % n;
            if (root.isSelectable(i)) {
                root.currentIndex = i;
                return;
            }
        }
    }

    function activateCurrent() {
        if (!root.isSelectable(root.currentIndex))
            return;
        const entry = root.entries[root.currentIndex];
        root.close();
        entry.action?.();
    }

    // Shared key handling: used by the menu's own focus item and by hosts
    // that keep keyboard focus themselves (the dashboard's search field).
    // Returns whether the key was consumed.
    function handleKey(key) {
        if (!root.visible)
            return false;
        switch (key) {
        case Qt.Key_Up:
        case Qt.Key_Backtab:
            root.moveSelection(-1);
            return true;
        case Qt.Key_Down:
        case Qt.Key_Tab:
            root.moveSelection(1);
            return true;
        case Qt.Key_Return:
        case Qt.Key_Enter:
            root.activateCurrent();
            return true;
        case Qt.Key_Escape:
        case Qt.Key_Left:
        case Qt.Key_Menu:
            root.close();
            return true;
        case Qt.Key_Right:
            return true; // no submenus; just don't leak it to the host
        }
        return false;
    }

    function popup(item, x, y, newEntries, fromKeyboard) {
        root.visible = false;
        root.currentIndex = -1;
        focusGrab.active = false;
        root.entries = newEntries;
        root.hostWindow = item.QsWindow?.window ?? null;
        root.hostContentItem = item.Window.contentItem ?? null;
        root.anchor.item = item;
        root.anchor.rect.x = x;
        root.anchor.rect.y = y;
        root.anchor.rect.width = 1;
        root.anchor.rect.height = 1;
        root.visible = true;
        if (fromKeyboard)
            root.moveSelection(1);
        // Activate the grab only after things settle: the popup surface must
        // be mapped, and a host that takes keyboard focus while the menu is
        // open (the dock) must have finished that focus change -- otherwise
        // Hyprland sees focus moving and clears the fresh grab, closing the
        // menu the instant it opened.
        grabDelay.restart();
    }

    function close() {
        if (!root.visible)
            return;
        grabDelay.stop();
        focusGrab.active = false;
        root.visible = false;
        root.menuClosed();
    }

    // Clicks in any OTHER window (desktop, apps, bar...) clear the grab.
    // The host window is part of the grab so its own clicks reach the
    // catcher below instead of being swallowed by the compositor.
    Timer {
        id: grabDelay
        interval: 150
        onTriggered: focusGrab.active = root.visible
    }

    HyprlandFocusGrab {
        id: focusGrab
        active: false
        windows: [root, root.hostWindow].filter(w => !!w)
        onCleared: root.close()
    }

    // Clicks inside the host window itself (rest of the dashboard / dock):
    // a full-window catcher laid over it while the menu is open.
    MouseArea {
        parent: root.hostContentItem
        anchors.fill: parent
        z: 100000
        visible: root.visible && parent !== null
        enabled: visible
        acceptedButtons: Qt.AllButtons
        onPressed: mouse => {
            mouse.accepted = true;
            root.close();
        }
        onWheel: wheel => root.close()
    }

    Item {
        anchors.fill: parent
        focus: true
        Keys.onPressed: event => event.accepted = root.handleKey(event.key)

        StyledRectangularShadow {
            target: popupBackground
        }

        Rectangle {
            id: popupBackground
            readonly property real padding: 4
            anchors {
                fill: parent
                margins: root.padding
            }
            color: Appearance.colors.colLayer0
            radius: Appearance.rounding.windowRounding
            border.width: 1
            border.color: Appearance.colors.colLayer0Border
            implicitWidth: Math.max(180, column.implicitWidth) + padding * 2
            implicitHeight: column.implicitHeight + padding * 2

            ColumnLayout {
                id: column
                anchors {
                    fill: parent
                    margins: popupBackground.padding
                }
                spacing: 0

                Repeater {
                    model: root.entries
                    delegate: Loader {
                        id: entryLoader
                        required property var modelData
                        required property int index
                        Layout.fillWidth: true
                        sourceComponent: modelData.type === "separator" ? separatorComp : itemComp

                        Component {
                            id: separatorComp
                            Rectangle {
                                implicitHeight: 9
                                color: "transparent"
                                Rectangle {
                                    anchors.centerIn: parent
                                    width: parent.width - 16
                                    height: 1
                                    color: Appearance.m3colors.m3outlineVariant
                                }
                            }
                        }

                        Component {
                            id: itemComp
                            RippleButton {
                                id: entryButton
                                readonly property var entry: entryLoader.modelData
                                readonly property bool selected: root.currentIndex === entryLoader.index
                                buttonRadius: popupBackground.radius - popupBackground.padding
                                // Keyboard selection uses the secondary-container tone (clearly
                                // visible on the menu's colLayer0 background, unlike the subtle
                                // colLayer1Hover); plain mouse hover keeps the usual hover tint.
                                buttonColor: entryButton.selected ? Appearance.colors.colSecondaryContainer
                                    : (entryButton.hovered ? colBackgroundHover : colBackground)
                                onHoveredChanged: if (hovered) root.currentIndex = entryLoader.index
                                horizontalPadding: 12
                                implicitWidth: entryRow.implicitWidth + horizontalPadding * 2
                                implicitHeight: 36

                                releaseAction: () => {
                                    root.close();
                                    entryButton.entry.action?.();
                                }

                                contentItem: RowLayout {
                                    id: entryRow
                                    anchors {
                                        verticalCenter: parent.verticalCenter
                                        left: parent.left
                                        right: parent.right
                                        leftMargin: entryButton.horizontalPadding
                                        rightMargin: entryButton.horizontalPadding
                                    }
                                    spacing: 8

                                    // Check column
                                    Item {
                                        visible: root.hasChecks
                                        implicitWidth: 20
                                        implicitHeight: 20
                                        MaterialSymbol {
                                            anchors.centerIn: parent
                                            visible: entryButton.entry.type === "check" && entryButton.entry.checked === true
                                            text: "check"
                                            iconSize: 20
                                        }
                                    }

                                    // Icon column
                                    Item {
                                        visible: root.hasIcons
                                        implicitWidth: 20
                                        implicitHeight: 20
                                        Loader {
                                            anchors.centerIn: parent
                                            active: !!entryButton.entry.icon
                                            sourceComponent: IconImage {
                                                asynchronous: true
                                                source: Quickshell.iconPath(entryButton.entry.icon, "image-missing")
                                                implicitSize: 20
                                                mipmap: true
                                            }
                                        }
                                        Loader {
                                            anchors.centerIn: parent
                                            active: !entryButton.entry.icon && !!entryButton.entry.symbol
                                            sourceComponent: MaterialSymbol {
                                                text: entryButton.entry.symbol
                                                iconSize: 20
                                            }
                                        }
                                    }

                                    StyledText {
                                        Layout.fillWidth: true
                                        text: entryButton.entry.text
                                        font.pixelSize: Appearance.font.pixelSize.smallie
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
