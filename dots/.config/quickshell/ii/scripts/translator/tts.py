#!/usr/bin/env python3
"""Speak text with the chosen voice: the local XTTS-v2 (xtts.py), ElevenLabs (API key in env
ELEVENLABS_API_KEY) or Google Translate's voice. XTTS-v2 uses Google's voice for languages it
doesn't speak; ElevenLabs and Google never fall back: errors exit 1 with the reason on stderr.

Usage: tts.py <language name, endonym or code | auto> <text> [speed: normal|slow|slower] [voice: xtts|elevenlabs|googlecloud|google] [--save <file.mp3>]
       tts.py google-voices [--refresh]   (Google Cloud TTS voices as JSON; key in env GOOGLE_TTS_API_KEY)
       With --save, the audio is written to an MP3 file (with ffmpeg) instead of played; prints the path.
       tts.py voices  -> {"voices": [{id, name, label, preview}]} ElevenLabs voices of the account (or {"error"})

ElevenLabs voice: env ELEVENLABS_VOICE_ID (default: "Sarah").
"""
import json
import os
import re
import signal
import socket
import subprocess
import sys
import tempfile
import urllib.error
import urllib.parse
import urllib.request

UA = {"User-Agent": "Mozilla/5.0"}
MAX_CHUNK = 180

# ElevenLabs: premade multilingual voice "Sarah" and the model with the best quality in many languages
ELEVENLABS_VOICE = os.environ.get("ELEVENLABS_VOICE_ID", "").strip() or "EXAVITQu4vr4xnxDXMLL"
ELEVENLABS_MODEL = "eleven_multilingual_v2"
ELEVENLABS_LANGUAGES = {  # Languages of eleven_multilingual_v2 (Google codes)
    "en", "ja", "zh", "de", "hi", "fr", "ko", "pt", "it", "es", "id", "nl", "tr", "tl", "fil", "pl", "sv",
    "bg", "ro", "ar", "cs", "el", "fi", "hr", "ms", "sk", "da", "ta", "uk", "ru",
}


def resolve_code(lang: str) -> str:
    lang = lang.strip()
    if not lang or lang.lower() == "auto":
        return "auto"
    try:
        out = subprocess.run(["trans", "-list-all", "-no-ansi"], capture_output=True, text=True, timeout=10).stdout
    except Exception:
        return lang
    wanted = lang.lower()
    for line in out.splitlines():
        parts = [p.strip() for p in re.split(r"\s{2,}", line.strip()) if p.strip()]
        if len(parts) >= 2 and wanted in (p.lower() for p in parts):
            return parts[0]
    return lang


def detect_language(text: str) -> str:
    for engine in ("google", "bing"):
        try:
            out = subprocess.run(
                ["trans", "-no-ansi", "-id", "-e", engine, text[:500]],
                capture_output=True, text=True, timeout=10,
            ).stdout
        except Exception:
            continue
        match = re.search(r"^Code\s+(\S+)", out, re.MULTILINE)
        if match:
            return match.group(1)
    # No connection: detect offline with lingua (installed in the translator's venv)
    python = os.path.expanduser("~/.local/share/quickshell-ii/stt-venv/bin/python")
    try:
        out = subprocess.run([python, "-c", (
            "import sys\nfrom lingua import LanguageDetectorBuilder as B\n"
            "l = B.from_all_languages().build().detect_language_of(sys.argv[1])\n"
            "print(l.iso_code_639_1.name.lower() if l else '')"), text[:500]],
            capture_output=True, text=True, timeout=20).stdout.strip()
        if out:
            return out
    except Exception:
        pass
    return "en"


def chunks(text: str):
    words, current = text.split(), ""
    for word in words:
        while len(word) > MAX_CHUNK:
            if current:
                yield current
                current = ""
            yield word[:MAX_CHUNK]
            word = word[MAX_CHUNK:]
        if len(current) + len(word) + 1 > MAX_CHUNK:
            yield current
            current = word
        else:
            current = f"{current} {word}".strip()
    if current:
        yield current


