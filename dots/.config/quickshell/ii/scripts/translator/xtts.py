#!/usr/bin/env python3
"""Local voice for Listen with Coqui XTTS-v2, on the GPU when available.

The model takes a while to load, so a small server keeps it in memory (and in VRAM) while it's
being used, and exits after IDLE_TIMEOUT seconds without requests. Audio is streamed while it's
generated (sentence by sentence), so long texts start playing right away.

  xtts.py serve                 -> run the server (started automatically by stream())
  xtts.py stop                  -> stop the server

stream() / is_installed() / language() only use the standard library, so tts.py can call them
from the system Python; the server runs with its own venv (Python 3.12, PyTorch CUDA, coqui-tts).
"""
import json
import os
import re
import socket
import subprocess
import sys
import time

DATA_DIR = os.path.expanduser("~/.local/share/quickshell-ii")
MODEL_DIR = os.path.join(DATA_DIR, "xtts-v2")
MODEL_REPO = "coqui/XTTS-v2"
MODEL_FILES = ["config.json", "vocab.json", "speakers_xtts.pth", "LICENSE.txt", "model.pth"]
VENV_PYTHON = os.path.join(DATA_DIR, "tts-venv/bin/python")
SOCKET = os.path.join(os.environ.get("XDG_RUNTIME_DIR") or "/tmp", "quickshell-ii-xtts.sock")
IDLE_TIMEOUT = 600  # Free the VRAM after 10 minutes without requests
SAMPLE_RATE = 24000
# Built-in voice (speakers_xtts.pth), chosen by transcribing test clips of 32 voices with Whisper:
# "Zacharie Aimilios" (male) is the most intelligible overall, and good in both Chinese and Korean
SPEAKER = "Zacharie Aimilios"
SPEAKERS = {}  # Language -> different voice for it (none needed)
TEMPERATURE = 0.3  # Less random than the default 0.75: fewer mispronunciations in short texts

# Google Translate codes -> XTTS-v2 languages
LANGUAGES = {
    "en": "en", "es": "es", "fr": "fr", "fr-CA": "fr", "de": "de", "it": "it", "pt": "pt", "pt-BR": "pt",
    "pt-PT": "pt", "pl": "pl", "tr": "tr", "ru": "ru", "nl": "nl", "cs": "cs", "ar": "ar", "zh": "zh-cn",
    "zh-CN": "zh-cn", "zh-TW": "zh-cn", "hu": "hu", "ko": "ko", "ja": "ja", "hi": "hi",
}


def is_installed():
    return all(os.path.exists(os.path.join(MODEL_DIR, f)) for f in MODEL_FILES) and os.path.exists(VENV_PYTHON)


def language(code):
    """Google code -> XTTS language, or None when XTTS doesn't speak it."""
    return LANGUAGES.get(code) or LANGUAGES.get(code.split("-")[0].lower())


# ---- Client (standard library only) ----

def _connect(timeout):
    s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    s.settimeout(timeout)
    try:
        s.connect(SOCKET)
    except BaseException:
        s.close()
        raise
    return s


def voice_for(lang):
    """Voice chosen for a language in the widget ("Choose" tab): env XTTS_VOICES, JSON {"es": "<voice>"}; None = default."""
    try:
        voices = json.loads(os.environ.get("XTTS_VOICES") or "{}")
    except ValueError:
        return None
    return voices.get(lang.split("-")[0]) if isinstance(voices, dict) else None  # "zh-cn" -> "zh"


def stream(lang, text):
    """Yields raw audio (float32 mono, SAMPLE_RATE) while it's generated. Raises RuntimeError on errors."""
    try:
        s = _connect(300)
    except (FileNotFoundError, ConnectionRefusedError):
        log = open(SOCKET + ".log", "w")  # Server errors, to report why it didn't start
        proc = subprocess.Popen([VENV_PYTHON, os.path.abspath(__file__), "serve"], start_new_session=True,
                                stdin=subprocess.DEVNULL, stdout=log, stderr=log)
        deadline, s = time.time() + 180, None
        while time.time() < deadline and s is None:
            time.sleep(0.3)
            try:
                s = _connect(300)
            except (FileNotFoundError, ConnectionRefusedError):
                if proc.poll() is not None and not os.path.exists(SOCKET):
                    lines = [l for l in open(SOCKET + ".log").read().splitlines() if l.strip()]
                    raise RuntimeError("The voice model didn't start: " + (lines[-1] if lines else "unknown error"))
        if s is None:
            raise RuntimeError("The voice model didn't start")
    with s:
        s.sendall(json.dumps({"lang": lang, "text": text, "speaker": voice_for(lang)}).encode() + b"\n")
        header = b""
        while not header.endswith(b"\n"):
            chunk = s.recv(1)
            if not chunk:
                raise RuntimeError("The voice model stopped")
            header += chunk
        info = json.loads(header.decode())
        if "error" in info:
            raise RuntimeError(info["error"])
        while chunk := s.recv(65536):
            yield chunk


