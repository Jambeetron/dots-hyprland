pragma Singleton

import qs
import qs.modules.common
import QtQuick
import Quickshell

/**
 * Builds the entry lists for AppContextMenu (dock right-click).
 */
Singleton {
    id: root

    // Desktop-file "Actions=" (New Window, New Private Window, Profile
    // Manager...), as declared by the app itself.
    function desktopActions(entry, onLaunch) {
        if (!entry || !entry.actions)
            return [];
        const result = [];
        for (const a of entry.actions) {
            result.push({
                type: "action",
                text: a.name,
                icon: a.icon || entry.icon,
                action: () => {
                    onLaunch?.();
                    a.execute();
                }
            });
        }
        return result;
    }

    function dockEntries(appId) {
        const actions = root.desktopActions(DesktopEntries.heuristicLookup(appId));
        if (actions.length > 0)
            actions.push({ type: "separator" });
        return actions.concat([
            {
                type: "check",
                text: Translation.tr("Pin to Task Manager"),
                checked: TaskbarApps.isPinned(appId),
                action: () => TaskbarApps.togglePin(appId)
            },
            {
                type: "check",
                text: Translation.tr("Allow this program to be grouped"),
                checked: TaskbarApps.isGrouped(appId),
                action: () => TaskbarApps.toggleGrouped(appId)
            }
        ]);
    }
}
