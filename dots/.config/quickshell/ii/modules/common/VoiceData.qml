pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell

/**
 * The built-in XTTS-v2 voices (speakers_xtts.pth), shared by the "Voices" and "Accuracy" tabs of VoiceStatsDialog.
 * gender: by Coqui's grouping, checked with the pitch of a test sentence.
 * pitch: median pitch (Hz) of that sentence.
 * woman / man / child: probability (%) and age: estimated age (years), by ageGenderModel (mean of 3 test sentences).
 * accuracy: percentage of what was said that Whisper large-v3 understood, per language (order of `languages`):
 *           mean of 3 sentences + 2 single words. total: sum of the 17 percentages / 100 (max 17).
 */
Singleton {
    id: root

    // The 17 languages of XTTS-v2
    readonly property var languages: ["es", "en", "de", "fr", "it", "pt", "ru", "ja", "zh", "ko", "ar", "hi", "tr", "nl", "pl", "cs", "hu"]
    readonly property var languageNames: ({
        es: "Spanish", en: "English", de: "German", fr: "French", it: "Italian", pt: "Portuguese", ru: "Russian", ja: "Japanese",
        zh: "Chinese", ko: "Korean", ar: "Arabic", hi: "Hindi", tr: "Turkish", nl: "Dutch", pl: "Polish", cs: "Czech", hu: "Hungarian",
    })

    // A short sentence per language, to test voices (the first test sentence)
    readonly property var sampleTexts: ({
        es: "Buenos días, ¿cómo estás hoy?", en: "Good morning, how are you today?", de: "Guten Morgen, wie geht es dir heute?",
        fr: "Bonjour, comment vas-tu aujourd'hui ?", it: "Buongiorno, come stai oggi?", pt: "Bom dia, como você está hoje?",
        ru: "Доброе утро, как ты сегодня?", ja: "おはようございます、今日はお元気ですか？", zh: "早上好，你今天好吗？",
        ko: "좋은 아침이에요, 오늘 어떠세요?", ar: "صباح الخير، كيف حالك اليوم؟", hi: "सुप्रभात, आज आप कैसे हैं?",
        tr: "Günaydın, bugün nasılsın?", nl: "Goedemorgen, hoe gaat het vandaag met je?", pl: "Dzień dobry, jak się dzisiaj masz?",
        cs: "Dobré ráno, jak se dnes máš?", hu: "Jó reggelt, hogy vagy ma?",
    })

    // ---- Voice chosen per language ("Choose" tab), saved in Config (xttsVoices) and used by xtts.py ----
    readonly property string defaultVoice: "Zacharie Aimilios" // xtts.py SPEAKER: only when a language has no ranked voice
    // Voice of a language without a choice: its #1 female voice (best accuracy in that language)
    function defaultVoiceFor(lang) {
        return root.rankedVoices(lang, "female")[0]?.name ?? root.defaultVoice;
    }
    readonly property var chosenVoices: {
        try {
            const map = JSON.parse(Config.options.language.translator.xttsVoices || "{}");
            return map && typeof map === "object" ? map : {};
        } catch (e) {
            return {};
        }
    }
    function chosenVoice(lang) {
        const name = root.chosenVoices[lang];
        return root.voices.some(v => v.name === name) ? name : root.defaultVoiceFor(lang);
    }
    // Voice of every language (chosen or default), for xtts.py (env XTTS_VOICES)
    // (Qt's JS engine has no Object.fromEntries)
    readonly property string effectiveVoicesJson: JSON.stringify(root.languages.reduce((map, lang) => {
        map[lang] = root.chosenVoice(lang);
        return map;
    }, {}))
    function chooseVoice(lang, name) {
        const map = Object.assign({}, root.chosenVoices);
        if (name === root.defaultVoiceFor(lang)) delete map[lang]; // The default: no choice
        else map[lang] = name;
        Config.options.language.translator.xttsVoices = JSON.stringify(map);
    }
    // Language of the system (UI) as an XTTS-v2 language, "en" when XTTS-v2 doesn't speak it
    readonly property string systemLanguage: {
        const ui = Config.options.language.ui ?? "auto";
        const code = (ui !== "auto" ? ui : Qt.locale().name).split(/[_-]/)[0].toLowerCase();
        return root.languages.includes(code) ? code : "en";
    }
    // Test clips of the accuracy test (~/.local/share/voice-tests/audio/<voice>/<lang>_<0-4>.flac): 3 sentences + 2 words
    readonly property string samplesDir: "$HOME/.local/share/voice-tests/audio"
    readonly property int samplesPerLanguage: 5

    // Accuracy (%) of a voice in a language, or null
    function accuracyOf(voice, lang) {
        return voice?.accuracy?.[root.languages.indexOf(lang)] ?? null;
    }
    // Voices of a gender, best first in a language
    function rankedVoices(lang, gender) {
        return root.voices.filter(v => v.gender === gender)
            .sort((a, b) => (root.accuracyOf(b, lang) ?? -1) - (root.accuracyOf(a, lang) ?? -1) || a.name.localeCompare(b.name));
    }

    // Model used for the accuracy test (what was understood, per language)
    readonly property string accuracyModel: "Whisper large-v3"
    readonly property string accuracyTestedOn: "2026-11-20"
    // Every model of the accuracy test and what for (the table shows Whisper; the rest is in xtts_voice_tests.xlsx)
    readonly property var accuracyModels: [
        { name: "XTTS-v2", use: "generated the audio of every voice" },
        { name: root.accuracyModel, use: "transcribed the audio: the percentages of this table" },
        { name: "MMS-1b-all (Meta)", use: "second transcription, to tell XTTS errors from recognizer errors" },
        { name: "wav2vec2-lv-60-espeak-cv-ft", use: "phonemes heard, useful for single words" },
        { name: "UTMOS22", use: "naturalness of the voice (1-5)" },
    ]

    // Mean accuracy of each language over the tested voices; the weakest ones, worst first
    function weakestLanguages(count) {
        const tested = root.voices.filter(v => v.accuracy);
        if (tested.length === 0) return [];
        return root.languages.map((lang, i) => ({ lang, mean: tested.reduce((sum, v) => sum + (v.accuracy[i] ?? 0), 0) / tested.length }))
            .sort((a, b) => a.mean - b.mean).slice(0, count).map(l => l.lang);
    }

    // Model used for the woman / man / child and age test
    readonly property string ageGenderModel: "audeering/wav2vec2-large-robust-24-ft-age-gender"


    readonly property var voices: [
        { name: "Zacharie Aimilios", gender: "male", pitch: 113, woman: 0, man: 100, child: 0, age: 26, total: 15.06, accuracy: [100, 97, 100, 80, 100, 98, 96, 99, 100, 60, 97, 60, 97, 77, 80, 96, 70] },
        { name: "Gilberto Mathias", gender: "male", pitch: 120, woman: 1, man: 99, child: 0, age: 42, total: 15.11, accuracy: [100, 100, 94, 80, 100, 100, 96, 99, 100, 43, 56, 73, 93, 100, 100, 97, 80] },
        { name: "Ilkin Urbano", gender: "male", pitch: 104, woman: 0, man: 100, child: 0, age: 35, total: 14.58, accuracy: [100, 100, 71, 80, 100, 98, 96, 90, 100, 60, 80, 40, 97, 100, 100, 80, 66] },
        { name: "Viktor Eka", gender: "male", pitch: 147, woman: 0, man: 100, child: 0, age: 52, total: 14.16, accuracy: [100, 80, 100, 80, 100, 100, 96, 88, 80, 80, 73, 49, 97, 100, 100, 57, 36] },
        { name: "Adde Michal", gender: "male", pitch: 106, woman: 0, man: 100, child: 0, age: 29, total: 14.83, accuracy: [100, 100, 86, 80, 100, 100, 96, 99, 100, 60, 77, 70, 97, 60, 100, 86, 73] },
        { name: "Kazuhiko Atallah", gender: "male", pitch: 124, woman: 1, man: 99, child: 0, age: 28, total: 15.71, accuracy: [100, 100, 100, 80, 100, 100, 96, 89, 100, 80, 77, 57, 97, 100, 100, 96, 100] },
        { name: "Aaron Dreschner", gender: "male", pitch: 93, woman: 0, man: 100, child: 0, age: 38, total: 14.48, accuracy: [100, 100, 97, 80, 100, 100, 96, 99, 100, 49, 56, 53, 100, 100, 53, 93, 72] },
        { name: "Abrahan Mack", gender: "male", pitch: 101, woman: 0, man: 100, child: 0, age: 34, total: 15.23, accuracy: [100, 100, 97, 80, 100, 100, 96, 99, 100, 49, 73, 57, 97, 100, 100, 96, 80] },
        { name: "Andrew Chipper", gender: "male", pitch: 230, woman: 27, man: 1, child: 72, age: 21, total: 15.12, accuracy: [100, 100, 97, 80, 100, 100, 96, 99, 100, 80, 77, 77, 97, 80, 100, 72, 58] },
        { name: "Baldur Sanjin", gender: "male", pitch: 94, woman: 0, man: 100, child: 0, age: 41, total: 15.02, accuracy: [100, 100, 97, 80, 100, 100, 96, 100, 100, 57, 57, 39, 97, 100, 100, 100, 80] },
        { name: "Craig Gutsy", gender: "male", pitch: 186, woman: 2, man: 98, child: 0, age: 40, total: 14.40, accuracy: [100, 100, 80, 80, 100, 100, 96, 99, 100, 80, 77, 49, 97, 100, 57, 76, 50] },
        { name: "Damien Black", gender: "male", pitch: 76, woman: 0, man: 99, child: 0, age: 48, total: 14.24, accuracy: [100, 100, 100, 80, 80, 100, 96, 99, 90, 80, 57, 49, 73, 80, 100, 80, 60] },
        { name: "Damjan Chapman", gender: "male", pitch: 106, woman: 0, man: 100, child: 0, age: 31, total: 14.39, accuracy: [100, 100, 100, 80, 80, 100, 96, 79, 98, 40, 77, 57, 97, 80, 93, 89, 75] },
        { name: "Dionisio Schuyler", gender: "male", pitch: 90, woman: 0, man: 100, child: 0, age: 43, total: 14.75, accuracy: [100, 100, 97, 80, 100, 100, 96, 90, 100, 60, 80, 60, 93, 97, 73, 69, 80] },
        { name: "Eugenio Mataracı", gender: "male", pitch: 99, woman: 1, man: 99, child: 0, age: 36, total: 14.23, accuracy: [100, 80, 91, 100, 100, 98, 96, 99, 80, 40, 77, 57, 97, 80, 70, 64, 95] },
        { name: "Ferran Simen", gender: "male", pitch: 104, woman: 0, man: 100, child: 0, age: 47, total: 14.12, accuracy: [100, 91, 69, 80, 80, 100, 96, 99, 100, 60, 80, 57, 97, 100, 87, 76, 41] },
        { name: "Filip Traverse", gender: "male", pitch: 99, woman: 3, man: 97, child: 0, age: 33, total: 14.48, accuracy: [100, 100, 74, 80, 100, 100, 96, 99, 100, 43, 57, 60, 93, 100, 100, 76, 70] },
        { name: "Ige Behringer", gender: "male", pitch: 117, woman: 0, man: 100, child: 0, age: 26, total: 13.93, accuracy: [100, 90, 63, 80, 100, 100, 96, 80, 100, 45, 80, 45, 97, 80, 100, 73, 65] },
        { name: "Kumar Dahl", gender: "male", pitch: 83, woman: 4, man: 95, child: 1, age: 30, total: 14.46, accuracy: [100, 100, 80, 80, 100, 100, 96, 99, 100, 38, 77, 57, 93, 100, 88, 69, 70] },
        { name: "Ludvig Milivoj", gender: "male", pitch: 118, woman: 0, man: 100, child: 0, age: 37, total: 15.33, accuracy: [100, 100, 86, 80, 100, 100, 96, 99, 80, 80, 77, 80, 97, 100, 93, 66, 100] },
        { name: "Luis Moray", gender: "male", pitch: 94, woman: 0, man: 100, child: 0, age: 41, total: 13.82, accuracy: [100, 80, 100, 80, 80, 100, 96, 99, 100, 60, 53, 57, 77, 100, 80, 76, 45] },
        { name: "Marcos Rudaski", gender: "male", pitch: 127, woman: 0, man: 100, child: 0, age: 37, total: 15.04, accuracy: [100, 100, 100, 80, 100, 100, 96, 99, 100, 64, 72, 60, 97, 100, 93, 73, 70] },
        { name: "Royston Min", gender: "male", pitch: 106, woman: 0, man: 99, child: 0, age: 34, total: 14.89, accuracy: [100, 100, 100, 76, 100, 100, 96, 99, 100, 51, 80, 53, 97, 100, 100, 80, 57] },
        { name: "Torcull Diarmuid", gender: "male", pitch: 126, woman: 0, man: 100, child: 0, age: 54, total: 14.11, accuracy: [100, 100, 97, 80, 100, 100, 96, 89, 80, 63, 77, 49, 77, 100, 57, 96, 50] },
        { name: "Viktor Menelaos", gender: "male", pitch: 119, woman: 0, man: 100, child: 0, age: 38, total: 14.62, accuracy: [100, 100, 77, 80, 100, 100, 96, 95, 100, 60, 69, 67, 100, 100, 93, 73, 52] },
        { name: "Wulf Carlevaro", gender: "male", pitch: 107, woman: 1, man: 99, child: 0, age: 29, total: 15.28, accuracy: [100, 100, 100, 80, 100, 100, 96, 79, 100, 80, 97, 60, 97, 100, 93, 77, 70] },
        { name: "Xavier Hayasaka", gender: "male", pitch: 106, woman: 1, man: 98, child: 1, age: 28, total: 14.52, accuracy: [100, 95, 74, 80, 100, 100, 96, 99, 100, 35, 77, 57, 97, 80, 73, 100, 90] },

        { name: "Daisy Studious", gender: "female", pitch: 244, woman: 57, man: 1, child: 42, age: 23, total: 13.61, accuracy: [100, 100, 77, 80, 100, 100, 96, 79, 100, 60, 48, 49, 93, 80, 80, 64, 55] },
        { name: "Ana Florence", gender: "female", pitch: 144, woman: 99, man: 1, child: 0, age: 43, total: 14.42, accuracy: [100, 100, 69, 80, 100, 100, 96, 99, 100, 13, 97, 39, 97, 100, 80, 93, 80] },
        { name: "Alexandra Hisakawa", gender: "female", pitch: 194, woman: 100, man: 0, child: 0, age: 39, total: 14.28, accuracy: [100, 100, 63, 80, 100, 98, 96, 99, 100, 60, 57, 89, 90, 80, 67, 80, 70] },
        { name: "Alison Dietlinde", gender: "female", pitch: 229, woman: 99, man: 1, child: 0, age: 34, total: 14.37, accuracy: [100, 100, 97, 80, 100, 100, 93, 89, 100, 60, 77, 51, 97, 80, 57, 82, 75] },
        { name: "Alma María", gender: "female", pitch: 215, woman: 99, man: 1, child: 0, age: 34, total: 14.31, accuracy: [100, 80, 83, 80, 100, 100, 96, 96, 100, 52, 77, 41, 100, 100, 60, 96, 70] },
        { name: "Annmarie Nele", gender: "female", pitch: 192, woman: 99, man: 0, child: 0, age: 34, total: 15.02, accuracy: [100, 100, 74, 100, 80, 98, 96, 99, 100, 70, 73, 76, 97, 80, 93, 97, 70] },
        { name: "Asya Anara", gender: "female", pitch: 159, woman: 100, man: 0, child: 0, age: 42, total: 15.00, accuracy: [100, 100, 80, 80, 100, 100, 100, 99, 100, 58, 77, 46, 93, 97, 100, 100, 70] },
        { name: "Badr Odhiambo", gender: "female", pitch: 230, woman: 98, man: 1, child: 1, age: 31, total: 14.47, accuracy: [100, 80, 94, 80, 100, 100, 96, 89, 100, 69, 77, 73, 97, 80, 80, 93, 40] },
        { name: "Barbora MacLean", gender: "female", pitch: 224, woman: 99, man: 1, child: 1, age: 29, total: 14.57, accuracy: [100, 100, 97, 80, 100, 98, 96, 79, 100, 57, 52, 60, 97, 100, 100, 77, 66] },
        { name: "Brenda Stern", gender: "female", pitch: 223, woman: 98, man: 1, child: 1, age: 32, total: 13.82, accuracy: [100, 97, 54, 80, 80, 100, 96, 99, 90, 70, 60, 53, 100, 80, 100, 57, 66] },
        { name: "Camilla Holmström", gender: "female", pitch: 220, woman: 99, man: 1, child: 1, age: 32, total: 13.78, accuracy: [100, 80, 77, 80, 100, 100, 96, 99, 90, 60, 77, 49, 77, 80, 48, 96, 70] },
        { name: "Chandra MacFarland", gender: "female", pitch: 221, woman: 99, man: 1, child: 1, age: 30, total: 14.90, accuracy: [100, 100, 86, 77, 100, 98, 96, 99, 100, 60, 73, 73, 97, 80, 77, 96, 80] },
        { name: "Claribel Dervla", gender: "female", pitch: 128, woman: 98, man: 2, child: 0, age: 41, total: 14.39, accuracy: [100, 100, 100, 80, 100, 98, 100, 99, 80, 20, 77, 49, 97, 100, 100, 60, 80] },
        { name: "Gitta Nikolina", gender: "female", pitch: 195, woman: 99, man: 0, child: 0, age: 37, total: 14.60, accuracy: [100, 100, 69, 100, 100, 97, 96, 95, 100, 49, 89, 46, 77, 80, 100, 93, 70] },
        { name: "Gracie Wise", gender: "female", pitch: 201, woman: 99, man: 1, child: 0, age: 39, total: 15.05, accuracy: [100, 89, 97, 80, 100, 98, 96, 99, 100, 100, 80, 48, 100, 100, 93, 76, 50] },
        { name: "Henriette Usha", gender: "female", pitch: 199, woman: 100, man: 0, child: 0, age: 45, total: 14.55, accuracy: [100, 100, 100, 80, 100, 100, 100, 79, 100, 78, 73, 47, 57, 100, 77, 90, 75] },
        { name: "Lidiya Szekeres", gender: "female", pitch: 193, woman: 100, man: 0, child: 0, age: 39, total: 14.00, accuracy: [97, 89, 77, 80, 100, 100, 96, 96, 90, 80, 49, 57, 97, 100, 60, 73, 60] },
        { name: "Lilya Stainthorpe", gender: "female", pitch: 194, woman: 99, man: 1, child: 0, age: 36, total: 14.96, accuracy: [100, 100, 97, 80, 100, 100, 96, 100, 80, 73, 80, 47, 97, 100, 77, 100, 70] },
        { name: "Maja Ruoho", gender: "female", pitch: 230, woman: 96, man: 1, child: 3, age: 26, total: 14.66, accuracy: [100, 100, 100, 80, 100, 100, 96, 97, 100, 40, 80, 57, 93, 77, 100, 76, 70] },
        { name: "Narelle Moon", gender: "female", pitch: 197, woman: 99, man: 1, child: 1, age: 29, total: 14.18, accuracy: [100, 97, 80, 80, 100, 98, 96, 96, 90, 60, 80, 10, 97, 80, 80, 100, 75] },
        { name: "Nova Hogarth", gender: "female", pitch: 177, woman: 100, man: 0, child: 0, age: 39, total: 13.94, accuracy: [100, 86, 80, 80, 100, 100, 96, 99, 100, 35, 57, 29, 97, 80, 100, 76, 80] },
        { name: "Rosemary Okafor", gender: "female", pitch: 228, woman: 99, man: 1, child: 1, age: 28, total: 14.92, accuracy: [100, 100, 100, 80, 100, 100, 96, 100, 100, 55, 73, 60, 97, 80, 77, 100, 75] },
        { name: "Sofia Hellen", gender: "female", pitch: 157, woman: 99, man: 0, child: 0, age: 36, total: 14.91, accuracy: [100, 100, 97, 80, 100, 98, 100, 99, 100, 31, 77, 52, 97, 80, 94, 93, 95] },
        { name: "Suad Qasim", gender: "female", pitch: 192, woman: 99, man: 0, child: 0, age: 32, total: 14.54, accuracy: [100, 100, 94, 60, 100, 100, 96, 99, 100, 22, 77, 49, 97, 100, 93, 93, 75] },
        { name: "Szofi Granger", gender: "female", pitch: 220, woman: 99, man: 0, child: 0, age: 39, total: 14.47, accuracy: [100, 77, 97, 80, 100, 100, 96, 99, 100, 49, 77, 60, 97, 77, 91, 90, 58] },
        { name: "Tammie Ema", gender: "female", pitch: 181, woman: 99, man: 1, child: 0, age: 36, total: 14.25, accuracy: [100, 80, 80, 80, 100, 100, 96, 95, 90, 52, 73, 56, 97, 97, 100, 77, 53] },
        { name: "Tammy Grit", gender: "female", pitch: 144, woman: 99, man: 1, child: 0, age: 35, total: 15.28, accuracy: [100, 100, 100, 80, 100, 100, 100, 100, 100, 56, 97, 49, 97, 100, 100, 100, 50] },
        { name: "Tanja Adelina", gender: "female", pitch: 181, woman: 100, man: 0, child: 0, age: 50, total: 14.57, accuracy: [100, 100, 100, 80, 100, 100, 96, 99, 100, 40, 77, 53, 73, 100, 80, 97, 63] },
        { name: "Uta Obando", gender: "female", pitch: 237, woman: 99, man: 1, child: 1, age: 32, total: 15.38, accuracy: [100, 100, 97, 80, 100, 100, 96, 99, 100, 60, 77, 97, 97, 77, 93, 96, 70] },
        { name: "Vjollca Johnnie", gender: "female", pitch: 174, woman: 100, man: 0, child: 0, age: 36, total: 14.47, accuracy: [100, 100, 100, 80, 100, 100, 96, 80, 100, 35, 77, 60, 97, 100, 79, 100, 43] },
        { name: "Zofija Kendrick", gender: "female", pitch: 220, woman: 99, man: 1, child: 1, age: 25, total: 14.44, accuracy: [100, 97, 77, 80, 100, 100, 100, 99, 100, 60, 77, 53, 77, 80, 74, 100, 70] },
    ]

    readonly property var maleVoices: root.voices.filter(v => v.gender === "male")
    readonly property var femaleVoices: root.voices.filter(v => v.gender === "female")

    // Pitch range of each group ("76 ~ 230"), computed from the voices: updates when a voice changes group
    function pitchRange(voices) {
        const pitches = voices.map(v => v.pitch);
        return pitches.length > 0 ? `${Math.min(...pitches)} ~ ${Math.max(...pitches)}` : "–";
    }
    readonly property var decision: ({ male: root.pitchRange(root.maleVoices), female: root.pitchRange(root.femaleVoices) })
}
