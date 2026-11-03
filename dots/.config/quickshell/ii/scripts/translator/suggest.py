#!/usr/bin/env python3
"""Word suggestions while typing, ranked by frequency (wordfreq), with their translations.

Usage: suggest.py <source lang (name/code)> <target lang (name/code)> <prefix> [count]
Prints JSON lines: first {"prefix", "words"} right away, then {"prefix", "translations"}.
Must run with the venv at ~/.local/share/quickshell-ii/stt-venv (wordfreq installed there).
"""
import json
import os
import subprocess
import sys

from tts import resolve_code  # same directory


def emit(obj):
    print(json.dumps(obj, ensure_ascii=False), flush=True)


def main():
    if len(sys.argv) < 4:
        sys.exit(1)
    source, target, prefix = sys.argv[1], sys.argv[2], sys.argv[3].strip()
    count = int(sys.argv[4]) if len(sys.argv) > 4 else 3
    if len(prefix) < 2:
        emit({"prefix": prefix, "words": []})
        return

    from wordfreq import available_languages, top_n_list, zipf_frequency

    code = resolve_code(source)
    lang = code.split("-")[0].lower() if code != "auto" else "en"
    if lang not in available_languages():
        emit({"prefix": prefix, "words": []})
        return

    lower = prefix.lower()
    vocabulary = top_n_list(lang, 200000)
    words = []
    # A real word (not a fragment like "selec": zipf 1.6 vs "select" 4.5)
    if zipf_frequency(lower, lang) >= 3.0:
        # Complete word: itself first, then phrases that start with it ("advanced level")
        # Expressions from the offline Wiktionary dictionary, only when it's installed ("mano de obra")
        import dictionary as D
        found = D.phrases(lang, prefix, count - 1) if os.path.exists(D.db_path(lang)) else []
        words = [prefix] + found
    for w in vocabulary:
        if len(words) >= count:
            break
        if w.startswith(lower) and w != lower:
            # Keep the user's capitalization of the first letter
            words.append(prefix[0] + w[1:] if prefix[0].isupper() else w)
    emit({"prefix": prefix, "words": words})
    if not words:
        return

    try:
        out = subprocess.run(
            ["trans", "-4", "-b", "-no-ansi", "-s", source, "-t", target],
            input="\n".join(words), capture_output=True, text=True, timeout=15,
        ).stdout.strip().splitlines()
    except Exception:
        out = []
    translations = [t.strip() for t in out][: len(words)]
    if len(translations) == len(words):
        emit({"prefix": prefix, "translations": translations})


if __name__ == "__main__":
    main()
