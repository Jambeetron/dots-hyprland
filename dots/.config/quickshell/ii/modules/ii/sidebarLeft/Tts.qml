import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.modules.ii.sidebarLeft.translator
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io

/**
 * Text to speech: reads the written text aloud, without translating it.
 * Uses the same voices as the translator (scripts/translator/tts.py) and shares its voice settings.
 */
Item {
    id: root

    property real padding: 4
    property var inputField: inputCanvas.inputTextArea
    property list<string> languages: []

    // Options (voice engine and speed are shared with the translator)
    property string language: Config.options.language.tts?.language ?? "auto"
    readonly property string voiceSpeed: Config.options.language.translator.voiceSpeed ?? "normal"
    readonly property string voiceEngine: Config.options.language.translator.voiceEngine ?? "xtts"
    readonly property var speedOptions: [Translation.tr("Normal"), Translation.tr("Slow"), Translation.tr("Slower")]
    readonly property var speedKeys: ["normal", "slow", "slower"]
    readonly property var voiceOptions: [
        Translation.tr("Google — online voice"),
        Translation.tr("Google Cloud TTS — online, many voices (needs API key)"),
        Translation.tr("ElevenLabs — online, natural voice (needs API key)"),
        Translation.tr("XTTS-v2 — local on your GPU (17 languages)"),
    ]
    readonly property var voiceKeys: ["google", "googlecloud", "elevenlabs", "xtts"]
    readonly property var voiceLabels: ({ "google": "Google", "googlecloud": "Google Cloud", "xtts": "XTTS-v2", "elevenlabs": "ElevenLabs" })
    // "XTTS-v2 / Normal", shown on the settings button
    readonly property string settingsSummary: `${root.voiceLabels[root.voiceEngine] ?? root.voiceEngine} / ${root.speedOptions[Math.max(0, root.speedKeys.indexOf(root.voiceSpeed))]}`
    readonly property bool hasElevenLabsKey: (Ai.apiKeys?.elevenlabs ?? "").length > 0
    readonly property bool hasGoogleCloudKey: (Ai.apiKeys?.googlecloud ?? "").length > 0
    property string googleCloudKeyTyped: "" // Key typed in Settings before opening the Google Cloud voice dialog
    // "Female · Neural2", next to Google Cloud TTS in Settings
    readonly property string googleCloudSummary: `${(Config.options.language.translator.googleCloudGender ?? "female") === "male" ? Translation.tr("Male") : Translation.tr("Female")} · ${
        ({ chirp3hd: "Chirp 3 HD", neural2: "Neural2", wavenet: "WaveNet", standard: "Standard" })[Config.options.language.translator.googleCloudTier ?? "neural2"] ?? "Neural2"}`
    property string settingsVoice: ""
    property var elevenVoices: []
    property string elevenVoicesError: ""
    property bool elevenVoicesLoading: false
    readonly property var elevenVoiceLabels: root.elevenVoices.map(v => v.label)

    // States
    property string activeDialog: "" // "", "speed" (Settings), "elevenVoice" or "googleVoice"
    property bool showVoiceStats: false // Whisper accuracy table of the XTTS-v2 voices
    property bool showLanguageSelector: false
    property string speakingSource: "" // "input", "test" or "" when idle
    property string ttsError: ""
    property string voiceState: "" // Dictation: "", "recording" or "transcribing"
    readonly property string voiceStopFile: FileUtils.trimFileProtocol(`${Directories.cache}/tts-stt.stop`)
    readonly property string scriptDir: `${FileUtils.trimFileProtocol(Directories.scriptPath)}/translator`

    readonly property string voiceFootnote: {
        const entry = (root.offlineRevision, root.offlineEntryFor("xtts"));
        const busy = root.offlineBusy["xtts"];
        const license = Translation.tr("License: Coqui Public Model License, for personal use (non-commercial).");
        if (busy === "downloading" || busy === "queued") {
            const progress = root.offlineProgress["xtts"];
            return Translation.tr("Downloading the local voice (XTTS-v2)... %1").arg(progress ? root.formatProgress(progress.done, progress.total) : "")
                + "\n" + license;
        }
        if (root.settingsVoice === "elevenlabs")
            return Translation.tr("ElevenLabs uses your account's credits (1 per character; 10,000 free per month). Listening and saving as MP3 each use them, so saving a text you already listened to costs again. Get a key at elevenlabs.io → Developers → API keys.");
        if (root.settingsVoice === "googlecloud")
            return Translation.tr("Google Cloud Text-to-Speech: many male and female voices per language. Needs a Google Cloud project with the Text-to-Speech API and billing enabled (it has a free monthly quota). Get a key at console.cloud.google.com → APIs & Services → Credentials.");
        if (root.settingsVoice === "google")
            return Translation.tr("Google Translate's voice, online.");
        if (entry?.installed)
            return Translation.tr("With XTTS-v2, languages it doesn't speak use Google's voice.") + "\n" + license;
        return Translation.tr("XTTS-v2 needs a download (~%1); until then Google's voice is used.")
            .arg(root.formatBytes(entry?.size ?? 1.88e9)) + "\n" + license;
    }

    onFocusChanged: focus => {
        if (focus) root.inputField.forceActiveFocus();
    }

    function formatProgress(done, total) {
        const gb = total >= 1e9;
        const unit = gb ? 1e9 : 1e6;
        const fmt = v => (v / unit).toFixed(gb || v / unit < 10 ? 1 : 0);
        return `${fmt(done)} / ${fmt(total)} ${gb ? "GB" : "MB"}`;
    }
    function formatBytes(bytes) {
        if (!bytes) return "?";
        return bytes >= 1e9 ? `${(bytes / 1e9).toFixed(1)} GB` : `${Math.round(bytes / 1e6)} MB`;
    }

    // ---- Speaking ----
    function saveElevenLabsKey(key) {
        key = (key ?? "").trim();
        if (key.length > 0 && key !== Ai.apiKeys?.elevenlabs)
            KeyringStorage.setNestedField(["apiKeys", "elevenlabs"], key);
    }

    // Saves the key typed in Settings for the voice that needs one (ElevenLabs or Google Cloud)
    function saveVoiceKey(engine, key) {
        if (engine === "elevenlabs") root.saveElevenLabsKey(key);
        key = (key ?? "").trim();
        if (engine === "googlecloud" && key.length > 0 && key !== Ai.apiKeys?.googlecloud)
            KeyringStorage.setNestedField(["apiKeys", "googlecloud"], key);
    }

    function ttsEnvironment() {
        return ({
            "ELEVENLABS_API_KEY": Ai.apiKeys?.elevenlabs ?? "",
            "ELEVENLABS_VOICE_ID": Config.options.language.translator.elevenLabsVoice ?? "",
            "XTTS_VOICES": VoiceData.effectiveVoicesJson, // Voice of every language: chosen or #1 female (xtts.py)
            "GOOGLE_TTS_API_KEY": Ai.apiKeys?.googlecloud ?? "", // Google Cloud TTS (googlecloud.py)
            "GOOGLE_TTS_GENDER": Config.options.language.translator.googleCloudGender ?? "female",
            "GOOGLE_TTS_TIER": Config.options.language.translator.googleCloudTier ?? "neural2",
            "GOOGLE_TTS_VOICES": Config.options.language.translator.googleCloudVoices ?? "{}",
        });
    }

    function speak(source, language, text, speed, engine) {
        ttsProc.running = false;
        if ((engine === "elevenlabs" || engine === "googlecloud") && !KeyringStorage.loaded) KeyringStorage.fetchKeyringData();
        ttsProc.environment = root.ttsEnvironment();
        ttsProc.command = ["python3", `${root.scriptDir}/tts.py`, language, text, speed, engine];
        root.speakingSource = source;
        ttsProc.running = true;
    }

    function toggleSpeak() {
        const wasSpeaking = root.speakingSource === "input";
        ttsProc.running = false;
        root.speakingSource = "";
        const text = root.inputField.text.trim();
        if (wasSpeaking || text.length === 0) return;
        root.speak("input", root.language, text, root.voiceSpeed, root.voiceEngine);
    }

    function openElevenLabsVoices(key) {
        root.saveElevenLabsKey(key);
        root.elevenVoicesError = "";
        root.elevenVoicesLoading = true;
        elevenVoicesProc.running = false;
        elevenVoicesProc.buffer = "";
        elevenVoicesProc.environment = ({ "ELEVENLABS_API_KEY": (key ?? "").trim() || (Ai.apiKeys?.elevenlabs ?? "") });
        elevenVoicesProc.running = true;
        root.activeDialog = "elevenVoice";
    }

    // ---- Save the recording as MP3 in a chosen folder ----
    property bool saving: false

    function toggleSave() {
        if (root.saving) { // Cancel (the script removes the partial file)
            saveProc.running = false;
            folderPickerProc.running = false;
            root.saving = false;
            return;
        }
        if (root.inputField.text.trim().length === 0) return;
        const start = Config.options.language.tts?.saveFolder || FileUtils.trimFileProtocol(Directories.music) || FileUtils.trimFileProtocol(Directories.home);
        folderPickerProc.buffer = "";
        // "Save as" dialog: choose (or create) the folder and the file name
        const suggested = `${start}/tts-${Qt.formatDateTime(new Date(), "yyyyMMdd-HHmmss")}.mp3`;
        folderPickerProc.command = ["kdialog", "--title", Translation.tr("Save the recording"), "--getsavefilename", suggested, "*.mp3|MP3 audio"];
        root.saving = true;
        folderPickerProc.running = true;
    }

    Process {
        id: folderPickerProc
        property string buffer: ""
        stdout: SplitParser {
            onRead: data => folderPickerProc.buffer += data
        }
        onExited: (exitCode, exitStatus) => {
            let file = folderPickerProc.buffer.trim();
            if (exitCode !== 0 || file.length === 0 || !root.saving) { // Canceled
                root.saving = false;
                return;
            }
            if (!/\.mp3$/i.test(file)) file += ".mp3";
            Config.options.language.tts.saveFolder = file.slice(0, file.lastIndexOf("/")) || "/";
            if ((root.voiceEngine === "elevenlabs" || root.voiceEngine === "googlecloud") && !KeyringStorage.loaded) KeyringStorage.fetchKeyringData();
            saveProc.environment = root.ttsEnvironment();
            saveProc.command = ["python3", `${root.scriptDir}/tts.py`, root.language, root.inputField.text.trim(),
                root.voiceSpeed, root.voiceEngine, "--save", file];
            saveProc.running = true;
        }
    }

    Process {
        id: saveProc
        property string errorText: ""
        property string savedPath: ""
        stdout: SplitParser {
            onRead: line => { if (line.trim().length > 0) saveProc.savedPath = line.trim(); }
        }
        stderr: SplitParser {
            onRead: line => { if (line.trim().length > 0) saveProc.errorText = line.trim(); }
        }
        onRunningChanged: if (running) { saveProc.errorText = ""; saveProc.savedPath = ""; root.ttsError = ""; }
        onExited: (exitCode, exitStatus) => {
            if (!root.saving) return; // Canceled
            root.saving = false;
            if (exitCode === 0 && saveProc.savedPath.length > 0)
                Quickshell.execDetached(["notify-send", "-a", "TTS", "-i", "audio-x-generic", Translation.tr("Recording saved"), saveProc.savedPath]);
            else
                root.ttsError = saveProc.errorText.length > 0 ? saveProc.errorText : Translation.tr("Couldn't save the recording");
        }
    }

    // ---- Dictation (speech to text into the box) ----
    function toggleVoiceInput() {
        if (root.voiceState === "recording") {
            root.voiceState = "transcribing";
            Quickshell.execDetached(["touch", root.voiceStopFile]);
        } else if (root.voiceState === "") {
            ttsProc.running = false;
            root.speakingSource = "";
            sttProc.buffer = "";
            sttProc.command = ["bash", "-c", 'exec "$HOME/.local/share/quickshell-ii/stt-venv/bin/python" "$@"', "stt",
                `${root.scriptDir}/stt.py`, root.language, root.voiceStopFile];
            root.voiceState = "recording";
            sttProc.running = true;
        }
    }

    Process {
        id: sttProc
        property string buffer: ""
        stdout: SplitParser {
            onRead: data => sttProc.buffer += data + "\n"
        }
        onExited: (exitCode, exitStatus) => {
            root.voiceState = "";
            const text = sttProc.buffer.trim();
            if (text.length > 0) root.inputField.text = text;
        }
    }

    Process {
        id: ttsProc
        property string errorText: ""
        stderr: SplitParser {
            onRead: line => { if (line.trim().length > 0) ttsProc.errorText = line.trim(); }
        }
        onRunningChanged: if (running) { ttsProc.errorText = ""; root.ttsError = ""; }
        onExited: (exitCode, exitStatus) => {
            if (exitCode !== 0 && exitStatus === Process.NormalExit && ttsProc.errorText.length > 0)
                root.ttsError = ttsProc.errorText;
            if (!ttsProc.running) root.speakingSource = "";
        }
    }

    Process {
        id: elevenVoicesProc
        property string buffer: ""
        command: ["python3", `${root.scriptDir}/tts.py`, "voices"]
        stdout: SplitParser {
            onRead: data => elevenVoicesProc.buffer += data
        }
        onExited: {
            root.elevenVoicesLoading = false;
            try {
                const result = JSON.parse(elevenVoicesProc.buffer);
                root.elevenVoicesError = result.error ?? "";
                if (result.voices) root.elevenVoices = result.voices;
            } catch (e) {
                root.elevenVoicesError = Translation.tr("Couldn't load the voices");
            }
        }
    }

    Process {
        id: getLanguagesProc
        command: ["trans", "-list-languages", "-no-bidi"]
        property list<string> bufferList: []
        running: true
        stdout: SplitParser {
            onRead: data => getLanguagesProc.bufferList.push(data.trim())
        }
        onExited: (exitCode, exitStatus) => {
            let langs = getLanguagesProc.bufferList
                .filter(lang => lang.trim().length > 0 && lang !== "auto")
                .sort((a, b) => a.localeCompare(b));
            langs.unshift("auto");
            root.languages = langs;
            getLanguagesProc.bufferList = [];
        }
    }

    // ---- Local voice XTTS-v2: download / remove (same offline.py as the translator) ----
    readonly property string venvPython: "$HOME/.local/share/quickshell-ii/stt-venv/bin/python"
    readonly property string offlineScript: `${root.scriptDir}/offline.py`
    property var offlineLanguages: []
    property var offlineBusy: ({})
    property int offlineRevision: 0
    property var offlineProgress: ({})

    function offlineEntryFor(name) {
        return root.offlineLanguages.find(l => l.code === name || l.name === name || (l.names ?? []).includes(name)) ?? null;
    }

    function setOfflineBusy(code, state) {
        const busy = Object.assign({}, root.offlineBusy);
        if (state) busy[code] = state; else delete busy[code];
        root.offlineBusy = busy;
        root.offlineRevision++;
    }

    function refreshOffline() {
        if (offlineListProc.running) return;
        offlineListProc.buffer = "";
        offlineListProc.command = ["bash", "-c", `exec "${root.venvPython}" "$@"`, "offline", root.offlineScript, "list"];
        offlineListProc.running = true;
    }

    function runOffline(cmd) {
        if (offlineOpProc.running) return;
        root.setOfflineBusy("xtts", cmd === "remove" ? "removing" : "downloading");
        offlineOpProc.command = ["bash", "-c", `exec "${root.venvPython}" "$@"`, "offline", root.offlineScript, cmd, "xtts"];
        offlineOpProc.running = true;
    }

    function xttsAction() {
        const entry = root.offlineEntryFor("xtts");
        if (!entry || !entry.available) return;
        const busy = root.offlineBusy["xtts"];
        if (busy === "downloading") { offlineOpProc.running = false; return; }
        if (busy && busy !== "confirmRemove") return;
        if (!entry.installed) root.runOffline("install");
        else if (busy === "confirmRemove") root.runOffline("remove");
        else { root.setOfflineBusy("xtts", "confirmRemove"); confirmRemoveTimer.restart(); }
    }

    function xttsActionInfo() {
        const entry = root.offlineEntryFor("xtts");
        if (!entry || !entry.available) return null;
        const busy = root.offlineBusy["xtts"];
        if (busy === "installing")
            return { icon: "downloading", text: Translation.tr("Installing..."), tooltip: Translation.tr("Installing..."), busy: true };
        if (busy === "downloading") {
            const progress = root.offlineProgress["xtts"];
            const percent = progress && progress.total > 0 ? Math.floor(progress.done * 100 / progress.total) : -1;
            return { icon: "cancel", text: progress ? root.formatProgress(progress.done, progress.total) : "…",
                tooltip: (percent >= 0 ? Translation.tr("Downloading... %1%").arg(percent) : Translation.tr("Downloading..."))
                    + "\n" + Translation.tr("Click to cancel") };
        }
        if (busy === "removing")
            return { icon: "hourglass_top", tooltip: Translation.tr("Removing..."), busy: true };
        if (busy === "confirmRemove")
            return { icon: "delete", text: Translation.tr("Remove?"), tooltip: Translation.tr("Click again to remove") };
        if (entry.installed)
            return { icon: "download_done", highlight: false,
                tooltip: Translation.tr("Local voice downloaded (%1). Click to remove").arg(root.formatBytes(entry.size)) };
        return { icon: "download", tooltip: Translation.tr("Download the local voice XTTS-v2 (~%1)").arg(root.formatBytes(entry.size)) };
    }

    Timer {
        id: confirmRemoveTimer
        interval: 3000
        onTriggered: if (root.offlineBusy["xtts"] === "confirmRemove") root.setOfflineBusy("xtts", null)
    }

    Process {
        id: offlineListProc
        property string buffer: ""
        stdout: SplitParser {
            onRead: data => offlineListProc.buffer += data + "\n"
        }
        onExited: (exitCode, exitStatus) => {
            try {
                const result = JSON.parse(offlineListProc.buffer.trim().split("\n").pop());
                if (result.languages) {
                    root.offlineLanguages = result.languages;
                    root.offlineRevision++;
                }
            } catch (e) {}
        }
    }

    Process {
        id: offlineOpProc
        stdout: SplitParser {
            onRead: data => {
                let msg;
                try { msg = JSON.parse(data); } catch (e) { return; }
                if (msg.status === "progress") {
                    root.offlineProgress = ({ "xtts": { done: msg.done, total: msg.total } });
                    if (root.offlineBusy["xtts"] !== "downloading") root.setOfflineBusy("xtts", "downloading");
                    else root.offlineRevision++;
                }
                if (msg.status === "installing" || msg.status === "indexing") root.setOfflineBusy("xtts", "installing");
                if (msg.status === "error") root.ttsError = msg.error ?? Translation.tr("Offline language operation failed");
            }
        }
        onExited: (exitCode, exitStatus) => {
            root.offlineProgress = ({});
            root.setOfflineBusy("xtts", null);
            root.refreshOffline();
        }
    }

    Component.onCompleted: root.refreshOffline()

    // ---- Layout ----
    ColumnLayout {
        anchors {
            fill: parent
            margins: root.padding
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: 6

            LanguageSelectorButton { // Reading language
                id: languageButton
                displayText: root.language
                onClicked: root.showLanguageSelector = true
                StyledToolTip {
                    text: Translation.tr("Language of the text (auto detects it)")
                }
            }

            Item { Layout.fillWidth: true }

            GroupButton { // Dictate
                id: dictateButton
                Layout.alignment: Qt.AlignVCenter
                baseWidth: height
                buttonRadius: Appearance.rounding.small
                enabled: root.voiceState !== "transcribing"
                contentItem: MaterialSymbol {
                    anchors.centerIn: parent
                    horizontalAlignment: Text.AlignHCenter
                    iconSize: Appearance.font.pixelSize.larger
                    text: root.voiceState === "recording" ? "stop_circle" : root.voiceState === "transcribing" ? "hourglass_top" : "mic"
                    color: root.voiceState === "recording" ? Appearance.m3colors.m3error
                        : dictateButton.enabled ? Appearance.colors.colOnLayer1 : Appearance.colors.colSubtext
                }
                StyledToolTip {
                    text: root.voiceState === "recording" ? Translation.tr("Stop recording")
                        : root.voiceState === "transcribing" ? Translation.tr("Transcribing...")
                        : Translation.tr("Dictate")
                }
                onClicked: root.toggleVoiceInput()
            }

            LanguageSelectorButton { // Settings: current voice / speed
                id: settingsButton
                displayText: root.settingsSummary
                onClicked: root.activeDialog = "speed"
                StyledToolTip {
                    text: Translation.tr("Settings: voice and speed")
                }
            }
        }

        TextCanvas { // Text to read
            id: inputCanvas
            Layout.fillHeight: true
            implicitHeight: 150
            maxInputHeight: 100000 // Use all the tab's height, scroll beyond it
            isInput: true
            placeholderText: Translation.tr("Enter text to read aloud...\nCtrl+Enter to listen")
            keyHandler: event => {
                if ((event.key === Qt.Key_Return || event.key === Qt.Key_Enter) && (event.modifiers & Qt.ControlModifier)) {
                    root.toggleSpeak();
                    event.accepted = true;
                }
            }
            GroupButton {
                id: saveButton
                baseWidth: height
                buttonRadius: Appearance.rounding.small
                enabled: root.saving || inputCanvas.inputTextArea.text.trim().length > 0
                contentItem: MaterialSymbol {
                    anchors.centerIn: parent
                    horizontalAlignment: Text.AlignHCenter
                    iconSize: Appearance.font.pixelSize.larger
                    text: root.saving ? "hourglass_top" : "download"
                    color: saveButton.enabled ? Appearance.colors.colOnLayer1 : Appearance.colors.colSubtext
                }
                StyledToolTip {
                    text: root.saving ? Translation.tr("Saving the recording... Click to cancel")
                        : Translation.tr("Save as audio (MP3)")
                }
                onClicked: root.toggleSave()
            }
            GroupButton {
                id: listenButton
                baseWidth: height
                buttonRadius: Appearance.rounding.small
                enabled: inputCanvas.inputTextArea.text.trim().length > 0
                contentItem: MaterialSymbol {
                    anchors.centerIn: parent
                    horizontalAlignment: Text.AlignHCenter
                    iconSize: Appearance.font.pixelSize.larger
                    text: root.speakingSource === "input" ? "stop" : "volume_up"
                    color: listenButton.enabled ? Appearance.colors.colOnLayer1 : Appearance.colors.colSubtext
                }
                StyledToolTip {
                    text: root.speakingSource === "input" ? Translation.tr("Stop") : Translation.tr("Listen")
                }
                onClicked: root.toggleSpeak()
            }
            GroupButton {
                id: pasteButton
                baseWidth: height
                buttonRadius: Appearance.rounding.small
                contentItem: MaterialSymbol {
                    anchors.centerIn: parent
                    horizontalAlignment: Text.AlignHCenter
                    iconSize: Appearance.font.pixelSize.larger
                    text: "content_paste"
                    color: Appearance.colors.colOnLayer1
                }
                StyledToolTip {
                    text: Translation.tr("Paste from clipboard")
                }
                onClicked: root.inputField.text = Quickshell.clipboardText
            }
            GroupButton {
                id: deleteButton
                baseWidth: height
                buttonRadius: Appearance.rounding.small
                enabled: inputCanvas.inputTextArea.text.length > 0
                contentItem: MaterialSymbol {
                    anchors.centerIn: parent
                    horizontalAlignment: Text.AlignHCenter
                    iconSize: Appearance.font.pixelSize.larger
                    text: "close"
                    color: deleteButton.enabled ? Appearance.colors.colOnLayer1 : Appearance.colors.colSubtext
                }
                StyledToolTip {
                    text: Translation.tr("Clear text")
                }
                onClicked: root.inputField.text = ""
            }
        }

        StyledText { // Why the last Listen failed
            Layout.fillWidth: true
            Layout.margins: 6
            visible: root.ttsError.length > 0
            text: root.ttsError
            wrapMode: Text.Wrap
            color: Appearance.m3colors.m3error
            font.pixelSize: Appearance.font.pixelSize.smaller
        }
    }

    Loader { // Settings: voice + speed
        id: settingsDialogLoader
        anchors.fill: parent
        active: root.activeDialog === "speed"
        visible: active
        z: 9999
        sourceComponent: SelectionDialog {
            id: optionsDialog
            searchable: false
            menuMode: true // Voice / Speed as submenus
            titleText: Translation.tr("Settings")
            items: root.speedOptions
            defaultChoice: root.speedOptions[Math.max(0, root.speedKeys.indexOf(root.voiceSpeed))]
            itemActionText: Translation.tr("Test")
            itemActionIcon: "volume_up"
            footnote: (root.ttsError.length > 0 ? root.ttsError + "\n" : "") + root.voiceFootnote
            groupTitle: Translation.tr("Voice")
            groupItems: root.voiceOptions
            groupDefaultChoice: root.voiceOptions[Math.max(0, root.voiceKeys.indexOf(root.voiceEngine))]
            groupItemActionProvider: item => {
                const key = root.voiceKeys[root.voiceOptions.indexOf(item)];
                if (key === "xtts") return root.xttsActionInfo();
                if (key === "googlecloud") return {
                    icon: "record_voice_over", highlight: true,
                    text: root.googleCloudSummary,
                    tooltip: Translation.tr("Choose the Google Cloud voice"),
                };
                if (key === "elevenlabs") return {
                    icon: "record_voice_over", highlight: true,
                    text: Config.options.language.translator.elevenLabsVoiceName ?? "Sarah",
                    tooltip: Translation.tr("Choose the ElevenLabs voice"),
                };
                return null;
            }
            groupItemInfoProvider: item => { // Next to the downloaded local voice: its voice for the system language; opens "Choose"
                const entry = root.offlineEntryFor("xtts");
                if (root.voiceKeys[root.voiceOptions.indexOf(item)] !== "xtts" || !entry?.installed || root.offlineBusy["xtts"]) return null;
                return { icon: "record_voice_over", highlight: true, text: VoiceData.chosenVoice(VoiceData.systemLanguage),
                    tooltip: Translation.tr("Choose the XTTS-v2 voice per language") };
            }
            onGroupItemInfo: root.showVoiceStats = true
            onGroupSelectedValueChanged: {
                root.settingsVoice = root.voiceKeys[root.voiceOptions.indexOf(groupSelectedValue)] ?? "";
                groupFieldText = ""; // A key typed for one voice isn't the other's
            }
            Component.onCompleted: {
                root.settingsVoice = root.voiceKeys[root.voiceOptions.indexOf(groupSelectedValue)] ?? "";
                if (!KeyringStorage.loaded) KeyringStorage.fetchKeyringData();
            }
            groupFieldVisible: root.settingsVoice === "elevenlabs" || root.settingsVoice === "googlecloud"
            groupFieldPlaceholder: (root.settingsVoice === "googlecloud" ? root.hasGoogleCloudKey : root.hasElevenLabsKey)
                ? Translation.tr("API key saved (paste a new one to replace it)")
                : root.settingsVoice === "googlecloud" ? Translation.tr("Google Cloud API key") : Translation.tr("ElevenLabs API key")
            onGroupItemAction: item => {
                if (root.voiceKeys[root.voiceOptions.indexOf(item)] === "xtts") {
                    root.xttsAction();
                    return;
                }
                if (root.voiceKeys[root.voiceOptions.indexOf(item)] === "googlecloud") {
                    // Keep what's chosen here, then open the Google Cloud voice dialog (it comes back to Settings)
                    root.saveVoiceKey("googlecloud", optionsDialog.groupFieldText);
                    root.googleCloudKeyTyped = optionsDialog.groupFieldText.trim();
                    Config.options.language.translator.voiceEngine = "googlecloud";
                    Config.options.language.translator.voiceSpeed = root.speedKeys[root.speedOptions.indexOf(optionsDialog.selectedValue)] ?? "normal";
                    root.activeDialog = "googleVoice";
                    return;
                }
                Config.options.language.translator.voiceEngine = "elevenlabs";
                Config.options.language.translator.voiceSpeed = root.speedKeys[root.speedOptions.indexOf(optionsDialog.selectedValue)] ?? "normal";
                root.openElevenLabsVoices(optionsDialog.groupFieldText);
            }
            listTitle: Translation.tr("Speed")
            itemActionRevision: root.offlineRevision
            onItemAction: item => {
                const speed = root.speedKeys[root.speedOptions.indexOf(item)] ?? "normal";
                const hasText = root.inputField.text.trim().length > 0;
                const engine = root.voiceKeys[root.voiceOptions.indexOf(optionsDialog.groupSelectedValue)] ?? "xtts";
                root.saveVoiceKey(engine, optionsDialog.groupFieldText);
                root.speak("test", hasText ? root.language : "English", hasText ? root.inputField.text.trim() : "Hello, this is a test", speed, engine);
            }
            onCanceled: root.activeDialog = ""
            onSelected: result => {
                root.activeDialog = "";
                if (!result) return;
                Config.options.language.translator.voiceSpeed = root.speedKeys[root.speedOptions.indexOf(result)] ?? "normal";
                Config.options.language.translator.voiceEngine = root.voiceKeys[root.voiceOptions.indexOf(optionsDialog.groupSelectedValue)] ?? "xtts";
                root.saveVoiceKey(root.voiceKeys[root.voiceOptions.indexOf(optionsDialog.groupSelectedValue)] ?? "", optionsDialog.groupFieldText);
            }
        }
    }

    Loader { // XTTS-v2 voices: Whisper accuracy (opened from Settings, on top of it)
        anchors.fill: parent
        active: root.showVoiceStats
        visible: active
        z: 10000
        sourceComponent: VoiceStatsDialog {
            onClosed: {
                root.showVoiceStats = false;
                settingsDialogLoader.item?.forceActiveFocus();
            }
        }
    }

    Loader { // Google Cloud TTS voice: gender + quality, or one per language (opened from Settings)
        anchors.fill: parent
        active: root.activeDialog === "googleVoice"
        visible: active
        z: 9999
        sourceComponent: GoogleCloudVoiceDialog {
            apiKey: root.googleCloudKeyTyped || (Ai.apiKeys?.googlecloud ?? "")
            onClosed: {
                root.googleCloudKeyTyped = "";
                root.activeDialog = "speed";
            }
        }
    }

    Loader { // ElevenLabs voice picker (opened from Settings)
        anchors.fill: parent
        active: root.activeDialog === "elevenVoice"
        visible: active
        z: 9999
        sourceComponent: SelectionDialog {
            titleText: Translation.tr("ElevenLabs voice")
            items: root.elevenVoiceLabels
            defaultChoice: root.elevenVoices.find(v => v.id === Config.options.language.translator.elevenLabsVoice)?.label
            itemActionIcon: "volume_up"
            itemActionText: Translation.tr("Test")
            footnote: root.elevenVoicesLoading ? Translation.tr("Loading your voices...")
                : root.elevenVoicesError.length > 0 ? root.elevenVoicesError
                : Translation.tr("Voices of your ElevenLabs account (add more from its Voice Library, or clone yours there). Test plays its free sample, without using credits.")
            onItemAction: item => {
                const voice = root.elevenVoices.find(v => v.label === item);
                ttsProc.running = false;
                if (!voice?.preview) return;
                ttsProc.command = ["mpv", "--no-video", "--really-quiet", "--no-terminal", voice.preview];
                root.speakingSource = "test";
                ttsProc.running = true;
            }
            onCanceled: {
                ttsProc.running = false;
                root.activeDialog = "speed";
            }
            onSelected: result => {
                ttsProc.running = false;
                const voice = root.elevenVoices.find(v => v.label === result);
                if (voice) {
                    Config.options.language.translator.elevenLabsVoice = voice.id;
                    Config.options.language.translator.elevenLabsVoiceName = voice.name;
                }
                root.activeDialog = "speed";
            }
        }
    }

    Loader { // Language selector
        anchors.fill: parent
        active: root.showLanguageSelector
        visible: active
        z: 9999
        sourceComponent: SelectionDialog {
            titleText: Translation.tr("Select Language")
            items: root.languages
            defaultChoice: root.language
            onCanceled: root.showLanguageSelector = false
            onSelected: result => {
                root.showLanguageSelector = false;
                if (!result || result.length === 0) return;
                root.language = result;
                Config.options.language.tts.language = result;
            }
        }
    }
}
