import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts
import Quickshell

RippleButton {
    id: root
    required property var entry
    // AppContextMenu hosted by DashboardContent; null falls back to pin toggle.
    property var appMenu: null

    property bool pinned: DashboardApps.isPinned(entry.id)
    // Driven by DashboardContent's virtual keyboard focus. RippleButton only
    // styles mouse hover, so mirror its hover look for keyboard focus here.
    property bool keyboardFocused: false
    // Set when this cell is both keyboard-focused and the user tapped Ctrl
    // to reveal it -- shows the tooltip below without needing mouse hover.
    property bool showDescription: false

    implicitWidth: 96
    implicitHeight: 84
    horizontalPadding: 0
    verticalPadding: 0
    buttonRadius: Appearance.rounding.normal
    // All of DashboardContent's arrow-key navigation depends on searchField
    // holding real active focus; a plain click (e.g. right-click to pin,
    // which doesn't close the dashboard) would otherwise hand real focus to
    // this button instead and leave the arrow keys with nowhere to land.
    focusPolicy: Qt.NoFocus
    buttonColor: root.toggled ? (root.hovered ? colBackgroundToggledHover : colBackgroundToggled)
        : ((root.hovered || root.keyboardFocused) ? colBackgroundHover : colBackground)

    onClicked: {
        GlobalStates.dashboardOpen = false;
        entry.execute();
    }
    altAction: (event) => {
        if (root.appMenu)
            root.appMenu.popup(root, event.x, event.y, AppMenuEntries.dashboardEntries(root.entry));
        else
            DashboardApps.togglePin(entry.id);
    }

    // Keyboard focus gets its own ring, separate from the hover-tint
    // buttonColor above -- a background tint alone was easy to miss,
    // especially right after a cross-region handoff from Favorites.
    Rectangle {
        anchors.fill: parent
        radius: root.buttonRadius
        color: "transparent"
        border.width: root.keyboardFocused ? 2 : 0
        border.color: Appearance.colors.colPrimary
    }

    contentItem: ColumnLayout {
        spacing: 3
        AppIcon {
            Layout.topMargin: 12
            Layout.alignment: Qt.AlignHCenter
            source: Quickshell.iconPath(root.entry.icon, "image-missing")
            implicitSize: 34
        }
        StyledText {
            Layout.fillHeight: true
            Layout.fillWidth: true
            Layout.leftMargin: 8
            Layout.rightMargin: 8
            text: root.entry.name
            wrapMode: Text.Wrap
            elide: Text.ElideRight
            maximumLineCount: 2
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignTop
            color: Appearance.colors.colOnLayer0
        }
    }

    StyledToolTip {
        text: Translation.tr("%1\nRight-click for options").arg(root.entry.name)
        alternativeVisibleCondition: root.showDescription
    }
}
