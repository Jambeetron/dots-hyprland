#!/usr/bin/env python3
"""Offline Wiktionary dictionaries (data from kaikki.org / wiktextract), stored as SQLite.

Each language uses its own Wiktionary edition when there is one (Spanish words with Spanish
definitions, French with French...). English uses the English edition.

  dictionary.py list                         -> {"dictionaries": [{code, installed, size, updatable}]}
  dictionary.py install <code>               -> JSON lines {"status": "progress", "done", "total"} ... {"status": "done"}
  dictionary.py remove <code>
  dictionary.py lookup <code> <word> [target code]  -> panel data (definitions, examples, related, ipa, translations)
  dictionary.py phrases <code> <word> [limit]       -> {"phrases": [...]}

Only the standard library is required (wordfreq is used for ranking when available).
"""
import gzip
import io
import json
import os
import re
import signal
import sqlite3
import sys
import time
import urllib.request

DATA_DIR = os.path.expanduser("~/.local/share/quickshell-ii/dictionaries")
NATIVE_EDITIONS = {"cs", "de", "el", "es", "fr", "id", "it", "ja", "ko", "ku", "ms", "nl", "pl", "pt", "ru", "th", "tr", "vi", "zh"}
UA = {"User-Agent": "quickshell-translator (offline dictionary)"}

POS_NAMES = {
    "adj": "adjective", "adv": "adverb", "noun": "noun", "verb": "verb", "name": "proper noun", "pron": "pronoun",
    "prep": "preposition", "conj": "conjunction", "intj": "interjection", "det": "determiner", "num": "numeral",
    "article": "article", "particle": "particle", "phrase": "phrase", "prep_phrase": "prepositional phrase",
    "suffix": "suffix", "prefix": "prefix", "affix": "affix", "abbrev": "abbreviation", "symbol": "symbol",
    "proverb": "proverb", "contraction": "contraction", "postp": "postposition", "character": "character",
}
# Sense tags shown as labels (register / usage), like Google's "informal", "rare"...
LABEL_TAGS = {
    "informal", "colloquial", "slang", "vulgar", "derogatory", "offensive", "formal", "literary", "poetic",
    "archaic", "obsolete", "dated", "rare", "uncommon", "figuratively", "figurative", "humorous", "euphemistic",
    "technical", "regional", "dialectal", "nonstandard", "pejorative", "ironic", "childish", "jargon",
}


def source_url(code):
    if code == "en":
        return "https://kaikki.org/dictionary/English/kaikki.org-dictionary-English.jsonl.gz"
    if code in NATIVE_EDITIONS:
        return f"https://kaikki.org/{code}wiktionary/raw-wiktextract-data.jsonl.gz"
    return None


def db_path(code):
    return os.path.join(DATA_DIR, f"{code}.sqlite")


def emit(obj):
    print(json.dumps(obj, ensure_ascii=False), flush=True)


def remote_info(url):
    req = urllib.request.Request(url, method="HEAD", headers=UA)
    with urllib.request.urlopen(req, timeout=20) as r:
        return int(r.headers.get("Content-Length") or 0), r.headers.get("Last-Modified") or ""


def meta(conn, key):
    row = conn.execute("SELECT value FROM meta WHERE key = ?", (key,)).fetchone()
    return row[0] if row else ""


# ---------------------------------------------------------------- building

