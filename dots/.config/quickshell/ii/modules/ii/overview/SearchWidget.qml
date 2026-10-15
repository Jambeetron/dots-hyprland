pragma ComponentBehavior: Bound

import Qt.labs.synchronizer
import Qt5Compat.GraphicalEffects
import QtQuick
import QtQuick.Layouts
import Quickshell

import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions

Item { // Wrapper
    id: root

    readonly property string xdgConfigHome: Directories.config
    readonly property int typingDebounceInterval: 200
    readonly property int typingResultLimit: 15 // Should be enough to cover the whole view

    property string searchingText: LauncherSearch.query
    readonly property bool clipboardMode: root.searchingText.startsWith(Config.options.search.prefix.clipboard)
    property var hoveredItem: null // Search item currently under the mouse
    property bool showResults: searchingText != ""
    implicitWidth: searchWidgetContent.implicitWidth + Appearance.sizes.elevationMargin * 2
    implicitHeight: searchWidgetContent.implicitHeight + searchBar.verticalPadding * 2 + Appearance.sizes.elevationMargin * 2

    function focusFirstItem() {
        appResults.currentIndex = 0;
    }

    function focusSearchInput() {
        searchBar.forceFocus();
    }

    function disableExpandAnimation() {
        searchBar.animateWidth = false;
    }

    function cancelSearch() {
        searchBar.searchInput.selectAll();
        LauncherSearch.query = "";
        searchBar.animateWidth = true;
    }

    function setSearchingText(text) {
        searchBar.searchInput.text = text;
        LauncherSearch.query = text;
    }

    // Clipboard-mode shortcuts. Returns true if handled.
    //   Ctrl+S            toggle "All history" / "Starred only"
    //   Ctrl+Shift+Delete clear clipboard history (starred entries are kept)
    //   Delete            delete the entry under the mouse (when typing in the search box)
    //   ←/→ + Enter       move between / run the actions of the entry under the mouse
    //                     (→ only enters the actions when the text cursor is at the end)
    function handleClipboardKeys(event, fromSearchInput) {
        if (!root.clipboardMode)
            return false;
        const ctrl = event.modifiers & Qt.ControlModifier;
        const shift = event.modifiers & Qt.ShiftModifier;
        const alt = event.modifiers & Qt.AltModifier;
        if (fromSearchInput && event.key === Qt.Key_Down && !ctrl && !shift && !alt && starFilter.visible) {
            starFilter.forceActiveFocus();
        } else if (event.key === Qt.Key_Delete && ctrl && shift) {
            Cliphist.wipe();
        } else if (event.key === Qt.Key_S && ctrl && !shift && !alt) {
            if (Cliphist.hasStarred)
                Cliphist.starredOnly = !Cliphist.starredOnly;
        } else if (fromSearchInput && event.key === Qt.Key_Delete && !ctrl && !shift && !alt
                && root.hoveredItem?.isClipboardEntry
                && searchBar.searchInput.cursorPosition === searchBar.searchInput.length
                && searchBar.searchInput.selectedText.length === 0) {
            root.hoveredItem.requestDelete();
        } else if (fromSearchInput && (event.key === Qt.Key_Left || event.key === Qt.Key_Right) && !ctrl && !shift && !alt
                && root.hoveredItem?.isClipboardEntry
                && (root.hoveredItem.actionIndex >= 0
                    || (event.key === Qt.Key_Right
                        && searchBar.searchInput.cursorPosition === searchBar.searchInput.length
                        && searchBar.searchInput.selectedText.length === 0))) {
            root.hoveredItem.moveAction(event.key === Qt.Key_Right ? 1 : -1);
        } else if (fromSearchInput && (event.key === Qt.Key_Return || event.key === Qt.Key_Enter)
                && root.hoveredItem?.isClipboardEntry && root.hoveredItem.actionIndex >= 0) {
            root.hoveredItem.triggerCurrentAction();
        } else {
            return false;
        }
        event.accepted = true;
        return true;
    }

    Keys.onPressed: event => {
        if (root.handleClipboardKeys(event, false))
            return;
        // Prevent Esc and Backspace from registering
        if (event.key === Qt.Key_Escape)
            return;

        // Handle Backspace: focus and delete character if not focused
        if (event.key === Qt.Key_Backspace) {
            if (!searchBar.searchInput.activeFocus) {
                root.focusSearchInput();
                if (event.modifiers & Qt.ControlModifier) {
                    // Delete word before cursor
                    let text = searchBar.searchInput.text;
                    let pos = searchBar.searchInput.cursorPosition;
                    if (pos > 0) {
                        // Find the start of the previous word
                        let left = text.slice(0, pos);
                        let match = left.match(/(\s*\S+)\s*$/);
                        let deleteLen = match ? match[0].length : 1;
                        searchBar.searchInput.text = text.slice(0, pos - deleteLen) + text.slice(pos);
                        searchBar.searchInput.cursorPosition = pos - deleteLen;
                    }
                } else {
                    // Delete character before cursor if any
                    if (searchBar.searchInput.cursorPosition > 0) {
                        searchBar.searchInput.text = searchBar.searchInput.text.slice(0, searchBar.searchInput.cursorPosition - 1) + searchBar.searchInput.text.slice(searchBar.searchInput.cursorPosition);
                        searchBar.searchInput.cursorPosition -= 1;
                    }
                }
                // Always move cursor to end after programmatic edit
                searchBar.searchInput.cursorPosition = searchBar.searchInput.text.length;
                event.accepted = true;
            }
            // If already focused, let TextField handle it
            return;
        }

        // Only handle visible printable characters (ignore control chars, arrows, etc.)
        if (event.text && event.text.length === 1 && event.key !== Qt.Key_Enter && event.key !== Qt.Key_Return && event.key !== Qt.Key_Delete && event.text.charCodeAt(0) >= 0x20) // ignore control chars like Backspace, Tab, etc.
        {
            if (!searchBar.searchInput.activeFocus) {
                root.focusSearchInput();
                // Insert the character at the cursor position
                searchBar.searchInput.text = searchBar.searchInput.text.slice(0, searchBar.searchInput.cursorPosition) + event.text + searchBar.searchInput.text.slice(searchBar.searchInput.cursorPosition);
                searchBar.searchInput.cursorPosition += 1;
                event.accepted = true;
                root.focusFirstItem();
            }
        }
    }

    StyledRectangularShadow {
        target: searchWidgetContent
    }
    Rectangle { // Background
        id: searchWidgetContent
        anchors {
            top: parent.top
            horizontalCenter: parent.horizontalCenter
            topMargin: Appearance.sizes.elevationMargin
        }
        clip: true
        implicitWidth: columnLayout.implicitWidth
        implicitHeight: columnLayout.implicitHeight
        radius: searchBar.height / 2 + searchBar.verticalPadding
        color: Appearance.colors.colBackgroundSurfaceContainer

        Behavior on implicitHeight {
            id: searchHeightBehavior
            enabled: GlobalStates.searchOpen && root.showResults
            animation: Appearance.animation.elementMove.numberAnimation.createObject(this)
        }

        ColumnLayout {
            id: columnLayout
            anchors {
                top: parent.top
                horizontalCenter: parent.horizontalCenter
            }
            spacing: 0

            // clip: true
            layer.enabled: true
            layer.effect: OpacityMask {
                maskSource: Rectangle {
                    width: searchWidgetContent.width
                    height: searchWidgetContent.width
                    radius: searchWidgetContent.radius
                }
            }

            SearchBar {
                id: searchBar
                property real verticalPadding: 4
                keyHandler: event => root.handleClipboardKeys(event, true)
                Layout.fillWidth: true
                Layout.leftMargin: 10
                Layout.rightMargin: 4
                Layout.topMargin: verticalPadding
                Layout.bottomMargin: verticalPadding
                Synchronizer on searchingText {
                    property alias source: root.searchingText
                }
            }

            Rectangle {
                // Separator
                visible: root.showResults
                Layout.fillWidth: true
                height: 1
                color: Appearance.colors.colOutlineVariant
            }

            Rectangle { // Clipboard filter: only shown when something is starred. ↑/↓ to enter/leave, ←/→ to choose
                id: starFilter
                visible: root.showResults && root.clipboardMode && Cliphist.hasStarred
                Layout.alignment: Qt.AlignHCenter
                Layout.topMargin: 7
                implicitWidth: filterRow.implicitWidth + 6
                implicitHeight: filterRow.implicitHeight + 6
                radius: height / 2
                color: "transparent"
                border.width: starFilter.activeFocus ? 2 : 0
                border.color: Appearance.colors.colPrimary

                function enterList() {
                    appResults.forceActiveFocus();
                    appResults.currentIndex = 0;
                }

                Keys.onPressed: event => {
                    if (event.modifiers & (Qt.ControlModifier | Qt.AltModifier | Qt.ShiftModifier))
                        return;
                    switch (event.key) {
                    case Qt.Key_Left:
                        Cliphist.starredOnly = false;
                        break;
                    case Qt.Key_Right:
                        Cliphist.starredOnly = true;
                        break;
                    case Qt.Key_Up:
                        root.focusSearchInput();
                        break;
                    case Qt.Key_Down:
                    case Qt.Key_Return:
                    case Qt.Key_Enter:
                        starFilter.enterList();
                        break;
                    default:
                        return;
                    }
                    event.accepted = true;
                }

                RowLayout {
                    id: filterRow
                    anchors.centerIn: parent
                    spacing: 2
                    SelectionGroupButton {
                        leftmost: true
                        buttonIcon: "history"
                        buttonText: Translation.tr("All history")
                        toggled: !Cliphist.starredOnly
                        onClicked: Cliphist.starredOnly = false
                    }
                    SelectionGroupButton {
                        rightmost: true
                        buttonIcon: "star"
                        buttonText: Translation.tr("Starred only")
                        toggled: Cliphist.starredOnly
                        onClicked: Cliphist.starredOnly = true
                        StyledToolTip {
                            text: Translation.tr("Ctrl+S to toggle")
                        }
                    }
                }
            }

            ListView { // App results
                id: appResults
                visible: root.showResults
                Layout.fillWidth: true
                implicitHeight: Math.min(600, appResults.contentHeight + topMargin + bottomMargin)
                clip: true
                topMargin: 10
                bottomMargin: 10
                spacing: 2
                KeyNavigation.up: starFilter.visible ? starFilter : searchBar
                highlightMoveDuration: 100
                property int restoreIndex: -1 // Keep position after deleting an entry

                onFocusChanged: {
                    if (focus)
                        appResults.currentIndex = 1;
                }

                Connections {
                    target: root
                    function onSearchingTextChanged() {
                        if (appResults.count > 0)
                            appResults.currentIndex = 0;
                    }
                }

                Timer {
                    id: debounceTimer
                    interval: root.typingDebounceInterval
                    onTriggered: {
                        resultModel.values = LauncherSearch.results ?? [];
                    }
                }

                Connections {
                    target: LauncherSearch
                    function onResultsChanged() {
                        const restore = appResults.restoreIndex;
                        appResults.restoreIndex = -1;
                        if (restore >= 0) {
                            const savedY = appResults.contentY;
                            resultModel.values = LauncherSearch.results ?? [];
                            appResults.currentIndex = Math.max(0, Math.min(restore, appResults.count - 1));
                            Qt.callLater(() => {
                                appResults.contentY = savedY;
                                appResults.returnToBounds();
                            });
                            return;
                        }
                        resultModel.values = LauncherSearch.results.slice(0, root.typingResultLimit);
                        root.focusFirstItem();
                        debounceTimer.restart();
                    }
                }

                model: ScriptModel {
                    id: resultModel
                    objectProp: "key"
                }

                delegate: SearchItem {
                    id: searchItem
                    // The selectable item for each search result
                    required property var modelData
                    required property int index
                    anchors.left: parent?.left
                    anchors.right: parent?.right
                    entry: modelData
                    onDeleteRequested: appResults.restoreIndex = searchItem.index
                    onHoveredChanged: {
                        if (searchItem.hovered)
                            root.hoveredItem = searchItem;
                        else if (root.hoveredItem === searchItem)
                            root.hoveredItem = null;
                    }
                    Component.onDestruction: {
                        if (root.hoveredItem === searchItem)
                            root.hoveredItem = null;
                    }
                    query: StringUtils.cleanOnePrefix(root.searchingText, [Config.options.search.prefix.action, Config.options.search.prefix.app, Config.options.search.prefix.clipboard, Config.options.search.prefix.emojis, Config.options.search.prefix.math, Config.options.search.prefix.shellCommand, Config.options.search.prefix.webSearch])

                    Keys.onPressed: event => {
                        if (event.key === Qt.Key_Tab) {
                            if (LauncherSearch.results.length === 0)
                                return;
                            const tabbedText = searchItem.modelData.name;
                            LauncherSearch.query = tabbedText;
                            searchBar.searchInput.text = tabbedText;
                            event.accepted = true;
                            root.focusSearchInput();
                        }
                    }
                }
            }
        }
    }
}
