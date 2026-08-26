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
    property bool screenLocked: false
    property bool screenLockContainsCharacters: false
    property bool screenUnlockFailed: false
    property bool screenTranslatorOpen: false
    property bool sessionOpen: false
    property bool superDown: false
    property bool superReleaseMightTrigger: true
    // Direcciones de ventanas seleccionadas en el overview (click derecho).
    // Click izquierdo sobre un workspace del overview las mueve ahi (sin cambiar de workspace).
    property var selectedWindows: []

    // Las ventanas que se cierran salen de la seleccion al instante: si una ventana
    // reabierta reutiliza la direccion de una cerrada, no hereda la seleccion.
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
}