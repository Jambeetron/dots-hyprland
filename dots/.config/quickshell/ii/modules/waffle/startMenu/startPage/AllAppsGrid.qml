pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import Quickshell
import qs
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import qs.modules.waffle.looks

GridLayout {
    id: root

    required property list<DesktopEntry> desktopEntries

    columns: 4

    property list<AggregatedAppCategoryModel> aggregatedCategories: [
        AggregatedAppCategoryModel {
            name: Translation.tr("Development")
            categories: ["Development"]
        },
        AggregatedAppCategoryModel {
            name: Translation.tr("Education")
            categories: ["Education"]
        },
        AggregatedAppCategoryModel {
            name: Translation.tr("Graphics")
            categories: ["Graphics"]
        },
        AggregatedAppCategoryModel {
            name: Translation.tr("Internet")
            categories: ["Network"]
        },
        AggregatedAppCategoryModel {
            name: Translation.tr("Multimedia")
            categories: ["AudioVideo"]
        },
        AggregatedAppCategoryModel {
            name: Translation.tr("Office")
            categories: ["Office"]
        },
        AggregatedAppCategoryModel {
            name: Translation.tr("System")
            categories: ["System", "Settings"]
        },
        AggregatedAppCategoryModel {
            name: Translation.tr("Utilities")
            categories: ["Utility"]
        },
        AggregatedAppCategoryModel {
            name: Translation.tr("Lost & Found")
            categories: []
        }
    ]

    function appsInCategory(category: AggregatedAppCategoryModel): var {
        if (category.categories.length > 0)
            return root.desktopEntries.filter(app => app.categories.some(c => category.categories.includes(c)));

        // No categories = Lost & Found, which gets whatever the others didn't
        const known = new Set();
        for (const other of root.aggregatedCategories)
            other.categories.forEach(c => known.add(c));
        return root.desktopEntries.filter(app => !app.categories.some(c => known.has(c)));
    }

    Repeater {
        model: root.aggregatedCategories
        delegate: AppCategory {
            required property var modelData
            aggregatedCategory: modelData
            desktopEntries: root.appsInCategory(modelData)
            visible: desktopEntries.length > 0
        }
    }

    columnSpacing: 27
    rowSpacing: 12
    component AppCategory: Item {
        id: categoryItem
        property AggregatedAppCategoryModel aggregatedCategory
        property list<DesktopEntry> desktopEntries
        implicitWidth: categoryLayout.implicitWidth
        implicitHeight: categoryLayout.implicitHeight
        ColumnLayout {
            id: categoryLayout
            anchors.fill: parent
            spacing: 4

            AppCategoryGrid {
                id: categoryGrid
                Layout.fillWidth: true
                aggregatedCategory: categoryItem.aggregatedCategory
                desktopEntries: categoryItem.desktopEntries
            }

            WButton {
                id: categoryButton
                Layout.fillWidth: true
                implicitHeight: 32

                contentItem: WText {
                    id: categoryButtonText
                    Layout.fillWidth: true
                    horizontalAlignment: Text.AlignHCenter
                    elide: Text.ElideRight
                    text: categoryItem.aggregatedCategory.name
                }
                onClicked: {
                    categoryGrid.openCategoryFolder();
                }
            }
        }
    }
}
