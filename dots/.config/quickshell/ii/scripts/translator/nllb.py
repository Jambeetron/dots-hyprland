#!/usr/bin/env python3
"""Offline translation with NLLB-200 3.3B (Meta), CTranslate2 int8, on the GPU when available.

One multilingual model: every language pair is translated directly (Spanish -> French doesn't
go through English).

The model takes a few seconds to load, so a small server keeps it in memory (and in VRAM)
while it's being used, and exits after IDLE_TIMEOUT seconds without requests.

  nllb.py serve                          -> run the server (started automatically by translate())
  nllb.py translate <src> <tgt> <text>   -> {"translation"} or {"error"}

translate() / is_installed() only use the standard library, so translate.py can call them from
the system Python; the server runs with the venv (ctranslate2, tokenizers, cuBLAS 12).
"""
import json
import os
import re
import socket
import subprocess
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
DATA_DIR = os.path.expanduser("~/.local/share/quickshell-ii")
MODEL_DIR = os.path.join(DATA_DIR, "nllb-200-3.3B-int8")
MODEL_REPO = "OpenNMT/nllb-200-3.3B-ct2-int8"
MODEL_FILES = ["config.json", "generation_config.json", "shared_vocabulary.json", "special_tokens_map.json",
               "tokenizer.json", "tokenizer_config.json", "README.md", "model.bin"]
VENV_PYTHON = os.path.join(DATA_DIR, "stt-venv/bin/python")
SOCKET = os.path.join(os.environ.get("XDG_RUNTIME_DIR") or "/tmp", "quickshell-ii-nllb.sock")
IDLE_TIMEOUT = 600  # Free the VRAM after 10 minutes without translations

# Google Translate / translate-shell codes -> NLLB (FLORES-200) codes
FLORES = {
    "af": "afr_Latn", "am": "amh_Ethi", "ar": "arb_Arab", "as": "asm_Beng", "ay": "ayr_Latn", "az": "azj_Latn",
    "ba": "bak_Cyrl", "be": "bel_Cyrl", "bg": "bul_Cyrl", "bho": "bho_Deva", "bm": "bam_Latn", "bn": "ben_Beng",
    "bo": "bod_Tibt", "bs": "bos_Latn", "ca": "cat_Latn", "ceb": "ceb_Latn", "ckb": "ckb_Arab", "cs": "ces_Latn",
    "cy": "cym_Latn", "da": "dan_Latn", "de": "deu_Latn", "ee": "ewe_Latn", "el": "ell_Grek", "en": "eng_Latn",
    "eo": "epo_Latn", "es": "spa_Latn", "et": "est_Latn", "eu": "eus_Latn", "fa": "pes_Arab", "fi": "fin_Latn",
    "fj": "fij_Latn", "fo": "fao_Latn", "fr": "fra_Latn", "fr-CA": "fra_Latn", "ga": "gle_Latn", "gd": "gla_Latn",
    "gl": "glg_Latn", "gn": "grn_Latn", "gu": "guj_Gujr", "ha": "hau_Latn", "he": "heb_Hebr", "iw": "heb_Hebr",
    "hi": "hin_Deva", "hr": "hrv_Latn", "ht": "hat_Latn", "hu": "hun_Latn", "hy": "hye_Armn", "id": "ind_Latn",
    "ig": "ibo_Latn", "ilo": "ilo_Latn", "is": "isl_Latn", "it": "ita_Latn", "ja": "jpn_Jpan", "jv": "jav_Latn",
    "jw": "jav_Latn", "ka": "kat_Geor", "kk": "kaz_Cyrl", "km": "khm_Khmr", "kn": "kan_Knda", "ko": "kor_Hang",
    "ku": "kmr_Latn", "ky": "kir_Cyrl", "lb": "ltz_Latn", "lg": "lug_Latn", "ln": "lin_Latn", "lo": "lao_Laoo",
    "lt": "lit_Latn", "lus": "lus_Latn", "lv": "lvs_Latn", "mai": "mai_Deva", "mg": "plt_Latn", "mi": "mri_Latn",
    "mk": "mkd_Cyrl", "ml": "mal_Mlym", "mn": "khk_Cyrl", "mr": "mar_Deva", "ms": "zsm_Latn", "mt": "mlt_Latn",
    "my": "mya_Mymr", "ne": "npi_Deva", "nl": "nld_Latn", "no": "nob_Latn", "nso": "nso_Latn", "ny": "nya_Latn",
    "om": "gaz_Latn", "or": "ory_Orya", "pa": "pan_Guru", "pap": "pap_Latn", "pl": "pol_Latn", "prs": "prs_Arab",
    "ps": "pbt_Arab", "pt": "por_Latn", "pt-BR": "por_Latn", "pt-PT": "por_Latn", "qu": "quy_Latn", "ro": "ron_Latn",
    "ru": "rus_Cyrl", "rw": "kin_Latn", "sa": "san_Deva", "sd": "snd_Arab", "si": "sin_Sinh", "sk": "slk_Latn",
    "sl": "slv_Latn", "sm": "smo_Latn", "sn": "sna_Latn", "so": "som_Latn", "sq": "als_Latn", "sr": "srp_Cyrl",
    "sr-Cyrl": "srp_Cyrl", "st": "sot_Latn", "su": "sun_Latn", "sv": "swe_Latn", "sw": "swh_Latn", "ta": "tam_Taml",
    "te": "tel_Telu", "tg": "tgk_Cyrl", "th": "tha_Thai", "ti": "tir_Ethi", "tk": "tuk_Latn", "tl": "tgl_Latn",
    "tr": "tur_Latn", "ts": "tso_Latn", "tt": "tat_Cyrl", "tw": "twi_Latn", "ug": "uig_Arab", "uk": "ukr_Cyrl",
    "ur": "urd_Arab", "uz": "uzn_Latn", "vi": "vie_Latn", "xh": "xho_Latn", "yi": "ydd_Hebr", "yo": "yor_Latn",
    "yue": "yue_Hant", "zh": "zho_Hans", "zh-CN": "zho_Hans", "zh-TW": "zho_Hant", "zu": "zul_Latn",
}


