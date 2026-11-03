import qs.modules.common
import qs.modules.common.widgets
import qs.services
import QtQuick

// "Accuracy" tab of VoiceStatsDialog: what Whisper understood per language, only the tested voices (best first)
VoiceTable {
    id: root

    readonly property string infoText: "" // Always visible
    // Behind "Details" (collapsed by default)
    readonly property string detailsText: [
        Translation.tr("Tested: %1 voices × %2 languages, 3 sentences + 2 single words each.")
            .arg(VoiceData.voices.filter(v => v.accuracy).length).arg(VoiceData.languages.length),
        Translation.tr("% = words understood (characters in ja/ko, syllables in zh)."),
        Translation.tr("Total = sum of the %1 percentages / 100 (max %1).").arg(VoiceData.languages.length),
        Translation.tr("Weakest languages: %1.").arg(VoiceData.weakestLanguages(4).join(", ")),
        Translation.tr("Colors: red < 75%, gray 75–89%, normal ≥ 90%."),
        Translation.tr("Tested on: %1.").arg(VoiceData.accuracyTestedOn),
        "",
        Translation.tr("Models used for the test:"),
        ...VoiceData.accuracyModels.map(m => `• ${m.name}: ${Translation.tr(m.use)}.`),
    ].join("\n")

    function rowsOf(voices) {
        return voices.filter(v => v.accuracy)
            .sort((a, b) => b.total - a.total)
            .map(v => [v.name, ...VoiceData.languages.map((_, i) => v.accuracy[i] ?? "–"), v.total.toFixed(2)]);
    }

    columns: [
        { title: Translation.tr("Voice"), width: 128, role: "name" },
        ...VoiceData.languages.map(lang => ({ title: lang, width: 30, role: "value" })),
        { title: Translation.tr("Total"), width: 46, role: "total" },
    ]
    sections: [
        { title: Translation.tr("Male"), rows: root.rowsOf(VoiceData.maleVoices) },
        { title: Translation.tr("Female"), rows: root.rowsOf(VoiceData.femaleVoices) },
    ]
}