def http_error(service, e):
    """Readable reason of an HTTP/connection error."""
    if isinstance(e, urllib.error.HTTPError):
        try:
            detail = json.loads(e.read()).get("detail")
            detail = detail.get("message", detail) if isinstance(detail, dict) else detail
        except Exception:
            detail = e.reason
        if e.code == 401 and service == "ElevenLabs":
            return f"ElevenLabs: invalid API key or missing permission ({detail})"
        return f"{service}: {detail or e.reason}"
    reason = getattr(e, "reason", e)
    if isinstance(reason, (TimeoutError, socket.timeout)):
        return f"{service}: didn't respond in time"
    if isinstance(reason, OSError):
        return f"No internet connection: {service} needs internet"
    return f"{service}: couldn't connect ({reason})"


def list_voices(key):
    """ElevenLabs voices available to the account (premade + added from the library + cloned)."""
    if not key:
        return {"error": "Add your ElevenLabs API key in Settings first"}
    request = urllib.request.Request("https://api.elevenlabs.io/v1/voices", headers={"xi-api-key": key})
    try:
        with urllib.request.urlopen(request, timeout=20) as r:
            data = json.loads(r.read())
    except OSError as e:
        return {"error": http_error("ElevenLabs", e)}
    voices = []
    for v in data.get("voices", []):
        labels = v.get("labels") or {}
        traits = [labels.get(k) for k in ("gender", "accent", "age", "descriptive", "description", "use_case")]
        traits = list(dict.fromkeys(t.replace("_", " ") for t in traits if t))
        label = v.get("name", "?") + (" — " + ", ".join(traits) if traits else "")
        if v.get("category") and v["category"] != "premade":
            label += f" ({v['category']})"
        voices.append({"id": v.get("voice_id"), "name": v.get("name", "?"), "label": label,
                       "preview": v.get("preview_url") or ""})
    voices.sort(key=lambda v: v["name"].lower())
    return {"voices": voices}


def main():
    signal.signal(signal.SIGTERM, lambda *_: sys.exit(0))
    save_path = None
    if "--save" in sys.argv:
        i = sys.argv.index("--save")
        save_path = sys.argv[i + 1] if i + 1 < len(sys.argv) else None
        del sys.argv[i:i + 2]
        if not save_path:
            print("No file to save to", file=sys.stderr)
            sys.exit(1)
    if sys.argv[1:2] == ["voices"]:
        print(json.dumps(list_voices(os.environ.get("ELEVENLABS_API_KEY", "").strip()), ensure_ascii=False))
        return
    if sys.argv[1:2] == ["google-voices"]:
        sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
        import googlecloud
        try:
            voices = googlecloud.list_voices(os.environ.get("GOOGLE_TTS_API_KEY", "").strip(), refresh="--refresh" in sys.argv)
        except RuntimeError as e:
            print(e, file=sys.stderr)
            sys.exit(1)
        print(json.dumps(voices, ensure_ascii=False))
        return
    if len(sys.argv) < 3 or not sys.argv[2].strip():
        sys.exit(1)
    text = sys.argv[2].strip()
    speed = {"normal": 1.0, "slow": 0.75, "slower": 0.5}.get(sys.argv[3] if len(sys.argv) > 3 else "normal", 1.0)
    code = resolve_code(sys.argv[1])
    if code == "auto":
        code = detect_language(text)

    sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
    import xtts
    engine = sys.argv[4] if len(sys.argv) > 4 else "xtts"
    if save_path:
        save(save_path, xtts, engine, code, text, speed)
        return
    if engine == "xtts" and xtts.is_installed() and xtts.language(code):
        speak_local(xtts, xtts.language(code), text, speed)
        return
    try:
        if engine == "elevenlabs":
            key = os.environ.get("ELEVENLABS_API_KEY", "").strip()
            if not key:
                raise RuntimeError("ElevenLabs: add your API key in Settings")
            if code.split("-")[0].lower() not in ELEVENLABS_LANGUAGES:
                raise RuntimeError(f"ElevenLabs doesn't speak this language ({code}). Choose another voice in Settings")
            speak_elevenlabs(key, text, speed)
        elif engine == "googlecloud":
            speak_googlecloud(code, text, speed)
        else:
            speak_google(code, text, speed)
    except RuntimeError as e:
        print(e, file=sys.stderr)
        sys.exit(1)