def is_installed():
    return all(os.path.exists(os.path.join(MODEL_DIR, f)) for f in MODEL_FILES)


def flores_code(lang):
    """Language name or code (as used in the UI) -> FLORES-200 code, or None if NLLB doesn't have it."""
    sys.path.insert(0, HERE)
    from tts import resolve_code
    code = resolve_code(lang)
    found = FLORES.get(code) or FLORES.get(code.split("-")[0].lower())
    if found:
        return found
    # Names with variants in translate-shell: "Portuguese" -> "Portuguese (Brazil)" (pt-BR)
    try:
        out = subprocess.run(["trans", "-list-all", "-no-ansi"], capture_output=True, text=True, timeout=10).stdout
    except Exception:
        return None
    wanted = lang.strip().lower()
    for line in out.splitlines():
        parts = [p.strip() for p in re.split(r"\s{2,}", line.strip()) if p.strip()]
        if len(parts) >= 2 and any(wanted in (n.lower().split(" (")[0], n.lower().split()[0]) for n in parts[1:]):
            found = FLORES.get(parts[0]) or FLORES.get(parts[0].split("-")[0].lower())
            if found:
                return found
    return None


# ---- Client (standard library only) ----

def _request(payload, timeout):
    with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as s:
        s.settimeout(timeout)
        s.connect(SOCKET)
        s.sendall(json.dumps(payload).encode() + b"\n")
        data = b""
        while not data.endswith(b"\n"):
            chunk = s.recv(65536)
            if not chunk:
                break
            data += chunk
    return json.loads(data.decode())


