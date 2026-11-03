import qs.modules.common
import qs.modules.common.widgets
import qs.services
import QtQuick

// "Voices" tab of VoiceStatsDialog: every XTTS-v2 voice, categorized (pitch, woman/man/child, age)
VoiceTable {
    id: root

    readonly property string infoText: "" // Always visible
    // Behind "Details" (collapsed by default)
    readonly property string detailsText: Translation.tr("Total voices: %1").arg(VoiceData.voices.length)
        + "\n" + Translation.tr("Total of male voices: %1").arg(VoiceData.maleVoices.length)
        + "\n" + Translation.tr("Total of female voices: %1").arg(VoiceData.femaleVoices.length)
        + "\n\n" + Translation.tr("Approximate ranges. For informational purposes only. Pitch alone is no longer sufficient to determine gender.")
        + "\n" + Translation.tr("Male pitch: %1 Hz.").arg(VoiceData.decision.male)
        + "\n" + Translation.tr("Female pitch: %1 Hz.").arg(VoiceData.decision.female)
        + "\n\n" + Translation.tr("Model used for the test: %1").arg(VoiceData.ageGenderModel)

    function rowsOf(voices) {
        // Woman / man / child: probability (%) from the age/gender model; "–" when not measured
        const percent = value => value === undefined ? "–" : `${value}%`;
        return voices.map(v => [v.name, `${v.pitch} Hz`, percent(v.woman), percent(v.man), percent(v.child),
            v.age === undefined ? "–" : Translation.tr("%1 years").arg(v.age)]);
    }

    columns: [
        { title: Translation.tr("Voice"), width: 128, role: "name" },
        { title: Translation.tr("Pitch"), width: 56, role: "sub" },
        { title: Translation.tr("Woman"), width: 52, role: "sub" },
        { title: Translation.tr("Man"), width: 44, role: "sub" },
        { title: Translation.tr("Child"), width: 44, role: "sub" },
        { title: Translation.tr("Estimated age"), width: 92, role: "sub" },
    ]
    sections: [
        { title: Translation.tr("Male"), rows: root.rowsOf(VoiceData.maleVoices) },
        { title: Translation.tr("Female"), rows: root.rowsOf(VoiceData.femaleVoices) },
    ]
}
