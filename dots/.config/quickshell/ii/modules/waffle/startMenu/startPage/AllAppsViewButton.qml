pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import qs
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import qs.modules.waffle.looks

HeaderButton {
    id: root

    readonly property string currentView: Persistent.states.waffle.startMenu.allAppsView

    text: root.currentView === "grid" ? Translation.tr("Grid")
        : root.currentView === "list" ? Translation.tr("List")
        : Translation.tr("Category")
    trailingIcon: "chevron-down"
    onClicked: viewMenu.open()

    WMenu {
        id: viewMenu
        downDirection: true
        x: root.width - width
        y: root.height

        ViewItem {
            view: "category"
            text: Translation.tr("Category")
        }
        ViewItem {
            view: "grid"
            text: Translation.tr("Grid")
        }
        ViewItem {
            view: "list"
            text: Translation.tr("List")
        }
    }

    component ViewItem: WMenuItem {
        id: viewItem
        required property string view
        // Fixed, as WMenu and its background size themselves from this before the label is laid out
        implicitWidth: 164
        onTriggered: Persistent.states.waffle.startMenu.allAppsView = viewItem.view

        contentItem: RowLayout {
            spacing: 12
            FluentIcon {
                // Transparent instead of invisible so the labels stay aligned
                opacity: root.currentView === viewItem.view ? 1 : 0
                icon: "checkmark"
                implicitSize: 16
            }
            WText {
                Layout.fillWidth: true
                text: viewItem.text
                font.pixelSize: Looks.font.pixelSize.large
            }
        }
    }
}