def compact(entry):
    """Keep only what the translator shows."""
    def words(items, limit=40):
        out = []
        for it in items or []:
            w = it.get("word") if isinstance(it, dict) else None
            if w and w not in out:
                out.append(w)
            if len(out) >= limit:
                break
        return out

    def syn_list(items):
        return [{"w": s["word"], "si": s.get("sense_index", ""), "sense": s.get("sense", ""),
                 "tags": [t for t in (s.get("tags") or []) + (s.get("raw_tags") or []) if t]}
                for s in items or [] if s.get("word")]

    def translations(items, limit=8):
        tr = {}
        for t in items or []:
            code, w = t.get("lang_code") or t.get("code"), t.get("word")
            if not code or not w:
                continue
            lst = tr.setdefault(code, [])
            if len(lst) < limit:
                lst.append({"w": w, "si": t.get("sense_index", ""), "sense": t.get("sense", "")})
        return tr

    senses = []
    for i, s in enumerate(entry.get("senses") or []):
        glosses = s.get("glosses") or s.get("raw_glosses")
        if not glosses:
            continue
        labels = [t for t in (s.get("topics") or [])]
        labels += [t for t in (s.get("tags") or []) if t in LABEL_TAGS]
        labels += [t for t in (s.get("raw_tags") or []) if len(t) < 40]
        examples = []
        for ex in (s.get("examples") or [])[:3]:
            if ex.get("text"):
                examples.append({"t": ex["text"], "b": ex.get("bold_text_offsets") or []})
        senses.append({
            "g": glosses[-1],
            "si": s.get("sense_index") or str(i + 1),
            "lab": labels,
            "ex": examples,
            "syn": syn_list(s.get("synonyms")),
            "tr": translations(s.get("translations")),
            "fo": [f["word"] for f in (s.get("form_of") or []) if f.get("word")],
        })
    ipa = ""
    for snd in entry.get("sounds") or []:
        if snd.get("ipa"):
            ipa = snd["ipa"]
            break
    return {
        "ipa": ipa,
        "senses": senses,
        "syn": syn_list(entry.get("synonyms")),
        "rel": words(entry.get("related")),
        "der": words((entry.get("derived") or []) + (entry.get("idioms") or []) + (entry.get("compounds") or []), 60),
        "tr": translations(entry.get("translations")),
    }


class CountingReader(io.RawIOBase):
    """Wraps the HTTP response to count downloaded (compressed) bytes."""

    def __init__(self, raw, on_read):
        self.raw, self.on_read = raw, on_read

    def readable(self):
        return True

    def readinto(self, b):
        data = self.raw.read(len(b))
        n = len(data)
        b[:n] = data
        self.on_read(n)
        return n


def cmd_install(code, progress_offset=0, progress_total=0, emit_done=True):
    url = source_url(code)
    if not url:
        emit({"status": "error", "code": code, "error": "No Wiktionary dictionary for this language"})
        return
    os.makedirs(DATA_DIR, exist_ok=True)
    size, last_modified = remote_info(url)
    total = progress_total or size
    tmp = db_path(code) + ".part"
    if os.path.exists(tmp):
        os.remove(tmp)
    state = {"done": 0, "last": 0.0}

    def on_read(n):
        state["done"] += n
        if time.time() - state["last"] > 0.3:
            state["last"] = time.time()
            emit({"status": "progress", "code": code, "done": progress_offset + state["done"], "total": max(total, progress_offset + state["done"])})

    conn = sqlite3.connect(tmp)
    try:
        conn.executescript("""
            PRAGMA journal_mode = OFF; PRAGMA synchronous = OFF;
            CREATE TABLE entries (word TEXT, lower TEXT, pos TEXT, data TEXT);
            CREATE TABLE phrases (head TEXT, phrase TEXT, UNIQUE(head, phrase));
            CREATE TABLE meta (key TEXT PRIMARY KEY, value TEXT);
        """)
        req = urllib.request.Request(url, headers=UA)
        with urllib.request.urlopen(req, timeout=60) as resp:
            stream = io.BufferedReader(CountingReader(resp, on_read), buffer_size=1 << 20)
            batch, phrases = [], set()
            with gzip.GzipFile(fileobj=stream) as gz:
                for line in gz:
                    entry = json.loads(line)
                    if entry.get("lang_code") != code or not entry.get("word"):
                        continue
                    word = entry["word"]
                    data = compact(entry)
                    batch.append((word, word.lower(), entry.get("pos", ""), json.dumps(data, ensure_ascii=False, separators=(",", ":"))))
                    if " " in word:
                        phrases.add((word.split(" ", 1)[0].lower(), word))
                    for d in data["der"]:
                        if d.lower().startswith(word.lower() + " "):
                            phrases.add((word.lower(), d))
                    if len(batch) >= 5000:
                        conn.executemany("INSERT INTO entries VALUES (?, ?, ?, ?)", batch)
                        batch = []
            if batch:
                conn.executemany("INSERT INTO entries VALUES (?, ?, ?, ?)", batch)
            conn.executemany("INSERT OR IGNORE INTO phrases VALUES (?, ?)", list(phrases))
        emit({"status": "indexing", "code": code})
        conn.executescript("""
            CREATE INDEX entries_lower ON entries(lower);
            CREATE INDEX phrases_head ON phrases(head);
        """)
        conn.executemany("INSERT INTO meta VALUES (?, ?)", [
            ("source", url), ("last_modified", last_modified), ("built", time.strftime("%Y-%m-%d")),
        ])
        conn.commit()
        conn.close()
        os.replace(tmp, db_path(code))
    except BaseException:
        conn.close()
        if os.path.exists(tmp):
            os.remove(tmp)
        raise
    if emit_done:
        emit({"status": "done", "code": code})


