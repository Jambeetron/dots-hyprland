pragma Singleton
import qs.modules.common
import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    readonly property bool inhibit: inhibitProcess.running

    function toggleInhibit(active = null) {
        if (active !== null) {
            Persistent.states.idle.inhibit = active;
        } else {
            Persistent.states.idle.inhibit = !Persistent.states.idle.inhibit;
        }
    }

    function touch() {}

    Process {
        id: inhibitProcess
        running: Persistent.states.idle.inhibit
        command: [
            "systemd-inhibit",
            "--what=idle",
            "--who=Quickshell",
            "--why=Keep system awake",
            "--mode=block",
            "sleep",
            "1000000000",
        ]
    }
}
