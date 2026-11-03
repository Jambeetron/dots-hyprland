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
 * Translator widget with the `trans` commandline tool.
 */
Item {
    id: root

    // Sizes
    property real padding: 4

    // Widgets
    property var inputField: inputCanvas.inputTextArea

    // Widget variables
    property bool translationFor: false // Indicates if the translation is for an autocorrected text
    property string translatedText: ""
    property list<string> languages: []

    // Options
    property string targetLanguage: Config.options.language.translator.targetLanguage
    property string sourceLanguage: Config.options.language.translator.sourceLanguage
    property string hostLanguage: targetLanguage

    // Translation details (classic model)
    property var correction: null // {html, plain}: spelling suggestion from Google
    property bool autocorrect: true // false after "Translate instead"
    property string sourcePhonetic: ""
    property var dictionary: [] // [{pos, words: [{word, article, back: []}]}]
    property var genderTranslations: [] // [{gender, text}]
    property string lemma: ""
    property var definitions: [] // [{pos, items: [{text, example, labels, synonyms}]}]
    property var examples: [] // HTML strings with <b> around the word
    property var relatedWords: [] // "See also"
    property bool showDictionaryPanel: false
    property string detectedLanguage: ""
    property var sourceSuggestion: null // {code, name, names}: "Translate from: X"
    // Data shown in the "See dictionary" panel (current text or a word looked up from a translation)
    property var panel: ({ lemma: "", phonetic: "", lang: "", definitions: [], examples: [], dictionary: [], related: [], loading: false })
    readonly property bool panelHasContent: (panel.definitions?.length ?? 0) > 0 || (panel.examples?.length ?? 0) > 0
        || (panel.dictionary?.length ?? 0) > 0 || (panel.related?.length ?? 0) > 0

    // Move to the next (step = 1) or previous (step = -1) non-empty tab of the dictionary panel
    function switchDictionaryTab(step) {
        const available = [root.panel.definitions.length > 0, root.panel.examples.length > 0,
            root.panel.dictionary.length > 0, root.panel.related.length > 0];
        for (let i = root.dictionaryTab + step; i >= 0 && i < available.length; i += step) {
            if (available[i]) {
                root.dictionaryTab = i;
                return;
            }
        }
    }

    function openPanel(data) {
        root.panel = data;
        root.dictionaryTab = data.definitions.length > 0 ? 0 : data.examples.length > 0 ? 1 : data.dictionary.length > 0 ? 2 : 3;
        root.showDictionaryPanel = true;
    }

    function openSourceDictionary() {
        root.openPanel({ lemma: root.lemma, phonetic: root.sourcePhonetic, lang: root.sourceLanguage,
            definitions: root.definitions, examples: root.examples, dictionary: root.dictionary, related: root.relatedWords, loading: false });
    }

    // Look up a word of the target language (e.g. "adelantado") and show its dictionary
    function openTargetDictionary(word) {
        const backLanguage = root.sourceLanguage === "auto" ? (root.detectedLanguage || "en") : root.sourceLanguage;
        root.openPanel({ lemma: word, phonetic: "", lang: root.targetLanguage, definitions: [], examples: [], dictionary: [], related: [], loading: true });
        dictLookupProc.running = false;
        dictLookupProc.buffer = "";
        dictLookupProc.command = ["python3", `${FileUtils.trimFileProtocol(Directories.scriptPath)}/translator/translate.py`,
            "classic", root.targetLanguage, backLanguage, word];
        dictLookupProc.running = true;
    }

    // Translations already shown above (main / gender) are not repeated in "More translations"
    readonly property var shownTranslations: [root.translatedText, ...root.genderTranslations.map(g => g.text)]
        .map(t => (t ?? "").trim().toLowerCase())
    // Sorted by frequency across parts of speech, like Google Translate (not grouped by noun/verb)
    readonly property var moreTranslations: {
        const entries = [];
        for (const group of root.dictionary)
            for (const w of group.words)
                if (!root.shownTranslations.includes((w.word ?? "").toLowerCase()))
                    entries.push({ pos: group.pos, words: [w] });
        return entries.sort((a, b) => (b.words[0].score ?? 0) - (a.words[0].score ?? 0));
    }
    // Dictionary entry of the main translation (e.g. "avance": Noun, el, [advance, progress...])
    readonly property var mainTranslationEntry: {
        const t = root.translatedText.trim().toLowerCase();
        if (t.length === 0) return null;
        for (const group of root.dictionary)
            for (const w of group.words)
                if ((w.word ?? "").toLowerCase() === t) return { pos: group.pos, article: w.article, back: w.back ?? [] };
        return null;
    }
    readonly property string mainPos: root.capitalize(root.dictionary[0]?.pos ?? root.definitions[0]?.pos ?? "")

    Process {
        id: dictLookupProc
        property string buffer: ""
        stdout: SplitParser {
            onRead: data => dictLookupProc.buffer += data + "\n"
        }
        onExited: (exitCode, exitStatus) => {
            if (dictLookupProc.running) return;
            let result = {};
            try { result = JSON.parse(dictLookupProc.buffer.trim()); } catch (e) {}
            if (!root.showDictionaryPanel) return;
            root.openPanel({ lemma: result.lemma || root.panel.lemma, phonetic: result.phonetic ?? "", lang: root.panel.lang,
                definitions: result.definitions ?? [], examples: result.examples ?? [], dictionary: result.dictionary ?? [],
                related: result.related ?? [], loading: false });
        }
    }
    property int dictionaryTab: 0 // 0: Definitions, 1: Examples, 2: Translations
    readonly property bool hasDictionaryPanel: definitions.length > 0 || examples.length > 0 || dictionary.length > 0 || relatedWords.length > 0
    property string translateError: ""
    property string ttsError: "" // Why the last Listen failed
    property bool translating: false

    // Model & voice options
    readonly property string translationModel: Config.options.language.translator.model ?? "classic"
    readonly property string voiceSpeed: Config.options.language.translator.voiceSpeed ?? "normal"
    readonly property string voiceEngine: Config.options.language.translator.voiceEngine ?? "xtts"
    readonly property var modelLabels: ({
        "classic": Translation.tr("Classic"),
        "advanced": Translation.tr("Advanced"),
        "offline": Translation.tr("Offline"),
    })
    readonly property var modelOptions: [
        Translation.tr("Advanced — Improved accuracy, built with Gemini (needs API key)"),
        Translation.tr("Classic — Google Translate"),
        Translation.tr("Offline — NLLB-200 3.3B on your GPU, direct between 200 languages"),
    ]
    readonly property var modelKeys: ["advanced", "classic", "offline"]
    readonly property var speedOptions: [Translation.tr("Normal"), Translation.tr("Slow"), Translation.tr("Slower")]
    readonly property var speedKeys: ["normal", "slow", "slower"]
    readonly property var voiceOptions: [
        Translation.tr("Google — online voice"),
        Translation.tr("Google Cloud TTS — online, many voices (needs API key)"),
        Translation.tr("ElevenLabs — online, natural voice (needs API key)"),
        Translation.tr("XTTS-v2 — local on your GPU (17 languages)"),
    ]
    readonly property var voiceKeys: ["google", "googlecloud", "elevenlabs", "xtts"]
    // "XTTS-v2 / Normal", shown on the settings button
    readonly property string settingsSummary: `${root.voiceOptions[Math.max(0, root.voiceKeys.indexOf(root.voiceEngine))].split(" — ")[0]} / ${root.speedOptions[Math.max(0, root.speedKeys.indexOf(root.voiceSpeed))]}`
    readonly property bool hasElevenLabsKey: (Ai.apiKeys?.elevenlabs ?? "").length > 0
    readonly property bool hasGoogleCloudKey: (Ai.apiKeys?.googlecloud ?? "").length > 0
    property string googleCloudKeyTyped: "" // Key typed in Settings before opening the Google Cloud voice dialog
    // "Female · Neural2", next to Google Cloud TTS in Settings
    readonly property string googleCloudSummary: `${(Config.options.language.translator.googleCloudGender ?? "female") === "male" ? Translation.tr("Male") : Translation.tr("Female")} · ${
        ({ chirp3hd: "Chirp 3 HD", neural2: "Neural2", wavenet: "WaveNet", standard: "Standard" })[Config.options.language.translator.googleCloudTier ?? "neural2"] ?? "Neural2"}`
    property string settingsVoice: "" // Voice selected in the open Settings dialog
    // ElevenLabs voices of the account, loaded when the voice picker opens
    property var elevenVoices: [] // [{id, name, label, preview}]
    property string elevenVoicesError: ""
    property bool elevenVoicesLoading: false
    readonly property var elevenVoiceLabels: root.elevenVoices.map(v => v.label)
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
            return Translation.tr("ElevenLabs uses your account's credits (1 per character; 10,000 free per month). Get a key at elevenlabs.io → Developers → API keys.");
        if (root.settingsVoice === "googlecloud")
            return Translation.tr("Google Cloud Text-to-Speech: many male and female voices per language. Needs a Google Cloud project with the Text-to-Speech API and billing enabled (it has a free monthly quota). Get a key at console.cloud.google.com → APIs & Services → Credentials.");
        if (root.settingsVoice === "google")
            return Translation.tr("Google Translate's voice, online.");
        if (entry?.installed)
            return Translation.tr("With XTTS-v2, languages it doesn't speak use Google's voice.") + "\n" + license;
        return Translation.tr("XTTS-v2 needs a download (~%1); until then Google's voice is used.")
            .arg(root.formatBytes(entry?.size ?? 1.88e9)) + "\n" + license;
    }

    // States
    property string activeDialog: "" // "", "model", "speed" (Settings), "elevenVoice" or "googleVoice"
    property bool showVoiceStats: false // Whisper accuracy table of the XTTS-v2 voices
    property bool showLanguageSelector: false
    property bool languageSelectorTarget: false // true for target language, false for source language

    function showLanguageSelectorDialog(isTargetLang: bool) {
        root.languageSelectorTarget = isTargetLang;
        root.showLanguageSelector = true
    }

    function swapLanguages() {
        const previousTargetLanguage = root.targetLanguage;
        root.targetLanguage = root.sourceLanguage;
        root.sourceLanguage = previousTargetLanguage;
        Config.options.language.translator.targetLanguage = root.targetLanguage;
        Config.options.language.translator.sourceLanguage = root.sourceLanguage;
        translateTimer.restart();
    }

    Shortcut {
        sequence: "Ctrl+Shift+S"
        enabled: root.visible && !root.showLanguageSelector && root.activeDialog === "" && !root.showDictionaryPanel
        onActivated: root.swapLanguages()
    }

    onFocusChanged: (focus) => {
        if (focus) {
            root.inputField.forceActiveFocus()
        }
    }

    // ---- Offline mode: NLLB-200 model (code "nllb") and Wiktionary dictionaries per language ----
    readonly property string venvPython: "$HOME/.local/share/quickshell-ii/stt-venv/bin/python"
    readonly property string offlineScript: `${FileUtils.trimFileProtocol(Directories.scriptPath)}/translator/offline.py`
    property var offlineLanguages: [] // [{code, name, names, installed, available, updatable}]
    property var offlineBusy: ({}) // code -> "downloading" | "installing" | "removing" | "confirmRemove" | "queued"
    property int offlineRevision: 0
    property var offlineProgress: ({}) // code -> {done, total} in bytes

    // 12.4 MB / 132 MB, 0.21 GB / 1.1 GB
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
    property var offlineQueue: [] // [{cmd, code}]
    property bool offlineChecking: false // Checking for updates (button in the language selector)
    property string offlineCheckResult: "" // Last translation used downloaded languages because the online one failed

    function offlineEntryFor(name) {
        return root.offlineLanguages.find(l => l.code === name || l.name === name || (l.names ?? []).includes(name)) ?? null;
    }

    function setOfflineBusy(code, state) {
        const busy = Object.assign({}, root.offlineBusy);
        if (state) busy[code] = state; else delete busy[code];
        root.offlineBusy = busy;
        root.offlineRevision++;
    }

    function refreshOfflineLanguages(refresh) {
        if (offlineListProc.running) return;
        root.offlineChecking = refresh;
        if (refresh) root.offlineCheckResult = "";
        offlineListProc.buffer = "";
        offlineListProc.command = ["bash", "-c", `exec "${root.venvPython}" "$@"`, "offline", root.offlineScript, "list", ...(refresh ? ["--refresh"] : [])];
        offlineListProc.running = true;
    }

    function enqueueOffline(cmd, code) {
        root.offlineQueue = [...root.offlineQueue, { cmd: cmd, code: code }];
        if (code) root.setOfflineBusy(code, "queued");
        root.runNextOffline();
    }

    function runNextOffline() {
        if (offlineOpProc.running || root.offlineQueue.length === 0) return;
        const op = root.offlineQueue[0];
        root.offlineQueue = root.offlineQueue.slice(1);
        offlineOpProc.op = op;
        if (op.code) root.setOfflineBusy(op.code, op.cmd === "remove" ? "removing" : "downloading");
        offlineOpProc.command = ["bash", "-c", `exec "${root.venvPython}" "$@"`, "offline", root.offlineScript, op.cmd, ...(op.code ? [op.code] : [])];
        offlineOpProc.running = true;
    }

    // Download / update / remove (two clicks) the language shown in the selector
    function offlineAction(name) {
        const entry = root.offlineEntryFor(name);
        if (!entry || !entry.available) return;
        const busy = root.offlineBusy[entry.code];
        if (busy === "queued") { // Cancel a pending download
            root.offlineQueue = root.offlineQueue.filter(op => op.code !== entry.code);
            root.setOfflineBusy(entry.code, null);
            return;
        }
        if (busy === "downloading") { // Cancel the running download (SIGTERM; the script removes partial files)
            if (offlineOpProc.running && (offlineOpProc.op?.code === entry.code || offlineOpProc.op?.cmd === "update"))
                offlineOpProc.running = false;
            return;
        }
        if (busy && busy !== "confirmRemove") return;
        if (!entry.installed) {
            root.enqueueOffline("install", entry.code);
        } else if (entry.updatable) {
            root.setOfflineBusy(entry.code, "downloading");
            root.enqueueOffline("update", "");
        } else if (busy === "confirmRemove") {
            root.enqueueOffline("remove", entry.code);
        } else {
            root.setOfflineBusy(entry.code, "confirmRemove");
            confirmRemoveTimer.code = entry.code;
            confirmRemoveTimer.restart();
        }
    }

    function offlineActionFor(name) {
        if (name === "auto") return null;
        const entry = root.offlineEntryFor(name);
        if (!entry || !entry.available) return null;
        const busy = root.offlineBusy[entry.code];
        if (busy === "queued")
            return { icon: "schedule", tooltip: Translation.tr("Waiting to download. Click to cancel") };
        if (busy === "installing")
            return { icon: "downloading", text: Translation.tr("Installing..."), tooltip: Translation.tr("Installing..."), busy: true };
        if (busy === "downloading") {
            const progress = root.offlineProgress[entry.code];
            const percent = progress && progress.total > 0 ? Math.floor(progress.done * 100 / progress.total) : -1;
            return { icon: "cancel", text: progress ? root.formatProgress(progress.done, progress.total) : "…",
                tooltip: (percent >= 0 ? Translation.tr("Downloading... %1%").arg(percent) : Translation.tr("Downloading..."))
                    + "\n" + Translation.tr("Click to cancel") };
        }
        if (busy === "removing")
            return { icon: "hourglass_top", tooltip: Translation.tr("Removing..."), busy: true };
        if (busy === "confirmRemove")
            return { icon: "delete", text: Translation.tr("Remove?"), tooltip: Translation.tr("Click again to remove") };
        if (entry.installed && entry.updatable)
            return { icon: "update", tooltip: Translation.tr("Update the offline dictionary") };
        const isModel = entry.kind === "model", isVoice = entry.kind === "voice";
        if (entry.installed)
            return { icon: "download_done", highlight: false, tooltip: (isModel
                ? Translation.tr("Translation model downloaded (%1). Click to remove")
                : isVoice ? Translation.tr("Local voice downloaded (%1). Click to remove")
                : Translation.tr("Dictionary downloaded for offline use (%1). Click to remove")).arg(root.formatBytes(entry.size)) };
        return { icon: "download", tooltip: isModel
            ? Translation.tr("Download the translation model (~%1)").arg(root.formatBytes(entry.size))
            : isVoice ? Translation.tr("Download the local voice XTTS-v2 (~%1)").arg(root.formatBytes(entry.size))
            : Translation.tr("Download the dictionary for offline use") };
    }

    Timer {
        id: confirmRemoveTimer
        property string code: ""
        interval: 3000
        onTriggered: if (root.offlineBusy[code] === "confirmRemove") root.setOfflineBusy(code, null)
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
                    if (root.offlineChecking) {
                        const updatable = result.languages.filter(l => l.updatable).length;
                        root.offlineCheckResult = updatable > 0
                            ? Translation.tr("Updates available for %1 offline dictionaries").arg(updatable)
                            : Translation.tr("Offline dictionaries are up to date");
                    }
                }
            } catch (e) {
                if (root.offlineChecking) root.offlineCheckResult = Translation.tr("Couldn't check for updates");
            }
            root.offlineChecking = false;
        }
    }

    Process {
        id: offlineOpProc
        property var op: null
        stdout: SplitParser {
            onRead: data => {
                let msg;
                try { msg = JSON.parse(data); } catch (e) { return; }
                if (msg.status === "progress" && msg.code) {
                    const progress = Object.assign({}, root.offlineProgress);
                    progress[msg.code] = { done: msg.done, total: msg.total };
                    root.offlineProgress = progress;
                    if (root.offlineBusy[msg.code] !== "downloading") root.setOfflineBusy(msg.code, "downloading");
                    else root.offlineRevision++;
                }
                if ((msg.status === "installing" || msg.status === "indexing") && (msg.code || offlineOpProc.op?.code))
                    root.setOfflineBusy(msg.code || offlineOpProc.op.code, "installing");
                if (msg.status === "error") root.translateError = msg.error ?? Translation.tr("Offline language operation failed");
            }
        }
        onExited: (exitCode, exitStatus) => {
            root.offlineProgress = ({});
            if (offlineOpProc.op?.code) root.setOfflineBusy(offlineOpProc.op.code, null);
            if (offlineOpProc.op?.cmd === "update") {
                for (const l of root.offlineLanguages)
                    if (root.offlineBusy[l.code] === "downloading") root.setOfflineBusy(l.code, null);
            }
            offlineOpProc.op = null;
            root.refreshOfflineLanguages(false);
            root.runNextOffline();
        }
    }

    Component.onCompleted: root.refreshOfflineLanguages(false)

    // ---- Word suggestions while typing ----
    property var suggestions: [] // [{word, translation}]
    property int suggestionIndex: -1
    property string suggestionPrefix: ""
    property bool suggestionsDismissed: false
    property bool skipNextSuggestion: false
    readonly property bool showSuggestions: root.suggestions.length > 0 && !root.suggestionsDismissed
        && (root.inputField?.activeFocus ?? false) && !root.showDictionaryPanel && root.activeDialog === "" && !root.showLanguageSelector

    // The word right before the cursor, if the cursor is at the end of a word
    function wordAtCursor() {
        const field = root.inputField;
        if (!field) return "";
        const text = field.text;
        const pos = field.cursorPosition;
        if (pos < text.length && /[^\s.,;:!?¿¡"()]/.test(text.charAt(pos))) return "";
        const match = text.slice(0, pos).match(/[^\s.,;:!?¿¡"()\[\]{}]+$/);
        return match ? match[0] : "";
    }

    function hideSuggestions() {
        suggestProc.running = false;
        root.suggestions = [];
        root.suggestionIndex = -1;
    }

    function acceptSuggestion(index) {
        const item = root.suggestions[index];
        if (!item) return;
        const field = root.inputField;
        const pos = field.cursorPosition;
        const start = pos - root.suggestionPrefix.length;
        if (start < 0 || field.text.slice(start, pos) !== root.suggestionPrefix) { root.hideSuggestions(); return; }
        // After a single word, suggest phrases that start with it ("advanced" -> "advanced level");
        // after a phrase, stop suggesting
        root.skipNextSuggestion = item.word.includes(" ");
        field.text = field.text.slice(0, start) + item.word + field.text.slice(pos);
        field.cursorPosition = start + item.word.length;
        root.hideSuggestions();
    }

    function handleInputKey(event) {
        if (!root.showSuggestions) return;
        const count = root.suggestions.length;
        if (event.key === Qt.Key_Down) {
            root.suggestionIndex = (root.suggestionIndex + 1) % count;
            event.accepted = true;
        } else if (event.key === Qt.Key_Up) {
            root.suggestionIndex = root.suggestionIndex <= 0 ? count - 1 : root.suggestionIndex - 1;
            event.accepted = true;
        } else if (event.key === Qt.Key_Tab) {
            root.acceptSuggestion(Math.max(0, root.suggestionIndex));
            event.accepted = true;
        } else if ((event.key === Qt.Key_Return || event.key === Qt.Key_Enter) && root.suggestionIndex >= 0) {
            root.acceptSuggestion(root.suggestionIndex);
            event.accepted = true;
        } else if (event.key === Qt.Key_Escape) {
            root.suggestionsDismissed = true;
            event.accepted = true;
        }
    }

    Timer {
        id: suggestTimer
        interval: 150
        onTriggered: {
            const prefix = root.wordAtCursor();
            if (prefix.length < 2) { root.hideSuggestions(); return; }
            if (prefix === root.suggestionPrefix && root.suggestions.length > 0) return;
            root.suggestionPrefix = prefix;
            const source = root.sourceLanguage === "auto" ? (root.detectedLanguage || "en") : root.sourceLanguage;
            suggestProc.running = false;
            suggestProc.command = ["bash", "-c", 'exec "$HOME/.local/share/quickshell-ii/stt-venv/bin/python" "$@"', "suggest",
                `${FileUtils.trimFileProtocol(Directories.scriptPath)}/translator/suggest.py`, source, root.targetLanguage, prefix, "3"];
            suggestProc.running = true;
        }
    }

    Process {
        id: suggestProc
        stdout: SplitParser {
            onRead: data => {
                let msg;
                try { msg = JSON.parse(data); } catch (e) { return; }
                if (msg.prefix !== root.suggestionPrefix) return; // Outdated
                if (msg.words) {
                    root.suggestions = msg.words.map(w => ({ word: w, translation: "" }));
                    root.suggestionIndex = -1;
                } else if (msg.translations) {
                    root.suggestions = root.suggestions.map((s, i) => ({ word: s.word, translation: msg.translations[i] ?? "" }));
                }
            }
        }
    }

    property string speakingSource: "" // "input", "output", "test" or "" when idle

    function escapeHtml(str) {
        return (str ?? "").toString().replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");
    }

    function capitalize(str) {
        return str.length > 0 ? str.charAt(0).toUpperCase() + str.slice(1) : str;
    }

    function clearDetails() {
        root.correction = null;
        root.sourcePhonetic = "";
        root.dictionary = [];
        root.translateError = "";
        root.genderTranslations = [];
        root.lemma = "";
        root.definitions = [];
        root.examples = [];
        root.relatedWords = [];
        root.sourceSuggestion = null;
    }

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

    function toggleSpeak(source: string, language: string, text: string) {
        const wasSpeaking = root.speakingSource === source;
        ttsProc.running = false;
        root.speakingSource = "";
        if (wasSpeaking || text.trim().length === 0) return;
        ttsProc.command = ["python3", `${FileUtils.trimFileProtocol(Directories.scriptPath)}/translator/tts.py`, language, text.trim(), root.voiceSpeed, root.voiceEngine];
        if ((root.voiceEngine === "elevenlabs" || root.voiceEngine === "googlecloud") && !KeyringStorage.loaded) KeyringStorage.fetchKeyringData();
        ttsProc.environment = root.ttsEnvironment();
        root.speakingSource = source;
        ttsProc.running = true;
    }

    // Voice input: "" (idle), "recording" or "transcribing"
    property string voiceState: ""
    readonly property string voiceStopFile: FileUtils.trimFileProtocol(`${Directories.cache}/translator-stt.stop`)

    function toggleVoiceInput() {
        if (root.voiceState === "recording") {
            root.voiceState = "transcribing";
            Quickshell.execDetached(["touch", root.voiceStopFile]);
        } else if (root.voiceState === "") {
            ttsProc.running = false;
            root.speakingSource = "";
            sttProc.buffer = "";
            sttProc.command = ["bash", "-c", 'exec "$HOME/.local/share/quickshell-ii/stt-venv/bin/python" "$@"', "stt",
                `${FileUtils.trimFileProtocol(Directories.scriptPath)}/translator/stt.py`, root.sourceLanguage, root.voiceStopFile];
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
            if (text.length > 0) root.inputField.text = text; // Triggers translation
        }
    }

    Process {
        id: elevenVoicesProc
        property string buffer: ""
        command: ["python3", `${FileUtils.trimFileProtocol(Directories.scriptPath)}/translator/tts.py`, "voices"]
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

    Timer {
        id: translateTimer
        interval: Config.options.sidebar.translator.delay
        repeat: false
        onTriggered: () => {
            if (root.inputField.text.trim().length > 0) {
                translateProc.running = false;
                translateProc.buffer = ""; // Clear the buffer
                translateProc.command = ["python3", `${FileUtils.trimFileProtocol(Directories.scriptPath)}/translator/translate.py`,
                    root.translationModel, root.sourceLanguage, root.targetLanguage, root.inputField.text.trim(),
                    ...(root.autocorrect ? [] : ["--no-autocorrect"])];
                translateProc.environment = root.translationModel === "advanced"
                    ? ({ "GEMINI_API_KEY": Ai.apiKeys?.gemini ?? "" }) : ({});
                root.translating = true;
                translateProc.running = true; // Restart the process
            } else {
                root.translatedText = "";
                root.clearDetails();
            }
        }
    }

    Process {
        id: translateProc
        property string buffer: ""
        stdout: SplitParser {
            onRead: data => {
                translateProc.buffer += data + "\n";
            }
        }
        onExited: (exitCode, exitStatus) => {
            if (translateProc.running) return; // A newer request already started
            root.translating = false;
            const output = translateProc.buffer.trim();
            if (output.length === 0) return;
            let result;
            try {
                result = JSON.parse(output);
            } catch (e) {
                root.clearDetails();
                root.translateError = output;
                return;
            }
            root.clearDetails();
            if (result.error) {
                root.translateError = result.error;
                return;
            }
            root.translatedText = result.translation ?? "";
            root.correction = result.correction ?? null;
            root.sourcePhonetic = result.phonetic ?? "";
            root.dictionary = result.dictionary ?? [];
            root.genderTranslations = result.gender ?? [];
            root.lemma = result.lemma ?? "";
            root.definitions = result.definitions ?? [];
            root.examples = result.examples ?? [];
            root.relatedWords = result.related ?? [];
            root.detectedLanguage = result.detected ?? "";
            root.sourceSuggestion = result.sourceSuggestion ?? null;
        }
    }

    Process {
        id: getLanguagesProc
        command: ["trans", "-list-languages", "-no-bidi"]
        property list<string> bufferList: ["auto"]
        running: true
        stdout: SplitParser {
            onRead: data => {
                getLanguagesProc.bufferList.push(data.trim());
            }
        }
        onExited: (exitCode, exitStatus) => {
            // Ensure "auto" is always the first language
            let langs = getLanguagesProc.bufferList
                .filter(lang => lang.trim().length > 0 && lang !== "auto")
                .sort((a, b) => a.localeCompare(b));
            langs.unshift("auto");
            root.languages = langs;
            getLanguagesProc.bufferList = []; // Clear the buffer
        }
    }

    ColumnLayout {
        visible: !root.showDictionaryPanel // Avoid text showing through the dictionary panel
        anchors {
            fill: parent
            margins: root.padding
        }

        StyledFlickable {
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true // Long translations must not draw over the input area
            contentHeight: contentColumn.implicitHeight

            ColumnLayout {
                id: contentColumn
                anchors.fill: parent

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 6

                    LanguageSelectorButton { // Target language button
                        id: targetLanguageButton
                        displayText: root.targetLanguage
                        onClicked: {
                            root.showLanguageSelectorDialog(true);
                        }
                    }

                    GroupButton {
                        id: swapLanguagesButton
                        Layout.alignment: Qt.AlignVCenter
                        buttonRadius: Appearance.rounding.small
                        contentItem: MaterialSymbol {
                            anchors.centerIn: parent
                            horizontalAlignment: Text.AlignHCenter
                            iconSize: Appearance.font.pixelSize.larger
                            text: "swap_vert"
                            color: Appearance.colors.colOnLayer1
                        }
                        StyledToolTip {
                            text: Translation.tr("Swap languages\nChange with Ctrl+Shift+S")
                        }
                        onClicked: root.swapLanguages()
                    }

                    Item { Layout.fillWidth: true }

                    LanguageSelectorButton { // Settings: current voice / speed
                        id: settingsButton
                        displayText: root.settingsSummary
                        onClicked: root.activeDialog = "speed"
                        StyledToolTip {
                            text: Translation.tr("Settings: voice and speed")
                        }
                    }
                }

                TextCanvas { // Content translation
                    id: outputCanvas
                    isInput: false
                    // Gender-specific results replace the single translation (like Google)
                    visible: root.genderTranslations.length === 0
                    placeholderText: Translation.tr("Translation goes here...")
                    property bool hasTranslation: (root.translatedText.trim().length > 0)
                    text: hasTranslation ? root.translatedText : ""
                    GroupButton {
                        id: listenOutputButton
                        baseWidth: height
                        buttonRadius: Appearance.rounding.small
                        enabled: outputCanvas.displayedText.trim().length > 0
                        contentItem: MaterialSymbol {
                            anchors.centerIn: parent
                            horizontalAlignment: Text.AlignHCenter
                            iconSize: Appearance.font.pixelSize.larger
                            text: root.speakingSource === "output" ? "stop" : "volume_up"
                            color: listenOutputButton.enabled ? Appearance.colors.colOnLayer1 : Appearance.colors.colSubtext
                        }
                        StyledToolTip {
                            text: root.speakingSource === "output" ? Translation.tr("Stop") : Translation.tr("Listen")
                        }
                        onClicked: root.toggleSpeak("output", root.targetLanguage, outputCanvas.displayedText)
                    }
                    GroupButton {
                        id: copyButton
                        baseWidth: height
                        buttonRadius: Appearance.rounding.small
                        enabled: outputCanvas.displayedText.trim().length > 0
                        contentItem: MaterialSymbol {
                            anchors.centerIn: parent
                            horizontalAlignment: Text.AlignHCenter
                            iconSize: Appearance.font.pixelSize.larger
                            text: "content_copy"
                            color: copyButton.enabled ? Appearance.colors.colOnLayer1 : Appearance.colors.colSubtext
                        }
                        StyledToolTip {
                            text: Translation.tr("Copy translation")
                        }
                        onClicked: {
                            Quickshell.clipboardText = outputCanvas.displayedText
                        }
                    }
                    GroupButton {
                        id: searchButton
                        baseWidth: height
                        buttonRadius: Appearance.rounding.small
                        enabled: outputCanvas.displayedText.trim().length > 0
                        contentItem: MaterialSymbol {
                            anchors.centerIn: parent
                            horizontalAlignment: Text.AlignHCenter
                            iconSize: Appearance.font.pixelSize.larger
                            text: "travel_explore"
                            color: searchButton.enabled ? Appearance.colors.colOnLayer1 : Appearance.colors.colSubtext
                        }
                        StyledToolTip {
                            text: Translation.tr("Search on the web")
                        }
                        onClicked: {
                            let url = Config.options.search.engineBaseUrl + outputCanvas.displayedText;
                            for (let site of Config.options.search.excludedSites) {
                                url += ` -site:${site}`;
                            }
                            Qt.openUrlExternally(url);
                        }
                    }
                }

                Flow { // Target side: "Noun  el avance  [advance] [progress]  See dictionary"
                    visible: root.genderTranslations.length === 0 && root.translationModel === "classic"
                        && (root.mainTranslationEntry !== null || (root.translatedText.trim().length > 0 && !/\s/.test(root.translatedText.trim())))
                    Layout.fillWidth: true
                    Layout.leftMargin: 6
                    Layout.rightMargin: 6
                    spacing: 4
                    StyledText {
                        visible: root.mainTranslationEntry !== null
                        height: 22
                        rightPadding: 2
                        verticalAlignment: Text.AlignVCenter
                        textFormat: Text.StyledText
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        color: Appearance.colors.colOnLayer1
                        text: root.mainTranslationEntry
                            ? `<b>${root.escapeHtml(root.capitalize(root.mainTranslationEntry.pos ?? ""))}</b>`
                                + (root.mainTranslationEntry.article
                                    ? `&nbsp;&nbsp;<i>${root.escapeHtml(root.mainTranslationEntry.article)}</i> ${root.escapeHtml(root.translatedText.trim())}` : "")
                            : ""
                    }
                    Repeater {
                        model: root.mainTranslationEntry?.back ?? []
                        delegate: Rectangle {
                            id: mainChip
                            required property string modelData
                            radius: Appearance.rounding.unsharpenmore
                            color: Appearance.colors.colLayer2
                            implicitWidth: mainChipText.implicitWidth + 12
                            implicitHeight: mainChipText.implicitHeight + 6
                            StyledText {
                                id: mainChipText
                                anchors.centerIn: parent
                                font.pixelSize: Appearance.font.pixelSize.smaller
                                color: Appearance.colors.colOnLayer2
                                text: mainChip.modelData
                            }
                        }
                    }
                    StyledText {
                        height: 22
                        leftPadding: 4
                        verticalAlignment: Text.AlignVCenter
                        textFormat: Text.StyledText
                        linkColor: Appearance.colors.colSubtext
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        text: `<a href="dict"><u>${Translation.tr("See dictionary")}</u></a>`
                        onLinkActivated: root.openTargetDictionary(root.translatedText.trim())
                        HoverHandler {
                            cursorShape: Qt.PointingHandCursor
                        }
                    }
                }

                Rectangle { // Gender-specific translations
                    visible: root.genderTranslations.length > 0
                    Layout.fillWidth: true
                    radius: Appearance.rounding.normal
                    color: Appearance.colors.colLayer2
                    implicitHeight: genderColumn.implicitHeight + 20

                    ColumnLayout {
                        id: genderColumn
                        anchors {
                            left: parent.left
                            right: parent.right
                            top: parent.top
                            margins: 10
                        }
                        spacing: 8

                        StyledText {
                            Layout.fillWidth: true
                            wrapMode: Text.Wrap
                            textFormat: Text.StyledText
                            color: Appearance.colors.colSubtext
                            linkColor: Appearance.colors.colPrimary
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            text: Translation.tr("Translations are gender-specific.") + ` <a href="https://support.google.com/translate/answer/9179237">${Translation.tr("Learn more")}</a>`
                            onLinkActivated: link => Qt.openUrlExternally(link)
                            HoverHandler {
                                cursorShape: parent.hoveredLink.length > 0 ? Qt.PointingHandCursor : Qt.ArrowCursor
                            }
                        }

                        Repeater {
                            model: root.genderTranslations
                            delegate: RowLayout {
                                id: genderRow
                                required property var modelData
                                Layout.fillWidth: true
                                spacing: 6

                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 0
                                    StyledText {
                                        Layout.fillWidth: true
                                        wrapMode: Text.Wrap
                                        color: Appearance.colors.colOnLayer2
                                        font.pixelSize: Appearance.font.pixelSize.normal
                                        text: genderRow.modelData.text
                                    }
                                    StyledText {
                                        color: Appearance.colors.colSubtext
                                        font.pixelSize: Appearance.font.pixelSize.smaller
                                        font.italic: true
                                        text: genderRow.modelData.gender === "feminine" ? Translation.tr("(feminine)") : Translation.tr("(masculine)")
                                    }
                                    StyledText {
                                        Layout.topMargin: 4
                                        textFormat: Text.StyledText
                                        color: Appearance.colors.colOnLayer1
                                        linkColor: Appearance.colors.colSubtext
                                        font.pixelSize: Appearance.font.pixelSize.smaller
                                        text: (root.mainPos ? `<b>${root.mainPos}</b>&nbsp;&nbsp;` : "")
                                            + `<a href="dict"><u>${Translation.tr("See dictionary")}</u></a>`
                                        onLinkActivated: root.openTargetDictionary(genderRow.modelData.text)
                                        HoverHandler {
                                            cursorShape: parent.hoveredLink.length > 0 ? Qt.PointingHandCursor : Qt.ArrowCursor
                                        }
                                    }
                                }
                                GroupButton {
                                    id: genderListenButton
                                    baseWidth: height
                                    buttonRadius: Appearance.rounding.small
                                    contentItem: MaterialSymbol {
                                        anchors.centerIn: parent
                                        horizontalAlignment: Text.AlignHCenter
                                        iconSize: Appearance.font.pixelSize.larger
                                        text: "volume_up"
                                        color: Appearance.colors.colOnLayer1
                                    }
                                    StyledToolTip {
                                        text: Translation.tr("Listen")
                                    }
                                    onClicked: root.toggleSpeak("gender", root.targetLanguage, genderRow.modelData.text)
                                }
                                GroupButton {
                                    id: genderCopyButton
                                    baseWidth: height
                                    buttonRadius: Appearance.rounding.small
                                    contentItem: MaterialSymbol {
                                        anchors.centerIn: parent
                                        horizontalAlignment: Text.AlignHCenter
                                        iconSize: Appearance.font.pixelSize.larger
                                        text: "content_copy"
                                        color: Appearance.colors.colOnLayer1
                                    }
                                    StyledToolTip {
                                        text: Translation.tr("Copy translation")
                                    }
                                    onClicked: Quickshell.clipboardText = genderRow.modelData.text
                                }
                            }
                        }
                    }
                }

                StyledText { // Why Listen failed (no key, no credits, no connection...)
                    visible: root.ttsError.length > 0
                    Layout.fillWidth: true
                    Layout.leftMargin: 6
                    Layout.rightMargin: 6
                    wrapMode: Text.Wrap
                    color: Appearance.m3colors.m3error
                    font.pixelSize: Appearance.font.pixelSize.small
                    text: root.ttsError
                }

                StyledText { // Errors (e.g. missing API key)
                    visible: root.translateError.length > 0
                    Layout.fillWidth: true
                    Layout.leftMargin: 6
                    Layout.rightMargin: 6
                    wrapMode: Text.Wrap
                    color: Appearance.m3colors.m3error
                    font.pixelSize: Appearance.font.pixelSize.small
                    text: root.translateError
                }

                ColumnLayout { // Phonetics & dictionary
                    visible: root.sourcePhonetic.length > 0 || root.dictionary.length > 0 || root.hasDictionaryPanel
                    Layout.fillWidth: true
                    Layout.topMargin: 4
                    Layout.leftMargin: 6
                    Layout.rightMargin: 6
                    spacing: 8

                    StyledText {
                        visible: root.sourcePhonetic.length > 0
                        Layout.fillWidth: true
                        wrapMode: Text.Wrap
                        color: Appearance.colors.colSubtext
                        text: root.sourcePhonetic
                    }

                    RowLayout {
                        visible: root.moreTranslations.length > 0
                        Layout.fillWidth: true
                        StyledText {
                            Layout.fillWidth: true
                            font.pixelSize: Appearance.font.pixelSize.normal
                            color: Appearance.colors.colOnLayer1
                            text: Translation.tr("More translations")
                        }
                    }

                    Repeater {
                        model: root.moreTranslations
                        delegate: ColumnLayout {
                            id: posGroup
                            required property var modelData
                            Layout.fillWidth: true
                            spacing: 6

                            Repeater {
                                model: posGroup.modelData.words
                                delegate: ColumnLayout {
                                    id: wordEntry
                                    required property var modelData
                                    Layout.fillWidth: true
                                    spacing: 3

                                    RowLayout {
                                        Layout.fillWidth: true
                                        spacing: 4
                                        StyledText {
                                            Layout.fillWidth: true
                                            wrapMode: Text.Wrap
                                            textFormat: Text.StyledText
                                            color: Appearance.colors.colOnLayer1
                                            text: (wordEntry.modelData.article ? `<i>${root.escapeHtml(wordEntry.modelData.article)}</i> ` : "")
                                                + `<b>${root.escapeHtml(wordEntry.modelData.word)}</b>`
                                        }
                                        GroupButton {
                                            id: wordListenButton
                                            baseWidth: height
                                            buttonRadius: Appearance.rounding.small
                                            contentItem: MaterialSymbol {
                                                anchors.centerIn: parent
                                                horizontalAlignment: Text.AlignHCenter
                                                iconSize: Appearance.font.pixelSize.larger
                                                text: "volume_up"
                                                color: Appearance.colors.colOnLayer1
                                            }
                                            StyledToolTip {
                                                text: Translation.tr("Listen")
                                            }
                                            onClicked: root.toggleSpeak("word", root.targetLanguage,
                                                (wordEntry.modelData.article ? wordEntry.modelData.article + " " : "") + wordEntry.modelData.word)
                                        }
                                        GroupButton {
                                            id: wordCopyButton
                                            baseWidth: height
                                            buttonRadius: Appearance.rounding.small
                                            contentItem: MaterialSymbol {
                                                anchors.centerIn: parent
                                                horizontalAlignment: Text.AlignHCenter
                                                iconSize: Appearance.font.pixelSize.larger
                                                text: "content_copy"
                                                color: Appearance.colors.colOnLayer1
                                            }
                                            StyledToolTip {
                                                text: Translation.tr("Copy translation")
                                            }
                                            onClicked: Quickshell.clipboardText = wordEntry.modelData.word
                                        }
                                    }

                                    Flow {
                                        Layout.fillWidth: true
                                        spacing: 4
                                        StyledText { // Part of speech
                                            height: 22
                                            rightPadding: 2
                                            verticalAlignment: Text.AlignVCenter
                                            font.pixelSize: Appearance.font.pixelSize.smaller
                                            font.weight: Font.DemiBold
                                            color: Appearance.colors.colOnLayer1
                                            text: root.capitalize(posGroup.modelData.pos ?? "")
                                        }
                                        Repeater {
                                            model: wordEntry.modelData.back ?? []
                                            delegate: Rectangle {
                                                id: chip
                                                required property string modelData
                                                radius: Appearance.rounding.unsharpenmore
                                                color: Appearance.colors.colLayer2
                                                implicitWidth: chipText.implicitWidth + 12
                                                implicitHeight: chipText.implicitHeight + 6
                                                StyledText {
                                                    id: chipText
                                                    anchors.centerIn: parent
                                                    font.pixelSize: Appearance.font.pixelSize.smaller
                                                    color: Appearance.colors.colOnLayer2
                                                    text: chip.modelData
                                                }
                                            }
                                        }
                                        StyledText { // See dictionary for this word
                                            height: 22
                                            leftPadding: 4
                                            verticalAlignment: Text.AlignVCenter
                                            textFormat: Text.StyledText
                                            linkColor: Appearance.colors.colSubtext
                                            font.pixelSize: Appearance.font.pixelSize.smaller
                                            text: `<a href="dict"><u>${Translation.tr("See dictionary")}</u></a>`
                                            onLinkActivated: root.openTargetDictionary(wordEntry.modelData.word)
                                            HoverHandler {
                                                cursorShape: Qt.PointingHandCursor
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

            }    
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: 6

            LanguageSelectorButton { // Source language button
                id: sourceLanguageButton
                displayText: root.sourceLanguage
                onClicked: {
                    root.showLanguageSelectorDialog(false);
                }
            }

            Item { Layout.fillWidth: true }

            LanguageSelectorButton { // Translation model
                id: modelButton
                displayText: root.modelLabels[root.translationModel] ?? root.translationModel
                onClicked: root.activeDialog = "model"
                StyledToolTip {
                    text: Translation.tr("Choose text translation model")
                }
            }

            GroupButton { // Translate by voice
                id: voiceButton
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
                        : voiceButton.enabled ? Appearance.colors.colOnLayer1 : Appearance.colors.colSubtext
                }
                StyledToolTip {
                    text: root.voiceState === "recording" ? Translation.tr("Stop recording")
                        : root.voiceState === "transcribing" ? Translation.tr("Transcribing...")
                        : Translation.tr("Translate by voice")
                }
                onClicked: root.toggleVoiceInput()
            }
        }

        TextCanvas { // Content input
            id: inputCanvas
            isInput: true
            placeholderText: Translation.tr("Enter text to translate...")
            keyHandler: event => root.handleInputKey(event)
            onInputTextChanged: {
                root.autocorrect = true;
                translateTimer.restart();
                root.suggestionsDismissed = false;
                if (root.skipNextSuggestion) {
                    root.skipNextSuggestion = false;
                    return;
                }
                suggestTimer.restart();
            }
            GroupButton {
                id: listenInputButton
                baseWidth: height
                buttonRadius: Appearance.rounding.small
                enabled: inputCanvas.inputTextArea.text.trim().length > 0
                contentItem: MaterialSymbol {
                    anchors.centerIn: parent
                    horizontalAlignment: Text.AlignHCenter
                    iconSize: Appearance.font.pixelSize.larger
                    text: root.speakingSource === "input" ? "stop" : "volume_up"
                    color: listenInputButton.enabled ? Appearance.colors.colOnLayer1 : Appearance.colors.colSubtext
                }
                StyledToolTip {
                    text: root.speakingSource === "input" ? Translation.tr("Stop") : Translation.tr("Listen")
                }
                onClicked: root.toggleSpeak("input", root.sourceLanguage, inputCanvas.inputTextArea.text)
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
                onClicked: {
                    root.inputField.text = Quickshell.clipboardText
                }
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
                onClicked: {
                    root.inputField.text = ""
                }
            }
        }

        StyledText { // Source word: "Verb +2 more  See dictionary"
            visible: root.hasDictionaryPanel
            Layout.leftMargin: 8
            Layout.rightMargin: 8
            Layout.fillWidth: true
            wrapMode: Text.Wrap
            textFormat: Text.StyledText
            color: Appearance.colors.colOnLayer1
            linkColor: Appearance.colors.colPrimary
            font.pixelSize: Appearance.font.pixelSize.small
            readonly property var posList: (root.definitions.length > 0 ? root.definitions : root.dictionary).map(e => root.capitalize(e.pos ?? ""))
            text: (posList.length > 0 ? `<b>${posList[0]}</b>` + (posList.length > 1 ? ` +${posList.length - 1} ${Translation.tr("more")}` : "") + "&nbsp;&nbsp;" : "")
                + `<a href="dict"><u>${Translation.tr("See dictionary")}</u></a>`
            onLinkActivated: root.openSourceDictionary()
            HoverHandler {
                cursorShape: parent.hoveredLink.length > 0 ? Qt.PointingHandCursor : Qt.ArrowCursor
            }
        }

        Rectangle { // "Translate from: Icelandic"
            visible: root.sourceSuggestion !== null && root.translationModel === "classic"
            Layout.fillWidth: true
            radius: Appearance.rounding.normal
            color: Appearance.colors.colLayer2
            implicitHeight: sourceSuggestionRow.implicitHeight + 16

            RowLayout {
                id: sourceSuggestionRow
                anchors {
                    left: parent.left
                    right: parent.right
                    verticalCenter: parent.verticalCenter
                    leftMargin: 10
                    rightMargin: 10
                }
                spacing: 8

                MaterialSymbol {
                    text: "auto_awesome"
                    iconSize: Appearance.font.pixelSize.larger
                    color: Appearance.colors.colPrimary
                }

                StyledText {
                    Layout.fillWidth: true
                    wrapMode: Text.Wrap
                    textFormat: Text.StyledText
                    color: Appearance.colors.colOnLayer1
                    linkColor: Appearance.colors.colPrimary
                    font.pixelSize: Appearance.font.pixelSize.small
                    text: Translation.tr("Translate from:") + ` <a href="lang"><b>${root.escapeHtml(root.sourceSuggestion?.name ?? "")}</b></a>`
                    onLinkActivated: {
                        const suggestion = root.sourceSuggestion;
                        // Use the name as it appears in the language list (English name or endonym)
                        const lang = (suggestion.names ?? []).find(n => root.languages.includes(n)) ?? suggestion.code;
                        root.sourceLanguage = lang;
                        Config.options.language.translator.sourceLanguage = lang;
                        translateTimer.restart();
                    }
                    HoverHandler {
                        cursorShape: parent.hoveredLink.length > 0 ? Qt.PointingHandCursor : Qt.ArrowCursor
                    }
                }
            }
        }

        Rectangle { // Spelling suggestion
            visible: root.correction !== null && root.translationModel === "classic"
            Layout.fillWidth: true
            radius: Appearance.rounding.normal
            color: Appearance.colors.colLayer2
            implicitHeight: correctionRow.implicitHeight + 16

            RowLayout {
                id: correctionRow
                anchors {
                    left: parent.left
                    right: parent.right
                    verticalCenter: parent.verticalCenter
                    leftMargin: 10
                    rightMargin: 10
                }
                spacing: 8

                MaterialSymbol {
                    Layout.alignment: Qt.AlignTop
                    text: "auto_awesome"
                    iconSize: Appearance.font.pixelSize.larger
                    color: Appearance.colors.colPrimary
                }

                StyledText {
                    Layout.fillWidth: true
                    wrapMode: Text.Wrap
                    textFormat: Text.StyledText
                    color: Appearance.colors.colOnLayer1
                    font.pixelSize: Appearance.font.pixelSize.small
                    linkColor: Appearance.colors.colPrimary
                    readonly property string suggested: root.correction?.html ?? ""
                    readonly property string original: root.escapeHtml(root.inputField?.text.trim() ?? "")
                    text: root.autocorrect
                        ? Translation.tr("Showing translation for") + ` <a href="none"><b>${suggested}</b></a><br>`
                            + Translation.tr("Translate instead") + ` <a href="original"><b>${original}</b></a>`
                        : Translation.tr("Did you mean:") + ` <a href="suggested"><b>${suggested}</b></a>`
                    onLinkActivated: link => {
                        if (link === "original") {
                            root.autocorrect = false;
                            translateTimer.restart();
                        } else if (link === "suggested") {
                            root.inputField.text = root.correction.plain; // Resets autocorrect
                        }
                    }
                    HoverHandler {
                        cursorShape: parent.hoveredLink.length > 0 && parent.hoveredLink !== "none" ? Qt.PointingHandCursor : Qt.ArrowCursor
                    }
                }
            }
        }
    }

    Rectangle { // Word suggestions, shown right above the input box
        id: suggestionPopup
        visible: root.showSuggestions
        z: 500
        x: inputCanvas.x + root.padding
        width: inputCanvas.width
        height: suggestionColumn.implicitHeight
        y: {
            inputCanvas.y; inputCanvas.height; root.height; height; // Re-evaluate on layout changes
            return inputCanvas.mapToItem(root, 0, 0).y - height - 4;
        }
        radius: Appearance.rounding.normal
        color: Appearance.m3colors.m3surfaceContainerHigh
        border.width: 1
        border.color: Appearance.m3colors.m3outlineVariant
        clip: true

        ColumnLayout {
            id: suggestionColumn
            anchors { left: parent.left; right: parent.right; top: parent.top }
            spacing: 0

            Repeater {
                model: root.suggestions
                delegate: RippleButton {
                    id: suggestionItem
                    required property var modelData
                    required property int index
                    Layout.fillWidth: true
                    implicitHeight: suggestionText.implicitHeight + 14
                    buttonRadius: 0
                    colBackground: root.suggestionIndex === index ? Appearance.colors.colLayer2Hover : "transparent"
                    onClicked: root.acceptSuggestion(index)
                    contentItem: ColumnLayout {
                        id: suggestionText
                        spacing: 0
                        StyledText {
                            Layout.fillWidth: true
                            Layout.leftMargin: 12
                            elide: Text.ElideRight
                            textFormat: Text.StyledText
                            font.pixelSize: Appearance.font.pixelSize.normal
                            color: Appearance.colors.colOnLayer1
                            // The typed part normal, the completion in bold
                            readonly property string typed: suggestionItem.modelData.word.slice(0, root.suggestionPrefix.length)
                            text: root.escapeHtml(typed) + `<b>${root.escapeHtml(suggestionItem.modelData.word.slice(typed.length))}</b>`
                        }
                        StyledText {
                            Layout.fillWidth: true
                            Layout.leftMargin: 12
                            elide: Text.ElideRight
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            color: Appearance.colors.colSubtext
                            text: suggestionItem.modelData.translation || "…"
                        }
                    }
                    Rectangle { // Separator
                        visible: suggestionItem.index < root.suggestions.length - 1
                        anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
                        height: 1
                        color: Appearance.m3colors.m3outlineVariant
                    }
                }
            }
        }
    }

    Loader { // "See dictionary" panel
        anchors.fill: parent
        active: root.showDictionaryPanel
        visible: active
        z: 9000
        sourceComponent: Rectangle {
            id: dictPanel
            color: Appearance.m3colors.m3surfaceContainerLow // Opaque: colLayer1 can be transparent
            radius: Appearance.rounding.normal
            focus: true
            Keys.onEscapePressed: root.showDictionaryPanel = false
            Keys.onLeftPressed: root.switchDictionaryTab(-1)
            Keys.onRightPressed: root.switchDictionaryTab(1)
            Component.onCompleted: forceActiveFocus()
            readonly property string word: root.escapeHtml(root.panel.lemma)

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 10
                spacing: 8

                RowLayout { // Header
                    Layout.fillWidth: true
                    spacing: 4
                    ColumnLayout {
                        spacing: 0
                        StyledText {
                            font.pixelSize: Appearance.font.pixelSize.larger
                            color: Appearance.colors.colOnLayer1
                            text: root.panel.lemma
                        }
                        StyledText {
                            visible: root.panel.phonetic.length > 0
                            font.pixelSize: Appearance.font.pixelSize.small
                            color: Appearance.colors.colSubtext
                            text: root.panel.phonetic
                        }
                    }
                    GroupButton {
                        id: dictListenButton
                        baseWidth: height
                        buttonRadius: Appearance.rounding.small
                        contentItem: MaterialSymbol {
                            anchors.centerIn: parent
                            horizontalAlignment: Text.AlignHCenter
                            iconSize: Appearance.font.pixelSize.larger
                            text: root.speakingSource === "dictionary" ? "stop" : "volume_up"
                            color: Appearance.colors.colOnLayer1
                        }
                        onClicked: root.toggleSpeak("dictionary", root.panel.lang, root.panel.lemma)
                    }
                    Item { Layout.fillWidth: true }
                    GroupButton {
                        id: dictCloseButton
                        baseWidth: height
                        buttonRadius: Appearance.rounding.small
                        contentItem: MaterialSymbol {
                            anchors.centerIn: parent
                            horizontalAlignment: Text.AlignHCenter
                            iconSize: Appearance.font.pixelSize.larger
                            text: "close"
                            color: Appearance.colors.colOnLayer1
                        }
                        StyledToolTip {
                            text: Translation.tr("Close")
                        }
                        onClicked: root.showDictionaryPanel = false
                    }
                }

                Item { // Tabs: scroll horizontally by hovering near the edges (or with the wheel)
                    id: tabStrip
                    Layout.fillWidth: true
                    implicitHeight: 40
                    readonly property real edgeSize: 36
                    readonly property bool overflowing: tabFlick.contentWidth > tabFlick.width
                    readonly property bool canScrollLeft: tabFlick.contentX > 0.5
                    readonly property bool canScrollRight: tabFlick.contentX < tabFlick.contentWidth - tabFlick.width - 0.5
                    property int scrollDirection: 0 // -1 left, 1 right, 0 stopped

                    Flickable {
                        id: tabFlick
                        anchors.fill: parent
                        clip: true
                        contentWidth: tabRow.implicitWidth
                        contentHeight: height
                        flickableDirection: Flickable.HorizontalFlick
                        boundsBehavior: Flickable.StopAtBounds
                        // Scrolled programmatically (edge hover / current tab); not interactive so the
                        // wheel reaches the WheelHandler that switches tabs
                        interactive: false

                        Row {
                            id: tabRow
                            height: parent.height
                            spacing: 0
                            Repeater {
                                model: [Translation.tr("Definitions"), Translation.tr("Examples"), Translation.tr("Translations"), Translation.tr("Related words")]
                                delegate: RippleButton {
                                    id: tabButton
                                    required property string modelData
                                    required property int index
                                    readonly property bool available: index === 0 ? root.panel.definitions.length > 0
                                        : index === 1 ? root.panel.examples.length > 0 : index === 2 ? root.panel.dictionary.length > 0 : root.panel.related.length > 0
                                    readonly property bool current: root.dictionaryTab === index
                                    enabled: available
                                    // Fill the width when everything fits, natural size otherwise
                                    width: Math.max(tabLabel.implicitWidth + 28, tabStrip.width / 4)
                                    height: tabRow.height
                                    buttonRadius: Appearance.rounding.small
                                    onClicked: root.dictionaryTab = index
                                    onCurrentChanged: if (current) tabFlick.ensureVisible(tabButton)
                                    contentItem: Item {
                                        StyledText {
                                            id: tabLabel
                                            anchors.centerIn: parent
                                            font.pixelSize: Appearance.font.pixelSize.small
                                            color: tabButton.current ? Appearance.colors.colPrimary
                                                : tabButton.available ? Appearance.colors.colOnLayer1 : Appearance.colors.colSubtext
                                            text: tabButton.modelData
                                        }
                                        Rectangle {
                                            visible: tabButton.current
                                            anchors.bottom: parent.bottom
                                            anchors.horizontalCenter: parent.horizontalCenter
                                            width: tabLabel.implicitWidth + 12
                                            height: 2
                                            radius: 1
                                            color: Appearance.colors.colPrimary
                                        }
                                    }
                                }
                            }
                        }

                        function ensureVisible(item) {
                            if (item.x < contentX) contentX = item.x;
                            else if (item.x + item.width > contentX + width) contentX = item.x + item.width - width;
                        }

                        Behavior on contentX {
                            enabled: tabStrip.scrollDirection === 0
                            NumberAnimation { duration: 200; easing.type: Easing.OutCubic }
                        }
                    }

                    MouseArea { // Wheel / touchpad switches tabs: up or right = next, down or left = previous
                        anchors.fill: parent
                        z: 10
                        acceptedButtons: Qt.NoButton // Clicks go through to the tabs
                        property real accumulated: 0
                        onWheel: wheel => {
                            wheel.accepted = true;
                            const horizontal = Math.abs(wheel.angleDelta.x) > Math.abs(wheel.angleDelta.y);
                            // Positive = towards the next tab
                            accumulated += horizontal ? -wheel.angleDelta.x : wheel.angleDelta.y;
                            if (Math.abs(accumulated) < 120) return; // One wheel notch (touchpads send small steps)
                            const step = accumulated > 0 ? 1 : -1;
                            accumulated = 0;
                            root.switchDictionaryTab(step);
                        }
                    }

                    HoverHandler {
                        id: tabHover
                        onPointChanged: {
                            const x = point.position.x;
                            if (!tabStrip.overflowing) tabStrip.scrollDirection = 0;
                            else if (x < tabStrip.edgeSize) tabStrip.scrollDirection = -1;
                            else if (x > tabStrip.width - tabStrip.edgeSize) tabStrip.scrollDirection = 1;
                            else tabStrip.scrollDirection = 0;
                        }
                        onHoveredChanged: if (!hovered) tabStrip.scrollDirection = 0
                    }

                    Timer { // Continuous scrolling while hovering an edge
                        interval: 16
                        repeat: true
                        running: tabStrip.scrollDirection !== 0
                        onTriggered: {
                            const maxX = Math.max(0, tabFlick.contentWidth - tabFlick.width);
                            tabFlick.contentX = Math.max(0, Math.min(maxX, tabFlick.contentX + tabStrip.scrollDirection * 4));
                        }
                    }

                    // Fades + arrows hint that there is more to the side
                    Rectangle {
                        visible: tabStrip.canScrollLeft
                        anchors { left: parent.left; top: parent.top; bottom: parent.bottom }
                        width: tabStrip.edgeSize
                        gradient: Gradient {
                            orientation: Gradient.Horizontal
                            GradientStop { position: 0; color: Appearance.m3colors.m3surfaceContainerLow }
                            GradientStop { position: 1; color: "transparent" }
                        }
                        MaterialSymbol {
                            anchors.left: parent.left
                            anchors.verticalCenter: parent.verticalCenter
                            text: "chevron_left"
                            iconSize: Appearance.font.pixelSize.larger
                            color: Appearance.colors.colSubtext
                        }
                    }
                    Rectangle {
                        visible: tabStrip.canScrollRight
                        anchors { right: parent.right; top: parent.top; bottom: parent.bottom }
                        width: tabStrip.edgeSize
                        gradient: Gradient {
                            orientation: Gradient.Horizontal
                            GradientStop { position: 0; color: "transparent" }
                            GradientStop { position: 1; color: Appearance.m3colors.m3surfaceContainerLow }
                        }
                        MaterialSymbol {
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            text: "chevron_right"
                            iconSize: Appearance.font.pixelSize.larger
                            color: Appearance.colors.colSubtext
                        }
                    }
                }

                StyledFlickable {
                    id: dictFlickable
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    clip: true
                    contentHeight: dictContent.implicitHeight
                    Connections {
                        target: root
                        function onDictionaryTabChanged() { dictFlickable.contentY = 0; }
                    }

                    ColumnLayout {
                        id: dictContent
                        width: dictFlickable.width
                        spacing: 10

                        StyledText { // Loading / nothing found
                            visible: root.panel.loading || !root.panelHasContent
                            Layout.fillWidth: true
                            Layout.topMargin: 10
                            horizontalAlignment: Text.AlignHCenter
                            wrapMode: Text.Wrap
                            color: Appearance.colors.colSubtext
                            font.pixelSize: Appearance.font.pixelSize.small
                            text: root.panel.loading ? Translation.tr("Loading...") : Translation.tr("No dictionary entries for this word")
                        }

                        StyledText { // Section title
                            visible: !root.panel.loading && root.panelHasContent
                            Layout.fillWidth: true
                            wrapMode: Text.Wrap
                            textFormat: Text.StyledText
                            font.pixelSize: Appearance.font.pixelSize.normal
                            color: Appearance.colors.colOnLayer1
                            text: [Translation.tr("Definitions of"), Translation.tr("Examples of"), Translation.tr("Translations of"), Translation.tr("Words related to")][root.dictionaryTab]
                                + ` <b>${dictPanel.word}</b>`
                        }

                        // ---- Definitions ----
                        Repeater {
                            model: root.dictionaryTab === 0 ? root.panel.definitions : []
                            delegate: ColumnLayout {
                                id: defGroup
                                required property var modelData
                                Layout.fillWidth: true
                                spacing: 8
                                StyledText {
                                    color: Appearance.colors.colPrimary
                                    font.pixelSize: Appearance.font.pixelSize.small
                                    font.weight: Font.DemiBold
                                    text: root.capitalize(defGroup.modelData.pos ?? "")
                                }
                                Repeater {
                                    model: defGroup.modelData.items
                                    delegate: RowLayout {
                                        id: defItem
                                        required property var modelData
                                        required property int index
                                        Layout.fillWidth: true
                                        spacing: 8
                                        Rectangle {
                                            Layout.alignment: Qt.AlignTop
                                            implicitWidth: 22
                                            implicitHeight: 22
                                            radius: 11
                                            color: Appearance.colors.colLayer2
                                            StyledText {
                                                anchors.centerIn: parent
                                                font.pixelSize: Appearance.font.pixelSize.smaller
                                                color: Appearance.colors.colOnLayer2
                                                text: defItem.index + 1
                                            }
                                        }
                                        ColumnLayout {
                                            Layout.fillWidth: true
                                            spacing: 4
                                            StyledText {
                                                visible: defItem.modelData.labels.length > 0
                                                font.pixelSize: Appearance.font.pixelSize.smaller
                                                color: Appearance.colors.colSubtext
                                                text: defItem.modelData.labels.join(", ")
                                            }
                                            StyledText {
                                                Layout.fillWidth: true
                                                wrapMode: Text.Wrap
                                                color: Appearance.colors.colOnLayer1
                                                font.pixelSize: Appearance.font.pixelSize.small
                                                text: defItem.modelData.text
                                            }
                                            StyledText {
                                                visible: defItem.modelData.example.length > 0
                                                Layout.fillWidth: true
                                                wrapMode: Text.Wrap
                                                color: Appearance.colors.colSubtext
                                                font.pixelSize: Appearance.font.pixelSize.small
                                                font.italic: true
                                                text: `“${defItem.modelData.example}”`
                                            }
                                            StyledText {
                                                visible: defItem.modelData.synonyms.length > 0
                                                font.pixelSize: Appearance.font.pixelSize.smaller
                                                color: Appearance.colors.colSubtext
                                                text: Translation.tr("Synonyms:")
                                            }
                                            Flow {
                                                visible: defItem.modelData.synonyms.length > 0
                                                Layout.fillWidth: true
                                                spacing: 4
                                                Repeater {
                                                    // Flatten groups: a label marker (e.g. "informal:") before its words
                                                    model: defItem.modelData.synonyms.reduce((acc, g) =>
                                                        acc.concat(g.label ? [`\u0000${g.label}:`] : [], g.words), [])
                                                    delegate: Loader {
                                                        id: synEntry
                                                        required property string modelData
                                                        readonly property bool isLabel: modelData.startsWith("\u0000")
                                                        sourceComponent: isLabel ? synLabel : synChipComponent
                                                        Component {
                                                            id: synLabel
                                                            StyledText {
                                                                height: 26
                                                                verticalAlignment: Text.AlignVCenter
                                                                leftPadding: 4
                                                                font.pixelSize: Appearance.font.pixelSize.smaller
                                                                font.italic: true
                                                                color: Appearance.colors.colSubtext
                                                                text: synEntry.modelData.slice(1)
                                                            }
                                                        }
                                                        Component {
                                                            id: synChipComponent
                                                    RippleButton { // Click a synonym to translate it
                                                        id: synChip
                                                        readonly property string modelData: synEntry.modelData
                                                        buttonRadius: Appearance.rounding.full
                                                        colBackground: Appearance.colors.colLayer2
                                                        implicitHeight: synText.implicitHeight + 8
                                                        implicitWidth: synText.implicitWidth + 16
                                                        onClicked: {
                                                            root.showDictionaryPanel = false;
                                                            root.inputField.text = synChip.modelData;
                                                        }
                                                        contentItem: StyledText {
                                                            id: synText
                                                            horizontalAlignment: Text.AlignHCenter
                                                            font.pixelSize: Appearance.font.pixelSize.smaller
                                                            color: Appearance.colors.colOnLayer2
                                                            text: synChip.modelData
                                                        }
                                                    }
                                                        }
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }

                        // ---- Examples ----
                        Repeater {
                            model: root.dictionaryTab === 1 ? root.panel.examples : []
                            delegate: RowLayout {
                                id: exampleItem
                                required property string modelData
                                Layout.fillWidth: true
                                spacing: 10
                                MaterialSymbol {
                                    Layout.alignment: Qt.AlignTop
                                    text: "format_quote"
                                    iconSize: Appearance.font.pixelSize.larger
                                    color: Appearance.colors.colSubtext
                                }
                                StyledText {
                                    Layout.fillWidth: true
                                    wrapMode: Text.Wrap
                                    textFormat: Text.StyledText
                                    color: Appearance.colors.colOnLayer1
                                    font.pixelSize: Appearance.font.pixelSize.small
                                    text: exampleItem.modelData
                                }
                            }
                        }

                        // ---- Translations with frequency ----
                        RowLayout {
                            visible: root.dictionaryTab === 2
                            Layout.fillWidth: true
                            Item { Layout.fillWidth: true }
                            StyledText {
                                font.pixelSize: Appearance.font.pixelSize.smaller
                                font.italic: true
                                color: Appearance.colors.colSubtext
                                text: Translation.tr("Frequency")
                            }
                            MaterialSymbol {
                                text: "help_outline"
                                iconSize: Appearance.font.pixelSize.normal
                                color: Appearance.colors.colSubtext
                                HoverHandler { id: freqHover }
                                StyledToolTip {
                                    extraVisibleCondition: freqHover.hovered
                                    text: Translation.tr("How often a translation appears in public documents.\n▮▮▮ Common  ▮▮▯ Uncommon  ▮▯▯ Rare")
                                }
                            }
                        }
                        Repeater {
                            model: root.dictionaryTab === 2 ? root.panel.dictionary : []
                            delegate: ColumnLayout {
                                id: transGroup
                                required property var modelData
                                Layout.fillWidth: true
                                spacing: 8
                                StyledText {
                                    color: Appearance.colors.colPrimary
                                    font.pixelSize: Appearance.font.pixelSize.small
                                    font.weight: Font.DemiBold
                                    text: root.capitalize(transGroup.modelData.pos ?? "")
                                }
                                Repeater {
                                    model: transGroup.modelData.words
                                    delegate: RowLayout {
                                        id: transRow
                                        required property var modelData
                                        Layout.fillWidth: true
                                        spacing: 10
                                        StyledText {
                                            Layout.alignment: Qt.AlignTop
                                            Layout.preferredWidth: dictContent.width * 0.32
                                            wrapMode: Text.Wrap
                                            textFormat: Text.StyledText
                                            color: Appearance.colors.colOnLayer1
                                            font.pixelSize: Appearance.font.pixelSize.small
                                            text: (transRow.modelData.article ? `<i>${root.escapeHtml(transRow.modelData.article)}</i> ` : "")
                                                + root.escapeHtml(transRow.modelData.word)
                                        }
                                        StyledText {
                                            Layout.alignment: Qt.AlignTop
                                            Layout.fillWidth: true
                                            wrapMode: Text.Wrap
                                            color: Appearance.colors.colSubtext
                                            font.pixelSize: Appearance.font.pixelSize.smaller
                                            text: (transRow.modelData.back ?? []).join(", ")
                                        }
                                        Row {
                                            Layout.alignment: Qt.AlignTop
                                            Layout.topMargin: 6
                                            spacing: 2
                                            Repeater {
                                                model: 3
                                                delegate: Rectangle {
                                                    required property int index
                                                    width: 8
                                                    height: 4
                                                    radius: 2
                                                    color: index < (transRow.modelData.frequency ?? 1) ? Appearance.colors.colPrimary : Appearance.colors.colLayer3
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }

                        // ---- Related words ----
                        StyledText {
                            visible: root.dictionaryTab === 3
                            color: Appearance.colors.colPrimary
                            font.pixelSize: Appearance.font.pixelSize.small
                            font.weight: Font.DemiBold
                            text: Translation.tr("See also")
                        }
                        Flow {
                            visible: root.dictionaryTab === 3
                            Layout.fillWidth: true
                            spacing: 6
                            Repeater {
                                model: root.dictionaryTab === 3 ? root.panel.related : []
                                delegate: RippleButton { // Click to translate the related word
                                    id: relatedChip
                                    required property string modelData
                                    buttonRadius: Appearance.rounding.full
                                    colBackground: Appearance.colors.colLayer2
                                    implicitHeight: relatedText.implicitHeight + 10
                                    implicitWidth: relatedText.implicitWidth + 20
                                    onClicked: {
                                        root.showDictionaryPanel = false;
                                        root.inputField.text = relatedChip.modelData;
                                    }
                                    contentItem: StyledText {
                                        id: relatedText
                                        horizontalAlignment: Text.AlignHCenter
                                        font.pixelSize: Appearance.font.pixelSize.small
                                        color: Appearance.colors.colOnLayer2
                                        text: relatedChip.modelData
                                    }
                                }
                            }
                        }

                        Item { implicitHeight: 6 }
                    }
                }
            }
        }
    }

    Loader { // Model / settings dialogs
        id: optionsDialogLoader
        anchors.fill: parent
        active: root.activeDialog === "model" || root.activeDialog === "speed"
        visible: active
        z: 9999
        sourceComponent: SelectionDialog {
            searchable: false
            id: optionsDialog
            menuMode: root.activeDialog === "speed" // Settings: Voice / Speed as submenus
            titleText: root.activeDialog === "model" ? Translation.tr("Choose text translation model") : Translation.tr("Settings")
            items: root.activeDialog === "model" ? root.modelOptions : root.speedOptions
            defaultChoice: root.activeDialog === "model"
                ? root.modelOptions[Math.max(0, root.modelKeys.indexOf(root.translationModel))]
                : root.speedOptions[Math.max(0, root.speedKeys.indexOf(root.voiceSpeed))]
            itemActionText: root.activeDialog === "speed" ? Translation.tr("Test") : ""
            footnote: root.activeDialog === "model"
                ? Translation.tr("Advanced is supported for text translation only in select languages.")
                    + "\n" + Translation.tr("Offline model license: CC-BY-NC 4.0, for personal use (non-commercial).")
                : (root.ttsError.length > 0 ? root.ttsError + "\n" : "") + root.voiceFootnote
            // Settings: voice engine (XTTS-v2 with its download/remove button) above the speeds
            groupTitle: root.activeDialog === "speed" ? Translation.tr("Voice") : ""
            groupItems: root.activeDialog === "speed" ? root.voiceOptions : []
            groupDefaultChoice: root.voiceOptions[Math.max(0, root.voiceKeys.indexOf(root.voiceEngine))]
            groupItemActionProvider: item => {
                const key = root.voiceKeys[root.voiceOptions.indexOf(item)];
                if (key === "xtts") return root.offlineActionFor("xtts");
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
                if (root.voiceKeys[root.voiceOptions.indexOf(item)] !== "xtts" || !entry?.installed || root.offlineBusy[entry.code]) return null;
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
            groupFieldVisible: root.activeDialog === "speed" && (root.settingsVoice === "elevenlabs" || root.settingsVoice === "googlecloud")
            groupFieldPlaceholder: (root.settingsVoice === "googlecloud" ? root.hasGoogleCloudKey : root.hasElevenLabsKey)
                ? Translation.tr("API key saved (paste a new one to replace it)")
                : root.settingsVoice === "googlecloud" ? Translation.tr("Google Cloud API key") : Translation.tr("ElevenLabs API key")
            onGroupItemAction: item => {
                if (root.voiceKeys[root.voiceOptions.indexOf(item)] === "xtts") {
                    root.offlineAction("xtts");
                    return;
                }
                // Keep what's chosen here, then open the voice picker (it comes back to Settings)
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
            listTitle: root.activeDialog === "speed" ? Translation.tr("Speed") : ""
            itemActionIcon: "volume_up"
            // Offline model: download (with progress/cancel) or remove, next to its option
            itemActionProvider: root.activeDialog === "model"
                ? (item => root.modelKeys[root.modelOptions.indexOf(item)] === "offline" ? root.offlineActionFor("nllb") : null)
                : null
            itemActionRevision: root.offlineRevision
            onItemAction: item => {
                if (root.activeDialog === "model") {
                    root.offlineAction("nllb");
                    return;
                }
                const speed = root.speedKeys[root.speedOptions.indexOf(item)] ?? "normal";
                const sample = root.inputField.text.trim().length > 0 ? root.inputField.text.trim() : "Hello, this is a test";
                const lang = root.inputField.text.trim().length > 0 ? root.sourceLanguage : "English";
                ttsProc.running = false;
                const engine = root.voiceKeys[root.voiceOptions.indexOf(optionsDialog.groupSelectedValue)] ?? "xtts";
                root.saveVoiceKey(engine, optionsDialog.groupFieldText);
                ttsProc.environment = root.ttsEnvironment();
                ttsProc.command = ["python3", `${FileUtils.trimFileProtocol(Directories.scriptPath)}/translator/tts.py`, lang, sample, speed, engine];
                root.speakingSource = "test";
                ttsProc.running = true;
            }
            onCanceled: root.activeDialog = ""
            onSelected: result => {
                const dialog = root.activeDialog;
                root.activeDialog = "";
                if (!result) return;
                if (dialog === "model") {
                    Config.options.language.translator.model = root.modelKeys[root.modelOptions.indexOf(result)] ?? "classic";
                    translateTimer.restart();
                } else {
                    Config.options.language.translator.voiceSpeed = root.speedKeys[root.speedOptions.indexOf(result)] ?? "normal";
                    Config.options.language.translator.voiceEngine = root.voiceKeys[root.voiceOptions.indexOf(optionsDialog.groupSelectedValue)] ?? "xtts";
                    root.saveVoiceKey(root.voiceKeys[root.voiceOptions.indexOf(optionsDialog.groupSelectedValue)] ?? "", optionsDialog.groupFieldText);
                }
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
                optionsDialogLoader.item?.forceActiveFocus();
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

    Loader {
        anchors.fill: parent
        active: root.showLanguageSelector
        visible: root.showLanguageSelector
        z: 9999
        sourceComponent: SelectionDialog {
            id: languageSelectorDialog
            titleText: Translation.tr("Select Language")
            items: root.languages
            itemActionProvider: item => root.offlineActionFor(item)
            itemActionRevision: root.offlineRevision
            onItemAction: item => root.offlineAction(item)
            footnote: root.offlineCheckResult.length > 0 ? root.offlineCheckResult
                : Translation.tr("Download dictionaries (definitions, examples, synonyms) to use them without an internet connection.")
            titleActionIcon: "update"
            titleActionTooltip: Translation.tr("Check for updates of offline dictionaries")
            titleActionBusy: root.offlineChecking
            onTitleAction: root.refreshOfflineLanguages(true)
            defaultChoice: root.languageSelectorTarget ? root.targetLanguage : root.sourceLanguage
            onCanceled: () => {
                root.showLanguageSelector = false;
            }
            onSelected: (result) => {
                root.showLanguageSelector = false;
                if (!result || result.length === 0) return; // No selection made

                if (root.languageSelectorTarget) {
                    root.targetLanguage = result;
                    Config.options.language.translator.targetLanguage = result; // Save to config
                } else {
                    root.sourceLanguage = result;
                    Config.options.language.translator.sourceLanguage = result; // Save to config
                }

                translateTimer.restart(); // Restart translation after language change
            }
        }
    }
}
