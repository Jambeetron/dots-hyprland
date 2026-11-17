pragma Singleton

import qs.modules.common
import QtQuick
import Quickshell
import Quickshell.Wayland

Singleton {
    id: root

    // Case-insensitive: the dock passes lowercased ids, the dashboard passes
    // the desktop entry's real id -- both must agree on the same pin.
    function isPinned(appId) {
        const lower = appId.toLowerCase();
        return Config.options.dock.pinnedApps.some(id => id.toLowerCase() === lower);
    }

    function togglePin(appId) {
        const lower = appId.toLowerCase();
        if (root.isPinned(appId)) {
            Config.options.dock.pinnedApps = Config.options.dock.pinnedApps.filter(id => id.toLowerCase() !== lower)
        } else {
            Config.options.dock.pinnedApps = Config.options.dock.pinnedApps.concat([appId])
        }
    }

    // "Allow this program to be grouped": grouped by default; apps listed in
    // dock.ungroupedApps get one dock button per open window instead.
    function isGrouped(appId) {
        const lower = appId.toLowerCase();
        return !(Config.options.dock.ungroupedApps ?? []).some(id => id.toLowerCase() === lower);
    }

    function toggleGrouped(appId) {
        const lower = appId.toLowerCase();
        const list = Config.options.dock.ungroupedApps ?? [];
        if (root.isGrouped(appId))
            Config.options.dock.ungroupedApps = list.concat([lower]);
        else
            Config.options.dock.ungroupedApps = list.filter(id => id.toLowerCase() !== lower);
    }

    // Used while drag-reordering pinned dock icons (DockAppButton.qml).
    // appId arrives as apps[].appId, which is always lowercased (see the
    // Map below) -- match case-insensitively against pinnedApps (which may
    // hold the desktop entry's original casing) and splice back whatever
    // was actually stored, so this can't silently no-op or duplicate an
    // entry for an app whose id isn't already all-lowercase.
    function reorder(appId, newIndex) {
        const pinnedApps = Config.options.dock.pinnedApps.slice();
        const oldIndex = pinnedApps.findIndex(id => id.toLowerCase() === appId.toLowerCase());
        if (oldIndex === -1 || oldIndex === newIndex) return;
        const actualId = pinnedApps[oldIndex];
        pinnedApps.splice(oldIndex, 1);
        const clampedIndex = Math.max(0, Math.min(newIndex, pinnedApps.length));
        pinnedApps.splice(clampedIndex, 0, actualId);
        Config.options.dock.pinnedApps = pinnedApps;
    }

    // Manual order of running (unpinned) dock buttons, by entry key. Kept
    // for the session only; keys of closed apps stay so a reopened app
    // returns to where it was. Keys never seen go to the end.
    property list<string> runningOrder: []

    function reorderRunning(key, newIndex) {
        const keys = root.apps.filter(a => !a.pinned && a.appId !== "SEPARATOR").map(a => a.key);
        const oldIndex = keys.indexOf(key);
        if (oldIndex === -1 || oldIndex === newIndex) return;
        keys.splice(oldIndex, 1);
        keys.splice(Math.max(0, Math.min(newIndex, keys.length)), 0, key);
        const stale = root.runningOrder.filter(k => !keys.includes(k));
        root.runningOrder = keys.concat(stale);
    }

    property list<var> apps: {
        var map = new Map();

        // Pinned apps
        const pinnedApps = Config.options?.dock.pinnedApps ?? [];
        for (const appId of pinnedApps) {
            if (!map.has(appId.toLowerCase())) map.set(appId.toLowerCase(), ({
                pinned: true,
                toplevels: []
            }));
        }

        // Separator
        if (pinnedApps.length > 0) {
            map.set("SEPARATOR", { pinned: false, toplevels: [] });
        }

        // Ignored apps
        const ignoredRegexStrings = Config.options?.dock.ignoredAppRegexes ?? [];
        const ignoredRegexes = ignoredRegexStrings.map(pattern => new RegExp(pattern, "i"));
        const ungrouped = new Set((Config.options?.dock.ungroupedApps ?? []).map(id => id.toLowerCase()));
        // Extra per-window buttons for ungrouped apps, keyed by app id. The
        // app's first window stays on its main entry (so a pinned launcher
        // keeps working); every further window gets its own button.
        const extras = new Map();
        // Open windows
        for (const toplevel of ToplevelManager.toplevels.values) {
            if (ignoredRegexes.some(re => re.test(toplevel.appId))) continue;
            const id = toplevel.appId.toLowerCase();
            if (!map.has(id)) map.set(id, ({
                pinned: false,
                toplevels: []
            }));
            const main = map.get(id);
            if (ungrouped.has(id) && main.toplevels.length > 0) {
                if (!extras.has(id)) extras.set(id, []);
                extras.get(id).push(toplevel);
            } else {
                main.toplevels.push(toplevel);
            }
        }

        var values = [];
        const push = (key, appId, toplevels, pinned) => values.push(appEntryComp.createObject(null, {
            key: key, appId: appId, toplevels: toplevels, pinned: pinned
        }));

        // Section 1: pinned entries (drag-to-reorder relies on model index
        // == pinned index). Section 2, after the separator: running items
        // -- extras of pinned apps, then running apps each followed by their
        // own extras -- re-sorted by the manual runningOrder.
        for (const [key, value] of map) {
            if (value.pinned) push(key, key, value.toplevels, true);
        }
        if (map.has("SEPARATOR"))
            push("SEPARATOR", "SEPARATOR", [], false);

        const running = [];
        const addExtras = id => (extras.get(id) ?? []).forEach((t, i) => running.push({ key: `${id}#${i + 1}`, appId: id, toplevels: [t] }));
        for (const [key, value] of map) {
            if (value.pinned) addExtras(key);
        }
        for (const [key, value] of map) {
            if (value.pinned || key === "SEPARATOR") continue;
            running.push({ key: key, appId: key, toplevels: value.toplevels });
            addExtras(key);
        }
        const order = root.runningOrder;
        const rank = (r, i) => {
            const o = order.indexOf(r.key);
            return o === -1 ? order.length + i : o;
        };
        running.map((r, i) => ({ r: r, rank: rank(r, i) }))
            .sort((a, b) => a.rank - b.rank)
            .forEach(({ r }) => push(r.key, r.appId, r.toplevels, false));

        return values;
    }

    component TaskbarAppEntry: QtObject {
        id: wrapper
        // Unique per dock button (appId, or appId#n for an ungrouped window).
        required property string key
        required property string appId
        required property list<var> toplevels
        required property bool pinned
    }
    Component {
        id: appEntryComp
        TaskbarAppEntry {}
    }
}
