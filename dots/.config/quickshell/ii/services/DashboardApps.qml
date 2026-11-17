pragma Singleton

import qs.modules.common
import QtQuick
import Quickshell

Singleton {
    id: root

    // ---- Auto-clean favorites of uninstalled apps ----
    // A favorite whose .desktop file no longer exists is hidden by the grid
    // but would otherwise stay in pinnedApps forever (and throw off index-
    // based logic). Prune those ids automatically -- but only once both the
    // config and the desktop-entry database have loaded, and only after the
    // app list has been quiet for a few seconds, so a startup scan still in
    // progress (or a package update briefly removing/re-adding a .desktop
    // file) can never wipe a valid favorite.
    function pruneMissing() {
        if (!Config.ready)
            return;
        if ((DesktopEntries.applications?.values?.length ?? 0) === 0)
            return;
        const pinnedApps = Config.options.dashboard.pinnedApps;
        const kept = pinnedApps.filter(id => DesktopEntries.byId(id));
        if (kept.length === pinnedApps.length)
            return;
        console.log("[DashboardApps] Removing favorites of uninstalled apps:",
            pinnedApps.filter(id => !kept.includes(id)).join(", "));
        Config.options.dashboard.pinnedApps = kept;
    }

    Timer {
        id: pruneTimer
        interval: 5000
        onTriggered: root.pruneMissing()
    }

    Connections {
        target: DesktopEntries
        function onApplicationsChanged() {
            pruneTimer.restart();
        }
    }

    Connections {
        target: Config
        function onReadyChanged() {
            if (Config.ready)
                pruneTimer.restart();
        }
    }

    Component.onCompleted: pruneTimer.restart()

    function isPinned(appId) {
        return Config.options.dashboard.pinnedApps.indexOf(appId) !== -1;
    }

    function togglePin(appId) {
        if (root.isPinned(appId)) {
            Config.options.dashboard.pinnedApps = Config.options.dashboard.pinnedApps.filter(id => id !== appId)
        } else {
            Config.options.dashboard.pinnedApps = Config.options.dashboard.pinnedApps.concat([appId])
        }
    }

    function moveToFront(appId) {
        if (!root.isPinned(appId)) return;
        const pinnedApps = Config.options.dashboard.pinnedApps;
        Config.options.dashboard.pinnedApps = [appId].concat(pinnedApps.filter(id => id !== appId));
    }

    function moveLeft(appId) {
        const pinnedApps = Config.options.dashboard.pinnedApps;
        const index = pinnedApps.indexOf(appId);
        if (index === -1 || index === 0) return;
        Config.options.dashboard.pinnedApps = pinnedApps.slice(0, index - 1).concat([appId]).concat(pinnedApps[index - 1]).concat(pinnedApps.slice(index + 1));
    }

    function moveRight(appId) {
        const pinnedApps = Config.options.dashboard.pinnedApps;
        const index = pinnedApps.indexOf(appId);
        if (index === -1 || index === pinnedApps.length - 1) return;
        Config.options.dashboard.pinnedApps = pinnedApps.slice(0, index).concat(pinnedApps[index + 1]).concat([appId]).concat(pinnedApps.slice(index + 2));
    }

    // Used while drag-reordering: move appId to sit at newIndex among the
    // other pinned apps.
    function reorder(appId, newIndex) {
        const pinnedApps = Config.options.dashboard.pinnedApps.slice();
        const oldIndex = pinnedApps.indexOf(appId);
        if (oldIndex === -1 || oldIndex === newIndex) return;
        pinnedApps.splice(oldIndex, 1);
        const clampedIndex = Math.max(0, Math.min(newIndex, pinnedApps.length));
        pinnedApps.splice(clampedIndex, 0, appId);
        Config.options.dashboard.pinnedApps = pinnedApps;
    }

    // Used while drag-reordering the Favorites grid: move appId into the
    // slot currently held by targetId. Resolved by id, not by grid index --
    // pinnedApps can hold ids with no installed .desktop file, which the
    // grid filters out, so a grid index and a pinnedApps index drift apart
    // after the first such entry (dropping one slot early, i.e. down-left).
    function reorderToId(appId, targetId) {
        if (appId === targetId) return;
        const pinnedApps = Config.options.dashboard.pinnedApps.slice();
        const from = pinnedApps.indexOf(appId);
        const to = pinnedApps.indexOf(targetId);
        if (from === -1 || to === -1) return;
        pinnedApps.splice(from, 1);
        // Moving forward: target shifted left by the removal, so inserting at
        // `to` lands right after it. Moving backward: lands right before it.
        // Either way appId ends up in the target's original slot.
        pinnedApps.splice(to, 0, appId);
        Config.options.dashboard.pinnedApps = pinnedApps;
    }

    // Used for keyboard-driven reordering (Ctrl+arrows): a clean two-element
    // swap, unlike reorder() above which shifts everything between the old
    // and new slot -- that's the right call for a drag (one continuous
    // move), but would drag every other icon along with it for what's meant
    // to be a single grid-position swap.
    //
    // Takes both ends by id rather than a raw array index: pinnedApps can
    // contain ids that no longer resolve to an installed app (e.g. an
    // uninstalled app that's still pinned), which the dashboard's grid
    // silently filters out when rendering -- so a rendered grid position
    // and its raw index into this array can drift apart. Resolving both ids
    // against the live array here sidesteps that entirely.
    function swap(appIdA, appIdB) {
        if (appIdA === appIdB) return;
        const pinnedApps = Config.options.dashboard.pinnedApps.slice();
        const indexA = pinnedApps.indexOf(appIdA);
        const indexB = pinnedApps.indexOf(appIdB);
        if (indexA === -1 || indexB === -1) return;
        const tmp = pinnedApps[indexA];
        pinnedApps[indexA] = pinnedApps[indexB];
        pinnedApps[indexB] = tmp;
        Config.options.dashboard.pinnedApps = pinnedApps;
    }
}