def speak_google(code, text, speed):
    with tempfile.TemporaryDirectory(prefix="qs-tts-") as tmp:
        files = []
        for i, part in enumerate(chunks(text)):
            url = "https://translate.google.com/translate_tts?" + urllib.parse.urlencode(
                {"ie": "UTF-8", "client": "tw-ob", "tl": code, "q": part}
            )
            path = os.path.join(tmp, f"{i:03}.mp3")
            try:
                with urllib.request.urlopen(urllib.request.Request(url, headers=UA), timeout=15) as r:
                    open(path, "wb").write(r.read())
            except OSError as e:
                raise RuntimeError(http_error("Google's voice", e))
            files.append(path)
        player = subprocess.Popen(["mpv", "--no-video", "--really-quiet", "--keep-open=no", "--idle=no", "--no-terminal", f"--speed={speed}", *files])
        try:
            player.wait()
        finally:
            player.terminate()


def speak_googlecloud(code, text, speed):
    """Play Google Cloud TTS audio, starting with the first piece while the rest is generated."""
    import googlecloud
    pieces = googlecloud.synthesize(os.environ.get("GOOGLE_TTS_API_KEY", "").strip(), code, text)
    first = next(pieces)  # Errors (key, language...) before starting the player
    player = mpv_stdin(speed)
    try:
        player.stdin.write(first)
        for audio in pieces:
            player.stdin.write(audio)
        player.stdin.close()
        player.wait()
    except BrokenPipeError:
        pass  # mpv closed
    finally:
        if player.poll() is None:
            player.terminate()


def mpv_stdin(speed, *extra):
    return subprocess.Popen([
        "mpv", "--no-video", "--really-quiet", "--keep-open=no", "--idle=no", "--no-terminal", f"--speed={speed}",
        "--cache=no", *extra, "-",
    ], stdin=subprocess.PIPE)


def speak_elevenlabs(key, text, speed):
    """Play ElevenLabs audio while it downloads (MP3 stream). RuntimeError with the reason on errors."""
    request = urllib.request.Request(
        f"https://api.elevenlabs.io/v1/text-to-speech/{ELEVENLABS_VOICE}/stream?output_format=mp3_44100_128",
        data=json.dumps({"text": text, "model_id": ELEVENLABS_MODEL}).encode(),
        headers={"xi-api-key": key, "Content-Type": "application/json", "Accept": "audio/mpeg"},
    )
    try:
        response = urllib.request.urlopen(request, timeout=20)
    except OSError as e:
        raise RuntimeError(http_error("ElevenLabs", e))
    player = mpv_stdin(speed)
    try:
        with response:
            while chunk := response.read(16384):
                player.stdin.write(chunk)
                player.stdin.flush()
        player.stdin.close()
        player.wait()
    except BrokenPipeError:
        pass  # mpv closed
    except OSError as e:
        raise RuntimeError(f"ElevenLabs: the connection dropped ({e})")
    finally:
        if player.poll() is None:
            player.terminate()


def speak_local(xtts, lang, text, speed):
    """Play XTTS audio while it's generated (raw float32 piped into mpv)."""
    player = mpv_stdin(speed, "--demuxer=rawaudio", "--demuxer-rawaudio-format=floatle",
                       "--demuxer-rawaudio-channels=1", f"--demuxer-rawaudio-rate={xtts.SAMPLE_RATE}")
    try:
        for chunk in xtts.stream(lang, text):
            player.stdin.write(chunk)
            player.stdin.flush()
        player.stdin.close()
        player.wait()  # Finish playing
    except BrokenPipeError:
        pass  # mpv closed
    except RuntimeError as e:
        raise RuntimeError(f"XTTS-v2: {e}")
    finally:
        if player.poll() is None:  # Stopped from the UI (SIGTERM) or failed
            player.terminate()


# ---- Saving to a file (--save) ----

