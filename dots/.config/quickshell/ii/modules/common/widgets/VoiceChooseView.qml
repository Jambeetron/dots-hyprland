import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.services
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell.Io

/**
 * "Choose" tab of VoiceStatsDialog: the XTTS-v2 voice of each of the 17 languages. Every language opens a list of
 * its voices, male and female, best first (accuracy in that language); clicking one chooses it (saved in Config,
 * used by xtts.py). search: the dialog (matches(), highlighted(), query), like VoiceTable.
 */
Flickable {
    id: root

    property var search: null
    readonly property string infoText: "" // Always visible
    readonly property string detailsText: [
        Translation.tr("Choose the voice XTTS-v2 uses for each language. Voices sorted by accuracy in that language (%1), best first.")
            .arg(VoiceData.accuracyModel),
        Translation.tr("System language: %1.").arg(root.languageLabel(VoiceData.systemLanguage)),
        Translation.tr("Languages without a choice, use #1 female voice by language."),
        Translation.tr("Test folder clips (%1):").arg("~/.local/share/voice-tests"),
        Translation.tr("Approximate size: ~280 MB"),
        Translation.tr("Actual size: %1").arg(root.samplesSize.length > 0 ? root.samplesSize : Translation.tr("not found")),
    ].join("\n")

    // Languages open by hand (all start closed); while searching, the ones with a match open too
    property var expanded: ({})
    function isExpanded(lang) {
        return (root.expanded[lang] ?? false) || root.languageMatches(lang);
    }
    function toggle(lang) {
        root.expanded = Object.assign({}, root.expanded, { [lang]: !(root.expanded[lang] ?? false) });
    }

    // Test clips of a voice in a language, one after another (mpv); clicking again stops them
    property string playingKey: "" // "<voice>|<lang>" while playing
    function playSamples(voice, lang) {
        const key = `${voice}|${lang}`;
        const wasPlaying = root.playingKey === key;
        player.running = false;
        root.playingKey = "";
        if (wasPlaying) return;
        // Names as arguments (not in the script): no quoting problems
        player.command = ["bash", "-c", `dir="${VoiceData.samplesDir}/$1"; files=(); for i in $(seq 0 ${VoiceData.samplesPerLanguage - 1}); do `
            + `[ -f "$dir/$2_$i.flac" ] && files+=("$dir/$2_$i.flac"); done; [ \${#files[@]} -gt 0 ] || exit 3; `
            + `exec mpv --no-video --really-quiet --no-terminal "\${files[@]}"`, "samples", voice, lang];
        root.playingKey = key;
        player.running = true;
    }
    Process {
        id: player
        onExited: (exitCode, exitStatus) => {
            if (!player.running) root.playingKey = ""; // Not when it was restarted with other clips
        }
    }
    Component.onDestruction: player.running = false // Closing the dialog stops the clips

    // Real size of the test clips (du), "" when there are none
    property string samplesSize: ""
    Process {
        running: true
        command: ["bash", "-c", `ls "${VoiceData.samplesDir}"/*/*.flac >/dev/null 2>&1 && du -sb "${VoiceData.samplesDir}" | cut -f1`]
        stdout: StdioCollector {
            onStreamFinished: {
                const bytes = parseInt(text.trim());
                root.samplesSize = !(bytes > 0) ? ""
                    : bytes >= 1e9 ? `${(bytes / 1e9).toFixed(1)} GB` : bytes >= 1e6 ? `${Math.round(bytes / 1e6)} MB` : `${Math.round(bytes / 1e3)} KB`;
            }
        }
    }

    // Voice + language pairs that have test clips ("<voice>|<lang>"), found once when the dialog opens
    property var availableSamples: ({})
    property bool samplesScanned: false
    function hasSamples(voice, lang) {
        return root.availableSamples[`${voice}|${lang}`] ?? false;
    }
    Process {
        running: true
        command: ["bash", "-c", `cd "${VoiceData.samplesDir}" 2>/dev/null && find . -mindepth 2 -maxdepth 2 -name '*.flac' -printf '%P\\n'`]
        stdout: StdioCollector {
            onStreamFinished: {
                const found = {};
                for (const line of text.split("\n")) {
                    const match = line.match(/^(.+)\/([a-z]+)_\d+\.flac$/); // "<voice>/<lang>_<i>.flac"
                    if (match) found[`${match[1]}|${match[2]}`] = true;
                }
                root.availableSamples = found;
                root.samplesScanned = true;
            }
        }
    }

    function languageLabel(lang) {
        return `${Translation.tr(VoiceData.languageNames[lang] ?? lang)} (${lang})`;
    }
    function percentText(value) {
        return value === null || value === undefined ? "–" : `${value}%`;
    }
    function percentColor(value) {
        if (typeof value !== "number") return Appearance.colors.colSubtext;
        if (value >= 90) return Appearance.m3colors.m3onSurface;
        if (value >= 75) return Appearance.colors.colSubtext;
        return Appearance.m3colors.m3error;
    }

    // Texts of a language that can match the search: its name, its chosen voice and every voice row
    function languageCells(lang) {
        const chosen = VoiceData.voices.find(v => v.name === VoiceData.chosenVoice(lang));
        const cells = [root.languageLabel(lang), VoiceData.chosenVoice(lang), root.percentText(VoiceData.accuracyOf(chosen, lang))];
        for (const v of VoiceData.voices)
            cells.push(v.name, root.percentText(VoiceData.accuracyOf(v, lang)));
        return cells;
    }
    function languageMatches(lang) {
        return !!root.search && root.search.query.length > 0 && root.languageCells(lang).some(root.search.matches);
    }
    readonly property int matchCount: {
        if (!root.search || root.search.query.length === 0) return 0;
        let count = 0;
        for (const lang of VoiceData.languages)
            count += root.languageCells(lang).filter(root.search.matches).length;
        return count;
    }
    // Scrolls to the first language with a match
    readonly property string firstMatch: {
        if (!root.search || root.search.query.length === 0) return "";
        return VoiceData.languages.find(lang => root.languageMatches(lang)) ?? "";
    }
    onFirstMatchChanged: if (root.firstMatch.length > 0) Qt.callLater(() => {
        const item = languageRepeater.itemAt(VoiceData.languages.indexOf(root.firstMatch));
        if (!item) return;
        const y = item.mapToItem(languageColumn, 0, 0).y;
        if (y < root.contentY || y + 40 > root.contentY + root.height)
            root.contentY = Math.max(0, Math.min(y - 8, root.contentHeight - root.height));
    })

    clip: true
    contentWidth: width
    contentHeight: languageColumn.implicitHeight
    boundsBehavior: Flickable.StopAtBounds
    ScrollBar.vertical: StyledScrollBar {}

    component SearchText: StyledText { // Text that highlights the search
        id: label
        property var value: ""
        readonly property bool found: root.search?.matches(label.value) ?? false
        textFormat: Text.StyledText
        text: root.search ? root.search.highlighted(label.value) : String(label.value)
        elide: Text.ElideRight
        font.pixelSize: Appearance.font.pixelSize.small
        Rectangle { // Search match
            z: -1
            visible: label.found
            anchors.fill: parent
            anchors.margins: -2
            radius: Appearance.rounding.verysmall ?? 4
            color: ColorUtils.transparentize(Appearance.colors.colPrimary, 0.85)
        }
    }

    Column {
        id: languageColumn
        width: root.width
        spacing: 2
        bottomPadding: 10

        Repeater {
            id: languageRepeater
            model: VoiceData.languages
            delegate: Column {
                id: language
                required property string modelData
                readonly property string lang: modelData
                readonly property bool open: root.isExpanded(language.lang)
                readonly property string chosenName: VoiceData.chosenVoice(language.lang)
                readonly property var chosenAccuracy: VoiceData.accuracyOf(VoiceData.voices.find(v => v.name === language.chosenName), language.lang)
                width: languageColumn.width

                RippleButton { // Language: name, its voice and accuracy; opens the list
                    width: parent.width
                    implicitHeight: 36
                    buttonRadius: Appearance.rounding.small
                    focusPolicy: Qt.NoFocus
                    onClicked: root.toggle(language.lang)
                    contentItem: Item {
                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 6
                            anchors.rightMargin: 10
                            spacing: 6
                            MaterialSymbol {
                                text: language.open ? "expand_more" : "chevron_right"
                                iconSize: Appearance.font.pixelSize.larger
                                color: Appearance.colors.colSubtext
                            }
                            SearchText {
                                value: root.languageLabel(language.lang)
                                color: Appearance.m3colors.m3onSurface
                                font.pixelSize: Appearance.font.pixelSize.normal
                            }
                            Rectangle { // The system language
                                visible: language.lang === VoiceData.systemLanguage
                                implicitWidth: systemText.implicitWidth + 12
                                implicitHeight: systemText.implicitHeight + 4
                                radius: Appearance.rounding.full
                                color: Appearance.colors.colSecondaryContainer
                                StyledText {
                                    id: systemText
                                    anchors.centerIn: parent
                                    text: Translation.tr("System")
                                    color: Appearance.m3colors.m3onSecondaryContainer
                                    font.pixelSize: Appearance.font.pixelSize.smaller
                                }
                            }
                            Item { Layout.fillWidth: true }
                            SearchText {
                                Layout.maximumWidth: 140
                                value: language.chosenName
                                color: Appearance.colors.colPrimary
                            }
                            SearchText {
                                Layout.preferredWidth: 38
                                horizontalAlignment: Text.AlignRight
                                value: root.percentText(language.chosenAccuracy)
                                color: root.percentColor(language.chosenAccuracy)
                            }
                        }
                    }
                }

                Loader { // Its voices: male and female, best first
                    active: language.open
                    visible: active
                    width: parent.width
                    sourceComponent: Column {
                        leftPadding: 28
                        bottomPadding: 6
                        Repeater {
                            model: [
                                { gender: "male", title: Translation.tr("Male") },
                                { gender: "female", title: Translation.tr("Female") },
                            ]
                            delegate: Column {
                                id: genderGroup
                                required property var modelData
                                width: language.width - 28
                                StyledText {
                                    text: genderGroup.modelData.title
                                    color: Appearance.colors.colPrimary
                                    font.pixelSize: Appearance.font.pixelSize.small
                                    font.weight: Font.DemiBold
                                    topPadding: 6
                                    bottomPadding: 2
                                }
                                Repeater {
                                    model: VoiceData.rankedVoices(language.lang, genderGroup.modelData.gender)
                                    delegate: Item { // A voice: the row chooses it, ▶ (beside it, not inside: it'd take the clicks) plays its clips
                                        id: voiceRow
                                        required property var modelData
                                        required property int index
                                        readonly property bool chosen: voiceRow.modelData.name === language.chosenName
                                        readonly property var accuracy: VoiceData.accuracyOf(voiceRow.modelData, language.lang)
                                        readonly property bool playing: root.playingKey === `${voiceRow.modelData.name}|${language.lang}`
                                        width: genderGroup.width
                                        implicitHeight: 28

                                        RippleButton { // Choose this voice
                                            anchors.left: parent.left
                                            anchors.right: playButton.left
                                            anchors.rightMargin: 2
                                            height: parent.height
                                            buttonRadius: Appearance.rounding.small
                                            focusPolicy: Qt.NoFocus
                                            colBackground: voiceRow.chosen ? ColorUtils.transparentize(Appearance.colors.colPrimary, 0.88)
                                                : ColorUtils.transparentize(Appearance.colors.colLayer1Hover, 1)
                                            onClicked: VoiceData.chooseVoice(language.lang, voiceRow.modelData.name)
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
                                                        Layout.preferredWidth: 20
                                                        text: voiceRow.index + 1
                                                        color: Appearance.colors.colSubtext
                                                        font.pixelSize: Appearance.font.pixelSize.small
                                                    }
                                                    SearchText {
                                                        Layout.fillWidth: true
                                                        value: voiceRow.modelData.name
                                                        color: voiceRow.chosen ? Appearance.colors.colPrimary : Appearance.m3colors.m3onSurface
                                                    }
                                                    SearchText {
                                                        Layout.preferredWidth: 38
                                                        horizontalAlignment: Text.AlignRight
                                                        value: root.percentText(voiceRow.accuracy)
                                                        color: root.percentColor(voiceRow.accuracy)
                                                    }
                                                }
                                            }
                                            StyledToolTip {
                                                text: voiceRow.chosen ? Translation.tr("Voice of %1").arg(root.languageLabel(language.lang))
                                                    : Translation.tr("Use this voice for %1").arg(root.languageLabel(language.lang))
                                            }
                                        }

                                        RippleButton { // Listen to its test clips in this language
                                            id: playButton
                                            anchors.right: parent.right
                                            anchors.verticalCenter: parent.verticalCenter
                                            implicitWidth: 28
                                            implicitHeight: 28
                                            buttonRadius: Appearance.rounding.full
                                            focusPolicy: Qt.NoFocus
                                            readonly property bool available: root.hasSamples(voiceRow.modelData.name, language.lang)
                                            opacity: available || !root.samplesScanned ? 1 : 0.35 // Dim: no test clips
                                            onClicked: if (available) root.playSamples(voiceRow.modelData.name, language.lang)
                                            contentItem: Item {
                                                MaterialSymbol {
                                                    anchors.centerIn: parent
                                                    text: voiceRow.playing ? "stop_circle" : "play_circle"
                                                    iconSize: Appearance.font.pixelSize.larger
                                                    color: Appearance.colors.colPrimary
                                                }
                                            }
                                            StyledToolTip {
                                                text: !playButton.available && root.samplesScanned
                                                    ? Translation.tr("No test clips found. Download them or make them yourself (%1)").arg("~/.local/share/voice-tests")
                                                    : voiceRow.playing ? Translation.tr("Stop")
                                                    : Translation.tr("Listen to the test clips in %1 (%2)").arg(root.languageLabel(language.lang))
                                                        .arg(Translation.tr("3 sentences + 2 words"))
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
}