def cmd_remove(code):
    for path in (db_path(code), db_path(code) + ".part"):
        if os.path.exists(path):
            os.remove(path)
    emit({"status": "done", "code": code})


def info(code, check_updates=False):
    """{code, available, installed, size, updatable} for one language."""
    url = source_url(code)
    res = {"code": code, "available": url is not None, "installed": os.path.exists(db_path(code)), "updatable": False}
    if res["installed"]:
        res["size"] = os.path.getsize(db_path(code))
        if check_updates and url:
            try:
                _, remote_modified = remote_info(url)
                conn = sqlite3.connect(db_path(code))
                res["updatable"] = bool(remote_modified) and remote_modified != meta(conn, "last_modified")
                conn.close()
            except Exception:
                pass
    return res


# ---------------------------------------------------------------- lookups

def connect(code):
    path = db_path(code)
    if not code or not os.path.exists(path):
        return None
    return sqlite3.connect(f"file:{path}?mode=ro", uri=True)


def bold_html(text, offsets, word):
    def esc(s):
        return s.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;")
    if offsets:
        out, pos = "", 0
        for start, end in sorted(offsets):
            if end <= pos:
                continue  # Overlapping marks (e.g. "avanzada" inside "avanzadas")
            start = max(start, pos)
            out += esc(text[pos:start]) + "<b>" + esc(text[start:end]) + "</b>"
            pos = end
        return (out + esc(text[pos:])).replace("</b><b>", "")
    pattern = re.compile(r"(?i)\b(" + re.escape(word) + r"\w*)")
    return pattern.sub(r"<b>\1</b>", esc(text))


def frequency_level(word, code):
    try:
        from wordfreq import zipf_frequency
        z = zipf_frequency(word, code)
        return 3 if z >= 4 else 2 if z >= 2.5 else 1
    except Exception:
        return 2


