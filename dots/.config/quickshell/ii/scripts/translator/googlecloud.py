"""Google Cloud Text-to-Speech (API key in the keyring, passed as env GOOGLE_TTS_API_KEY).

Voice: the one chosen for the language in the widget (env GOOGLE_TTS_VOICES, JSON {"es": "es-US-Neural2-B"}), or else
the best voice of the language with the chosen gender (GOOGLE_TTS_GENDER: female|male) and quality
(GOOGLE_TTS_TIER: chirp3hd|neural2|wavenet|standard), falling back to the next quality / the other gender.
Standard library only (runs with the system python, like tts.py).
"""
import base64
import json
import os
import re
import time
import urllib.error
import urllib.parse
import urllib.request

API = "https://texttospeech.googleapis.com/v1"
CACHE = os.path.join(os.environ.get("XDG_CACHE_HOME") or os.path.expanduser("~/.cache"), "quickshell-ii", "google-tts-voices.json")
CACHE_SECONDS = 24 * 3600
TIERS = ["chirp3hd", "neural2", "wavenet", "standard"]  # Best first
MAX_REQUEST = 1500  # Characters per request (the API takes up to 5000 bytes)

# Language -> regional variant used when the text's language has no region (e.g. "es" -> Latin American Spanish)
PREFERRED_LOCALE = {
    "en": "en-US", "es": "es-US", "pt": "pt-BR", "fr": "fr-FR", "de": "de-DE", "it": "it-IT", "nl": "nl-NL",
    "zh": "cmn-CN", "ar": "ar-XA", "hi": "hi-IN", "ja": "ja-JP", "ko": "ko-KR", "ru": "ru-RU", "pl": "pl-PL",
    "tr": "tr-TR", "cs": "cs-CZ", "hu": "hu-HU",
}
# Google's language family -> the widget's language code
FAMILY = {"cmn": "zh", "yue": "zh", "fil": "tl", "nb": "no"}


class Error(RuntimeError):
    pass


def base_language(code):
    """"es-US" / "es" -> "es"; "cmn-CN" -> "zh"."""
    base = code.split("-")[0].lower()
    return FAMILY.get(base, base)


def tier_of(name):
    lower = name.lower()
    if "chirp3-hd" in lower or "chirp-hd" in lower:
        return "chirp3hd"
    for tier in ("neural2", "wavenet", "standard"):
        if tier in lower:
            return tier
    return "other"  # Studio, Polyglot, News...


def _request(url, data=None):
    request = urllib.request.Request(url, data=json.dumps(data).encode() if data is not None else None,
                                     headers={"Content-Type": "application/json"})
    try:
        with urllib.request.urlopen(request, timeout=30) as r:
            return json.loads(r.read().decode())
    except urllib.error.HTTPError as e:
        try:
            message = json.loads(e.read().decode()).get("error", {}).get("message", "")
        except ValueError:
            message = ""
        if e.code in (400, 403) and "API key not valid" in message:
            raise Error("Google Cloud TTS: the API key isn't valid. Check it in Settings")
        if e.code == 403 and ("has not been used" in message or "is disabled" in message):
            raise Error("Google Cloud TTS: enable the Cloud Text-to-Speech API for the project of your key "
                        "(console.cloud.google.com → APIs & Services → Library)")
        if e.code == 403 and "billing" in message.lower():
            raise Error("Google Cloud TTS: the project of your key needs billing enabled (it has a free monthly tier)")
        if e.code == 429:
            raise Error("Google Cloud TTS: too many requests or the quota is used up; try again later")
        raise Error(f"Google Cloud TTS: {message or f'error {e.code}'}")
    except OSError as e:
        raise Error(f"Google Cloud TTS: no connection ({getattr(e, 'reason', e)})")


