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

ColumnLayout {
    id: root

    required property list<DesktopEntry> desktopEntries
    property bool gridView: false
    property bool letterNavigation: false
    signal letterClicked

    function itemForLetter(letter: string): Item {
        return groupRepeater.itemAt(root.letterGroups.findIndex(group => group.letter === letter));
    }

    readonly property var letterGroups: {
        const groups = new Map();
        for (const app of root.desktopEntries) {
            // Accented letters go with their base letter, anything else under #
            const first = app.name.charAt(0).normalize("NFD").charAt(0).toUpperCase();
            const letter = /[A-Z]/.test(first) ? first : "#";
            if (!groups.has(letter))
                groups.set(letter, []);
            groups.get(letter).push(app);
        }
        return Array.from(groups.keys()).sort().map(letter => ({ letter: letter, apps: groups.get(letter) }));
    }

    spacing: 12

    Repeater {
        id: groupRepeater
        model: root.letterGroups
        delegate: ColumnLayout {
            id: letterGroup
            required property var modelData
            Layout.fillWidth: true
            spacing: 4

            WBorderlessButton {
                Layout.leftMargin: 20
                implicitWidth: 40
                implicitHeight: root.letterNavigation ? 36 : 24
                enabled: root.letterNavigation
                onClicked: root.letterClicked()
                contentItem: WText {
                    horizontalAlignment: Text.AlignHCenter
                    text: letterGroup.modelData.letter
                    font.pixelSize: Looks.font.pixelSize.large
                    font.weight: Looks.font.weight.stronger
                }
            }
            BigAppGrid {
                visible: root.gridView
                columns: 8
                desktopEntries: root.gridView ? letterGroup.modelData.apps : []
            }
            Repeater {
                model: root.gridView ? [] : letterGroup.modelData.apps
                delegate: StartAppListButton {
                    id: appButton
                    required property var modelData
                    Layout.fillWidth: true
                    Layout.leftMargin: 20
                    Layout.rightMargin: 20
                    desktopEntry: modelData
                    onClicked: {
                        GlobalStates.searchOpen = false;
                        appButton.desktopEntry.execute();
                    }
                }
            }
        }
    }
}
