import qs.modules.common
import qs.services
import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
pragma Singleton
pragma ComponentBehavior: Bound

Singleton {
    id: root
    property bool barOpen: true
    property bool crosshairOpen: false
    property bool dashboardOpen: false
    property bool sidebarLeftOpen: false
    property bool sidebarRightOpen: false
    property bool mediaControlsOpen: false
    property bool osdBrightnessOpen: false
    property bool osdVolumeOpen: false
    property bool oskOpen: false
    property bool overlayOpen: false
    property bool overviewOpen: false
    property bool regionSelectorOpen: false
    property bool searchOpen: false
    property real searchPanelHeight: 0
    property bool searchHasText: false
    property bool screenLocked: false
    property bool screenLockContainsCharacters: false
    property bool screenUnlockFailed: false
    property bool screenTranslatorOpen: false
    property bool sessionOpen: false
    property bool superDown: false
    property bool superReleaseMightTrigger: true
    // Addresses of windows selected in the overview (right-click).
    // Left-clicking a workspace in the overview moves them there (without switching workspace).
    property var selectedWindows: []

    // Closed windows leave the selection immediately: if a reopened window
    // reuses a closed one's address, it doesn't inherit the selection.
    Connections {
        target: HyprlandData
        function onAddressesChanged() {
            const filtered = root.selectedWindows.filter(a => HyprlandData.addresses.includes(a));
            if (filtered.length !== root.selectedWindows.length)
                root.selectedWindows = filtered;
        }
    }
    property bool wallpaperSelectorOpen: false
    property bool workspaceShowNumbers: false
    // Set by Workspaces.qml (bar widget) from its own containsMouse, so the
    // superScrollDown/Up GlobalShortcuts below know whether to jump a full
    // group of 10 (on the bar) or step by 1 (anywhere else). This is the
    // SOLE place that dispatches a workspace change for Super+scroll -- the
    // Hyprland bind (custom/wsextra.lua) only forwards here, it no longer
    // dispatches focus itself, so there's never two competing dispatches
    // (which used to cause a visible flicker to the wrong workspace before
    // a correction landed).
    property bool workspacesBarHovered: false

    onSidebarRightOpenChanged: {
        if (GlobalStates.sidebarRightOpen) {
            Notifications.timeoutAll();
            Notifications.markAllRead();
        }
    }

    GlobalShortcut {
        name: "workspaceNumber"
        description: "Hold to show workspace numbers, release to show icons"

        onPressed: {
            root.superDown = true
        }
        onReleased: {
            root.superDown = false
        }
    }

    function superScroll(direction) {
        const cur = Hyprland.focusedMonitor?.activeWorkspace?.id;
        if (cur === undefined)
            return;
        const step = root.workspacesBarHovered ? 10 : 1;
        const sign = Config.options.interactions.tabs.wheelUpIncrements ? 1 : -1; // direction is +1 for wheel up
        const target = cur + direction * sign * step;
        if (target >= 1 && target <= 100)
            Hyprland.dispatch(`hl.dsp.focus({workspace = ${target}})`);
    }

    GlobalShortcut {
        name: "superScrollDown"
        description: "Workspace: Focus -1 outside / -10 on bar"

        onPressed: root.superScroll(-1)
    }
    GlobalShortcut {
        name: "superScrollUp"
        description: "Workspace: Focus +1 outside / +10 on bar"

        onPressed: root.superScroll(1)
    }
}