def stop_server():
    try:
        with _connect(5) as s:
            s.sendall(b'{"cmd": "quit"}\n')
            s.recv(64)
    except Exception:
        pass


# ---- Server (tts-venv) ----

def load_model():
    import torch
    from TTS.tts.configs.xtts_config import XttsConfig
    from TTS.tts.models.xtts import Xtts

    config = XttsConfig()
    config.load_json(os.path.join(MODEL_DIR, "config.json"))
    model = Xtts.init_from_config(config)
    model.load_checkpoint(config, checkpoint_dir=MODEL_DIR, use_deepspeed=False)
    if torch.cuda.is_available():
        try:
            model.cuda()
        except torch.cuda.OutOfMemoryError:  # The GPU is full (e.g. with the translation model)
            model.cpu()
            torch.cuda.empty_cache()
    model.eval()
    return model


def max_duration(text, lang):
    """Longest plausible audio (seconds) for a text. XTTS sometimes babbles: much longer audio."""
    n = sum(1 for c in text if c.isalnum())
    per_char = 0.32 if lang in ("ja", "zh-cn", "ko") else 0.18
    return per_char * n + 1.5


def synthesize(model, lang, text, speaker=None, attempts=3):
    """Float32 audio chunks (numpy), sentence group by sentence group, regenerating babbled ones."""
    import numpy as np
    from TTS.tts.layers.xtts.tokenizer import split_sentence
    sp = model.speaker_manager.speakers[speaker or SPEAKERS.get(lang, SPEAKER)]
    limit = model.tokenizer.char_limits.get(lang, 250)
    # Sentence by sentence, so the first one plays while the rest are generated
    parts = []
    for sentence in re.split(r"(?<=[.!?…。！？])\s*", text):
        if sentence.strip():
            parts += split_sentence(sentence, lang, text_split_length=limit) if len(sentence) > limit else [sentence.strip()]
    for part in parts:
        best = None
        for _ in range(attempts):
            wav = np.asarray(model.inference(part, lang, sp["gpt_cond_latent"], sp["speaker_embedding"],
                                             temperature=TEMPERATURE, enable_text_splitting=False)["wav"], dtype=np.float32)
            if best is None or len(wav) < len(best):
                best = wav
            if len(wav) / SAMPLE_RATE <= max_duration(part, lang):
                break
        yield best


def serve():
    import fcntl
    lock = open(SOCKET + ".lock", "w")
    try:
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
    except OSError:
        return  # Already running

    import torch
    model = load_model()
    started = {"audio": False}

    def handle(conn, req):
        lang, text = req["lang"], req["text"].strip()
        speaker = req.get("speaker")
        if speaker not in model.speaker_manager.speakers:
            speaker = None  # Unknown or not chosen: the default voice
        if not text:
            conn.sendall(b'{"error": "No text"}\n')
            return
        conn.sendall(json.dumps({"rate": SAMPLE_RATE, "device": str(model.device)}).encode() + b"\n")
        started["audio"] = True
        with torch.inference_mode():
            for wav in synthesize(model, lang, text, speaker):
                conn.sendall(wav.tobytes())  # Fails when the client stopped

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
                conn.settimeout(None)
                data = b""
                while not data.endswith(b"\n"):
                    chunk = conn.recv(65536)
                    if not chunk:
                        break
                    data += chunk
                started["audio"] = False
                try:
                    req = json.loads(data.decode())
                    if req.get("cmd") == "quit":
                        conn.sendall(b'{"status": "bye"}\n')
                        break
                    handle(conn, req)
                except (BrokenPipeError, ConnectionResetError):
                    pass  # Stopped from the UI
                except Exception as e:
                    if started["audio"]:
                        continue  # Already streaming audio: just stop
                    try:
                        conn.sendall(json.dumps({"error": f"{type(e).__name__}: {e}"}).encode() + b"\n")
                    except OSError:
                        pass
    finally:
        server.close()
        if os.path.exists(SOCKET):
            os.remove(SOCKET)


def main():
    if len(sys.argv) < 2:
        sys.exit(1)
    if sys.argv[1] == "serve":
        serve()
    elif sys.argv[1] == "stop":
        stop_server()


if __name__ == "__main__":
    main()
