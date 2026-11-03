#!/usr/bin/env python3
"""Record from the microphone until SIGTERM, then transcribe with faster-whisper.

Usage: stt.py <language name, endonym or code | auto> [stop file]
Recording also stops when the stop file appears.
Prints the transcribed text to stdout.
Must run with the venv at ~/.local/share/quickshell-ii/stt-venv.
"""
import os
import signal
import subprocess
import sys
import tempfile
import threading

from tts import resolve_code  # same directory

MODEL = os.environ.get("QS_STT_MODEL", "small")

stop = threading.Event()
signal.signal(signal.SIGTERM, lambda *_: stop.set())
signal.signal(signal.SIGINT, lambda *_: stop.set())


def whisper_language(lang: str):
    from faster_whisper.tokenizer import _LANGUAGE_CODES
    code = resolve_code(lang).split("-")[0].lower()
    return code if code in _LANGUAGE_CODES else None


def main():
    lang = sys.argv[1] if len(sys.argv) > 1 else "auto"
    stop_file = sys.argv[2] if len(sys.argv) > 2 else None
    if stop_file and os.path.exists(stop_file):
        os.remove(stop_file)
    with tempfile.TemporaryDirectory(prefix="qs-stt-") as tmp:
        wav = os.path.join(tmp, "rec.wav")
        rec = subprocess.Popen(["pw-record", "--rate", "16000", "--channels", "1", wav])
        while not stop.wait(0.1):
            if stop_file and os.path.exists(stop_file):
                os.remove(stop_file)
                break
            if rec.poll() is not None:  # recorder died (e.g. no microphone)
                break
        rec.send_signal(signal.SIGINT)
        try:
            rec.wait(timeout=3)
        except subprocess.TimeoutExpired:
            rec.kill()
        if not os.path.exists(wav) or os.path.getsize(wav) < 1000:
            return

        import numpy as np
        from faster_whisper import WhisperModel

        raw = subprocess.run(
            ["ffmpeg", "-nostdin", "-loglevel", "error", "-i", wav, "-f", "f32le", "-ac", "1", "-ar", "16000", "-"],
            capture_output=True, check=True,
        ).stdout
        audio = np.frombuffer(raw, np.float32)
        model = WhisperModel(MODEL, device="cpu", compute_type="int8")
        segments, _ = model.transcribe(audio, language=whisper_language(lang), beam_size=5, vad_filter=True)
        print(" ".join(s.text.strip() for s in segments).strip(), flush=True)


if __name__ == "__main__":
    main()
