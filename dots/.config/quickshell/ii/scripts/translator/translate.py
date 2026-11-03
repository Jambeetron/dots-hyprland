#!/usr/bin/env python3
"""Translate text and print one JSON line for the sidebar translator.

Usage: translate.py <classic|advanced|offline> <source lang> <target lang> <text> [--no-autocorrect]

classic : Google Translate via translate-shell (`trans -dump`), with spelling
          suggestion, phonetics and dictionary.
advanced: Gemini API (key in env GEMINI_API_KEY, model in env GEMINI_MODEL).
offline : NLLB-200 3.3B on the GPU (nllb.py), downloaded model. Only when chosen: when
          classic/advanced fail, the error says why (e.g. no internet connection).

Output: {"translation", "source", "correction": {"html","plain"} | null,
         "phonetic", "translationPhonetic", "dictionary": [...],
         "gender": [{"gender": "feminine"|"masculine", "text"}],
         "lemma", "definitions": [{"pos", "items": [{"text", "example", "labels", "synonyms": [{"label", "words"}]}]}],
         "examples": [html], "related": ["see also" words], "error"}
"""
import json
import os
import re
import subprocess
import sys
import urllib.error
import urllib.request


def parse_dump(raw: str):
    start = raw.find("[")
    if start < 0:
        raise ValueError(raw.strip()[:200] or "Empty response")
    # translate-shell may print chunked transfer sizes around the JSON
    data, _ = json.JSONDecoder().raw_decode(raw[start:])
    return data


def language_names(code):
    """English name and endonym of a language code, from translate-shell."""
    try:
        out = subprocess.run(["trans", "-list-all", "-no-ansi"], capture_output=True, text=True, timeout=10).stdout
    except Exception:
        return []
    for line in out.splitlines():
        parts = [p.strip() for p in re.split(r"\s{2,}", line.strip()) if p.strip()]
        if len(parts) >= 2 and parts[0] == code:
            return parts[1:]
    return []


def source_suggestion(data, source):
    """Google's "Translate from: X" when the text looks like another language than the selected one."""
    if source.lower() == "auto":
        return None
    detected = get(data, 8)
    code = detected[0][0] if detected and detected[0] else None
    if not code:
        return None
    sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
    from tts import resolve_code
    if resolve_code(source).split("-")[0].lower() == code.split("-")[0].lower():
        return None
    names = language_names(code)
    return {"code": code, "names": names, "name": names[0] if names else code} if names else None


def frequency(score):
    return 3 if score >= 0.1 else 2 if score >= 0.01 else 1


def get(data, i):
    return data[i] if len(data) > i and data[i] else None


def classic(source, target, text, autocorrect):
    cmd = ["trans", "-4", "-no-ansi", "-dump", "-s", source, "-t", target]
    if not autocorrect:
        cmd.append("-no-autocorrect")
    out = subprocess.run(cmd + [text], capture_output=True, text=True, timeout=20)
    data = parse_dump(out.stdout)

    sentences = data[0] or []
    translation = "".join(s[0] for s in sentences if s and s[0])
    source_text = "".join(s[1] for s in sentences if s and len(s) > 1 and s[0] and s[1])
    phonetic, translation_phonetic = "", ""
    for s in sentences:
        if s and s[0] is None and len(s) > 2:
            translation_phonetic = s[2] or ""
            phonetic = s[3] if len(s) > 3 and s[3] else ""

    dictionary = []
    for entry in data[1] or []:
        pos, words = entry[0], []
        for w in entry[2] or []:
            words.append({
                "word": w[0],
                "back": w[1] or [],
                "article": w[4] if len(w) > 4 and w[4] else "",
                "score": w[3] if len(w) > 3 and w[3] else 0,
                "frequency": frequency(w[3] if len(w) > 3 and w[3] else 0),
            })
        dictionary.append({"pos": pos, "words": words})

    correction = None
    if len(data) > 7 and data[7] and data[7][1] and data[7][1].strip() != text.strip():
        html = re.sub(r"</?b>", "", data[7][0])
        correction = {"html": html, "plain": data[7][1]}

    gender = []
    g = get(data, 18)
    if g and g[0]:
        names = {1: "masculine", 2: "feminine"}
        for kind, alt in sorted(g[0], key=lambda x: -x[0]):  # feminine first, like Google
            gender.append({"gender": names.get(kind, ""), "text": alt})

    synonyms = {}  # definition id -> [{"label", "words"}], unlabeled groups first
    for pos_entry in get(data, 11) or []:
        for group in pos_entry[1] or []:
            if len(group) > 1 and group[1]:
                label = ", ".join(l[0] for l in group[2] if l) if len(group) > 2 and group[2] else ""
                synonyms.setdefault(group[1], []).append({"label": label, "words": group[0] or []})
    for groups in synonyms.values():
        groups.sort(key=lambda g: g["label"] != "")

    definitions, lemma = [], ""
    for pos_entry in get(data, 12) or []:
        items = []
        for d in pos_entry[1] or []:
            labels = []
            if len(d) > 3 and d[3] and len(d[3]) > 2 and d[3][2]:
                labels = d[3][2]
            items.append({
                "text": d[0],
                "example": d[2] if len(d) > 2 and d[2] else "",
                "labels": labels,
                "synonyms": synonyms.get(d[1], []) if len(d) > 1 else [],
            })
        definitions.append({"pos": pos_entry[0], "items": items})
        lemma = lemma or (pos_entry[2] if len(pos_entry) > 2 else "")

    examples = [e[0] for e in ((get(data, 13) or [[]])[0] or []) if e and e[0]]
    if not lemma and (data[1] or []):
        lemma = data[1][0][3] if len(data[1][0]) > 3 else ""

    return {
        "translation": translation,
        "gender": gender,
        "lemma": lemma or source_text or text,
        "definitions": definitions,
        "examples": examples,
        "sourceSuggestion": source_suggestion(data, source),
        "related": [w for w in ((get(data, 14) or [[]])[0] or []) if w],
        "source": source_text,
        "detected": data[2] if len(data) > 2 else "",
        "correction": correction,
        "phonetic": phonetic,
        "translationPhonetic": translation_phonetic,
        "dictionary": dictionary,
    }


