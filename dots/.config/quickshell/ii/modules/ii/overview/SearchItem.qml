// pragma NativeMethodBehavior: AcceptThisObject
import qs
import qs.services
import qs.modules.common
import qs.modules.common.models
import qs.modules.common.widgets
import qs.modules.common.functions
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Widgets
import Quickshell.Hyprland

RippleButton {
    id: root
    property LauncherSearchResult entry
    property string query
    property bool entryShown: entry?.shown ?? true
    property string itemType: entry?.type ?? Translation.tr("App")
    property string itemName: entry?.name ?? ""
    property var iconType: entry?.iconType
    property string iconName: entry?.iconName ?? ""
    property var itemExecute: entry?.execute
    property var fontType: switch(entry?.fontType) {
        case LauncherSearchResult.FontType.Monospace:
            return "monospace"
        case LauncherSearchResult.FontType.Normal:
            return "main"
        default:
            return "main"
    }
    property string itemClickActionName: entry?.verb ?? "Open"
    property string bigText: entry?.iconType === LauncherSearchResult.IconType.Text ? entry?.iconName ?? "" : ""
    property string materialSymbol: entry.iconType === LauncherSearchResult.IconType.Material ? entry?.iconName ?? "" : ""
    property string cliphistRawString: entry?.rawValue ?? ""
    property bool blurImage: entry?.blurImage ?? false
    readonly property bool isClipboardEntry: root.cliphistRawString.length > 0
    readonly property bool starred: root.isClipboardEntry && Cliphist.isStarred(root.cliphistRawString)

    signal deleteRequested() // Emitted right before a clipboard entry is deleted

    // ←/→ navigation between the action buttons (-1 = none, Enter acts on the row itself)
    readonly property var shownActions: root.isClipboardEntry ? (root.entry?.actions ?? []) : (root.entry?.actions ?? []).slice(0, 4)
    property int actionIndex: -1
    onSelectedChanged: if (!root.selected) root.actionIndex = -1
    function moveAction(delta) {
        const n = root.shownActions.length;
        if (n === 0) return false;
        root.actionIndex = Math.max(-1, Math.min(n - 1, root.actionIndex + delta));
        return true;
    }
    function triggerAction(action) {
        switch (action.id) {
        case "cliphist-qr":
            root.toggleQr();
            break;
        case "cliphist-delete":
            root.requestDelete();
            break;
        default:
            action.execute();
        }
    }
    function triggerCurrentAction() {
        const action = root.shownActions[root.actionIndex];
        if (!action) return false;
        root.triggerAction(action);
        return true;
    }

    function requestDelete() {
        const deleteAction = (root.entry?.actions ?? []).find(action => action.id === "cliphist-delete");
        if (!deleteAction) return false;
        root.deleteRequested();
        deleteAction.execute();
        return true;
    }

    // QR code (generated on demand into /tmp)
    property string qrPath: ""
    function toggleQr() {
        if (root.qrPath !== "") {
            root.qrPath = "";
            return;
        }
        const id = root.cliphistRawString.match(/^\s*(\d+)/)?.[1] ?? "x";
        qrProc.outPath = `/tmp/quickshell/media/cliphist-qr/${id}.png`;
        qrProc.running = true;
    }
    Process {
        id: qrProc
        property string outPath
        command: ["bash", "-c", 'mkdir -p "$(dirname "$3")" && printf "%s\\n" "$1" | "$2" decode | qrencode -s 8 -m 2 -o "$3"', "bash", root.cliphistRawString, Cliphist.cliphistBinary, qrProc.outPath]
        onExited: (exitCode, exitStatus) => {
            if (exitCode === 0) root.qrPath = qrProc.outPath;
            else Quickshell.execDetached(["notify-send", "Clipboard", Translation.tr("Couldn't generate QR code (content too long?)"), "-a", "Shell"]);
        }
    }
    
    visible: root.entryShown
    property int horizontalMargin: 10
    property int buttonHorizontalPadding: 10
    property int buttonVerticalPadding: 6
    property bool keyboardDown: false
    readonly property bool selected: (root.hovered || root.focus)

    implicitHeight: rowLayout.implicitHeight + root.buttonVerticalPadding * 2
    implicitWidth: rowLayout.implicitWidth + root.buttonHorizontalPadding * 2
    buttonRadius: Appearance.rounding.normal
    colBackground: (root.down || root.keyboardDown) ? Appearance.colors.colPrimaryContainerActive : 
        (selected ? Appearance.colors.colPrimaryContainer : 
        ColorUtils.transparentize(Appearance.colors.colPrimaryContainer, 1))
    colBackgroundHover: Appearance.colors.colPrimaryContainer
    colRipple: Appearance.colors.colPrimaryContainerActive
    property color colForeground: selected ? Appearance.colors.colOnPrimaryContainer : Appearance.m3colors.m3onSurface

    readonly property string highlightPrefix: `<u><font color="${Appearance.colors.colPrimary}">`
    readonly property string highlightSuffix: `</font></u>`
    // Note that this highlighting is independent from the search
    // It's close, but does not accurately represent how the fuzzy algorithm works
    function highlightContent(content, query) {
        if (!query || query.length === 0 || content == query || fontType === "monospace")
            return StringUtils.escapeHtml(content);

        let contentLower = content.toLowerCase();
        let queryLower = query.toLowerCase();

        let result = "";
        let lastIndex = 0;
        let qIndex = 0;

        for (let i = 0; i < content.length && qIndex < query.length; i++) {
            if (contentLower[i] === queryLower[qIndex]) {
                // Add non-highlighted part (escaped)
                if (i > lastIndex)
                    result += StringUtils.escapeHtml(content.slice(lastIndex, i));
                // Add highlighted character (escaped)
                result += root.highlightPrefix + StringUtils.escapeHtml(content[i]) + root.highlightSuffix;
                lastIndex = i + 1;
                qIndex++;
            }
        }
        // Add the rest of the string (escaped)
        if (lastIndex < content.length)
            result += StringUtils.escapeHtml(content.slice(lastIndex));

        return result;
    }
    property string displayContent: highlightContent(root.itemName, root.query)

    property list<string> urls: {
        if (!root.itemName) return [];
        // Regular expression to match URLs
        const urlRegex = /https?:\/\/[^\s<>"{}|\\^`[\]]+/gi;
        const matches = root.itemName?.match(urlRegex)
            ?.filter(url => !url.includes("…")) // Elided = invalid
        return matches ? matches : [];
    }
    
    PointingHandInteraction {}

    background {
        anchors.fill: root
        anchors.leftMargin: root.horizontalMargin
        anchors.rightMargin: root.horizontalMargin
    }

    onClicked: {
        GlobalStates.searchOpen = false
        root.itemExecute()
    }
    Keys.onPressed: (event) => {
        if (event.key === Qt.Key_Delete && root.isClipboardEntry && !(event.modifiers & Qt.ControlModifier)) {
            root.requestDelete();
            event.accepted = true;
        } else if (event.key === Qt.Key_Delete && event.modifiers === Qt.ShiftModifier) {
            const deleteAction = root.entry.actions.find(action => action.name == Translation.tr("Delete"));

            if (deleteAction) {
                deleteAction.execute()
            }
        } else if ((event.key === Qt.Key_Left || event.key === Qt.Key_Right) && event.modifiers === Qt.NoModifier
                && root.shownActions.length > 0) {
            root.moveAction(event.key === Qt.Key_Right ? 1 : -1);
            event.accepted = true;
        } else if ((event.key === Qt.Key_Return || event.key === Qt.Key_Enter) && root.actionIndex >= 0) {
            root.triggerCurrentAction();
            event.accepted = true;
        } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
            root.keyboardDown = true
            root.clicked()
            event.accepted = true;
        }
    }
    Keys.onReleased: (event) => {
        if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
            root.keyboardDown = false
            event.accepted = true;
        }
    }

    RowLayout {
        id: rowLayout
        spacing: iconLoader.sourceComponent === null ? 0 : 10
        anchors.fill: parent
        anchors.leftMargin: root.horizontalMargin + root.buttonHorizontalPadding
        anchors.rightMargin: root.horizontalMargin + root.buttonHorizontalPadding

        // Icon
        Loader {
            id: iconLoader
            active: true
            sourceComponent: switch(root.iconType) {
                case LauncherSearchResult.IconType.Material:
                    return materialSymbolComponent
                case LauncherSearchResult.IconType.Text:
                    return bigTextComponent
                case LauncherSearchResult.IconType.System:
                    return iconImageComponent
                case LauncherSearchResult.IconType.None:
                    return null
                default:
                    return null
            }
        }

        Component {
            id: iconImageComponent
            IconImage {
                source: Quickshell.iconPath(root.iconName, "image-missing")
                width: 35
                height: 35
            }
        }

        Component {
            id: materialSymbolComponent
            MaterialSymbol {
                text: root.materialSymbol
                iconSize: 30
                color: root.colForeground
            }
        }

        Component {
            id: bigTextComponent
            StyledText {
                text: root.bigText
                font.pixelSize: Appearance.font.pixelSize.larger
                color: root.colForeground
            }
        }

        // Main text
        ColumnLayout {
            id: contentColumn
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignVCenter
            spacing: 0
            StyledText {
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: root.selected ? Appearance.colors.colOnPrimaryContainer : Appearance.colors.colSubtext
                visible: root.itemType && root.itemType != Translation.tr("App")
                text: root.itemType
            }
            RowLayout {
                Loader { // Checkmark for copied clipboard entry
                    visible: itemName == Quickshell.clipboardText && root.cliphistRawString
                    active: itemName == Quickshell.clipboardText && root.cliphistRawString
                    sourceComponent: Rectangle {
                        implicitWidth: activeText.implicitHeight
                        implicitHeight: activeText.implicitHeight
                        radius: Appearance.rounding.full
                        color: Appearance.colors.colPrimary
                        MaterialSymbol {
                            id: activeText
                            anchors.centerIn: parent
                            text: "check"
                            font.pixelSize: Appearance.font.pixelSize.normal
                            color: Appearance.m3colors.m3onPrimary
                        }
                    }
                }
                Repeater { // Favicons for links
                    model: root.query == root.itemName ? [] : root.urls
                    Favicon {
                        required property var modelData
                        size: parent.height
                        url: modelData
                    }
                }
                StyledText { // Item name/content
                    Layout.fillWidth: true
                    id: nameText
                    textFormat: Text.StyledText // RichText also works, but StyledText ensures elide work
                    font.pixelSize: Appearance.font.pixelSize.small
                    font.family: Appearance.font.family[root.fontType]
                    color: root.colForeground
                    horizontalAlignment: Text.AlignLeft
                    elide: Text.ElideRight
                    text: root.selected ? StringUtils.escapeHtml(root.itemName) : root.displayContent
                }
            }
            Loader { // QR code for clipboard entry
                id: qrLoader
                active: root.qrPath !== ""
                visible: active
                Layout.fillWidth: true
                Layout.topMargin: 6
                Layout.bottomMargin: 4
                // Centered on the whole row (not the text column), so it doesn't
                // shift when the action buttons appear on hover/focus
                sourceComponent: Item {
                    implicitWidth: 0
                    implicitHeight: qrBox.height
                    Rectangle {
                        id: qrBox
                        readonly property real size: 240
                        width: size
                        height: size
                        x: root.width / 2 - size / 2 - rowLayout.x - contentColumn.x
                        color: "white"
                        radius: Appearance.rounding.small
                        Image {
                            anchors.fill: parent
                            anchors.margins: 6
                            source: root.qrPath === "" ? "" : `file://${root.qrPath}`
                            fillMode: Image.PreserveAspectFit
                            smooth: false
                            cache: false
                        }
                    }
                }
            }
            Loader { // Clipboard image preview
                active: root.cliphistRawString && Cliphist.entryIsImage(root.cliphistRawString)
                sourceComponent: CliphistImage {
                    Layout.fillWidth: true
                    entry: root.cliphistRawString
                    maxWidth: contentColumn.width
                    maxHeight: 140
                    blur: root.blurImage
                }
            }
        }

        // Action text
        StyledText {
            Layout.fillWidth: false
            visible: root.selected
            id: clickAction
            font.pixelSize: Appearance.font.pixelSize.normal
            color: Appearance.colors.colOnPrimaryContainer
            horizontalAlignment: Text.AlignRight
            text: root.itemClickActionName
        }

        RowLayout {
            // Clipboard entries only show their actions on hover / keyboard focus
            visible: !root.isClipboardEntry || root.selected
            Layout.alignment: Qt.AlignTop
            Layout.topMargin: root.buttonVerticalPadding
            Layout.bottomMargin: -root.buttonVerticalPadding // Why is this necessary? Good question.
            spacing: 4
            Repeater {
                model: root.shownActions
                delegate: RippleButton {
                    id: actionButton
                    required property var modelData
                    required property int index
                    readonly property bool keyboardSelected: actionButton.index === root.actionIndex
                    property var iconType: modelData.iconType
                    property string iconName: modelData.iconName ?? ""
                    implicitHeight: 34
                    implicitWidth: 34

                    colBackground: actionButton.keyboardSelected ? Appearance.colors.colSecondaryContainer
                        : ColorUtils.transparentize(Appearance.colors.colSecondaryContainer, 1)
                    colBackgroundHover: Appearance.colors.colSecondaryContainerHover
                    colRipple: Appearance.colors.colSecondaryContainerActive

                    contentItem: Item {
                        id: actionContentItem
                        anchors.centerIn: parent
                        Loader {
                            anchors.centerIn: parent
                            active: actionButton.iconType === LauncherSearchResult.IconType.Material || actionButton.iconName === ""
                            sourceComponent: MaterialSymbol {
                                text: actionButton.iconName || "video_settings"
                                font.pixelSize: Appearance.font.pixelSize.hugeass
                                fill: ((actionButton.modelData.id === "cliphist-star" && root.starred)
                                    || (actionButton.modelData.id === "cliphist-qr" && root.qrPath !== "")) ? 1 : 0
                                color: root.colForeground
                            }
                        }
                        Loader {
                            anchors.centerIn: parent
                            active: actionButton.iconType === LauncherSearchResult.IconType.System && actionButton.iconName !== ""
                            sourceComponent: IconImage {
                                source: Quickshell.iconPath(actionButton.iconName)
                                implicitSize: 20
                            }
                        }
                    }

                    onClicked: root.triggerAction(modelData)

                    StyledToolTip {
                        alternativeVisibleCondition: actionButton.keyboardSelected
                        text: {
                            switch (actionButton.modelData.id) {
                            case "cliphist-star":
                                return root.starred ? Translation.tr("Unstar") : Translation.tr("Star");
                            default:
                                return actionButton.modelData.name;
                            }
                        }
                    }
                }
            }
        }

    }
}