def encoder(path, speed, *input_args):
    """ffmpeg writing an MP3 to path (speed applied with atempo); audio goes to its stdin unless input_args say otherwise."""
    tempo = ["-filter:a", f"atempo={speed}"] if speed != 1.0 else []
    return subprocess.Popen(["ffmpeg", "-y", "-loglevel", "error", *input_args, *tempo,
                             "-codec:a", "libmp3lame", "-q:a", "2", path],
                            stdin=subprocess.PIPE, stderr=subprocess.PIPE)


def finish(proc):
    proc.stdin.close()
    if proc.wait() != 0:
        raise RuntimeError("Couldn't write the audio file: " + proc.stderr.read().decode(errors="replace").strip())


def save(path, xtts, engine, code, text, speed):
    """Write the speech to an MP3 file; removes the partial file if it fails or is canceled (SIGTERM)."""
    done = False
    try:
        folder = os.path.dirname(os.path.abspath(path))
        try:
            os.makedirs(folder, exist_ok=True)  # The folder may be new (typed in the dialog)
        except OSError as e:
            raise RuntimeError(f"Couldn't create the folder {folder}: {e.strerror}")
        if engine == "xtts" and xtts.is_installed() and xtts.language(code):
            proc = encoder(path, speed, "-f", "f32le", "-ar", str(xtts.SAMPLE_RATE), "-ac", "1", "-i", "-")
            try:
                for chunk in xtts.stream(xtts.language(code), text):
                    proc.stdin.write(chunk)
            except RuntimeError as e:
                proc.kill()
                raise RuntimeError(f"XTTS-v2: {e}")
            finish(proc)
        elif engine == "elevenlabs":
            key = os.environ.get("ELEVENLABS_API_KEY", "").strip()
            if not key:
                raise RuntimeError("ElevenLabs: add your API key in Settings")
            if code.split("-")[0].lower() not in ELEVENLABS_LANGUAGES:
                raise RuntimeError(f"ElevenLabs doesn't speak this language ({code}). Choose another voice in Settings")
            request = urllib.request.Request(
                f"https://api.elevenlabs.io/v1/text-to-speech/{ELEVENLABS_VOICE}?output_format=mp3_44100_128",
                data=json.dumps({"text": text, "model_id": ELEVENLABS_MODEL}).encode(),
                headers={"xi-api-key": key, "Content-Type": "application/json", "Accept": "audio/mpeg"},
            )
            try:
                with urllib.request.urlopen(request, timeout=60) as r:
                    audio = r.read()
            except OSError as e:
                raise RuntimeError(http_error("ElevenLabs", e))
            proc = encoder(path, speed, "-f", "mp3", "-i", "-")
            proc.stdin.write(audio)
            finish(proc)
        elif engine == "googlecloud":
            import googlecloud
            audio = b"".join(googlecloud.synthesize(os.environ.get("GOOGLE_TTS_API_KEY", "").strip(), code, text))
            proc = encoder(path, speed, "-f", "mp3", "-i", "-")
            proc.stdin.write(audio)
            finish(proc)
        else:  # Google's voice (also when XTTS-v2 isn't downloaded or doesn't speak the language)
            with tempfile.TemporaryDirectory(prefix="qs-tts-") as tmp:
                parts = []
                for i, part in enumerate(chunks(text)):
                    url = "https://translate.google.com/translate_tts?" + urllib.parse.urlencode(
                        {"ie": "UTF-8", "client": "tw-ob", "tl": code, "q": part})
                    part_path = os.path.join(tmp, f"{i:03}.mp3")
                    try:
                        with urllib.request.urlopen(urllib.request.Request(url, headers=UA), timeout=15) as r:
                            open(part_path, "wb").write(r.read())
                    except OSError as e:
                        raise RuntimeError(http_error("Google's voice", e))
                    parts.append(part_path)
                list_path = os.path.join(tmp, "list.txt")
                with open(list_path, "w") as f:
                    f.writelines(f"file '{p}'\n" for p in parts)
                proc = encoder(path, speed, "-f", "concat", "-safe", "0", "-i", list_path)
                finish(proc)
        done = True
        print(path)
    except RuntimeError as e:
        print(e, file=sys.stderr)
        sys.exit(1)
    finally:
        if not done and os.path.exists(path):
            os.remove(path)


if __name__ == "__main__":
    main()
