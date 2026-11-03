import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.services
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell.Io

/**
 * Google Cloud TTS voice (opened from Settings → Voice): the default voice by gender and quality, used in every
 * language, and optionally one voice for a language. Saved in Config (googleCloudGender / Tier / Voices) and used by
 * scripts/translator/googlecloud.py. Voices come from the API (tts.py google-voices), with ▶ to test each one.
 */
Item {
    id: root
    signal closed()

    property string apiKey: "" // Typed in Settings or saved in the keyring
    property real dialogPadding: 15
    property real dialogMargin: 30
    readonly property string scriptDir: `${FileUtils.trimFileProtocol(Directories.scriptPath)}/translator`

    readonly property string gender: Config.options.language.translator.googleCloudGender || "female"
    readonly property string tier: Config.options.language.translator.googleCloudTier || "neural2"
    readonly property var tiers: [
        { key: "chirp3hd", label: Translation.tr("Chirp 3 HD — most natural") },
        { key: "neural2", label: "Neural2" },
        { key: "wavenet", label: "WaveNet" },
        { key: "standard", label: Translation.tr("Standard — basic") },
    ]
    readonly property var tierNames: ({ chirp3hd: "Chirp 3 HD", neural2: "Neural2", wavenet: "WaveNet", standard: "Standard", other: "Studio" })
    // Same as googlecloud.py: the regional variant used for a language without region
    readonly property var preferredLocale: ({
        en: "en-US", es: "es-US", pt: "pt-BR", fr: "fr-FR", de: "de-DE", it: "it-IT", nl: "nl-NL", zh: "cmn-CN", ar: "ar-XA",
        hi: "hi-IN", ja: "ja-JP", ko: "ko-KR", ru: "ru-RU", pl: "pl-PL", tr: "tr-TR", cs: "cs-CZ", hu: "hu-HU",
    })

    // ---- Voices of the API ----
    property var voices: []
    property bool loading: false
    property string error: ""
    function loadVoices(refresh) {
        root.error = "";
        root.loading = true;
        voicesProc.running = false;
        voicesProc.environment = ({ "GOOGLE_TTS_API_KEY": root.apiKey });
        voicesProc.command = ["python3", `${root.scriptDir}/tts.py`, "google-voices", ...(refresh ? ["--refresh"] : [])];
        voicesProc.running = true;
    }
    Process {
        id: voicesProc
        stdout: StdioCollector {
            onStreamFinished: {
                if (text.trim().length === 0) return;
                try {
                    root.voices = JSON.parse(text);
                } catch (e) {
                    root.error = Translation.tr("Couldn't read the list of voices");
                }
            }
        }
        stderr: StdioCollector {
            onStreamFinished: if (text.trim().length > 0) root.error = text.trim().split("\n").pop()
        }
        onExited: root.loading = false
    }
    Component.onCompleted: {
        root.loadVoices(false);
        Qt.callLater(root.forceActiveFocus);
    }

    // ---- Voice per language ----
    readonly property var chosenVoices: {
        try {
            const map = JSON.parse(Config.options.language.translator.googleCloudVoices || "{}");
            return map && typeof map === "object" ? map : {};
        } catch (e) {
            return {};
        }
    }
    function choose(lang, name) { // name "" = automatic (gender + quality)
        const map = Object.assign({}, root.chosenVoices);
        if (name) map[lang] = name;
        else delete map[lang];
        Config.options.language.translator.googleCloudVoices = JSON.stringify(map);
    }
    function voicesOf(lang) {
        return root.voices.filter(v => v.lang === lang);
    }
    // The voice "automatic" picks for a language (like googlecloud.py: gender, then quality, then region)
    function automaticVoice(lang) {
        const order = [root.tier, ...root.tiers.map(t => t.key).filter(t => t !== root.tier)];
        const rank = v => order.includes(v.tier) ? order.indexOf(v.tier) : order.length;
        const sorted = root.voicesOf(lang).slice().sort((a, b) =>
            (a.gender !== root.gender) - (b.gender !== root.gender) || rank(a) - rank(b)
            || (a.locale !== root.preferredLocale[lang]) - (b.locale !== root.preferredLocale[lang]) || a.name.localeCompare(b.name));
        return sorted[0] ?? null;
    }
    function currentVoice(lang) {
        const named = root.chosenVoices[lang];
        return root.voices.find(v => v.name === named) ?? root.automaticVoice(lang);
    }
    function describe(voice) {
        if (!voice) return "–";
        return `${voice.name} · ${voice.gender === "male" ? Translation.tr("Male") : voice.gender === "female" ? Translation.tr("Female") : voice.gender}`;
    }

    property var expanded: ({})
    function toggle(lang) {
        root.expanded = Object.assign({}, root.expanded, { [lang]: !(root.expanded[lang] ?? false) });
    }

    // ---- Test (▶): a sentence of the language with that voice ----
    property string playingKey: ""
    function test(lang, voiceName) {
        const key = `${lang}|${voiceName}`;
        const wasPlaying = root.playingKey === key;
        testProc.running = false;
        root.playingKey = "";
        root.error = "";
        if (wasPlaying) return;
        testProc.environment = ({
            "GOOGLE_TTS_API_KEY": root.apiKey,
            "GOOGLE_TTS_VOICES": JSON.stringify({ [lang]: voiceName }),
            "GOOGLE_TTS_GENDER": root.gender,
            "GOOGLE_TTS_TIER": root.tier,
        });
        testProc.command = ["python3", `${root.scriptDir}/tts.py`, lang, VoiceData.sampleTexts[lang] ?? "Hello", "normal", "googlecloud"];
        root.playingKey = key;
        testProc.running = true;
    }
    Process {
        id: testProc
        stderr: StdioCollector {
            onStreamFinished: if (text.trim().length > 0) root.error = text.trim().split("\n").pop()
        }
        onExited: if (!testProc.running) root.playingKey = ""
    }
    Component.onDestruction: testProc.running = false

    focus: true
    Keys.onPressed: event => {
        if (event.key === Qt.Key_Escape || event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
            root.closed();
            event.accepted = true;
        }
    }

    component SectionTitle: StyledText {
        color: Appearance.colors.colSubtext
        font.pixelSize: Appearance.font.pixelSize.small
        topPadding: 4
    }

    Rectangle { // Scrim
        anchors.fill: parent
        radius: Appearance.rounding.small
        color: Appearance.colors.colScrim
        MouseArea {
            anchors.fill: parent
            hoverEnabled: true
            preventStealing: true
            onClicked: root.closed()
        }
    }

    Rectangle { // The dialog
        color: Appearance.m3colors.m3surfaceContainerHigh
        radius: Appearance.rounding.normal
        anchors.fill: parent
        anchors.margins: root.dialogMargin

        MouseArea { // Clicks inside don't reach the scrim
            anchors.fill: parent
        }

        ColumnLayout {
            anchors.fill: parent
            spacing: 10

            RowLayout {
                Layout.topMargin: root.dialogPadding
                Layout.leftMargin: root.dialogPadding
                Layout.rightMargin: root.dialogPadding - 6
                StyledText {
                    Layout.fillWidth: true
                    color: Appearance.m3colors.m3onSurface
                    font.pixelSize: Appearance.font.pixelSize.larger
                    text: Translation.tr("Google Cloud voice")
                }
                RippleButton { // Reload the list of voices
                    focusPolicy: Qt.NoFocus
                    enabled: !root.loading
                    implicitWidth: 34
                    implicitHeight: 34
                    buttonRadius: Appearance.rounding.full
                    onClicked: root.loadVoices(true)
                    contentItem: Item {
                        MaterialSymbol {
                            anchors.centerIn: parent
                            text: root.loading ? "sync" : "refresh"
                            iconSize: Appearance.font.pixelSize.huge
                            color: root.loading ? Appearance.colors.colSubtext : Appearance.m3colors.m3onSurface
                        }
                    }
                    StyledToolTip {
                        text: Translation.tr("Reload the list of voices")
                    }
                }
            }

            Rectangle {
                color: Appearance.m3colors.m3outline
                implicitHeight: 1
                Layout.fillWidth: true
                Layout.leftMargin: root.dialogPadding
                Layout.rightMargin: root.dialogPadding
            }

            StyledFlickable {
                id: flick
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.leftMargin: root.dialogPadding
                Layout.rightMargin: root.dialogPadding
                clip: true
                contentWidth: width
                contentHeight: content.implicitHeight

                ColumnLayout {
                    id: content
                    width: flick.width
                    spacing: 4

                    SectionTitle {
                        text: Translation.tr("Default voice (every language)")
                    }
                    RowLayout { // Gender
                        spacing: 16
                        Repeater {
                            model: [{ key: "female", label: Translation.tr("Female") }, { key: "male", label: Translation.tr("Male") }]
                            delegate: StyledRadioButton {
                                required property var modelData
                                focusPolicy: Qt.NoFocus
                                description: modelData.label
                                checked: root.gender === modelData.key
                                onClicked: Config.options.language.translator.googleCloudGender = modelData.key
                            }
                        }
                    }
                    ColumnLayout { // Quality
                        spacing: 0
                        Repeater {
                            model: root.tiers
                            delegate: StyledRadioButton {
                                required property var modelData
                                Layout.fillWidth: true
                                focusPolicy: Qt.NoFocus
                                description: modelData.label
                                checked: root.tier === modelData.key
                                onClicked: Config.options.language.translator.googleCloudTier = modelData.key
                            }
                        }
                    }

                    SectionTitle {
                        Layout.topMargin: 8
                        Layout.fillWidth: true
                        wrapMode: Text.Wrap
                        text: Translation.tr("Voice per language (optional): choose one to always use it in that language")
                    }
                    StyledText { // Loading / error
                        visible: text.length > 0
                        Layout.fillWidth: true
                        wrapMode: Text.Wrap
                        font.pixelSize: Appearance.font.pixelSize.small
                        color: root.error.length > 0 ? Appearance.m3colors.m3error : Appearance.colors.colSubtext
                        text: root.error.length > 0 ? root.error
                            : root.loading && root.voices.length === 0 ? Translation.tr("Loading the voices...") : ""
                    }

                    Repeater {
                        model: VoiceData.languages
                        delegate: ColumnLayout {
                            id: language
                            required property string modelData
                            readonly property string lang: modelData
                            readonly property bool open: root.expanded[language.lang] ?? false
                            readonly property bool fixed: !!root.chosenVoices[language.lang]
                            Layout.fillWidth: true
                            spacing: 0

                            RippleButton { // Language: its voice (fixed or automatic); opens the list
                                Layout.fillWidth: true
                                implicitHeight: 34
                                buttonRadius: Appearance.rounding.small
                                focusPolicy: Qt.NoFocus
                                onClicked: root.toggle(language.lang)
                                contentItem: Item {
                                    RowLayout {
                                        anchors.fill: parent
                                        anchors.leftMargin: 4
                                        anchors.rightMargin: 8
                                        spacing: 6
                                        MaterialSymbol {
                                            text: language.open ? "expand_more" : "chevron_right"
                                            iconSize: Appearance.font.pixelSize.larger
                                            color: Appearance.colors.colSubtext
                                        }
                                        StyledText {
                                            text: `${Translation.tr(VoiceData.languageNames[language.lang] ?? language.lang)} (${language.lang})`
                                            color: Appearance.m3colors.m3onSurface
                                        }
                                        Item { Layout.fillWidth: true }
                                        StyledText {
                                            Layout.maximumWidth: 170
                                            elide: Text.ElideRight
                                            font.pixelSize: Appearance.font.pixelSize.small
                                            color: language.fixed ? Appearance.colors.colPrimary : Appearance.colors.colSubtext
                                            text: language.fixed ? root.chosenVoices[language.lang] : Translation.tr("Automatic")
                                        }
                                    }
                                }
                            }

                            Loader {
                                active: language.open
                                visible: active
                                Layout.fillWidth: true
                                Layout.leftMargin: 24
                                sourceComponent: ColumnLayout {
                                    spacing: 0
                                    Repeater {
                                        // "Automatic" first, then the voices of the language
                                        model: [{ automatic: true }, ...root.voicesOf(language.lang)]
                                        delegate: Item {
                                            id: voiceRow
                                            required property var modelData
                                            readonly property bool automatic: voiceRow.modelData.automatic ?? false
                                            readonly property var voice: voiceRow.automatic ? root.automaticVoice(language.lang) : voiceRow.modelData
                                            readonly property bool chosen: voiceRow.automatic ? !language.fixed
                                                : root.chosenVoices[language.lang] === voiceRow.modelData.name
                                            readonly property bool playing: !!voiceRow.voice && root.playingKey === `${language.lang}|${voiceRow.voice.name}`
                                            Layout.fillWidth: true
                                            implicitHeight: 30

                                            RippleButton {
                                                anchors.left: parent.left
                                                anchors.right: playButton.left
                                                anchors.rightMargin: 2
                                                height: parent.height
                                                buttonRadius: Appearance.rounding.small
                                                focusPolicy: Qt.NoFocus
                                                colBackground: voiceRow.chosen ? ColorUtils.transparentize(Appearance.colors.colPrimary, 0.88)
                                                    : ColorUtils.transparentize(Appearance.colors.colLayer1Hover, 1)
                                                onClicked: root.choose(language.lang, voiceRow.automatic ? "" : voiceRow.modelData.name)
                                                contentItem: Item {
                                                    RowLayout {
                                                        anchors.fill: parent
                                                        anchors.leftMargin: 6
                                                        anchors.rightMargin: 8
                                                        spacing: 6
                                                        MaterialSymbol {
                                                            Layout.preferredWidth: 18
                                                            text: voiceRow.chosen ? "check" : ""
                                                            iconSize: Appearance.font.pixelSize.normal
                                                            color: Appearance.colors.colPrimary
                                                        }
                                                        StyledText {
                                                            Layout.fillWidth: true
                                                            elide: Text.ElideRight
                                                            font.pixelSize: Appearance.font.pixelSize.small
                                                            color: voiceRow.chosen ? Appearance.colors.colPrimary : Appearance.m3colors.m3onSurface
                                                            text: voiceRow.automatic
                                                                ? Translation.tr("Automatic: %1").arg(root.describe(voiceRow.voice))
                                                                : root.describe(voiceRow.modelData)
                                                        }
                                                        StyledText {
                                                            visible: !voiceRow.automatic
                                                            font.pixelSize: Appearance.font.pixelSize.smaller
                                                            color: Appearance.colors.colSubtext
                                                            text: root.tierNames[voiceRow.modelData.tier] ?? ""
                                                        }
                                                    }
                                                }
                                            }

                                            RippleButton { // Test this voice
                                                id: playButton
                                                enabled: !!voiceRow.voice
                                                anchors.right: parent.right
                                                anchors.verticalCenter: parent.verticalCenter
                                                implicitWidth: 28
                                                implicitHeight: 28
                                                buttonRadius: Appearance.rounding.full
                                                focusPolicy: Qt.NoFocus
                                                onClicked: root.test(language.lang, voiceRow.voice.name)
                                                contentItem: Item {
                                                    MaterialSymbol {
                                                        anchors.centerIn: parent
                                                        text: voiceRow.playing ? "stop_circle" : "play_circle"
                                                        iconSize: Appearance.font.pixelSize.larger
                                                        color: Appearance.colors.colPrimary
                                                    }
                                                }
                                                StyledToolTip {
                                                    text: voiceRow.playing ? Translation.tr("Stop")
                                                        : Translation.tr("Listen (uses a few characters of your quota)")
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }

                    StyledText {
                        Layout.topMargin: 6
                        Layout.bottomMargin: 6
                        Layout.fillWidth: true
                        wrapMode: Text.Wrap
                        font.pixelSize: Appearance.font.pixelSize.small
                        color: Appearance.colors.colSubtext
                        text: Translation.tr("Other languages use the default voice.")
                    }
                }
            }

            Rectangle {
                color: Appearance.m3colors.m3outline
                implicitHeight: 1
                Layout.fillWidth: true
                Layout.leftMargin: root.dialogPadding
                Layout.rightMargin: root.dialogPadding
            }

            DialogButton {
                Layout.alignment: Qt.AlignRight
                Layout.bottomMargin: root.dialogPadding
                Layout.rightMargin: root.dialogPadding
                buttonText: Translation.tr("Done")
                onClicked: root.closed()
            }
        }
    }
}
