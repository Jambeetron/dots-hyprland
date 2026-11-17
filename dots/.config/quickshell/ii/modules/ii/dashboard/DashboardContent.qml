pragma ComponentBehavior: Bound

import qs
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import qs.modules.ii.sessionScreen
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell

Item {
    id: root

    property string selectedView: "all" // "all" | "power" | a category label
    // What the main area shows. Follows selectedView (the highlight), except
    // while an arrow is held in the sidebar: rebuilding the app grid takes up
    // to ~250ms, so it waits until the key is released or stops repeating.
    property string shownView: "all"
    property string searchQuery: ""

    // Keyboard navigation: searchField keeps real active focus and steers a
    // "virtual focus" (focusZone + per-panel index) across the favorites
    // grid, the main app grid, and the category sidebar; arrows move it,
    // Enter acts on it.
    property string focusZone: "" // "", "favorites", "apps", "categories"
    property int appFocusIndex: -1
    // Up/Down is auto-repeating: the grids then scroll without animation,
    // which would restart on every repeat and leave the ring out of view.
    property bool arrowHeld: false
    // Last cell focused in favorites and in each view of the main grid (All,
    // every category, Power, the current search), to come back to when
    // switching zones. The sidebar needs none: it lands on selectedView.
    property int lastFavoriteIndex: -1
    readonly property var appMemory: new Map() // view -> index
    onAppFocusIndexChanged: root.rememberApp()

    function appMemoryKey() {
        return root.searchQuery.length > 0 ? "\nsearch" : root.shownView;
    }

    function rememberApp() {
        if (root.focusZone === "apps" && root.appFocusIndex !== -1)
            root.appMemory.set(root.appMemoryKey(), root.appFocusIndex);
    }

    function rememberedApp() {
        return root.appMemory.get(root.appMemoryKey()) ?? -1;
    }

    // Tapping Shift alone toggles showing the keyboard-focused cell's
    // tooltip (its full, untruncated name). Tapping Ctrl alone toggles
    // "move mode": pick up the focused favorite, steer it with the plain
    // arrow keys (no modifier needed while moving), tap Ctrl again to drop
    // it in place. Both are taps, not holds -- see isModifierTap below for
    // how a tap (e.g. Ctrl alone) is told apart from the modifier being
    // used for something else (e.g. Ctrl+C in the search field).
    property bool showDescriptions: false
    property bool moveMode: false
    property bool ctrlTapCandidate: false
    property bool shiftTapCandidate: false
    // Shift+F10 (or the Menu key) opens the focused cell's options menu
    // (same one as right-click); arrows then move through it, Enter picks,
    // Esc/Left close it. (Not an Alt tap: Hyprland's ALT_L/ALT_R release
    // binds in custom/wsextra.lua swallow Alt before it reaches the shell.)
    readonly property bool appMenuOpen: appContextMenu.visible
    // Last main-grid cell that took keyboard focus (AppFlow reports it via
    // focusCellRequested), so the menu can be anchored to it.
    property Item lastFocusedAppCell: null
    property Item lastFocusedLetterSection: null

    function openMenuForFocused() {
        if (root.focusZone === "favorites") {
            const index = favoritesFlow.focusedIndex;
            const entry = favoritesFlow.model[index];
            const cell = favoritesFlow.cellItem(index);
            if (!entry || !cell)
                return false;
            appContextMenu.popup(cell, cell.width / 2, cell.height / 2, AppMenuEntries.dashboardEntries(entry), true);
            return true;
        }
        if (root.focusZone === "apps") {
            const entry = root.mainViewItems[root.appFocusIndex];
            const cell = root.lastFocusedAppCell;
            if (!entry || entry.powerAction || !cell || cell.entry !== entry)
                return false;
            appContextMenu.popup(cell, cell.width / 2, cell.height / 2, AppMenuEntries.dashboardEntries(entry), true);
            return true;
        }
        return false;
    }

    // DashboardContent is destroyed and recreated by its Loader each time the
    // dashboard closes/opens, so defaults above already reset state -- just
    // grab focus for typing, same as this file's fresh "all" + empty query.
    Component.onCompleted: searchField.forceActiveFocus()

    // "All" is whatever the main area shows: every app, a category or the search results.
    function openBackgroundMenu(item, x, y) {
        const apps = root.mainViewItems.filter(entry => !entry.powerAction);
        if (apps.length > 0)
            appContextMenu.popup(item, x, y, AppMenuEntries.dashboardBackgroundEntries(apps));
    }

    // Shared right-click menu for every app cell (favorites + main grid) and the main grid's background.
    AppContextMenu {
        id: appContextMenu
        onMenuClosed: searchField.forceActiveFocus()
    }

    readonly property var categoryDefs: [
        { label: Translation.tr("Development"), match: ["Development"] },
        { label: Translation.tr("Education"), match: ["Education"] },
        { label: Translation.tr("Games"), match: ["Game"] },
        { label: Translation.tr("Graphics"), match: ["Graphics"] },
        { label: Translation.tr("Internet"), match: ["Network"] },
        { label: Translation.tr("Multimedia"), match: ["AudioVideo"] },
        { label: Translation.tr("Office"), match: ["Office"] },
        { label: Translation.tr("Science"), match: ["Science"] },
        { label: Translation.tr("System"), match: ["System", "Settings"] },
        { label: Translation.tr("Utilities"), match: ["Utility"] },
    ]

    readonly property var powerActions: [
        { icon: "lock", label: Translation.tr("Lock"), action: () => Session.lock() },
        { icon: "logout", label: Translation.tr("Log Out"), action: () => Session.logout() },
        { icon: "dark_mode", label: Translation.tr("Sleep"), action: () => Session.suspend() },
        { icon: "downloading", label: Translation.tr("Hibernate"), action: () => Session.hibernate() },
        { icon: "restart_alt", label: Translation.tr("Restart"), action: () => Session.reboot() },
        { icon: "power_settings_new", label: Translation.tr("Shut Down"), action: () => Session.poweroff() },
    ]

    // All apps, visible ones only, alphabetically sorted -- the same .desktop
    // "Categories=" field KDE's own menu reads, so edits made via KDE's menu
    // editor (or installing/removing apps) show up here automatically too.
    readonly property var allApps: AppSearch.list.filter(e => !e.noDisplay).slice().sort((a, b) => a.name.localeCompare(b.name))

    readonly property var categoryGroups: {
        const groups = [];
        const claimed = new Set();
        for (const def of root.categoryDefs) {
            const apps = root.allApps.filter(e => e.categories.some(c => def.match.includes(c)));
            if (apps.length > 0) {
                groups.push({ label: def.label, apps: apps });
                apps.forEach(a => claimed.add(a.id));
            }
        }
        const lostAndFound = root.allApps.filter(e => !claimed.has(e.id));
        if (lostAndFound.length > 0) {
            groups.push({ label: Translation.tr("Lost & Found"), apps: lostAndFound });
        }
        return groups;
    }

    readonly property var letterGroups: {
        const groups = [];
        let currentLetter = "";
        let currentApps = [];
        // Flat index of the group's first app within the "all" view; needed
        // to translate the keyboard navigation's flat index into a per-flow
        // highlight index.
        let offset = 0;
        for (const app of root.allApps) {
            const letter = (app.name.charAt(0) || "#").toUpperCase();
            if (letter !== currentLetter) {
                if (currentApps.length > 0) {
                    groups.push({ letter: currentLetter, apps: currentApps, offset: offset });
                    offset += currentApps.length;
                }
                currentLetter = letter;
                currentApps = [];
            }
            currentApps.push(app);
        }
        if (currentApps.length > 0)
            groups.push({ letter: currentLetter, apps: currentApps, offset: offset });
        return groups;
    }

    readonly property var searchResults: root.searchQuery.length > 0 ? AppSearch.fuzzyQuery(root.searchQuery) : []

    readonly property var favoriteApps: Config.options.dashboard.pinnedApps.map(id => DesktopEntries.byId(id)).filter(e => e)

    // A plain function here wasn't reliably treated as a live binding when
    // called from a Loader's sourceComponent -- a computed property (same
    // shape as categoryGroups/letterGroups/searchResults above, which do
    // update correctly) is what the QML engine actually re-evaluates here.
    readonly property var currentCategoryApps: {
        const group = root.categoryGroups.find(g => g.label === root.shownView);
        return group ? group.apps : [];
    }

    readonly property string headerText: {
        if (root.searchQuery.length > 0) return Translation.tr("Search results");
        if (root.shownView === "power") return Translation.tr("System actions");
        if (root.shownView === "all") return Translation.tr("Applications");
        return root.shownView;
    }

    // Flat, on-screen-ordered list of what the main area currently shows --
    // one entry per app cell (or power action) -- so keyboard navigation can
    // treat the view as a single grid regardless of letter-group structure.
    // Power actions are wrapped to distinguish their action() from an app's
    // execute().
    readonly property var mainViewItems: {
        if (root.searchQuery.length > 0)
            return root.searchResults;
        if (root.shownView === "power")
            return root.powerActions.map(action => ({ powerAction: action }));
        if (root.shownView === "all")
            return root.letterGroups.reduce((flat, group) => flat.concat(group.apps), []);
        return root.currentCategoryApps;
    }

    // App cells are uniform 96px wide (DashboardAppButton.implicitWidth) with
    // 2px flow spacing; how many fit per row of the main area right now.
    readonly property int mainColumns: Math.max(1, Math.floor((appFlickable.width + 2) / (96 + 2)))

    // Real on-screen row structure of the main view, as arrays of indices
    // into mainViewItems. This must mirror the Loaders below exactly:
    // "All Applications" renders one independently-wrapping Flow per letter
    // group, so a short group's last row never continues into the next
    // letter's apps; power actions sit in a single RowLayout (one row, no
    // wrapping); everything else (search results, a single category) is one
    // continuous wrapping Flow. Keyboard navigation reads real rows from
    // here instead of assuming a uniform grid, so letter-group boundaries in
    // "All Applications" don't scramble Up/Down/Left/Right.
    readonly property var mainViewRows: {
        const rows = [];
        function chunk(offset, length, columns) {
            for (let i = 0; i < length; i += columns) {
                const row = [];
                for (let j = i; j < Math.min(i + columns, length); j++)
                    row.push(offset + j);
                rows.push(row);
            }
        }
        if (root.searchQuery.length === 0 && root.shownView === "power")
            chunk(0, root.mainViewItems.length, Math.max(1, root.mainViewItems.length));
        else if (root.searchQuery.length === 0 && root.shownView === "all")
            root.letterGroups.forEach(group => chunk(group.offset, group.apps.length, root.mainColumns));
        else
            chunk(0, root.mainViewItems.length, root.mainColumns);
        return rows;
    }

    // Finds which on-screen row/column a mainViewItems index sits in.
    function locateInRows(rows, index) {
        for (let r = 0; r < rows.length; r++) {
            const c = rows[r].indexOf(index);
            if (c !== -1)
                return { row: r, col: c };
        }
        return { row: -1, col: -1 };
    }

    // Sidebar entries in on-screen order, for Up/Down keyboard navigation.
    readonly property var viewOrder: ["all"].concat(root.categoryGroups.map(g => g.label)).concat(["power"])

    function showSelectedView() {
        viewLoadTimer.stop();
        root.shownView = root.selectedView;
    }

    onSelectedViewChanged: if (!viewLoadTimer.running) root.showSelectedView()

    Timer {
        id: viewLoadTimer
        interval: 150 // Longer than the gap between two key repeats
        onTriggered: root.showSelectedView()
    }

    function selectAdjacentView(direction, held) {
        const order = root.viewOrder;
        const index = order.indexOf(root.selectedView);
        const next = (index === -1 ? 0 : index) + direction;
        // A held arrow stops at both ends (only a fresh press wraps around).
        // The timer is left alone there, so that end's apps get to load.
        if (held && (next < 0 || next >= order.length))
            return;
        // Before the assignment below: onSelectedViewChanged looks at it.
        if (held)
            viewLoadTimer.restart();
        else
            viewLoadTimer.stop();
        root.selectedView = order[(next + order.length) % order.length];
    }

    // Wheel over the sidebar: like the arrows, but stops at both ends so a
    // fast scroll doesn't jump from the first entry to the last.
    function scrollViews(steps) {
        const order = root.viewOrder;
        const index = Math.max(0, order.indexOf(root.selectedView));
        root.selectedView = order[Math.max(0, Math.min(order.length - 1, index + steps))];
    }

    // Flat-index -> row/col math shared by the favorites and app grids: both
    // are uniform-column Flow layouts, so a cell's row is "index / columns"
    // and its row runs from "row * columns" to the last in-bounds index in
    // that row (short on a partial final row).
    function gridRowBounds(index, count, columns) {
        const row = Math.floor(index / columns);
        const start = row * columns;
        const end = Math.min(start + columns, count) - 1;
        return { row: row, start: start, end: end };
    }

    // Keyboard focus transitions between the three panels (favorites, apps,
    // categories). Search field keeps real focus; these only maintain the
    // virtual highlight state.
    function enterFavorites(index) {
        root.focusZone = "favorites";
        root.appFocusIndex = -1;
        favoritesFlow.focusCell(index);
    }

    function enterApps(index) {
        const count = root.mainViewItems.length;
        if (count === 0)
            return;
        root.focusZone = "apps";
        favoritesFlow.focusedIndex = -1;
        root.appFocusIndex = Math.max(0, Math.min(index, count - 1));
        root.rememberApp(); // The index may not have changed, only the view
    }

    // Row-preserving handoff from favorites: lands on the first column of
    // the closest available on-screen row in the app grid, rather than
    // always snapping back to the very first item.
    function enterAppsAtRow(row) {
        const rows = root.mainViewRows;
        if (rows.length === 0)
            return;
        const targetRow = Math.min(row, rows.length - 1);
        root.enterApps(rows[targetRow][0]);
    }

    function enterCategories() {
        root.focusZone = "categories";
        favoritesFlow.focusedIndex = -1;
    }

    // Leaving the category list back towards the app grid: lands where the
    // ring last was in that view, or on its first app.
    function exitCategoriesToApps() {
        const justLoaded = root.shownView !== root.selectedView;
        root.showSelectedView(); // A held arrow may not have loaded it yet
        const count = root.mainViewItems.length;
        if (count === 0) {
            root.focusZone = "";
            root.appFocusIndex = -1;
            return;
        }
        root.enterApps(root.rememberedApp());
        if (justLoaded)
            revealAfterLayout.restart();
    }

    // Cells of a view created just now have no position until it's laid out,
    // so scroll to the ring again a couple of frames later.
    FrameAnimation {
        id: revealAfterLayout
        onTriggered: {
            if (currentFrame < 2)
                return;
            stop();
            if (root.focusZone === "apps" && root.lastFocusedAppCell)
                root.ensureAppCellVisible(root.lastFocusedAppCell, root.lastFocusedLetterSection);
        }
    }

    function clearAppFocus() {
        if (root.focusZone === "apps") {
            root.focusZone = "";
            root.appFocusIndex = -1;
        }
    }

    // Favorites grid navigation. Left/Right change column, Up/Down change
    // row. Right from the last column of a row hands focus off to the app
    // grid, landing where it last was there (the same row the first time).
    // Left at the first column, Up from the first row and Down past the last
    // one just clamp in place, so the ring never disappears.
    function moveFavoritesRight() {
        const bounds = root.gridRowBounds(favoritesFlow.focusedIndex, favoritesFlow.count, favoritesFlow.columns);
        if (favoritesFlow.focusedIndex === bounds.end) {
            const last = root.rememberedApp();
            if (last !== -1)
                root.enterApps(last);
            else
                root.enterAppsAtRow(bounds.row);
        } else
            favoritesFlow.focusCell(favoritesFlow.focusedIndex + 1);
    }

    function moveFavoritesLeft() {
        const bounds = root.gridRowBounds(favoritesFlow.focusedIndex, favoritesFlow.count, favoritesFlow.columns);
        if (favoritesFlow.focusedIndex > bounds.start)
            favoritesFlow.focusCell(favoritesFlow.focusedIndex - 1);
    }

    function moveFavoritesUp() {
        const columns = favoritesFlow.columns;
        const bounds = root.gridRowBounds(favoritesFlow.focusedIndex, favoritesFlow.count, columns);
        if (bounds.row === 0)
            return;
        const col = favoritesFlow.focusedIndex - bounds.start;
        const prevStart = bounds.start - columns;
        const prevLen = Math.min(columns, favoritesFlow.count - prevStart);
        favoritesFlow.focusCell(prevStart + Math.min(col, prevLen - 1));
    }

    function moveFavoritesDown() {
        const columns = favoritesFlow.columns;
        const count = favoritesFlow.count;
        const bounds = root.gridRowBounds(favoritesFlow.focusedIndex, count, columns);
        const nextStart = bounds.end + 1;
        if (nextStart >= count)
            return;
        const col = favoritesFlow.focusedIndex - bounds.start;
        const nextLen = Math.min(columns, count - nextStart);
        favoritesFlow.focusCell(nextStart + Math.min(col, nextLen - 1));
    }

    // While moveMode is on, the plain arrow keys swap the focused favorite
    // with its grid neighbor in that direction instead of just moving the
    // highlight -- the keyboard equivalent of picking a drag-to-reorder up
    // and steering it. confineToRow is true for Left/Right (a swap can't
    // cross into the next/previous row) and false for Up/Down (the whole
    // point is landing in a different row); either way the swap is a no-op
    // if there's no neighbor there.
    function moveFocusedFavorite(delta, confineToRow) {
        const index = favoritesFlow.focusedIndex;
        if (index === -1)
            return;
        const app = favoritesFlow.model[index];
        if (!app)
            return;
        const count = favoritesFlow.count;
        if (confineToRow) {
            const bounds = root.gridRowBounds(index, count, favoritesFlow.columns);
            if (delta > 0 && index === bounds.end)
                return;
            if (delta < 0 && index === bounds.start)
                return;
        }
        const target = index + delta;
        if (target < 0 || target >= count)
            return;
        const targetApp = favoritesFlow.model[target];
        if (!targetApp)
            return;
        DashboardApps.swap(app.id, targetApp.id);
        favoritesFlow.focusCell(target);
    }

    // App grid navigation, driven by the real on-screen rows in
    // mainViewRows (not a uniform-columns assumption, so letter-group
    // breaks in "All Applications" are respected). Left from the first
    // column hands off to favorites; Right from the last column hands off
    // to the category list. Up/Down clamp at the top/bottom row.
    function moveAppsRight() {
        const rows = root.mainViewRows;
        const pos = root.locateInRows(rows, root.appFocusIndex);
        if (pos.row === -1)
            return;
        const row = rows[pos.row];
        if (pos.col === row.length - 1)
            root.enterCategories();
        else
            root.appFocusIndex = row[pos.col + 1];
    }

    function moveAppsLeft() {
        const rows = root.mainViewRows;
        const pos = root.locateInRows(rows, root.appFocusIndex);
        if (pos.row === -1)
            return;
        const row = rows[pos.row];
        if (pos.col === 0) {
            const count = favoritesFlow.count;
            if (count > 0)
                root.enterFavorites(root.lastFavoriteIndex === -1 ? count - 1 : Math.min(root.lastFavoriteIndex, count - 1));
        } else {
            root.appFocusIndex = row[pos.col - 1];
        }
    }

    function moveAppsUp() {
        const rows = root.mainViewRows;
        const pos = root.locateInRows(rows, root.appFocusIndex);
        if (pos.row <= 0)
            return;
        const prevRow = rows[pos.row - 1];
        root.appFocusIndex = prevRow[Math.min(pos.col, prevRow.length - 1)];
    }

    function moveAppsDown() {
        const rows = root.mainViewRows;
        const pos = root.locateInRows(rows, root.appFocusIndex);
        if (pos.row === -1 || pos.row >= rows.length - 1)
            return;
        const nextRow = rows[pos.row + 1];
        root.appFocusIndex = nextRow[Math.min(pos.col, nextRow.length - 1)];
    }

    // Keep the keyboard-focused main-view cell inside the scroll viewport.
    // letterSection: the cell's letter group, whose header must be on screen
    // too when the cell is in the group's first row.
    function ensureAppCellVisible(cell, letterSection) {
        root.lastFocusedAppCell = cell;
        root.lastFocusedLetterSection = letterSection ?? null;
        const y = cell.mapToItem(appFlickable.contentItem, 0, 0).y;
        const top = letterSection && cell.y === 0 ? letterSection.mapToItem(appFlickable.contentItem, 0, 0).y : y;
        if (top < appFlickable.contentY)
            appFlickable.contentY = top;
        else if (y + cell.height > appFlickable.contentY + appFlickable.height)
            appFlickable.contentY = y + cell.height - appFlickable.height;
    }

    // Enter on the keyboard-focused main-view item launches the app (or runs
    // the power action) and closes the dashboard. Returns whether something
    // was focused, so key handlers know whether to accept the event.
    function activateFocusedApp() {
        if (root.focusZone !== "apps" || root.appFocusIndex === -1)
            return false;
        const item = root.mainViewItems[root.appFocusIndex];
        if (!item)
            return false;
        GlobalStates.dashboardOpen = false;
        if (item.powerAction)
            item.powerAction.action();
        else
            item.execute();
        return true;
    }

    // Enter on a focused favorite launches it, same as the grid's own
    // left-click. Returns whether an app was actually focused, so key
    // handlers know whether to accept the event.
    function activateFocusedFavorite() {
        if (favoritesFlow.focusedIndex === -1)
            return false;
        const app = favoritesFlow.model[favoritesFlow.focusedIndex];
        if (!app)
            return false;
        GlobalStates.dashboardOpen = false;
        app.execute();
        return true;
    }

    // "P" toggles pin on whichever item has keyboard focus, mirroring the
    // grids' own right-click pin toggle. Returns whether anything was
    // actually focused, so key handlers know whether to accept the event.
    function togglePinOnFocused() {
        if (root.focusZone === "favorites") {
            if (favoritesFlow.focusedIndex === -1)
                return false;
            const app = favoritesFlow.model[favoritesFlow.focusedIndex];
            if (!app)
                return false;
            DashboardApps.togglePin(app.id);
            // Unpinning removes it from the grid -- nothing left to move.
            root.moveMode = false;
            // Unpinning removes the app from the grid: keep the highlight on
            // whatever shifted into the same slot, or drop it when the grid
            // empties out.
            const count = favoritesFlow.model.length;
            if (count === 0) {
                favoritesFlow.focusedIndex = -1;
                root.focusZone = "";
            } else {
                favoritesFlow.focusCell(Math.min(favoritesFlow.focusedIndex, count - 1));
            }
            return true;
        }
        if (root.focusZone === "apps") {
            const item = root.mainViewItems[root.appFocusIndex];
            if (!item || item.powerAction)
                return false;
            DashboardApps.togglePin(item.id);
            return true;
        }
        return false;
    }

    component SectionSeparator: Rectangle {
        Layout.fillWidth: true
        implicitHeight: 1
        color: Appearance.colors.colOutlineVariant
    }

    component SectionHeader: StyledText {
        font {
            family: Appearance.font.family.title
            pixelSize: Appearance.font.pixelSize.larger
            variableAxes: Appearance.font.variableAxes.title
        }
        color: Appearance.colors.colOnLayer0
    }

    component AppFlow: Flow {
        id: appFlow

        property alias model: repeater.model
        // Virtual keyboard focus: index of the highlighted cell in this
        // flow, or -1. Emits the cell so the owner can scroll it into view.
        property int focusIndex: -1
        // Threaded in from root: whether a Ctrl tap should reveal the
        // focused cell's tooltip (its full, untruncated name).
        property bool showDescriptions: false
        property var appMenu: null
        signal focusCellRequested(Item cell)

        spacing: 2

        onFocusIndexChanged: {
            if (focusIndex < 0 || focusIndex >= repeater.count)
                return;
            const item = repeater.itemAt(focusIndex);
            if (item)
                focusCellRequested(item);
        }

        Repeater {
            id: repeater
            delegate: DashboardAppButton {
                required property int index
                required property var modelData
                entry: modelData
                appMenu: appFlow.appMenu
                keyboardFocused: appFlow.focusIndex === index
                showDescription: appFlow.showDescriptions && appFlow.focusIndex === index
            }
        }
    }

    // Favorites grid: same look as AppFlow, but drag-to-reorder. Needs stable
    // per-item identity (ScriptModel keyed by "id") so a delegate survives
    // being repositioned mid-drag when DashboardApps.reorder() reshuffles the
    // underlying list -- a plain array model would recreate every delegate
    // on each reorder step and drop the mouse grab.
    component FavoritesFlow: Item {
        id: favRoot
        property var model: []
        property var appMenu: null
        // The Flickable this grid scrolls in (for drag auto-scroll).
        property Flickable scrollView: null

        // Top y of a cell's row, from its index alone -- unlike a delegate's
        // live y, this is already final while the reorder animation runs.
        function rowY(index) {
            return Math.floor(index / favRoot.columns) * (favRoot.cellHeight + favRoot.cellSpacing);
        }

        // Mouse drag: move the dragged favorite onto whatever cell is under
        // pos (favRoot coordinates).
        function dragOver(pos) {
            const overIndex = favRoot.indexAtPos(pos.x, pos.y);
            const curIndex = favRoot.model.findIndex(e => e.id === favRoot.draggingId);
            if (overIndex === -1 || curIndex === -1 || overIndex === curIndex)
                return;
            const target = favRoot.model[overIndex];
            if (target)
                DashboardApps.reorderToId(favRoot.draggingId, target.id);
        }

        // Last drag cursor position in scrollView (viewport) coordinates.
        property point lastDragViewPos: Qt.point(0, 0)

        // Edge auto-scroll while dragging near the top/bottom of the viewport;
        // re-runs the hit-test each step since the grid moves under a still
        // cursor.
        Timer {
            interval: 16
            repeat: true
            running: favRoot.draggingId !== "" && favRoot.scrollView !== null
            onTriggered: {
                const view = favRoot.scrollView;
                const y = favRoot.lastDragViewPos.y;
                const edge = 48;
                const maxSpeed = 14;
                let v = 0;
                if (y < edge)
                    v = -maxSpeed * Math.min(1, (edge - y) / edge);
                else if (y > view.height - edge)
                    v = maxSpeed * Math.min(1, (y - (view.height - edge)) / edge);
                if (v === 0)
                    return;
                const maxY = Math.max(0, view.contentHeight - view.height);
                const next = Math.max(0, Math.min(view.contentY + v, maxY));
                if (next === view.contentY)
                    return;
                view.contentY = next;
                favRoot.dragOver(view.mapToItem(favRoot, favRoot.lastDragViewPos.x, favRoot.lastDragViewPos.y));
            }
        }

        readonly property int maxColumns: 5
        readonly property int cellWidth: 96
        readonly property int cellHeight: 84
        readonly property int cellSpacing: 2
        readonly property int columns: Math.max(1, Math.min(maxColumns, repeater.count))
        implicitWidth: columns * cellWidth + (columns - 1) * cellSpacing
        implicitHeight: flow.implicitHeight

        // Keyboard focus here is "virtual": the search field keeps real active
        // focus and the arrow keys steer this index, so no Item focus has to
        // survive delegates being destroyed mid-unpin.
        property int focusedIndex: -1
        // Threaded in from root, same as model above -- whether a Shift tap
        // should reveal the focused cell's tooltip, and whether the focused
        // cell is currently picked up for a Ctrl-tap move.
        property bool showDescriptions: false
        property bool moveMode: false

        // repeater's id is private to this inline component, so expose the
        // bits outside code needs (the search field's key handlers and the
        // scroll-into-view logic) through the component's public surface.
        readonly property int count: repeater.count

        function cellItem(index) {
            return repeater.itemAt(index);
        }

        function focusCell(index) {
            const count = repeater.count;
            if (count === 0) {
                focusedIndex = -1;
                return;
            }
            focusedIndex = ((index % count) + count) % count;
        }

        property string draggingId: ""

        function indexAtPos(px, py) {
            for (let i = 0; i < repeater.count; i++) {
                const item = repeater.itemAt(i);
                if (!item)
                    continue;
                const p = item.mapFromItem(favRoot, px, py);
                if (p.x >= 0 && p.x < item.width && p.y >= 0 && p.y < item.height)
                    return i;
            }
            return -1;
        }

        Flow {
            id: flow
            width: favRoot.implicitWidth
            spacing: favRoot.cellSpacing

            Repeater {
                id: repeater
                model: ScriptModel {
                    objectProp: "id"
                    values: favRoot.model
                }
                delegate: Item {
                    id: cell
                    required property int index
                    required property var modelData
                    // StyledToolTip shows itself based on "parent.hovered" --
                    // give this plain Item the same interface a button has.
                    property bool hovered: dragArea.containsMouse

                    width: favRoot.cellWidth
                    height: favRoot.cellHeight
                    opacity: favRoot.draggingId === cell.modelData.id ? 0.4 : 1.0

                    Behavior on x {
                        enabled: favRoot.draggingId !== cell.modelData.id
                        animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                    }
                    Behavior on y {
                        enabled: favRoot.draggingId !== cell.modelData.id
                        animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                    }

                    readonly property bool cellInMoveMode: favRoot.moveMode && favRoot.focusedIndex === cell.index

                    Rectangle {
                        anchors.fill: parent
                        radius: Appearance.rounding.normal
                        // A hardcoded amber, not another Appearance.colors
                        // token: colTertiary vs colPrimary already turned out
                        // to be nearly indistinguishable in this wallpaper-
                        // generated Material palette (same failure mode as
                        // the sidebar's colOnSecondaryContainer issue) -- a
                        // fixed, unmistakable color plus a translucent fill
                        // (not just a thin border line) guarantees the
                        // "picked up" state actually reads as different.
                        color: cell.cellInMoveMode ? Qt.rgba(1, 0.65, 0, 0.25)
                            : (dragArea.containsMouse ? Appearance.colors.colLayer1Hover : "transparent")
                        // Keyboard focus gets its own ring, separate from the
                        // hover fill above -- a background tint alone was easy
                        // to miss, especially while Up/Down also scrolls the
                        // focused row into view.
                        border.width: favRoot.focusedIndex === cell.index ? (cell.cellInMoveMode ? 3 : 2) : 0
                        border.color: cell.cellInMoveMode ? Qt.rgba(1, 0.65, 0, 1) : Appearance.colors.colPrimary
                    }

                    ColumnLayout {
                        anchors.fill: parent
                        spacing: 3
                        AppIcon {
                            Layout.topMargin: 12
                            Layout.alignment: Qt.AlignHCenter
                            source: Quickshell.iconPath(cell.modelData.icon, "image-missing")
                            implicitSize: 34
                        }
                        StyledText {
                            Layout.fillHeight: true
                            Layout.fillWidth: true
                            Layout.leftMargin: 8
                            Layout.rightMargin: 8
                            text: cell.modelData.name
                            wrapMode: Text.Wrap
                            elide: Text.ElideRight
                            maximumLineCount: 2
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignTop
                            color: Appearance.colors.colOnLayer0
                        }
                    }

                    MouseArea {
                        id: dragArea
                        anchors.fill: parent
                        hoverEnabled: true
                        acceptedButtons: Qt.LeftButton | Qt.RightButton
                        // The enclosing StyledFlickable would otherwise steal
                        // vertical drags for scrolling, killing drag-to-reorder.
                        // Wheel and dragging on the empty area below the grid
                        // still scroll the viewport.
                        preventStealing: true

                        property bool dragging: false
                        property real pressX: 0
                        property real pressY: 0

                        onPressed: mouse => {
                            pressX = mouse.x;
                            pressY = mouse.y;
                            dragging = false;
                        }
                        onPositionChanged: mouse => {
                            if (!(pressedButtons & Qt.LeftButton))
                                return;
                            if (!dragging && (Math.abs(mouse.x - pressX) > 8 || Math.abs(mouse.y - pressY) > 8)) {
                                dragging = true;
                                favRoot.draggingId = cell.modelData.id;
                            }
                            if (dragging) {
                                if (favRoot.scrollView)
                                    favRoot.lastDragViewPos = mapToItem(favRoot.scrollView, mouse.x, mouse.y);
                                favRoot.dragOver(mapToItem(favRoot, mouse.x, mouse.y));
                            }
                        }
                        onReleased: mouse => {
                            if (!dragging) {
                                if (mouse.button === Qt.RightButton) {
                                    favRoot.appMenu?.popup(dragArea, mouse.x, mouse.y, AppMenuEntries.dashboardEntries(cell.modelData));
                                } else {
                                    GlobalStates.dashboardOpen = false;
                                    cell.modelData.execute();
                                }
                            }
                            dragging = false;
                            favRoot.draggingId = "";
                        }
                    }

                    StyledToolTip {
                        text: Translation.tr("%1\nDrag to reorder -- right-click for options").arg(cell.modelData.name)
                        alternativeVisibleCondition: favRoot.showDescriptions && favRoot.focusedIndex === cell.index
                    }
                }
            }
        }
    }

    // Search bar
    Item {
        id: searchBarContainer
        anchors {
            top: parent.top
            horizontalCenter: parent.horizontalCenter
            topMargin: 36
        }
        implicitWidth: 520
        implicitHeight: searchField.implicitHeight

        MaterialSymbol {
            anchors {
                left: parent.left
                leftMargin: 14
                verticalCenter: parent.verticalCenter
            }
            z: 1
            text: "search"
            iconSize: 18
            color: Appearance.colors.colSubtext
        }

        ToolbarTextField {
            id: searchField
            anchors.fill: parent
            leftPadding: 40
            placeholderText: Translation.tr("Search...")
            onTextChanged: {
                root.searchQuery = text;
                // Typing means the user is back to searching -- drop any
                // keyboard focus state across both panels.
                favoritesFlow.focusedIndex = -1;
                root.appFocusIndex = -1;
                root.focusZone = "";
                root.moveMode = false;
            }

            // Arrow keys steer the virtual focus (root.focusZone) across four
            // regions: this search field, the favorites grid, the app grid,
            // and the category sidebar. With nothing highlighted, Left enters
            // favorites, Down the main grid (apps or search results) and Right
            // the categories (only the caret, while there's a query). Once a
            // grid is focused, Left/Right step one column and Up/Down one
            // row; reaching the last column of favorites hands off to apps,
            // reaching the last column of apps hands off to categories.
            // Typing always hands back to this field.
            // The category list's Up/Down cycle categories (updating the
            // view live) and its Left hands back to apps.
            //
            // Up/Down never conflict with text editing (a single-line field
            // doesn't use them for the caret), so they always navigate --
            // including entering the search results straight out of
            // typing a query, which is the whole point of Down's fallback
            // below. Left/Right DO move the caret while editing, so they
            // only take over once something is already focused in a grid;
            // with nothing focused yet, they're left alone whenever there's
            // a query to edit (searchQuery.length === 0 guards below).
            Keys.onUpPressed: event => {
                event.accepted = true;
                root.arrowHeld = event.isAutoRepeat;
                if (appContextMenu.handleKey(event.key))
                    return;
                if (root.moveMode && root.focusZone === "favorites")
                    root.moveFocusedFavorite(-favoritesFlow.columns, false);
                else if (root.focusZone === "favorites")
                    root.moveFavoritesUp();
                else if (root.focusZone === "apps")
                    root.moveAppsUp();
                else if (root.focusZone === "categories")
                    root.selectAdjacentView(-1, event.isAutoRepeat);
            }
            Keys.onDownPressed: event => {
                event.accepted = true;
                root.arrowHeld = event.isAutoRepeat;
                if (appContextMenu.handleKey(event.key))
                    return;
                if (root.moveMode && root.focusZone === "favorites")
                    root.moveFocusedFavorite(favoritesFlow.columns, false);
                else if (root.focusZone === "favorites")
                    root.moveFavoritesDown();
                else if (root.focusZone === "apps")
                    root.moveAppsDown();
                else if (root.focusZone === "categories")
                    root.selectAdjacentView(1, event.isAutoRepeat);
                else if (root.mainViewItems.length > 0)
                    root.enterApps(0);
            }
            // Keys.onPressed-family handlers default event.accepted to true
            // -- just not mentioning it (as the fall-through branches below
            // used to) still swallows the key, so the "leave the caret
            // alone" case has to set it to false explicitly or the native
            // TextField cursor movement never gets a chance to run.
            Keys.onLeftPressed: event => {
                if (appContextMenu.handleKey(event.key)) {
                    event.accepted = true;
                    return;
                }
                if (root.moveMode && root.focusZone === "favorites") {
                    event.accepted = true;
                    root.moveFocusedFavorite(-1, true);
                } else if (root.focusZone === "favorites") {
                    event.accepted = true;
                    root.moveFavoritesLeft();
                } else if (root.focusZone === "apps") {
                    event.accepted = true;
                    root.moveAppsLeft();
                } else if (root.focusZone === "categories") {
                    event.accepted = true;
                    root.exitCategoriesToApps();
                } else if (root.searchQuery.length === 0 && favoritesFlow.count > 0) {
                    event.accepted = true;
                    root.enterFavorites(0);
                } else {
                    // Nothing focused and there's a query to edit -- let the
                    // native TextField move the caret instead.
                    event.accepted = false;
                }
            }
            Keys.onRightPressed: event => {
                if (appContextMenu.handleKey(event.key)) {
                    event.accepted = true;
                    return;
                }
                if (root.moveMode && root.focusZone === "favorites") {
                    event.accepted = true;
                    root.moveFocusedFavorite(1, true);
                } else if (root.focusZone === "favorites") {
                    event.accepted = true;
                    root.moveFavoritesRight();
                } else if (root.focusZone === "apps") {
                    event.accepted = true;
                    root.moveAppsRight();
                } else if (root.focusZone !== "categories" && root.searchQuery.length === 0) {
                    event.accepted = true;
                    root.enterCategories();
                } else {
                    // There's a query to edit -- Right only moves the caret
                    // (Down is what enters the results).
                    event.accepted = false;
                }
            }
            // Enter on the focused cell launches it (favorite or app, or runs
            // the power action); "P" toggles pin instead, in either grid.
            // Plain TextField doesn't consume Return/Enter, so these arrive
            // here. Both are only reachable with a grid focused, which in
            // turn only happens with an empty query, so there's no risk of
            // swallowing a literal "p" the user is typing to search.
            //
            // Also tracks whether Ctrl/Shift are being tapped alone or held
            // for something else (Ctrl+C in the search field, Shift+letter
            // for a capital while typing): pressing either marks it a tap
            // candidate; pressing any other key while it's down cancels
            // that. Only resolved on release, below.
            Keys.onPressed: event => {
                // Menu open: it owns Enter/Space/Tab/Esc/Alt (arrows are
                // routed from the Keys.on*Pressed handlers above).
                if (appContextMenu.handleKey(event.key)) {
                    event.accepted = true;
                    return;
                }
                if (event.key === Qt.Key_Control) {
                    root.ctrlTapCandidate = true;
                } else if (event.key === Qt.Key_Shift) {
                    root.shiftTapCandidate = true;
                } else {
                    if (event.modifiers & Qt.ControlModifier)
                        root.ctrlTapCandidate = false;
                    if (event.modifiers & Qt.ShiftModifier)
                        root.shiftTapCandidate = false;
                }
                if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                    if (root.focusZone === "favorites" && root.activateFocusedFavorite())
                        event.accepted = true;
                    else if (root.focusZone === "apps" && root.activateFocusedApp())
                        event.accepted = true;
                } else if (event.key === Qt.Key_Menu
                    || (event.key === Qt.Key_F10 && (event.modifiers & Qt.ShiftModifier))) {
                    if (root.openMenuForFocused()) {
                        root.moveMode = false;
                        event.accepted = true;
                    }
                } else if (event.key === Qt.Key_P) {
                    if (root.togglePinOnFocused())
                        event.accepted = true;
                }
            }
            // A clean Ctrl tap (never cancelled by another key while held)
            // toggles move mode -- picking up the focused favorite so the
            // plain arrow keys steer it instead of just navigating, until
            // Ctrl is tapped again. A clean Shift tap toggles showDescriptions.
            Keys.onReleased: event => {
                if ((event.key === Qt.Key_Up || event.key === Qt.Key_Down) && !event.isAutoRepeat) {
                    root.arrowHeld = false;
                    if (viewLoadTimer.running)
                        root.showSelectedView();
                }
                if (event.key === Qt.Key_Control) {
                    if (root.ctrlTapCandidate) {
                        if (root.moveMode)
                            root.moveMode = false;
                        else if (root.focusZone === "favorites" && favoritesFlow.focusedIndex !== -1)
                            root.moveMode = true;
                    }
                    root.ctrlTapCandidate = false;
                } else if (event.key === Qt.Key_Shift) {
                    if (root.shiftTapCandidate)
                        root.showDescriptions = !root.showDescriptions;
                    root.shiftTapCandidate = false;
                }
            }
        }
    }

    RowLayout {
        id: contentRow
        anchors {
            top: searchBarContainer.bottom
            topMargin: 24
            left: parent.left
            right: parent.right
            bottom: parent.bottom
            margins: 24
        }
        spacing: 16

        // Favorites -- fixed width (not a % binding of an ancestor's size --
        // that settles one layout pass too late here and Qt Quick Layouts
        // doesn't re-run after Layout.preferredWidth updates, leaving stale
        // proportions) so the main app section keeps the large majority of
        // the space.
        ColumnLayout {
            id: favColumn
            // Rigid shrink-to-fit width: exactly maxColumns grid columns
            // (maxColumns * cellWidth + (maxColumns - 1) * cellSpacing).
            // maximumWidth is set to the same value so no layout pass can
            // ever stretch this column past the grid -- leftover space then
            // goes to the fillWidth main content column instead.
            Layout.fillWidth: false
            Layout.preferredWidth: favoritesFlow.maxColumns * favoritesFlow.cellWidth + (favoritesFlow.maxColumns - 1) * favoritesFlow.cellSpacing
            Layout.maximumWidth: favoritesFlow.maxColumns * favoritesFlow.cellWidth + (favoritesFlow.maxColumns - 1) * favoritesFlow.cellSpacing
            Layout.fillHeight: true
            spacing: 6

            // Same header + count layout as the main app section.
            RowLayout {
                Layout.fillWidth: true
                SectionHeader { Layout.fillWidth: true; text: Translation.tr("Favorites") }
                StyledText {
                    text: Translation.tr("%1 apps").arg(root.favoriteApps.length)
                    color: Appearance.colors.colSubtext
                    font.pixelSize: Appearance.font.pixelSize.small
                }
            }
            SectionSeparator {}

            // Scrollable viewport: with many pinned apps the grid would
            // otherwise overflow past the bottom of the panel.
            StyledFlickable {
                id: favFlickable
                animateScroll: !root.arrowHeld
                Layout.fillWidth: true
                Layout.fillHeight: true
                contentWidth: width
                contentHeight: favoritesFlow.implicitHeight
                clip: true

                FavoritesFlow {
                    id: favoritesFlow
                    width: favFlickable.width
                    model: root.favoriteApps
                    showDescriptions: root.showDescriptions
                    appMenu: appContextMenu
                    moveMode: root.moveMode
                    scrollView: favFlickable
                }
            }

            // Arrow-key focus may land on a row outside the visible viewport;
            // nudge the scroll position so the focused cell stays on screen.
            Connections {
                target: favoritesFlow
                function onFocusedIndexChanged() {
                    const index = favoritesFlow.focusedIndex;
                    if (index === -1)
                        return;
                    root.lastFavoriteIndex = index;
                    // Row position from the index, not the cell's live y: in
                    // Ctrl move mode the cell is still animating from its old
                    // slot, which made the scroll fall short.
                    const y = favoritesFlow.mapToItem(favFlickable.contentItem, 0, favoritesFlow.rowY(index)).y;
                    const h = favoritesFlow.cellHeight;
                    if (y < favFlickable.contentY)
                        favFlickable.contentY = y;
                    else if (y + h > favFlickable.contentY + favFlickable.height)
                        favFlickable.contentY = y + h - favFlickable.height;
                }
            }
        }

        // Main content
        ColumnLayout {
            id: mainContentColumn
            Layout.fillWidth: true
            Layout.fillHeight: true
            // Extra breathing room from Favorites specifically (on top of
            // contentRow's normal 16px spacing) -- left alone, sidebarColumn
            // keeps its original gap from this column.
            Layout.leftMargin: 24
            spacing: 10

            RowLayout {
                id: mainHeader
                Layout.fillWidth: true
                TapHandler {
                    acceptedButtons: Qt.RightButton
                    onTapped: point => root.openBackgroundMenu(mainHeader, point.position.x, point.position.y)
                }
                SectionHeader { Layout.fillWidth: true; text: root.headerText }
                StyledText {
                    // A search started from Power / Session lists apps again
                    text: (root.searchQuery.length === 0 && root.shownView === "power"
                        ? Translation.tr("%1 actions") : Translation.tr("%1 apps")).arg(root.mainViewItems.length)
                    color: Appearance.colors.colSubtext
                    font.pixelSize: Appearance.font.pixelSize.small
                }
            }
            SectionSeparator {}

            StyledFlickable {
                id: appFlickable
                animateScroll: !root.arrowHeld
                Layout.fillWidth: true
                Layout.fillHeight: true
                contentWidth: width
                contentHeight: mainColumn.implicitHeight
                clip: true

                // Background right-click. Parented to the viewport, not the content, to also
                // cover the space below a short list; z -1 leaves app cells their own menu.
                MouseArea {
                    id: appBackground
                    parent: appFlickable
                    anchors.fill: parent
                    z: -1
                    acceptedButtons: Qt.RightButton
                    onPressed: mouse => root.openBackgroundMenu(appBackground, mouse.x, mouse.y)
                }

                // Switching from a long view (e.g. "All Applications",
                // scrolled down) to a short one (a category, search results)
                // doesn't reset scroll position on its own -- the viewport
                // can end up past the end of the new, shorter content,
                // making it look like nothing rendered. Snap back to top on
                // every view change.
                Connections {
                    target: root
                    function onShownViewChanged() {
                        appFlickable.contentY = 0;
                        root.clearAppFocus();
                    }
                    function onSearchQueryChanged() {
                        appFlickable.contentY = 0;
                        root.clearAppFocus();
                        root.appMemory.delete("\nsearch");
                    }
                }

                ColumnLayout {
                    id: mainColumn
                    // Children declared directly inside a Flickable are
                    // reparented to its internal contentItem, so "parent"
                    // here is NOT appFlickable -- it would silently resolve
                    // to contentItem (whose width isn't driven by
                    // contentWidth), leaving this column -- and everything
                    // inside it -- stuck at its natural/implicit width
                    // instead of the ~80% share this is supposed to fill.
                    width: appFlickable.width
                    spacing: 20

                    Loader {
                        Layout.fillWidth: true
                        active: root.searchQuery.length > 0
                        // A deactivated Loader keeps reporting the
                        // implicitHeight of the item it just destroyed (a
                        // genuine Qt Quick Layouts quirk) instead of
                        // collapsing to 0, so it still eats ColumnLayout
                        // space -- and when this Loader was letterGroups
                        // (tens of thousands of px tall), everything
                        // declared after it landed far off-screen.
                        // ColumnLayout excludes invisible children outright,
                        // which sidesteps the stale-height reporting entirely.
                        visible: active
                        sourceComponent: AppFlow {
                            width: mainColumn.width
                            model: root.searchResults
                            focusIndex: root.focusZone === "apps" ? root.appFocusIndex : -1
                            showDescriptions: root.showDescriptions
                            appMenu: appContextMenu
                            onFocusCellRequested: cell => root.ensureAppCellVisible(cell)
                        }
                    }

                    Loader {
                        Layout.fillWidth: true
                        active: root.searchQuery.length === 0 && root.shownView === "power"
                        visible: active
                        sourceComponent: RowLayout {
                            spacing: 24
                            Repeater {
                                model: root.powerActions
                                delegate: ColumnLayout {
                                    required property int index
                                    required property var modelData
                                    // SessionActionButton styles real Item
                                    // focus; mirror that look for the
                                    // virtual keyboard focus here.
                                    property bool keyboardFocused: root.focusZone === "apps" && root.appFocusIndex === index
                                    spacing: 6
                                    SessionActionButton {
                                        Layout.alignment: Qt.AlignHCenter
                                        size: 56
                                        buttonIcon: modelData.icon
                                        buttonText: modelData.label
                                        keyboardDown: parent.keyboardFocused
                                        buttonRadius: parent.keyboardFocused ? size / 2 : Appearance.rounding.verylarge
                                        onClicked: {
                                            GlobalStates.dashboardOpen = false;
                                            modelData.action();
                                        }
                                    }
                                    StyledText {
                                        Layout.alignment: Qt.AlignHCenter
                                        text: modelData.label
                                        color: Appearance.colors.colOnLayer0
                                    }
                                }
                            }
                        }
                    }

                    Loader {
                        Layout.fillWidth: true
                        active: root.searchQuery.length === 0 && root.shownView === "all"
                        visible: active
                        sourceComponent: ColumnLayout {
                            width: mainColumn.width
                            spacing: 20
                            Repeater {
                                model: root.letterGroups
                                delegate: ColumnLayout {
                                    id: letterSection
                                    required property var modelData
                                    Layout.fillWidth: true
                                    spacing: 6
                                    StyledText {
                                        text: modelData.letter
                                        color: Appearance.colors.colOnLayer0
                                        font {
                                            family: Appearance.font.family.title
                                            pixelSize: Appearance.font.pixelSize.larger
                                            variableAxes: Appearance.font.variableAxes.title
                                        }
                                    }
                                    SectionSeparator {}
                                    AppFlow {
                                        Layout.fillWidth: true
                                        model: modelData.apps
                                        focusIndex: root.focusZone === "apps"
                                            && root.appFocusIndex >= modelData.offset
                                            && root.appFocusIndex < modelData.offset + modelData.apps.length
                                            ? root.appFocusIndex - modelData.offset : -1
                                        showDescriptions: root.showDescriptions
                                        appMenu: appContextMenu
                                        onFocusCellRequested: cell => root.ensureAppCellVisible(cell, letterSection)
                                    }
                                }
                            }
                        }
                    }

                    Loader {
                        Layout.fillWidth: true
                        active: root.searchQuery.length === 0 && root.shownView !== "all" && root.shownView !== "power"
                        visible: active
                        sourceComponent: AppFlow {
                            width: mainColumn.width
                            model: root.currentCategoryApps
                            focusIndex: root.focusZone === "apps" ? root.appFocusIndex : -1
                            showDescriptions: root.showDescriptions
                            appMenu: appContextMenu
                            onFocusCellRequested: cell => root.ensureAppCellVisible(cell)
                        }
                    }
                }
            }
        }

        // Sidebar -- same fixed-width reasoning as favColumn above.
        ColumnLayout {
            id: sidebarColumn
            Layout.preferredWidth: 190
            Layout.alignment: Qt.AlignTop
            spacing: 0

            // Vertical list, so wheel up = the entry above.
            WheelHandler {
                acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
                target: null
                property real pendingDelta: 0 // Touchpads send fractions of a notch
                onWheel: event => {
                    if (pendingDelta * event.angleDelta.y < 0) pendingDelta = 0; // Changed direction
                    pendingDelta += event.angleDelta.y;
                    const steps = Math.trunc(pendingDelta / 120);
                    if (steps === 0) return;
                    pendingDelta -= steps * 120;
                    root.scrollViews(-steps);
                }
            }

            // Clicking a RippleButton grabs real active focus, which would
            // otherwise leave the arrow keys with nowhere to land -- all of
            // this file's keyboard navigation depends on searchField always
            // holding real focus (see its Keys handlers below). Reclaim it
            // on every click, including re-clicking the already-active
            // category (whose selectedView assignment is a no-op and so
            // wouldn't otherwise fire anything).
            DashboardSidebarItem {
                label: Translation.tr("All Applications")
                toggled: root.selectedView === "all"
                onClicked: {
                    root.selectedView = "all";
                    searchField.forceActiveFocus();
                }
            }

            Repeater {
                model: root.categoryGroups
                delegate: DashboardSidebarItem {
                    required property var modelData
                    label: modelData.label
                    toggled: root.selectedView === modelData.label
                    onClicked: {
                        root.selectedView = modelData.label;
                        searchField.forceActiveFocus();
                    }
                }
            }

            Item { Layout.preferredHeight: 6 }

            DashboardSidebarItem {
                label: Translation.tr("Power / Session")
                toggled: root.selectedView === "power"
                onClicked: {
                    root.selectedView = "power";
                    searchField.forceActiveFocus();
                }
            }
        }
    }
}
