pragma Singleton
pragma ComponentBehavior: Bound

import qs.modules.common
import qs.modules.common.functions
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland

/**
 * A service that provides access to Hyprland keybinds.
 * Uses the `get_keybinds.py` script to parse comments in config files in a certain format and convert to JSON.
 */
Singleton {
    id: root
    property var keybinds: []
    property var keybindCategories: []

    Connections {
        target: Hyprland

        function onRawEvent(event) {
            if (event.name == "configreloaded") {
                getKeybinds.running = true
            }
        }
    }

    Process {
        id: getKeybinds
        running: true
        command: ["hyprctl", "binds", "-j"]
        
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    // Dashboard's Ctrl/Shift taps (move mode, show/hide
                    // description) are intentionally *not* real Hyprland
                    // binds -- they're handled entirely in DashboardContent.
                    // qml's own key handlers, so they only fire while the
                    // dashboard's layer-shell surface has focus, instead of
                    // intercepting Ctrl/Shift globally. Since hyprctl binds -j
                    // has no record of them, they're spliced in here as
                    // synthetic entries (same shape CheatsheetKeybindsCategory
                    // .qml expects: modmask/key/description). modmask: 0 and
                    // key: "Ctrl"/"Shift" (rather than modmask: Ctrl + some
                    // other key) renders as a standalone key with no "+"
                    // suffix, matching what a tap actually is.
                    const syntheticKeybinds = [
                        { modmask: 0, key: "Ctrl", description: "Dashboard: Pick up / drop focused favorite (move with arrows)" },
                        { modmask: 1, key: "F10", description: "Dashboard: Open focused app's options (arrows + Enter to pick)" },
                        { modmask: 0, key: "Shift", description: "Dashboard: Show / hide focused item's full name" },
                    ];
                    const binds = JSON.parse(text).concat(syntheticKeybinds)
                    // hyprctl lists binds in registration order: the base
                    // hyprland/keybinds.lua first, custom/keybinds.lua after.
                    // Move selected custom binds next to a related base bind
                    // (matched by description) so they read in a sensible order.
                    const placeAfter = [
                        { move: "Shell: Toggle dashboard", after: "Shell: Toggle search + overview" },
                    ];
                    for (const rule of placeAfter) {
                        const from = binds.findIndex(b => b.description === rule.move);
                        if (from === -1) continue;
                        const [moved] = binds.splice(from, 1);
                        const anchor = binds.findIndex(b => b.description === rule.after);
                        binds.splice(anchor === -1 ? from : anchor + 1, 0, moved);
                    }
                    root.keybinds = binds
                    var groups = []
                    for (var i = 0; i < root.keybinds.length; i++) {
                        var bind = root.keybinds[i].description
                        var group = bind.substring(0, bind.indexOf(":"))
                        if (!groups.includes(group) && group.length > 0) {
                            groups.push(group)
                        }
                    }
                    root.keybindCategories = groups
                } catch (e) {
                    console.error("[CheatsheetKeybinds] Error parsing keybinds:", e)
                }
            }
        }
    }
}