def advanced(source, target, text):
    key = os.environ.get("GEMINI_API_KEY", "")
    if not key:
        return {"error": "Advanced needs a Gemini API key. Set it in the Intelligence tab (/key)."}
    model = os.environ.get("GEMINI_MODEL", "gemini-2.5-flash")
    src = "the detected language" if source.lower() == "auto" else source
    prompt = (
        f"Translate the following text from {src} to {target}. "
        "Reply with the translation only, keeping the original formatting, no quotes or explanations.\n\n" + text
    )
    body = json.dumps({
        "contents": [{"parts": [{"text": prompt}]}],
        "generationConfig": {"temperature": 0},
    }).encode()
    req = urllib.request.Request(
        f"https://generativelanguage.googleapis.com/v1beta/models/{model}:generateContent",
        data=body,
        headers={"Content-Type": "application/json", "x-goog-api-key": key},
    )
    with urllib.request.urlopen(req, timeout=60) as r:
        res = json.loads(r.read().decode())
    parts = res["candidates"][0]["content"]["parts"]
    return {"translation": "".join(p.get("text", "") for p in parts).strip(), "dictionary": [], "correction": None}


def offline(source, target, text):
    """NLLB-200 on the GPU (nllb.py): direct translation between any two languages."""
    sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
    import nllb
    result = nllb.translate(source, target, text)
    result.pop("device", None)
    result.setdefault("dictionary", [])
    result.setdefault("correction", None)
    result["offline"] = True
    return result


def online(host="translate.googleapis.com"):
    """Whether the internet is reachable (to tell "no connection" from other errors)."""
    import socket
    try:
        socket.create_connection((host, 443), timeout=3).close()
        return True
    except OSError:
        return False


def describe_error(mode, e):
    """Why an online translation failed, in words for the UI."""
    name = "Advanced (Gemini)" if mode == "advanced" else "Classic (Google Translate)"
    if isinstance(e, urllib.error.HTTPError):
        try:
            detail = json.loads(e.read().decode()).get("error", {}).get("message", "")
        except Exception:
            detail = ""
        return f"{name} failed: HTTP {e.code} {detail or e.reason}".strip()
    if not online():
        return f"No internet connection: {name} needs internet. Choose Offline (NLLB-200) to translate without connection."
    if isinstance(e, subprocess.TimeoutExpired):
        return f"{name} didn't respond in time. Try again."
    if isinstance(e, (urllib.error.URLError, TimeoutError)):
        return f"{name} couldn't connect: {getattr(e, 'reason', e)}"
    if isinstance(e, ConnectionError):
        return f"{name} returned no translation (the service may be blocking requests for now). Try again later."
    return f"{name} failed: {type(e).__name__}: {e}"


def main():
    if len(sys.argv) < 5:
        sys.exit(1)
    mode, source, target, text = sys.argv[1:5]
    autocorrect = "--no-autocorrect" not in sys.argv[5:]
    try:
        if mode == "offline":
            result = offline(source, target, text)
        elif mode == "advanced":
            result = advanced(source, target, text)
        else:
            result = classic(source, target, text, autocorrect)
            if not result.get("translation"):
                raise ConnectionError("Empty response")
    except Exception as e:
        # No automatic fallback to the offline model: say why it failed
        result = {"error": f"{type(e).__name__}: {e}" if mode == "offline" else describe_error(mode, e)}
    if "error" not in result:
        add_wiktionary(result, source, target, text)
    print(json.dumps(result, ensure_ascii=False), flush=True)


def add_wiktionary(result, source, target, text):
    """Definitions, examples, synonyms, IPA and related words from the offline Wiktionary dictionary
    (dictionary.py), when it's installed for the source language. Works without internet."""
    words = (result.get("source") or text).strip()
    if not words or len(words.split()) > 4:
        return
    try:
        sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
        import dictionary as D
        from tts import resolve_code
        src = result.get("detected") if source.lower() == "auto" else resolve_code(source)
        src = (src or "").split("-")[0].lower()
        tgt = resolve_code(target).split("-")[0].lower()
        if not src or not os.path.exists(D.db_path(src)):
            return
        w = D.lookup(src, words, tgt) or (D.lookup(src, text.strip(), tgt) if text.strip() != words else None)
    except Exception:
        return
    if not w:
        return
    result["lemma"] = w["lemma"]
    result["phonetic"] = result.get("phonetic") or w["phonetic"]
    result["definitions"] = w["definitions"] or result.get("definitions", [])
    result["examples"] = w["examples"] or result.get("examples", [])
    result["related"] = w["related"] or result.get("related", [])
    if not result.get("dictionary"):
        result["dictionary"] = w["dictionary"]
    result["dictionarySource"] = "wiktionary"


if __name__ == "__main__":
    main()
