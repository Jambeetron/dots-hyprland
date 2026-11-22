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

BodyRectangle {
    id: root

    property bool showingAllApps: false
    readonly property list<DesktopEntry> sortedApps: AppSearch.list.filter(app => !app.noDisplay).sort((a, b) => a.name.localeCompare(b.name))

    // The list being navigated while the letter picker is open
    property AppsByLetter pickerSource: null

    function jumpToLetter(letter: string) {
        const target = root.pickerSource.itemForLetter(letter);
        root.pickerSource = null;
        if (!target)
            return;
        const y = target.mapToItem(flickable.contentItem, 0, 0).y;
        flickable.contentY = Math.max(0, Math.min(y, flickable.contentHeight - flickable.height));
    }

    Loader {
        anchors.fill: parent
        z: 1 // Above the (hidden, disabled) page, which otherwise fights it for hover
        active: root.pickerSource !== null
        sourceComponent: LetterPicker {
            availableLetters: root.pickerSource?.letterGroups.map(group => group.letter) ?? []
            onPicked: letter => root.jumpToLetter(letter)
            onDismissed: root.pickerSource = null
        }
    }

    // All apps' header stays put while the list scrolls under it
    PageHeader {
        id: allAppsHeader
        visible: root.showingAllApps && !root.pickerSource
        anchors {
            top: parent.top
            left: parent.left
            right: parent.right
            topMargin: 25
            leftMargin: 64
            rightMargin: 64
        }
        title: Translation.tr("All apps")
        headerAction: HeaderButton {
            text: Translation.tr("Back")
            leadingIcon: "chevron-left"
            onClicked: root.showAllApps(false)
        }
    }

    Flickable {
        id: flickable
        // Not using visible, the layout has to stay intact to find the letter's position
        opacity: root.pickerSource ? 0 : 1
        enabled: !root.pickerSource
        anchors {
            fill: parent
            topMargin: root.showingAllApps ? 25 + allAppsHeader.implicitHeight + 16 : 25
            bottomMargin: 8
        }
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        contentWidth: width
        contentHeight: pageLoader.height + 22
        ScrollBar.vertical: WScrollBar {}

        Loader {
            id: pageLoader
            x: 32
            width: flickable.width - 32 * 2
            sourceComponent: root.showingAllApps ? allAppsPage : mainPage
        }
    }

    function showAllApps(show: bool) {
        flickable.contentY = 0;
        root.showingAllApps = show;
    }

    Component {
        id: mainPage
        ColumnLayout {
            spacing: 26
            PageSection {
                Layout.fillWidth: true
                title: Translation.tr("Pinned")
                headerAction: HeaderButton {
                    text: Translation.tr("All apps")
                    trailingIcon: "chevron-right"
                    onClicked: root.showAllApps(true)
                }

                BigAppGrid {
                    Layout.fillWidth: true
                    columns: 8
                    desktopEntries: Config.options.launcher.pinnedApps.map(appId => DesktopEntries.byId(appId))
                }
            }
            PageSection {
                Layout.fillWidth: true
                id: allApps
                readonly property string view: Persistent.states.waffle.startMenu.allAppsView

                title: Translation.tr("All")
                headerAction: AllAppsViewButton {}

                Loader {
                    Layout.fillWidth: true
                    sourceComponent: allApps.view === "grid" ? gridViewComp
                        : allApps.view === "list" ? listViewComp
                        : categoryViewComp
                }
            }
        }
    }

    Component {
        id: allAppsPage
        AppsByLetter {
            id: allAppsList
            letterNavigation: true
            onLetterClicked: {
                flickable.cancelFlick();
                root.pickerSource = allAppsList;
            }
            desktopEntries: root.sortedApps
        }
    }

    Component {
        id: categoryViewComp
        Item {
            implicitHeight: categoryGrid.implicitHeight
            AllAppsGrid {
                id: categoryGrid
                x: 32
                desktopEntries: root.sortedApps
            }
        }
    }

    Component {
        id: gridViewComp
        AppsByLetter {
            gridView: true
            desktopEntries: root.sortedApps
        }
    }

    Component {
        id: listViewComp
        AppsByLetter {
            desktopEntries: root.sortedApps
        }
    }

    component PageSection: ColumnLayout {
        id: pageSection
        required property string title
        property Component headerAction
        default property alias pageData: pageSectionContentArea.data

        spacing: 16

        PageHeader {
            Layout.fillWidth: true
            Layout.leftMargin: 32
            Layout.rightMargin: 32
            title: pageSection.title
            headerAction: pageSection.headerAction
        }

        ColumnLayout {
            id: pageSectionContentArea
            Layout.fillWidth: true
        }
    }

    component PageHeader: RowLayout {
        id: pageHeader
        required property string title
        property Component headerAction

        WText {
            text: pageHeader.title
            font.pixelSize: Looks.font.pixelSize.large
            font.weight: Looks.font.weight.stronger
        }
        Item {
            Layout.fillWidth: true
        }
        Loader {
            sourceComponent: pageHeader.headerAction
        }
    }
}