def lookup(code, word, target=""):
    """Panel data for `word` in language `code` (and translations into `target`), or None."""
    conn = connect(code)
    if conn is None:
        return None
    word = word.strip()
    rows = conn.execute("SELECT word, pos, data FROM entries WHERE lower = ?", (word.lower(),)).fetchall()
    # Prefer the exact capitalization when there are both ("Polish" vs "polish")
    exact = [r for r in rows if r[0] == word]
    rows = exact or rows
    entries = [(w, pos, json.loads(d)) for w, pos, d in rows]
    lemma = word
    # Only inflected forms ("avanzados" -> "avanzado"): show the lemma, like Google
    real = [e for e in entries if any(not s["fo"] for s in e[2]["senses"])]
    if entries and not real:
        target_lemma = next((s["fo"][0] for e in entries for s in e[2]["senses"] if s["fo"]), None)
        if target_lemma and target_lemma.lower() != word.lower():
            lemma = target_lemma
            rows = conn.execute("SELECT word, pos, data FROM entries WHERE lower = ?", (lemma.lower(),)).fetchall()
            entries = [(w, pos, json.loads(d)) for w, pos, d in rows] or entries
            real = [e for e in entries if any(not s["fo"] for s in e[2]["senses"])]
    conn.close()
    entries = real or entries
    if not entries:
        return None

    definitions, examples, related, ipa = [], [], [], ""
    translations = {}
    for w, pos, data in entries:
        ipa = ipa or data.get("ipa", "")
        pos_name = POS_NAMES.get(pos, pos)
        items = []
        for s in data["senses"]:
            if s["fo"] and len(data["senses"]) > 1 and real:
                continue
            groups = {}
            for syn in s.get("syn", []) + [x for x in data.get("syn", [])
                                           if (x["si"] and x["si"] == s["si"]) or (x["sense"] and s["g"].lower().startswith(x["sense"].lower()[:30]))]:
                label = ", ".join(t for t in syn["tags"] if t in LABEL_TAGS)
                lst = groups.setdefault(label, [])
                if syn["w"] not in lst and syn["w"] != w:
                    lst.append(syn["w"])
            synonyms = sorted(({"label": k, "words": v} for k, v in groups.items() if v), key=lambda g: g["label"] != "")
            first_example = s["ex"][0]["t"] if s["ex"] else ""
            items.append({"text": s["g"], "example": first_example, "labels": s["lab"][:3], "synonyms": synonyms})
            for ex in s["ex"]:
                if len(examples) < 12:
                    examples.append(bold_html(ex["t"], ex["b"], lemma))
            if target:
                for t in s.get("tr", {}).get(target, []):
                    translations.setdefault(pos_name, []).append(t["w"])
        if items:
            definitions.append({"pos": pos_name, "items": items})
        for r in data.get("rel", []) + data.get("der", []):
            if r not in related and r.lower() != lemma.lower() and len(related) < 30:
                related.append(r)
        if target:
            for t in data.get("tr", {}).get(target, []):
                translations.setdefault(pos_name, []).append(t["w"])

    dictionary = []
    for pos_name, words in translations.items():
        seen, out = set(), []
        for t in words:
            for part in re.split(r"\s*[,;/]\s*", t):
                if part and part.lower() not in seen:
                    seen.add(part.lower())
                    out.append({"word": part, "back": [], "article": "", "score": 0, "frequency": frequency_level(part, target)})
        dictionary.append({"pos": pos_name, "words": out[:12]})

    return {
        "lemma": lemma,
        "phonetic": ipa.strip("[]/"),
        "definitions": definitions,
        "examples": examples,
        "related": related,
        "dictionary": dictionary,
        "source": "wiktionary",
    }


def phrases(code, word, limit=5):
    """Multi-word expressions starting with `word` ("advanced" -> "advanced level"), most common first."""
    conn = connect(code)
    if conn is None:
        return []
    found = [r[0] for r in conn.execute("SELECT phrase FROM phrases WHERE head = ?", (word.lower(),)).fetchall()]
    conn.close()
    found = [p for p in found if p.lower().startswith(word.lower() + " ") and len(p.split()) <= 4]
    try:
        from wordfreq import zipf_frequency
        # wordfreq only estimates phrase frequency, so prefer shorter expressions first
        found.sort(key=lambda p: (len(p.split()), -zipf_frequency(p, code)))
    except Exception:
        found.sort(key=len)
    return found[:limit]


def main():
    signal.signal(signal.SIGTERM, lambda *_: (_ for _ in ()).throw(KeyboardInterrupt()))
    if len(sys.argv) < 2:
        sys.exit(1)
    cmd, args = sys.argv[1], sys.argv[2:]
    try:
        if cmd == "list":
            codes = sorted(NATIVE_EDITIONS | {"en"})
            emit({"dictionaries": [info(c, "--refresh" in args) for c in codes]})
        elif cmd == "install":
            cmd_install(args[0])
        elif cmd == "remove":
            cmd_remove(args[0])
        elif cmd == "lookup":
            emit(lookup(args[0], args[1], args[2] if len(args) > 2 else "") or {})
        elif cmd == "phrases":
            emit({"phrases": phrases(args[0], args[1], int(args[2]) if len(args) > 2 else 5)})
    except KeyboardInterrupt:
        emit({"status": "cancelled"})
    except Exception as e:
        emit({"status": "error", "error": f"{type(e).__name__}: {e}"})


if __name__ == "__main__":
    main()
