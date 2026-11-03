import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import QtQuick
import QtQuick.Controls

/**
 * Table of VoiceStatsDialog, in sections (Male / Female), numbered from 1 in each one.
 * columns: [{ title, width, role }] — role: "name" (left aligned), "sub" (dim), "value" (percentage, colored),
 *          "total" (bold, primary). The "#" column is added by the table.
 * sections: [{ title, rows: [[cell, ...]] }], one cell per column; the first column is the voice name.
 * search: the dialog (matches(), highlighted(), query), to highlight and count the matches.
 */
Flickable {
    id: root

    property var columns: []
    property var sections: []
    property var search: null

    readonly property real numberWidth: 28
    readonly property real rowHeight: 26

    // Cells with a match (the highlighted ones)
    readonly property int matchCount: {
        if (!root.search || root.search.query.length === 0) return 0;
        const header = ["#", ...root.columns.map(c => c.title)];
        let count = 0;
        for (const section of root.sections) {
            count += header.filter(root.search.matches).length;
            section.rows.forEach((row, i) => count += [i + 1, ...row].filter(root.search.matches).length);
        }
        return count;
    }
    // First voice whose name matches: the table scrolls to it
    readonly property string firstMatch: {
        if (!root.search || root.search.query.length === 0) return "";
        for (const section of root.sections)
            for (const row of section.rows)
                if (root.search.matches(row[0])) return row[0];
        return "";
    }

    // Width of a column: at least its title (so it isn't cut, e.g. "Estimated age")
    function columnWidth(column) {
        return Math.max(column?.width ?? 30, Math.ceil(headerMetrics.advanceWidth(column?.title ?? "")) + 12);
    }

    function valueColor(value) {
        if (typeof value !== "number") return Appearance.colors.colSubtext; // "–": not tested
        if (value >= 90) return Appearance.m3colors.m3onSurface;
        if (value >= 75) return Appearance.colors.colSubtext;
        return Appearance.m3colors.m3error;
    }
    function cellColor(role, value) {
        if (role === "name") return Appearance.m3colors.m3onSurface;
        if (role === "value") return root.valueColor(value);
        if (role === "total") return Appearance.colors.colPrimary;
        return Appearance.colors.colSubtext;
    }

    clip: true
    contentWidth: tableColumn.implicitWidth
    contentHeight: tableColumn.implicitHeight
    boundsBehavior: Flickable.StopAtBounds
    ScrollBar.horizontal: ScrollBar { // Always visible: the table can be wider than the sidebar
        id: hBar
        policy: root.contentWidth > root.width ? ScrollBar.AlwaysOn : ScrollBar.AlwaysOff
        contentItem: Rectangle {
            implicitHeight: 4
            radius: height / 2
            color: Appearance.colors.colOnSurfaceVariant
            opacity: hBar.pressed || hBar.hovered ? 0.8 : 0.4
        }
    }
    ScrollBar.vertical: StyledScrollBar {}

    FontMetrics {
        id: headerMetrics
        font.family: Appearance.font.family.main
        font.pixelSize: Appearance.font.pixelSize.small
    }

    component Cell: StyledText {
        id: cell
        property real cellWidth: 30
        property var value: ""
        readonly property bool found: root.search?.matches(cell.value) ?? false
        width: cellWidth
        height: root.rowHeight
        verticalAlignment: Text.AlignVCenter
        horizontalAlignment: Text.AlignHCenter
        font.pixelSize: Appearance.font.pixelSize.small
        elide: Text.ElideRight
        textFormat: Text.StyledText
        text: root.search ? root.search.highlighted(cell.value) : String(cell.value)
        Rectangle { // Search match
            z: -1
            visible: cell.found
            anchors.fill: parent
            anchors.margins: 2
            radius: Appearance.rounding.verysmall ?? 4
            color: ColorUtils.transparentize(Appearance.colors.colPrimary, 0.85)
        }
    }

    Column {
        id: tableColumn
        spacing: 14
        bottomPadding: 10

        Repeater {
            model: root.sections
            delegate: Column {
                id: section
                required property var modelData
                spacing: 0

                StyledText {
                    text: section.modelData.title
                    color: Appearance.colors.colPrimary
                    font.pixelSize: Appearance.font.pixelSize.normal
                    font.weight: Font.DemiBold
                    bottomPadding: 4
                }

                Row { // Header
                    Cell {
                        cellWidth: root.numberWidth
                        color: Appearance.colors.colSubtext
                        value: "#"
                    }
                    Repeater {
                        model: root.columns
                        delegate: Cell {
                            required property var modelData
                            cellWidth: root.columnWidth(modelData)
                            horizontalAlignment: modelData.role === "name" ? Text.AlignLeft : Text.AlignHCenter
                            color: Appearance.colors.colSubtext
                            value: modelData.title
                        }
                    }
                }

                Rectangle {
                    width: parent.width
                    height: 1
                    color: Appearance.m3colors.m3outlineVariant
                }

                Repeater {
                    model: section.modelData.rows
                    delegate: Row {
                        id: voiceRow
                        required property var modelData
                        required property int index
                        readonly property bool isFirstMatch: root.firstMatch === voiceRow.modelData[0]
                        onIsFirstMatchChanged: if (isFirstMatch) Qt.callLater(() => {
                            const y = voiceRow.mapToItem(tableColumn, 0, 0).y;
                            if (y < root.contentY || y + root.rowHeight > root.contentY + root.height)
                                root.contentY = Math.max(0, Math.min(y - root.height / 3, root.contentHeight - root.height));
                        })
                        Cell {
                            cellWidth: root.numberWidth
                            color: Appearance.colors.colSubtext
                            value: voiceRow.index + 1
                        }
                        Repeater {
                            model: voiceRow.modelData
                            delegate: Cell {
                                required property var modelData
                                required property int index
                                readonly property var column: root.columns[index] ?? {}
                                cellWidth: root.columnWidth(column)
                                horizontalAlignment: column.role === "name" ? Text.AlignLeft : Text.AlignHCenter
                                color: root.cellColor(column.role, modelData)
                                font.weight: column.role === "total" ? Font.DemiBold : Font.Normal
                                value: modelData
                            }
                        }
                    }
                }
            }
        }
    }
}