def translate(source, target, text):
    if not is_installed():
        return {"error": "The offline model isn't downloaded. Download it in Choose text translation model > Offline."}
    auto = source.strip().lower() == "auto"
    src, tgt = ("auto" if auto else flores_code(source)), flores_code(target)
    missing = [name for name, code in ((source, src), (target, tgt)) if not code]
    if missing:
        return {"error": "Not supported by the offline model: " + ", ".join(missing)}
    if src == tgt:
        return {"translation": text}
    payload = {"src": src, "tgt": tgt, "text": text}
    try:
        return _request(payload, 120)
    except (FileNotFoundError, ConnectionRefusedError):
        pass
    # Start the server and wait until the model is loaded
    subprocess.Popen([VENV_PYTHON, os.path.abspath(__file__), "serve"], start_new_session=True,
                     stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    deadline = time.time() + 120
    while time.time() < deadline:
        time.sleep(0.3)
        try:
            return _request(payload, 120)
        except (FileNotFoundError, ConnectionRefusedError):
            continue
    return {"error": "The offline model didn't start"}


def stop_server():
    try:
        _request({"cmd": "quit"}, 5)
    except Exception:
        pass


# ---- Server (venv) ----

SENTENCE_END = re.compile(r"(?<=[.!?…])\s+(?=\S)|(?<=[。！？])")


def split_sentences(line):
    """NLLB is trained on sentences: long paragraphs are translated sentence by sentence."""
    return [s for s in SENTENCE_END.split(line) if s.strip()]


def serve():
    # Only one server (two translations can start it at the same time)
    import fcntl
    lock = open(SOCKET + ".lock", "w")
    try:
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
    except OSError:
        return
    import ctranslate2
    from tokenizers import Tokenizer

    # cuBLAS 12 from the venv (pip nvidia-cublas-cu12): the system CUDA is a newer major version
    import ctypes
    import glob
    for lib in sorted(glob.glob(os.path.join(sys.prefix, "lib/python*/site-packages/nvidia/cublas/lib/libcublas*.so.*"))):
        try:
            ctypes.CDLL(lib, mode=ctypes.RTLD_GLOBAL)
        except OSError:
            pass

    if ctranslate2.get_cuda_device_count() > 0:
        try:
            model = ctranslate2.Translator(MODEL_DIR, device="cuda", compute_type="int8_float16")
        except Exception:
            model = ctranslate2.Translator(MODEL_DIR, device="cpu", compute_type="int8")
    else:
        model = ctranslate2.Translator(MODEL_DIR, device="cpu", compute_type="int8")
    tokenizer = Tokenizer.from_file(os.path.join(MODEL_DIR, "tokenizer.json"))
    # Offline language detection for "Detect language" (lingua, ~75 languages)
    from lingua import Language, LanguageDetectorBuilder
    # Only languages NLLB can translate (Latin isn't one: "superior" -> Spanish/English, not Latin)
    supported = [l for l in Language.all() if l.iso_code_639_1.name.lower() in FLORES]
    detector = LanguageDetectorBuilder.from_languages(*supported).build()

    def detect(text):
        lang = detector.detect_language_of(text)
        if lang is None:  # Ambiguous (single words like "superior"): most likely language
            values = detector.compute_language_confidence_values(text)
            lang = values[0].language if values else None
        code = lang.iso_code_639_1.name.lower() if lang else ""
        return code, FLORES.get(code)

    def run(src, tgt, text):
        lines = text.split("\n")
        sentences = [split_sentences(line) for line in lines]
        flat = [s for group in sentences for s in group]
        if not flat:
            return text
        batch = [[src] + tokenizer.encode(s, add_special_tokens=False).tokens + ["</s>"] for s in flat]
        # Very short inputs ("Hola.", "Gracias") make NLLB add words ("Hi. How are you?",
        # "Thank you. Thank you."): limit their output length
        results = [None] * len(batch)
        short = [i for i, b in enumerate(batch) if len(b) <= 8]
        long = [i for i, b in enumerate(batch) if len(b) > 8]
        for idx, is_short in ((short, True), (long, False)):
            if not idx:
                continue
            longest = max(len(batch[i]) for i in idx)
            res = model.translate_batch(
                [batch[i] for i in idx], target_prefix=[[tgt]] * len(idx), beam_size=4, max_batch_size=16,
                max_decoding_length=2 * (longest - 2) + 3 if is_short else min(512, 3 * longest + 16),
                repetition_penalty=1.0 if is_short else 1.1,
            )
            for i, r in zip(idx, res):
                results[i] = r
        out = []
        for r in results:
            tokens = [t for t in r.hypotheses[0] if t != tgt]
            ids = [tokenizer.token_to_id(t) for t in tokens]
            sentence = tokenizer.decode([i for i in ids if i is not None], skip_special_tokens=True).strip()
            # NLLB sometimes outputs "Thank you ." (French keeps its space before ?!:;)
            sentence = re.sub(r"\s+([.,])(?=\s|$)", r"\1", sentence)
            if not tgt.startswith("fra"):
                sentence = re.sub(r"\s+([!?;:])(?=\s|$)", r"\1", sentence)
            if not flat[len(out)].lstrip().startswith(("-", "—", "–")):
                sentence = re.sub(r"^[-—–]\s*", "", sentence)  # Subtitle-style dialogue dash
            # Same sentence repeated ("Thank you. Thank you.")
            sentence = re.sub(r"^(.{2,}?[.!?。！？])(\s*\1)+$", r"\1", sentence)
            if tgt.split("_")[0] in ("jpn", "zho", "yue"):  # Full-width punctuation after CJK text
                sentence = re.sub(r"(?<=[぀-ヿ一-鿿])\.", "。", sentence)
                sentence = re.sub(r"(?<=[぀-ヿ一-鿿])([?!,])",
                                  lambda m: {"?": "？", "!": "！", ",": "，"}[m.group(1)], sentence)
            out.append(sentence)
        it = iter(out)
        # Same lines as the input; sentences of a line joined with a space (no space in CJK)
        joiner = "" if tgt.split("_")[0] in ("jpn", "zho", "yue") else " "
        return "\n".join(joiner.join(next(it) for _ in group) for group in sentences)

    if os.path.exists(SOCKET):
        os.remove(SOCKET)
    server = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    server.bind(SOCKET)
    os.chmod(SOCKET, 0o600)
    server.listen(4)
    server.settimeout(IDLE_TIMEOUT)
    try:
        while True:
            try:
                conn, _ = server.accept()
            except socket.timeout:
                break  # Idle: exit and free the memory
            with conn:
                data = b""
                while not data.endswith(b"\n"):
                    chunk = conn.recv(65536)
                    if not chunk:
                        break
                    data += chunk
                try:
                    req = json.loads(data.decode())
                    if req.get("cmd") == "quit":
                        conn.sendall(b'{"status": "bye"}\n')
                        break
                    src, detected = req["src"], ""
                    if src == "auto":
                        detected, src = detect(req["text"])
                        if not src:
                            raise ValueError("Couldn't detect the language. Choose the source language.")
                    if src == req["tgt"]:
                        reply = {"translation": req["text"]}
                    else:
                        reply = {"translation": run(src, req["tgt"], req["text"]), "device": model.device}
                    if detected:
                        reply["detected"] = detected
                except ValueError as e:
                    reply = {"error": str(e)}
                except Exception as e:
                    reply = {"error": f"{type(e).__name__}: {e}"}
                conn.sendall(json.dumps(reply, ensure_ascii=False).encode() + b"\n")
    finally:
        server.close()
        if os.path.exists(SOCKET):
            os.remove(SOCKET)


def main():
    if len(sys.argv) < 2:
        sys.exit(1)
    if sys.argv[1] == "serve":
        serve()
    elif sys.argv[1] == "translate" and len(sys.argv) >= 5:
        print(json.dumps(translate(*sys.argv[2:5]), ensure_ascii=False), flush=True)
    elif sys.argv[1] == "stop":
        stop_server()


if __name__ == "__main__":
    main()
