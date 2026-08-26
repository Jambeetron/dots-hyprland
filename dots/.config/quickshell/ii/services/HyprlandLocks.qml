import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland

Item {
    id: root

    property bool capsLock: false
    property bool numLock: false

    function updateLocks() {
        proc.running = true
    }

    Process {
        id: proc
        command: ["hyprctl", "devices"]

        stdout: StdioCollector {
            onStreamFinished: {
                const output = text

                const mainKb = output.split("Keyboard")
                    .find(kb => kb.includes("main: yes"))

                if (!mainKb)
                    return

                root.capsLock = mainKb.includes("capsLock: yes")
                root.numLock  = mainKb.includes("numLock: yes")
            }
        }
    }

    Connections {
        target: Hyprland

        function onRawEvent(event) {
            if (event.name === "activelayout"
                || event.name === "configreloaded") {
                root.updateLocks()
            }
        }
    }

    Timer {
        interval: 1200
        running: true
        repeat: true

        onTriggered: root.updateLocks()
    }

    // Initial fetch on startup
    Component.onCompleted: updateLocks()
}
