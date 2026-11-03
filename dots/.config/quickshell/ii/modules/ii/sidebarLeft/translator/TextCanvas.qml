import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Rectangle {
    id: root
    property bool isInput: true // true for input, false for output
    property string placeholderText
    property string text: ""
    property var inputTextArea: isInput ? inputLoader.item?.textArea : undefined
    property real maxInputHeight: 220 // Longer input scrolls instead of growing the box
    readonly property string displayedText: isInput ? (inputLoader.item?.textArea.text ?? "") : 
        root.text.length > 0 ? outputLoader.item.text : ""
    default property alias actionButtons: actions.groupData
    property var keyHandler: null // function(event): may accept key presses before the text area handles them
    Layout.fillWidth: true
    implicitHeight: Math.max(150, inputColumn.implicitHeight)
    color: Appearance.colors.colLayer2
    radius: Appearance.rounding.normal

    signal inputTextChanged(); // Signal emitted when text changes

    ColumnLayout {
        id: inputColumn
        anchors.fill: parent
        spacing: 0

        Loader {
            id: inputLoader
            active: root.isInput
            visible: root.isInput
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.minimumHeight: 48
            Layout.preferredHeight: Math.min(item?.textArea.implicitHeight ?? 0, root.maxInputHeight)
            sourceComponent: StyledFlickable { // Input area, scrolls when the text is long
                id: inputFlickable
                property alias textArea: inputTextArea
                clip: true
                contentWidth: width
                contentHeight: inputTextArea.implicitHeight

                // Keep the cursor in view while typing or moving it
                function ensureVisible(rect) {
                    if (rect.y < contentY) contentY = rect.y;
                    else if (rect.y + rect.height > contentY + height) contentY = rect.y + rect.height - height;
                }

                StyledTextArea {
                    id: inputTextArea
                    width: inputFlickable.width
                    height: Math.max(implicitHeight, inputFlickable.height)
                    placeholderText: root.placeholderText
                    wrapMode: TextEdit.Wrap
                    textFormat: TextEdit.PlainText
                    font.pixelSize: Appearance.font.pixelSize.small
                    color: Appearance.colors.colOnLayer1
                    padding: 15
                    background: null
                    onTextChanged: root.inputTextChanged()
                    onCursorRectangleChanged: if (activeFocus) inputFlickable.ensureVisible(cursorRectangle)
                    Keys.onPressed: event => {
                        if (root.keyHandler) root.keyHandler(event);
                    }
                }
            }
        }

        Loader {
            id: outputLoader
            active: !root.isInput
            visible: !root.isInput
            Layout.fillWidth: true
            sourceComponent: StyledText { // Output area
                id: outputTextArea
                padding: 15
                wrapMode: Text.Wrap
                font.pixelSize: Appearance.font.pixelSize.small
                color: root.text.length > 0 ? Appearance.colors.colOnLayer1 : Appearance.colors.colSubtext
                text: root.text.length > 0 ? root.text : root.placeholderText
            }
        }

        Item { Layout.fillHeight: !root.isInput }

        RowLayout { // Status row
            Layout.fillWidth: true
            Layout.minimumHeight: implicitHeight
            Layout.margins: 10
            spacing: 10

            Loader {
                Layout.leftMargin: 10
                sourceComponent: Text {
                    text: Translation.tr("%1 characters").arg(root.displayedText.length)
                    color: Appearance.colors.colOnLayer1
                    font.pixelSize: Appearance.font.pixelSize.smaller
                }
            }
        }
    }

    ButtonGroup {
        id: actions
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.rightMargin: 10
        anchors.bottomMargin: 10
        z: 1
    }
}
