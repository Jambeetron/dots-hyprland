import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.services
import QtQuick
import QtQuick.Layouts
import Quickshell

Item {
    id: root
    property real dialogPadding: 15
    property real dialogMargin: 30
    property string titleText: "Selection Dialog"
    property var items: []
    property var defaultChoice
    property var selectedValue: defaultChoice
    property int selectedId: root.items.indexOf(root.selectedValue)
    property string filterText: ""
    property bool searchable: true
    property string itemActionText: "" // When set, shows a button next to each item (emits itemAction)
    property string itemActionIcon: ""
    // Per-item button: function(item) -> {icon, text, tooltip, highlight, busy} or null. Overrides itemActionText/Icon.
    property var itemActionProvider: null
    property int itemActionRevision: 0 // Bump to re-evaluate itemActionProvider
    property string titleActionIcon: "" // Optional button at the right of the title (emits titleAction)
    property string titleActionTooltip: ""
    property bool titleActionBusy: false
    signal titleAction()
    property string footnote: "" // Optional note under the choices, with an info icon
    property string listTitle: "" // Optional label above the list
    // Optional second group of choices above the list (e.g. the voice engine above the speeds),
    // read with groupSelectedValue when the dialog is accepted
    property string groupTitle: ""
    property var groupItems: []
    property var groupDefaultChoice
    property var groupSelectedValue: groupDefaultChoice
    property var groupItemActionProvider: null // Like itemActionProvider
    signal groupItemAction(var item)
    property var groupItemInfoProvider: null // Optional second button after the action one (emits groupItemInfo)
    signal groupItemInfo(var item)
    // Optional hidden text field under the group (e.g. an API key), read with groupFieldText
    property bool groupFieldVisible: false
    property string groupFieldPlaceholder: ""
    property alias groupFieldText: groupField.text
    // Menu mode (needs groupItems): a main menu with two entries (groupTitle and listTitle) that open
    // their choices as submenus. ↑/↓ move between entries, ←/→ change the option of the current entry,
    // Enter opens a submenu / chooses, Esc goes back (and closes without saving).
    // ↓ past the last entry (or the last option of a submenu) focuses the Cancel/OK buttons (←/→ choose, Enter presses)
    property bool menuMode: false
    property string page: "" // "" (main menu), "group" or "list"
    property int menuIndex: 0 // 0..entries-1: the entries; entries.length: the Cancel/OK buttons
    property int buttonIndex: 1 // 0: Cancel, 1: OK (when the buttons row is focused)
    property bool pageButtons: false // The Cancel/OK buttons are focused inside a submenu
    readonly property bool buttonsFocused: root.menuMode
        && (root.page === "" ? root.menuIndex === root.menuEntries.length : root.pageButtons)

    function focusButtons(index) {
        if (!root.menuMode) return;
        if (root.page === "") root.menuIndex = root.menuEntries.length;
        else root.pageButtons = true;
        root.buttonIndex = index;
    }

    // Index of the chosen option in the open submenu, and how many there are
    function pageOptionIndex() {
        return root.page === "group" ? root.groupItems.indexOf(root.groupSelectedValue) : root.filteredItems.indexOf(root.selectedValue);
    }
    function pageOptionCount() {
        return root.page === "group" ? root.groupItems.length : root.filteredItems.length;
    }
    property var pageStartValue // Value when the submenu was opened, restored with Esc
    readonly property var menuEntries: [
        { page: "group", title: root.groupTitle, icon: "record_voice_over", value: root.groupSelectedValue },
        { page: "list", title: root.listTitle, icon: "speed", value: root.selectedValue },
    ]
    readonly property bool showGroup: root.groupItems.length > 0 && (!root.menuMode || root.page === "group")
    readonly property bool showList: !root.menuMode || root.page === "list"

    function openPage(page) {
        root.pageStartValue = page === "group" ? root.groupSelectedValue : root.selectedValue;
        root.page = page;
        root.pageButtons = false;
        root.menuIndex = page === "group" ? 0 : 1;
        root.forceActiveFocus();
    }

    function closePage(revert) {
        if (revert) {
            if (root.page === "group") root.groupSelectedValue = root.pageStartValue;
            else root.selectedValue = root.pageStartValue;
        }
        root.page = "";
        root.pageButtons = false;
        root.forceActiveFocus();
    }

    function moveGroupSelection(step) {
        const count = root.groupItems.length;
        if (count === 0) return;
        const current = root.groupItems.indexOf(root.groupSelectedValue);
        const next = current === -1 ? (step > 0 ? 0 : count - 1) : Math.max(0, Math.min(count - 1, current + step));
        root.groupSelectedValue = root.groupItems[next];
    }

    // "XTTS-v2 — local on your GPU" -> "XTTS-v2"
    function shortLabel(value) {
        return (value ?? "").toString().split(" — ")[0];
    }
    property var filteredItems: {
        const query = root.normalize(root.filterText.trim());
        if (query.length === 0) return root.items;
        return root.items.filter(item => root.normalize(item).includes(query));
    }

    function normalize(value) {
        let str = (value ?? "").toString().toLowerCase();
        try {
            str = str.normalize("NFD").replace(/[\u0300-\u036f]/g, "");
        } catch (e) {}
        return str;
    }

    function moveSelection(step) {
        const count = root.filteredItems.length;
        if (count === 0) return;
        const current = root.filteredItems.indexOf(root.selectedValue);
        const next = current === -1
            ? (step > 0 ? 0 : count - 1)
            : Math.max(0, Math.min(count - 1, current + step));
        root.selectedValue = root.filteredItems[next];
        choiceListView.positionViewAtIndex(next, ListView.Contain);
    }

    function accept() {
        if (root.filterText.trim().length > 0 && !root.filteredItems.includes(root.selectedValue))
            root.selected(root.filteredItems.length > 0 ? root.filteredItems[0] : null);
        else
            root.selected(root.selectedValue ?? null);
    }

    signal canceled();
    signal selected(var result);

    // Keyboard works in every dialog (with or without the search field) and after clicking an item;
    // Esc closes only this dialog, not the sidebar behind it
    focus: true
    Keys.onPressed: event => {
        if (root.menuMode) {
            const enter = event.key === Qt.Key_Return || event.key === Qt.Key_Enter;
            if (root.page === "") {
                if (event.key === Qt.Key_Escape) root.canceled(); // Close without saving
                else if (event.key === Qt.Key_Up) root.menuIndex = Math.max(0, root.menuIndex - 1);
                else if (event.key === Qt.Key_Down) root.menuIndex = Math.min(root.menuEntries.length, root.menuIndex + 1);
                else if (event.key === Qt.Key_Left || event.key === Qt.Key_Right) {
                    const step = event.key === Qt.Key_Left ? -1 : 1;
                    if (root.buttonsFocused) root.buttonIndex = step < 0 ? 0 : 1; // Cancel / OK
                    else root.menuEntries[root.menuIndex].page === "group" ? root.moveGroupSelection(step) : root.moveSelection(step); // Option of the entry
                }
                else if (enter) {
                    if (!root.buttonsFocused) root.openPage(root.menuEntries[root.menuIndex].page);
                    else if (root.buttonIndex === 0) root.canceled();
                    else root.accept();
                }
                else return;
            } else {
                const move = step => root.page === "group" ? root.moveGroupSelection(step) : root.moveSelection(step);
                if (event.key === Qt.Key_Escape) root.closePage(true);
                else if (event.key === Qt.Key_Up) {
                    if (root.pageButtons) root.pageButtons = false; // Back to the options
                    else move(-1);
                }
                else if (event.key === Qt.Key_Down) {
                    if (root.pageButtons) {}
                    else if (root.pageOptionIndex() >= root.pageOptionCount() - 1) root.focusButtons(1); // Past the last option
                    else move(1);
                }
                else if ((event.key === Qt.Key_Left || event.key === Qt.Key_Right) && root.pageButtons)
                    root.buttonIndex = event.key === Qt.Key_Left ? 0 : 1;
                else if (enter) {
                    if (!root.pageButtons) root.closePage(false);
                    else if (root.buttonIndex === 0) root.canceled();
                    else root.accept();
                }
                else return;
            }
            event.accepted = true;
            return;
        }
        if (event.key === Qt.Key_Escape) root.canceled();
        else if (event.key === Qt.Key_Up) root.moveSelection(-1);
        else if (event.key === Qt.Key_Down) root.moveSelection(1);
        else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) root.accept();
        else return;
        event.accepted = true;
    }
    Component.onCompleted: if (!root.searchable) Qt.callLater(root.forceActiveFocus) // After the children, so none keeps the focus
    signal itemAction(var item);

    component ItemActionButton: RippleButton { // Button next to a choice: {icon, text, tooltip, highlight, busy}
        id: itemActionButton
        property var choiceAction: null
        focusPolicy: Qt.NoFocus
        visible: choiceAction !== null
        enabled: !(choiceAction?.busy ?? false)
        Layout.alignment: Qt.AlignVCenter
        buttonRadius: Appearance.rounding.full
        implicitHeight: 30
        implicitWidth: actionRow.implicitWidth + 20
        StyledToolTip {
            extraVisibleCondition: (itemActionButton.choiceAction?.tooltip ?? "").length > 0
            text: itemActionButton.choiceAction?.tooltip ?? ""
        }
        contentItem: Item {
            RowLayout {
                id: actionRow
                anchors.centerIn: parent
                spacing: 4
                MaterialSymbol {
                    visible: (itemActionButton.choiceAction?.icon ?? "").length > 0
                    text: itemActionButton.choiceAction?.icon ?? ""
                    iconSize: Appearance.font.pixelSize.larger
                    color: (itemActionButton.choiceAction?.highlight ?? true) ? Appearance.colors.colPrimary : Appearance.colors.colSubtext
                }
                StyledText {
                    visible: text.length > 0
                    text: itemActionButton.choiceAction?.text ?? ""
                    color: (itemActionButton.choiceAction?.highlight ?? true) ? Appearance.colors.colPrimary : Appearance.colors.colSubtext
                    font.pixelSize: Appearance.font.pixelSize.small
                }
            }
        }
    }

    Rectangle { // Scrim
        id: scrimOverlay
        anchors.fill: parent
        radius: Appearance.rounding.small
        color: Appearance.colors.colScrim
        MouseArea {
            hoverEnabled: true
            anchors.fill: parent
            preventStealing: true
            propagateComposedEvents: false
        }
    }

    Rectangle { // The dialog
        id: dialog
        color: Appearance.m3colors.m3surfaceContainerHigh
        radius: Appearance.rounding.normal
        anchors.fill: parent
        anchors.margins: dialogMargin
        implicitHeight: dialogColumnLayout.implicitHeight
        
        ColumnLayout {
            id: dialogColumnLayout
            anchors.fill: parent
            spacing: 16

            RowLayout {
                Layout.topMargin: dialogPadding
                Layout.leftMargin: dialogPadding
                Layout.rightMargin: dialogPadding
                Layout.fillWidth: true

                RippleButton { // Back to the main menu
                    visible: root.menuMode && root.page !== ""
                    focusPolicy: Qt.NoFocus
                    Layout.alignment: Qt.AlignVCenter
                    implicitWidth: 34
                    implicitHeight: 34
                    buttonRadius: Appearance.rounding.full
                    onClicked: root.closePage(false)
                    contentItem: MaterialSymbol {
                        anchors.centerIn: parent
                        horizontalAlignment: Text.AlignHCenter
                        iconSize: Appearance.font.pixelSize.huge
                        text: "arrow_back"
                        color: Appearance.m3colors.m3onSurface
                    }
                    StyledToolTip {
                        text: Translation.tr("Back (Esc)")
                    }
                }

                StyledText {
                    id: dialogTitle
                    Layout.fillWidth: true
                    Layout.alignment: Qt.AlignLeft | Qt.AlignVCenter
                    color: Appearance.m3colors.m3onSurface
                    font.pixelSize: Appearance.font.pixelSize.larger
                    text: !root.menuMode || root.page === "" ? root.titleText
                        : root.page === "group" ? root.groupTitle : root.listTitle
                }

                RippleButton {
                    id: titleActionButton
                    focusPolicy: Qt.NoFocus
                    visible: root.titleActionIcon.length > 0
                    enabled: !root.titleActionBusy
                    Layout.alignment: Qt.AlignVCenter
                    implicitWidth: 34
                    implicitHeight: 34
                    buttonRadius: Appearance.rounding.full
                    onClicked: root.titleAction()
                    contentItem: MaterialSymbol {
                        anchors.centerIn: parent
                        horizontalAlignment: Text.AlignHCenter
                        iconSize: Appearance.font.pixelSize.huge
                        text: root.titleActionBusy ? "sync" : root.titleActionIcon
                        color: root.titleActionBusy ? Appearance.colors.colSubtext : Appearance.m3colors.m3onSurface
                        RotationAnimation on rotation { // Spin while busy
                            running: root.titleActionBusy
                            loops: Animation.Infinite
                            from: 360
                            to: 0
                            duration: 1000
                        }
                    }
                    StyledToolTip {
                        text: root.titleActionTooltip
                    }
                }
            }

            Rectangle {
                color: Appearance.m3colors.m3outline
                implicitHeight: 1
                Layout.fillWidth: true
                Layout.leftMargin: dialogPadding
                Layout.rightMargin: dialogPadding
            }

            MaterialTextField {
                id: searchField
                visible: root.searchable
                Layout.fillWidth: true
                Layout.leftMargin: dialogPadding
                Layout.rightMargin: dialogPadding
                placeholderText: Translation.tr("Search")
                wrapMode: TextEdit.NoWrap
                focus: root.searchable // Hidden: must not take the keys (↑/↓) from the dialog
                enabled: root.searchable
                onTextChanged: root.filterText = text
                onAccepted: root.accept()
                Keys.onEscapePressed: event => { root.canceled(); event.accepted = true; }
                Keys.onUpPressed: root.moveSelection(-1)
                Keys.onDownPressed: root.moveSelection(1)
                Component.onCompleted: if (root.searchable) forceActiveFocus()
            }

            ColumnLayout { // Main menu (menu mode)
                visible: root.menuMode && root.page === ""
                Layout.fillWidth: true
                Layout.leftMargin: dialogPadding
                Layout.rightMargin: dialogPadding
                spacing: 6
                Repeater {
                    model: root.menuEntries
                    delegate: RippleButton {
                        id: menuEntry
                        required property var modelData
                        required property int index
                        readonly property bool current: root.menuIndex === index
                        Layout.fillWidth: true
                        implicitHeight: 56
                        focusPolicy: Qt.NoFocus
                        buttonRadius: Appearance.rounding.normal
                        colBackground: current ? Appearance.colors.colSecondaryContainer : Appearance.colors.colLayer2
                        colBackgroundHover: current ? Appearance.colors.colSecondaryContainerHover : Appearance.colors.colLayer2Hover
                        colRipple: Appearance.colors.colSecondaryContainerActive
                        onHoveredChanged: if (hovered) root.menuIndex = index
                        onClicked: root.openPage(modelData.page)
                        leftPadding: 14
                        rightPadding: 10
                        contentItem: RowLayout {
                            spacing: 12
                            MaterialSymbol {
                                text: menuEntry.modelData.icon
                                iconSize: Appearance.font.pixelSize.huge
                                color: menuEntry.current ? Appearance.m3colors.m3onSecondaryContainer : Appearance.colors.colOnLayer2
                            }
                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 0
                                StyledText {
                                    text: menuEntry.modelData.title
                                    font.pixelSize: Appearance.font.pixelSize.normal
                                    color: menuEntry.current ? Appearance.m3colors.m3onSecondaryContainer : Appearance.colors.colOnLayer2
                                }
                                StyledText {
                                    Layout.fillWidth: true
                                    elide: Text.ElideRight
                                    // ‹ value › on the current entry: ←/→ change it
                                    text: menuEntry.current ? `‹ ${root.shortLabel(menuEntry.modelData.value)} ›` : root.shortLabel(menuEntry.modelData.value)
                                    font.pixelSize: Appearance.font.pixelSize.small
                                    color: menuEntry.current ? Appearance.m3colors.m3onSecondaryContainer : Appearance.colors.colSubtext
                                }
                            }
                            MaterialSymbol {
                                text: "chevron_right"
                                iconSize: Appearance.font.pixelSize.larger
                                color: menuEntry.current ? Appearance.m3colors.m3onSecondaryContainer : Appearance.colors.colSubtext
                            }
                        }
                    }
                }
            }

            ColumnLayout { // Optional group of choices above the list
                visible: root.showGroup
                Layout.fillWidth: true
                Layout.leftMargin: dialogPadding
                Layout.rightMargin: dialogPadding
                spacing: 6
                StyledText {
                    visible: root.groupTitle.length > 0 && !root.menuMode
                    text: root.groupTitle
                    color: Appearance.colors.colSubtext
                    font.pixelSize: Appearance.font.pixelSize.small
                }
                Repeater {
                    model: root.groupItems
                    delegate: GridLayout { // Option, with its buttons beside it; below it (right aligned) when there's little room
                        id: groupRow
                        required property var modelData
                        Layout.fillWidth: true
                        columnSpacing: 6
                        rowSpacing: 0
                        // Below when the text would need more than ~2 lines beside the buttons
                        readonly property bool narrow: groupButtons.implicitWidth > 0
                            && (groupRow.width - groupButtons.implicitWidth - groupRow.columnSpacing) * 2 < groupRadio.implicitWidth
                        columns: groupRow.narrow ? 1 : 2
                        readonly property var action: {
                            root.itemActionRevision; // Dependency
                            return root.groupItemActionProvider ? root.groupItemActionProvider(groupRow.modelData) : null;
                        }
                        StyledRadioButton {
                            id: groupRadio
                            Layout.fillWidth: true
                            focusPolicy: Qt.NoFocus
                            description: groupRow.modelData.toString()
                            checked: groupRow.modelData === root.groupSelectedValue
                            onCheckedChanged: if (checked) root.groupSelectedValue = groupRow.modelData
                        }
                        RowLayout {
                            id: groupButtons
                            Layout.alignment: Qt.AlignRight | Qt.AlignVCenter
                            spacing: 6
                            ItemActionButton {
                                choiceAction: groupRow.action
                                onClicked: root.groupItemAction(groupRow.modelData)
                            }
                            ItemActionButton {
                                choiceAction: {
                                    root.itemActionRevision; // Dependency
                                    return root.groupItemInfoProvider ? root.groupItemInfoProvider(groupRow.modelData) : null;
                                }
                                onClicked: root.groupItemInfo(groupRow.modelData)
                            }
                        }
                    }
                }
                MaterialTextField {
                    id: groupField
                    visible: root.groupFieldVisible
                    Layout.fillWidth: true
                    placeholderText: root.groupFieldPlaceholder
                    echoMode: TextInput.Password
                    onAccepted: root.menuMode ? root.closePage(false) : root.accept()
                    Keys.onEscapePressed: event => { root.menuMode ? root.closePage(true) : root.canceled(); event.accepted = true; }
                }
            }

            Item { // Keeps the footnote and buttons at the bottom when the list is hidden
                visible: !root.showList
                Layout.fillHeight: true
            }

            StyledText {
                visible: root.listTitle.length > 0 && !root.menuMode
                Layout.leftMargin: dialogPadding
                Layout.rightMargin: dialogPadding
                text: root.listTitle
                color: Appearance.colors.colSubtext
                font.pixelSize: Appearance.font.pixelSize.small
            }

            StyledListView {
                id: choiceListView
                visible: root.showList
                keyNavigationEnabled: false // ↑/↓ are handled by the dialog
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                currentIndex: root.filteredItems.indexOf(root.selectedValue)
                Component.onCompleted: if (currentIndex >= 0) positionViewAtIndex(currentIndex, ListView.Center)
                spacing: 6

                model: ScriptModel {
                    values: root.filteredItems
                }

                delegate: Item {
                    id: choiceItem
                    required property var modelData
                    required property int index
                    anchors {
                        left: parent?.left
                        right: parent?.right
                        leftMargin: root.dialogPadding
                        rightMargin: root.dialogPadding
                    }
                    implicitHeight: Math.max(radioButton.implicitHeight, actionButton.visible ? actionButton.implicitHeight : 0)
                    readonly property var action: {
                        root.itemActionRevision; // Dependency
                        if (root.itemActionProvider) return root.itemActionProvider(choiceItem.modelData);
                        return root.itemActionText.length > 0 ? { icon: root.itemActionIcon, text: root.itemActionText } : null;
                    }

                    RowLayout {
                        anchors.fill: parent
                        spacing: 6

                        StyledRadioButton {
                            id: radioButton
                            Layout.fillWidth: true
                            focusPolicy: Qt.NoFocus
                            description: choiceItem.modelData.toString()
                            checked: choiceItem.modelData === root.selectedValue

                            onCheckedChanged: {
                                if (checked) {
                                    root.selectedValue = choiceItem.modelData;
                                }
                            }
                        }

                        ItemActionButton {
                            id: actionButton
                            choiceAction: choiceItem.action
                            onClicked: root.itemAction(choiceItem.modelData)
                        }
                    }
                }
            }

            RowLayout {
                visible: root.footnote.length > 0
                Layout.fillWidth: true
                Layout.leftMargin: dialogPadding
                Layout.rightMargin: dialogPadding
                spacing: 10
                MaterialSymbol {
                    Layout.alignment: Qt.AlignTop
                    text: "info"
                    iconSize: Appearance.font.pixelSize.larger
                    color: Appearance.colors.colSubtext
                }
                StyledText {
                    Layout.fillWidth: true
                    wrapMode: Text.Wrap
                    font.pixelSize: Appearance.font.pixelSize.small
                    color: Appearance.colors.colSubtext
                    text: root.footnote
                }
            }

            Rectangle {
                color: Appearance.m3colors.m3outline
                implicitHeight: 1
                Layout.fillWidth: true
                Layout.leftMargin: dialogPadding
                Layout.rightMargin: dialogPadding
            }

            RowLayout {
                id: dialogButtonsRowLayout
                Layout.bottomMargin: dialogPadding
                Layout.leftMargin: dialogPadding
                Layout.rightMargin: dialogPadding
                Layout.alignment: Qt.AlignRight

                DialogButton {
                    readonly property bool current: root.buttonsFocused && root.buttonIndex === 0
                    buttonText: Translation.tr("Cancel")
                    colBackground: current ? Appearance.colors.colSecondaryContainer : ColorUtils.transparentize(Appearance.colors.colLayer3)
                    colBackgroundHover: current ? Appearance.colors.colSecondaryContainerHover : Appearance.colors.colLayer3Hover
                    colText: current ? Appearance.m3colors.m3onSecondaryContainer : Appearance.colors.colPrimary
                    onHoveredChanged: if (hovered) root.focusButtons(0)
                    onClicked: root.canceled()
                }
                DialogButton {
                    readonly property bool current: root.buttonsFocused && root.buttonIndex === 1
                    buttonText: Translation.tr("OK")
                    colBackground: current ? Appearance.colors.colSecondaryContainer : ColorUtils.transparentize(Appearance.colors.colLayer3)
                    colBackgroundHover: current ? Appearance.colors.colSecondaryContainerHover : Appearance.colors.colLayer3Hover
                    colText: current ? Appearance.m3colors.m3onSecondaryContainer : Appearance.colors.colPrimary
                    onHoveredChanged: if (hovered) root.focusButtons(1)
                    onClicked: root.accept()
                }
            }
        }
    }
}
