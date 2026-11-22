import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.services
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

// XTTS-v2 voices, in 3 tabs: "Choose" (the voice of each language), "Voices" (categorized: pitch, woman/man/child,
// age) and "Accuracy" (Whisper, per language).
// The data is in VoiceData; the search is shared by both tabs.
Item {
    id: root
    signal closed()

    property real dialogPadding: 15
    property real dialogMargin: 30
    property int currentTab: 0
    property bool detailsExpanded: false
    readonly property var currentView: [chooseView, catalogView, accuracyView][root.currentTab] ?? chooseView

    // Search: highlights the text in every cell (ignoring case and accents) and scrolls to the first voice found
    property string searchText: ""
    readonly property string query: root.fold(root.searchText.trim())

    // Lowercase without accents, keeping the length (so the indices match the original text)
    function fold(text) {
        return Array.from(String(text)).map(c => c.normalize("NFD")[0].toLowerCase()).join("");
    }
    function escapeHtml(text) {
        return String(text).replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");
    }
    function matches(text) {
        return root.query.length > 0 && root.fold(text).includes(root.query);
    }
    function highlighted(text) {
        text = String(text);
        if (!root.matches(text)) return root.escapeHtml(text);
        const folded = root.fold(text);
        let result = "", from = 0, at;
        while ((at = folded.indexOf(root.query, from)) >= 0) {
            result += root.escapeHtml(text.slice(from, at))
                + `<font color="${Appearance.colors.colPrimary}"><b>${root.escapeHtml(text.slice(at, at + root.query.length))}</b></font>`;
            from = at + root.query.length;
        }
        return result + root.escapeHtml(text.slice(from));
    }

    focus: true
    Component.onCompleted: Qt.callLater(() => searchField.forceActiveFocus())
    Keys.onPressed: event => {
        if (event.key === Qt.Key_Escape || event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
            root.closed();
            event.accepted = true;
        }
    }

    Rectangle { // Scrim
        anchors.fill: parent
        radius: Appearance.rounding.small
        color: Appearance.colors.colScrim
        MouseArea {
            anchors.fill: parent
            hoverEnabled: true
            preventStealing: true
            onClicked: root.closed()
        }
    }

    Rectangle { // The dialog
        color: Appearance.m3colors.m3surfaceContainerHigh
        radius: Appearance.rounding.normal
        anchors.fill: parent
        anchors.margins: root.dialogMargin

        MouseArea { // Clicks inside don't reach the scrim
            anchors.fill: parent
        }

        ColumnLayout {
            anchors.fill: parent
            spacing: 12

            StyledText {
                Layout.topMargin: root.dialogPadding
                Layout.leftMargin: root.dialogPadding
                Layout.rightMargin: root.dialogPadding
                Layout.fillWidth: true
                color: Appearance.m3colors.m3onSurface
                font.pixelSize: Appearance.font.pixelSize.larger
                text: Translation.tr("XTTS-v2 voices")
            }

            SecondaryTabBar {
                id: tabBar
                Layout.leftMargin: root.dialogPadding
                Layout.rightMargin: root.dialogPadding
                currentIndex: root.currentTab
                onCurrentIndexChanged: root.currentTab = currentIndex
                SecondaryTabButton {
                    buttonText: Translation.tr("Choose")
                    buttonIcon: "how_to_reg"
                }
                SecondaryTabButton {
                    buttonText: Translation.tr("Voices")
                    buttonIcon: "record_voice_over"
                }
                SecondaryTabButton {
                    buttonText: Translation.tr("Accuracy")
                    buttonIcon: "translate"
                }
            }

            RippleButton { // "ⓘ Details": shows/hides the details of the tab
                id: detailsButton
                visible: root.currentView.detailsText.length > 0
                focusPolicy: Qt.NoFocus
                Layout.leftMargin: root.dialogPadding - 6
                implicitHeight: 30
                implicitWidth: detailsRow.implicitWidth + 16
                buttonRadius: Appearance.rounding.full
                onClicked: root.detailsExpanded = !root.detailsExpanded
                contentItem: Item {
                    RowLayout {
                        id: detailsRow
                        anchors.centerIn: parent
                        spacing: 4
                        MaterialSymbol {
                            text: "info"
                            iconSize: Appearance.font.pixelSize.larger
                            color: Appearance.colors.colPrimary
                        }
                        StyledText {
                            text: Translation.tr("Details")
                            color: Appearance.colors.colPrimary
                            font.pixelSize: Appearance.font.pixelSize.small
                        }
                        MaterialSymbol {
                            text: root.detailsExpanded ? "expand_more" : "chevron_right"
                            iconSize: Appearance.font.pixelSize.larger
                            color: Appearance.colors.colPrimary
                        }
                    }
                }
                StyledToolTip {
                    text: root.detailsExpanded ? Translation.tr("Hide details") : Translation.tr("Show details")
                }
            }

            StyledText { // Details of the tab (collapsed by default)
                visible: detailsButton.visible && root.detailsExpanded
                Layout.leftMargin: root.dialogPadding
                Layout.rightMargin: root.dialogPadding
                Layout.fillWidth: true
                wrapMode: Text.Wrap
                color: Appearance.colors.colSubtext
                font.pixelSize: Appearance.font.pixelSize.small
                lineHeight: 1.2
                text: root.currentView.detailsText
            }

            StyledText { // Info of the tab (always visible)
                visible: text.length > 0
                Layout.leftMargin: root.dialogPadding
                Layout.rightMargin: root.dialogPadding
                Layout.fillWidth: true
                wrapMode: Text.Wrap
                color: Appearance.colors.colSubtext
                font.pixelSize: Appearance.font.pixelSize.small
                lineHeight: 1.2
                text: root.currentView.infoText
            }

            Rectangle {
                color: Appearance.m3colors.m3outline
                implicitHeight: 1
                Layout.fillWidth: true
                Layout.leftMargin: root.dialogPadding
                Layout.rightMargin: root.dialogPadding
            }

            RowLayout {
                Layout.fillWidth: true
                Layout.leftMargin: root.dialogPadding
                Layout.rightMargin: root.dialogPadding
                spacing: 10

                MaterialTextField {
                    id: searchField
                    Layout.fillWidth: true
                    placeholderText: Translation.tr("Search")
                    wrapMode: TextEdit.NoWrap
                    onTextChanged: root.searchText = text
                    Keys.onPressed: event => {
                        if (event.key === Qt.Key_Escape) { // Clears the search first, then closes
                            if (searchField.text.length > 0) searchField.text = "";
                            else root.closed();
                            event.accepted = true;
                        } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                            event.accepted = true; // Don't close the dialog while searching
                        }
                    }
                }

                StyledText { // Total of matches (in the current tab)
                    visible: root.query.length > 0
                    Layout.alignment: Qt.AlignVCenter
                    color: root.currentView.matchCount > 0 ? Appearance.colors.colPrimary : Appearance.m3colors.m3error
                    font.pixelSize: Appearance.font.pixelSize.small
                    text: root.currentView.matchCount === 1 ? Translation.tr("1 match")
                        : Translation.tr("%1 matches").arg(root.currentView.matchCount)
                }
            }

            StackLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.leftMargin: root.dialogPadding
                Layout.rightMargin: root.dialogPadding
                currentIndex: root.currentTab

                VoiceChooseView {
                    id: chooseView
                    search: root
                }
                VoiceCatalogView {
                    id: catalogView
                    search: root
                }
                VoiceAccuracyView {
                    id: accuracyView
                    search: root
                }
            }

            Rectangle {
                color: Appearance.m3colors.m3outline
                implicitHeight: 1
                Layout.fillWidth: true
                Layout.leftMargin: root.dialogPadding
                Layout.rightMargin: root.dialogPadding
            }

            DialogButton {
                Layout.alignment: Qt.AlignRight
                Layout.bottomMargin: root.dialogPadding
                Layout.rightMargin: root.dialogPadding
                buttonText: Translation.tr("Close")
                onClicked: root.closed()
            }
        }
    }
}
