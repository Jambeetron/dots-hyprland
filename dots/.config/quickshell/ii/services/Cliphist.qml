pragma Singleton
pragma ComponentBehavior: Bound

import qs.modules.common
import qs.modules.common.functions
import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root
    // property string cliphistBinary: FileUtils.trimFileProtocol(`${Directories.home}/.cargo/bin/stash`)
    property string cliphistBinary: "cliphist"
    property real pasteDelay: 0.05
    property string pressPasteCommand: "ydotool key -d 1 29:1 47:1 47:0 29:0"
    property bool sloppySearch: Config.options?.search.sloppy ?? false
    property real scoreThreshold: 0.2
    property list<string> entries: []
    readonly property var preparedEntries: entries.map(a => ({
        name: Fuzzy.prepare(`${a.replace(/^\s*\S+\s+/, "")}`),
        entry: a
    }))
    function fuzzyQuery(search: string): var {
        if (search.trim() === "") {
            return entries;
        }
        if (root.sloppySearch) {
            const results = entries.slice(0, 100).map(str => ({
                entry: str,
                score: Levendist.computeTextMatchScore(str.toLowerCase(), search.toLowerCase())
            })).filter(item => item.score > root.scoreThreshold)
                .sort((a, b) => b.score - a.score)
            return results
                .map(item => item.entry)
        }

        return Fuzzy.go(search, preparedEntries, {
            all: true,
            key: "name"
        }).map(r => {
            return r.obj.entry
        });
    }

    // ---------- Starred entries ----------
    // Keyed by the entry content (without the cliphist id) so a star survives re-copying.
    property string starredFilePath: FileUtils.trimFileProtocol(`${Directories.state}/user/cliphist_starred.json`)
    property list<string> starred: []
    property bool starredOnly: false
    readonly property bool hasStarred: root.starred.length > 0 && root.entries.some(e => root.starred.includes(root.entryKey(e)))
    onHasStarredChanged: if (!root.hasStarred) root.starredOnly = false

    function entryKey(entry) {
        return entry.replace(/^\s*\d+\t/, "");
    }
    function isStarred(entry) {
        return root.starred.includes(root.entryKey(entry));
    }
    function toggleStar(entry) {
        const key = root.entryKey(entry);
        if (root.starred.includes(key))
            root.starred = root.starred.filter(k => k !== key);
        else
            root.starred = [...root.starred, key];
        starredFileView.setText(JSON.stringify(root.starred));
    }
    function unstar(entry) {
        if (root.isStarred(entry)) root.toggleStar(entry);
    }

    FileView {
        id: starredFileView
        path: Qt.resolvedUrl(root.starredFilePath)
        onLoaded: {
            try {
                root.starred = JSON.parse(starredFileView.text());
            } catch (e) {
                console.error("[Cliphist] Bad starred file:", e);
            }
        }
        onLoadFailed: error => {
            if (error == FileViewError.FileNotFound) starredFileView.setText("[]");
        }
    }

    // ---------- Extra actions ----------
    // Invoke: open URLs / paths / images with the default app, otherwise web-search the text
    function invoke(entry) {
        Quickshell.execDetached([FileUtils.trimFileProtocol(`${Directories.scriptPath}/cliphist/invoke.sh`), entry, root.cliphistBinary, Config.options.search.engineBaseUrl]);
    }

    // Edit: open the full text in nvim (kitty); if it changed, the entry is replaced (keeping its star)
    function edit(entry) {
        if (editProc.running) return;
        editProc.wasStarred = root.isStarred(entry);
        editProc.newTop = "";
        editProc.oldEntry = entry;
        editProc.command = [FileUtils.trimFileProtocol(`${Directories.scriptPath}/cliphist/edit.sh`), entry, root.cliphistBinary];
        editProc.running = true;
    }

    Process {
        id: editProc
        property bool wasStarred: false
        property string oldEntry: ""
        property string newTop: ""
        stdout: SplitParser {
            onRead: line => editProc.newTop = line
        }
        onExited: (exitCode, exitStatus) => {
            if (editProc.wasStarred && editProc.newTop.length > 0) {
                root.unstar(editProc.oldEntry);
                if (!root.isStarred(editProc.newTop)) root.toggleStar(editProc.newTop);
            }
            root.refresh();
        }
    }

    function entryIsImage(entry) {
        return !!(/^\d+\t\[\[.*binary data.*\d+x\d+.*\]\]$/.test(entry))
    }

    function refresh() {
        readProc.buffer = []
        readProc.running = true
    }

    function copy(entry) {
        if (root.cliphistBinary.includes("cliphist")) // Classic cliphist
            Quickshell.execDetached(["bash", "-c", `printf '${StringUtils.shellSingleQuoteEscape(entry)}' | ${root.cliphistBinary} decode | wl-copy`]);
        else { // Stash
            const entryNumber = entry.split("\t")[0];
            Quickshell.execDetached(["bash", "-c", `${root.cliphistBinary} decode ${entryNumber} | wl-copy`]);
        }
    }

    function paste(entry) {
        if (root.cliphistBinary.includes("cliphist")) // Classic cliphist
            Quickshell.execDetached(["bash", "-c", `printf '${StringUtils.shellSingleQuoteEscape(entry)}' | ${root.cliphistBinary} decode | wl-copy && wl-paste`]);
        else { // Stash
            const entryNumber = entry.split("\t")[0];
            Quickshell.execDetached(["bash", "-c", `${root.cliphistBinary} decode ${entryNumber} | wl-copy; ${root.pressPasteCommand}`]);
        }
    }

    function superpaste(count, isImage = false) {
        // Find entries
        const targetEntries = entries.filter(entry => {
            if (!isImage) return true;
            return entryIsImage(entry);
        }).slice(0, count)
        const pasteCommands = [...targetEntries].reverse().map(entry => `printf '${StringUtils.shellSingleQuoteEscape(entry)}' | ${root.cliphistBinary} decode | wl-copy && sleep ${root.pasteDelay} && ${root.pressPasteCommand}`)
        // Act
        Quickshell.execDetached(["bash", "-c", pasteCommands.join(` && sleep ${root.pasteDelay} && `)]);
    }

    Process {
        id: deleteProc
        property string entry: ""
        command: ["bash", "-c", `echo '${StringUtils.shellSingleQuoteEscape(deleteProc.entry)}' | ${root.cliphistBinary} delete`]
        function deleteEntry(entry) {
            deleteProc.entry = entry;
            deleteProc.running = true;
            deleteProc.entry = "";
        }
        onExited: (exitCode, exitStatus) => {
            root.refresh();
        }
    }

    function deleteEntry(entry) {
        root.unstar(entry);
        deleteProc.deleteEntry(entry);
    }

    Process {
        id: wipeProc
        command: [root.cliphistBinary, "wipe"]
        onExited: (exitCode, exitStatus) => {
            root.refresh();
        }
    }

    Process {
        id: wipeKeepStarredProc
        onExited: (exitCode, exitStatus) => {
            root.refresh();
        }
    }

    // Clears history but keeps starred entries
    function wipe() {
        if (!root.hasStarred) {
            wipeProc.running = true;
            return;
        }
        const toDelete = root.entries.filter(e => !root.isStarred(e));
        wipeKeepStarredProc.command = ["bash", "-c", `bin="$1"; shift; for e in "$@"; do printf '%s\\n' "$e" | "$bin" delete; done`, "bash", root.cliphistBinary, ...toDelete];
        wipeKeepStarredProc.running = true;
    }

    Connections {
        target: Quickshell
        function onClipboardTextChanged() {
            delayedUpdateTimer.restart()
        }
    }

    Timer {
        id: delayedUpdateTimer
        interval: Config.options.hacks.arbitraryRaceConditionDelay
        repeat: false
        onTriggered: {
            root.refresh()
        }
    }

    Process {
        id: readProc
        property list<string> buffer: []

        command: [root.cliphistBinary, "list"]

        stdout: SplitParser {
            onRead: (line) => {
                readProc.buffer.push(line)
            }
        }

        onExited: (exitCode, exitStatus) => {
            if (exitCode === 0) {
                root.entries = readProc.buffer
            } else {
                console.error("[Cliphist] Failed to refresh with code", exitCode, "and status", exitStatus)
            }
        }
    }

    IpcHandler {
        target: "cliphistService"

        function update(): void {
            root.refresh()
        }
    }
}
