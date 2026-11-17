import qs
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import qs.modules.common.models.hyprland
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland

Scope {
    id: dashboardScope
    property var focusedScreen: Quickshell.screens.find(s => s.name === Hyprland.focusedMonitor?.name)
    // Quickshell's own screen object has no notion of reserved space (bar/
    // dock exclusive zones) -- that only comes from hyprctl's own monitor
    // data, kept live by HyprlandData (same source OverviewWidget.qml uses
    // for drawing to-scale window thumbnails).
    property var focusedMonitorData: HyprlandData.monitors.find(m => m.id === Hyprland.focusedMonitor?.id)

    // Same gap Hyprland puts between every tiled window and the work area
    // edge -- read live so the dashboard's window mode always matches
    // whatever the user has configured, not a copy that can drift out of
    // sync.
    HyprlandConfigOption {
        id: gapsOutOption
        key: "general:gaps_out"
    }
    HyprlandConfigOption {
        id: roundingOption
        key: "decoration:rounding"
    }

    Loader {
        id: dashboardLoader
        active: GlobalStates.dashboardOpen

        Connections {
            target: GlobalStates
            function onDashboardOpenChanged() {
                if (GlobalStates.dashboardOpen) {
                    // Window mode sizes itself from the monitor's reserved
                    // area; make sure it's fresh (e.g. dock pin toggled,
                    // which changes the exclusive zone without any event).
                    HyprlandData.updateMonitors();
                    GlobalStates.overviewOpen = false;
                    GlobalStates.searchOpen = false;
                }
            }
        }

        sourceComponent: PanelWindow {
            id: dashboardRoot
            visible: dashboardLoader.active

            readonly property bool windowMode: Config.options.dashboard.displayMode === "window"

            // Work-area geometry: the same area a maximized/tiled window
            // occupies -- hyprctl's reserved is [left, top, right, bottom]
            // in physical pixels (confirmed against hyprctl clients -j: a
            // tiled window here sits at [6,46] size [1908,963] on a
            // 1920x1080/scale-1 screen with reserved [0,40,0,65] and
            // gaps_out 5 -- matches once reserved is divided by scale and
            // one more gaps_out gap is added on every edge, same as
            // OverviewWidget.qml's reserved[]/monitor.scale conversion).
            readonly property real monitorScale: dashboardScope.focusedMonitorData?.scale ?? 1
            readonly property var reserved: dashboardScope.focusedMonitorData?.reserved ?? [0, 0, 0, 0]
            // general:gaps_out comes back from hyprctl as a CSS-style box
            // value ("5 5 5 5"), not a plain number -- parseFloat grabs just
            // the first of the four. "|| 5" (not "??") because parseFloat of
            // an unset/undefined value is NaN, which "??" wouldn't catch.
            readonly property real gap: parseFloat(gapsOutOption.value) || 5
            readonly property real insetLeft: reserved[0] / monitorScale + gap
            readonly property real insetTop: reserved[1] / monitorScale + gap
            readonly property real insetRight: reserved[2] / monitorScale + gap
            readonly property real insetBottom: reserved[3] / monitorScale + gap

            function hide() {
                GlobalStates.dashboardOpen = false;
            }

            exclusionMode: ExclusionMode.Ignore
            WlrLayershell.namespace: "quickshell:dashboard"
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
            // Full screen: a translucent tint over the whole desktop, same
            // as before. Window mode: transparent -- dashboardCard below
            // paints its own opaque bordered background instead, so it
            // reads as an actual floating window rather than a screen tint.
            color: dashboardRoot.windowMode ? "transparent" : ColorUtils.transparentize(Appearance.m3colors.m3background, Appearance.m3colors.darkmode ? 0.05 : 0.12)

            // Anchoring all four edges makes wlr-layer-shell treat this as a
            // "stretch to fill" request (constrainedSize() in Quickshell's
            // own wlr_layershell/surface.cpp forces size to 0, i.e. stretch,
            // whenever both opposite edges are anchored) -- implicitWidth/
            // Height can't shrink the actual surface below fullscreen, full
            // stop. So the surface itself always stays fullscreen; dashboardCard
            // below is what's actually small and centered in window mode
            // (same trick Cheatsheet.qml's "floating panel" secretly uses --
            // its surface is fullscreen and transparent too).
            anchors {
                top: true
                bottom: true
                left: true
                right: true
            }

            implicitWidth: dashboardScope.focusedScreen?.width ?? 0
            implicitHeight: dashboardScope.focusedScreen?.height ?? 0

            Shortcut {
                sequence: "Escape"
                // With the app options menu open, Esc closes just the menu.
                enabled: dashboardRoot.visible && !content.appMenuOpen
                onActivated: dashboardRoot.hide()
            }

            MouseArea {
                id: dashboardMouseArea
                anchors.fill: parent
                onClicked: dashboardRoot.hide();

                // StyledRectangularShadow anchors.fill: target, which only
                // works against a parent or sibling -- it has to live next
                // to dashboardCard, not up at the PanelWindow level.
                StyledRectangularShadow {
                    visible: dashboardRoot.windowMode
                    target: dashboardCard
                }

                Rectangle {
                    id: dashboardCard
                    // Always anchors.fill -- only the margins change. In
                    // window mode they're the work-area insets computed
                    // above (origin anchored like a maximized window, not
                    // centered at a size of its own); in fullscreen mode
                    // they're zero, filling the surface exactly like before.
                    anchors.fill: parent
                    anchors.leftMargin: dashboardRoot.windowMode ? dashboardRoot.insetLeft : 0
                    anchors.topMargin: dashboardRoot.windowMode ? dashboardRoot.insetTop : 0
                    anchors.rightMargin: dashboardRoot.windowMode ? dashboardRoot.insetRight : 0
                    anchors.bottomMargin: dashboardRoot.windowMode ? dashboardRoot.insetBottom : 0
                    color: dashboardRoot.windowMode ? Appearance.colors.colLayer0 : "transparent"
                    radius: dashboardRoot.windowMode ? (parseFloat(roundingOption.value) || Appearance.rounding.windowRounding) : 0
                    border.width: dashboardRoot.windowMode ? 1 : 0
                    border.color: Appearance.colors.colLayer0Border

                    DashboardContent {
                        id: content
                        anchors.fill: parent
                    }
                }
            }
        }
    }

    IpcHandler {
        target: "dashboard"

        function toggle(): void {
            GlobalStates.dashboardOpen = !GlobalStates.dashboardOpen;
        }
        function close(): void {
            GlobalStates.dashboardOpen = false;
        }
        function open(): void {
            GlobalStates.dashboardOpen = true;
        }
    }

    GlobalShortcut {
        name: "dashboardToggle"
        description: "Toggles the application dashboard on press"

        onPressed: {
            GlobalStates.dashboardOpen = !GlobalStates.dashboardOpen;
        }
    }
    GlobalShortcut {
        name: "dashboardClose"
        description: "Closes the application dashboard on press"

        onPressed: {
            GlobalStates.dashboardOpen = false;
        }
    }
}