def list_voices(key, refresh=False):
    """[{name, locale, lang, gender, tier}], cached for a day (the list doesn't depend on the key)."""
    if not refresh:
        try:
            if time.time() - os.path.getmtime(CACHE) < CACHE_SECONDS:
                return json.load(open(CACHE))
        except (OSError, ValueError):
            pass
    if not key:
        raise Error("Google Cloud TTS: add your API key in Settings")
    data = _request(f"{API}/voices?" + urllib.parse.urlencode({"key": key}))
    voices = []
    for v in data.get("voices", []):
        locale = (v.get("languageCodes") or [""])[0]
        voices.append({"name": v["name"], "locale": locale, "lang": base_language(locale),
                       "gender": (v.get("ssmlGender") or "").lower(), "tier": tier_of(v["name"])})
    voices.sort(key=lambda v: (v["lang"], v["locale"], TIERS.index(v["tier"]) if v["tier"] in TIERS else 9, v["name"]))
    os.makedirs(os.path.dirname(CACHE), exist_ok=True)
    json.dump(voices, open(CACHE, "w"))
    return voices


def settings():
    try:
        chosen = json.loads(os.environ.get("GOOGLE_TTS_VOICES") or "{}")
    except ValueError:
        chosen = {}
    gender = (os.environ.get("GOOGLE_TTS_GENDER") or "female").lower()
    tier = (os.environ.get("GOOGLE_TTS_TIER") or "neural2").lower()
    return (chosen if isinstance(chosen, dict) else {}), gender, tier


def pick_voice(voices, code):
    """Voice for a language code ("es", "pt-PT", "zh-CN"...), or None when Google Cloud doesn't speak it."""
    chosen, gender, tier = settings()
    lang = base_language(code)
    named = chosen.get(lang)
    if named:
        for v in voices:
            if v["name"] == named:
                return v
    candidates = [v for v in voices if v["lang"] == lang]
    if not candidates:
        return None
    # The text's region if it has one (pt-PT), else the preferred one for the language
    wanted_locale = code if "-" in code and lang != "zh" else PREFERRED_LOCALE.get(lang, "")
    order = [tier] + [t for t in TIERS if t != tier]

    explicit_region = "-" in code and lang != "zh"  # "pt-PT": the region matters more than the quality

    def score(v):
        tier_rank = order.index(v["tier"]) if v["tier"] in order else len(order)
        other_locale = v["locale"].lower() != wanted_locale.lower()
        return (v["gender"] != gender, *((other_locale, tier_rank) if explicit_region else (tier_rank, other_locale)), v["name"])
    return min(candidates, key=score)


def split(text):
    """Pieces of up to MAX_REQUEST characters, cut at sentence ends when possible."""
    parts, current = [], ""
    for sentence in re.split(r"(?<=[.!?…。！？])\s+", text.strip()):
        while len(sentence) > MAX_REQUEST:
            cut = sentence.rfind(" ", 0, MAX_REQUEST)
            cut = cut if cut > 0 else MAX_REQUEST
            parts.append(sentence[:cut])
            sentence = sentence[cut:].strip()
        if current and len(current) + len(sentence) + 1 > MAX_REQUEST:
            parts.append(current)
            current = ""
        current = f"{current} {sentence}".strip()
    if current:
        parts.append(current)
    return parts


def synthesize(key, code, text):
    """Yields MP3 audio (bytes) piece by piece, so playback can start with the first one."""
    if not key:
        raise Error("Google Cloud TTS: add your API key in Settings")
    voice = pick_voice(list_voices(key), code)
    if voice is None:
        raise Error(f"Google Cloud TTS doesn't speak this language ({code}). Choose another voice in Settings")
    for part in split(text):
        data = _request(f"{API}/text:synthesize?" + urllib.parse.urlencode({"key": key}), {
            "input": {"text": part},
            "voice": {"languageCode": voice["locale"], "name": voice["name"]},
            "audioConfig": {"audioEncoding": "MP3"},
        })
        yield base64.b64decode(data.get("audioContent", ""))
