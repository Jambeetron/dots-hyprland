import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts

RippleButton {
    id: root
    required property string label

    Layout.alignment: Qt.AlignRight
    implicitHeight: 28
    horizontalPadding: 8
    buttonRadius: Appearance.rounding.small
    // DashboardContent's arrow-key navigation depends on searchField
    // holding real active focus; without this, clicking a sidebar item
    // hands real focus to the button instead and the arrow keys stop
    // reaching searchField's Keys handlers entirely.
    focusPolicy: Qt.NoFocus

    contentItem: StyledText {
        text: root.label
        font.pixelSize: Appearance.font.pixelSize.small
        // RippleButton's own toggled background is colBackgroundToggled,
        // which defaults to colPrimary -- not colSecondaryContainer -- so
        // the text needs to pair with colOnPrimary to actually contrast
        // against it (colOnSecondaryContainer was paired with a background
        // this button never actually uses while toggled).
        color: root.toggled ? Appearance.colors.colOnPrimary : Appearance.colors.colOnLayer0
        horizontalAlignment: Text.AlignRight
        verticalAlignment: Text.AlignVCenter
        elide: Text.ElideRight
    }
}
