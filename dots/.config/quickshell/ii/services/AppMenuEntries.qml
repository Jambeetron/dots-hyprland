pragma Singleton

import qs
import qs.modules.common
import QtQuick
import Quickshell

/**
 * Builds the entry lists for AppContextMenu (dock + dashboard right-click).
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

    function dashboardEntries(entry) {
        const close = () => GlobalStates.dashboardOpen = false;
        const result = root.desktopActions(entry, close);
        if (result.length > 0)
            result.push({ type: "separator" });
        result.push({
            type: "check",
            text: Translation.tr("Show in Favorites"),
            checked: DashboardApps.isPinned(entry.id),
            action: () => DashboardApps.togglePin(entry.id)
        });
        result.push({
            type: "check",
            text: Translation.tr("Pin to Task Manager"),
            checked: TaskbarApps.isPinned(entry.id),
            action: () => TaskbarApps.togglePin(entry.id)
        });
        result.push({ type: "separator" });
        result.push({
            type: "action",
            text: Translation.tr("Edit Application..."),
            icon: "kmenuedit",
            action: () => {
                close();
                Quickshell.execDetached(["kmenuedit", `${entry.id}.desktop`]);
            }
        });
        result.push({
            type: "action",
            text: Translation.tr("Uninstall or Manage Add-ons..."),
            icon: "plasmadiscover",
            action: () => {
                close();
                Quickshell.execDetached(["plasma-discover", "--application", `appstream://${entry.id}`]);
            }
        });
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
