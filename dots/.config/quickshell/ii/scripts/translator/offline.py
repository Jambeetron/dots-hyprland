#!/usr/bin/env python3
"""Offline mode: the NLLB-200 translation model (nllb.py) and the Wiktionary dictionaries (dictionary.py).

Run with the venv at ~/.local/share/quickshell-ii/stt-venv.

  offline.py list [--refresh]   -> {"languages": [{code, name, names, kind, installed, available, updatable, size}]}
                                   (--refresh: check for dictionary updates). The model is the entry with code "nllb".
  offline.py install <code>     -> JSON lines {"status": "downloading"|"progress"|"installing"|"done"|"error"|"cancelled"}
  offline.py remove <code>      -> {"status": "done"}
  offline.py update             -> rebuild dictionaries with a newer Wiktionary export, JSON lines
  offline.py translate <src> <tgt> <text>  -> {"translation"} or {"error"}

<code> is "nllb" for the translation model (one model, every language, ~3.4 GB), "xtts" for the
voice model of Listen (~1.9 GB) or a language code for its dictionary.
"""
import json
import os
import re
import shutil
import signal
import subprocess
import sys
import time
import urllib.error
import urllib.request

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

import dictionary as D  # noqa: E402
import nllb  # noqa: E402
import xtts  # noqa: E402

# Downloadable models: code -> (module with MODEL_REPO/MODEL_FILES/MODEL_DIR/is_installed, name, kind, approx. size)
MODELS = {
    "nllb": (nllb, "NLLB-200 3.3B", "model", 3_380_000_000),
    "xtts": (xtts, "XTTS-v2", "voice", 1_880_000_000),
}


def emit(obj):
    print(json.dumps(obj, ensure_ascii=False), flush=True)


def trans_names():
    """code -> [English name, endonym] from translate-shell (names used in the UI)."""
    try:
        out = subprocess.run(["trans", "-list-all", "-no-ansi"], capture_output=True, text=True, timeout=10).stdout
    except Exception:
        return {}
    names = {}
    for line in out.splitlines():
        parts = [p.strip() for p in re.split(r"\s{2,}", line.strip()) if p.strip()]
        if len(parts) >= 2:
            names[parts[0]] = parts[1:]
    return names


def model_files(module):
    """[(name, size)] of a model in its Hugging Face repo."""
    url = f"https://huggingface.co/api/models/{module.MODEL_REPO}/tree/main"
    with urllib.request.urlopen(urllib.request.Request(url, headers={"User-Agent": "quickshell-ii"}), timeout=20) as r:
        tree = json.loads(r.read())
    sizes = {f["path"]: f.get("size", 0) for f in tree}
    return [(name, sizes.get(name, 0)) for name in module.MODEL_FILES]


def model_size(module, approx):
    if all(os.path.exists(os.path.join(module.MODEL_DIR, f)) for f in module.MODEL_FILES):
        return sum(os.path.getsize(os.path.join(module.MODEL_DIR, f)) for f in module.MODEL_FILES)
    return approx  # Without asking the server


def cmd_list(refresh):
    names = trans_names()
    langs = [{
        "code": code, "name": name, "names": [name], "kind": kind, "available": True,
        "installed": module.is_installed(), "updatable": False, "size": model_size(module, approx),
    } for code, (module, name, kind, approx) in MODELS.items()]
    for code in sorted(D.NATIVE_EDITIONS | {"en"}):
        d = D.info(code, check_updates=refresh)
        n = names.get(code) or next((v for k, v in names.items() if k.split("-")[0] == code), [code])
        langs.append({
            "code": code, "name": n[0], "names": n, "kind": "dictionary",
            "available": d["available"], "installed": d["installed"], "updatable": d["updatable"],
            "size": d.get("size", 0),
        })
    emit({"languages": langs})


def install_model(code):
    module = MODELS[code][0]
    if module.is_installed():
        emit({"status": "done", "code": code})
        return
    emit({"status": "downloading", "code": code})
    files = model_files(module)
    total = sum(size for _, size in files)
    part = module.MODEL_DIR + ".part"
    os.makedirs(part, exist_ok=True)
    done, last_emit = 0, 0.0
    try:
        for name, size in files:
            path = os.path.join(part, name)
            if size and os.path.exists(path) and os.path.getsize(path) == size:
                done += size  # Already complete
                continue
            url = f"https://huggingface.co/{module.MODEL_REPO}/resolve/main/{name}"
            start = done
            for attempt in range(10):  # The connection can drop on big files: resume where it stopped
                have = os.path.getsize(path) if os.path.exists(path) else 0
                if size and have >= size:
                    break
                headers = {"User-Agent": "quickshell-ii", **({"Range": f"bytes={have}-"} if have else {})}
                try:
                    with urllib.request.urlopen(urllib.request.Request(url, headers=headers), timeout=60) as r, \
                            open(path, "ab" if have and r.status == 206 else "wb") as f:
                        done = start + (have if r.status == 206 else 0)
                        while chunk := r.read(1024 * 1024):
                            f.write(chunk)
                            done += len(chunk)
                            if time.time() - last_emit > 0.3:
                                last_emit = time.time()
                                emit({"status": "progress", "code": code, "done": done, "total": max(total, done)})
                    if not size:
                        break
                except (OSError, urllib.error.URLError):
                    if attempt == 9:
                        raise
                    time.sleep(3)
            done = start + (size or os.path.getsize(path))
    except BaseException:
        shutil.rmtree(part, ignore_errors=True)  # Cancelled or failed: don't leave GBs of partial files
        raise
    signal.signal(signal.SIGTERM, signal.SIG_IGN)
    emit({"status": "installing", "code": code})
    if os.path.exists(module.MODEL_DIR):
        shutil.rmtree(module.MODEL_DIR)
    os.replace(part, module.MODEL_DIR)
    emit({"status": "done", "code": code})


def cmd_install(code):
    if code in MODELS:
        install_model(code)
        return
    if not D.source_url(code):
        emit({"status": "error", "code": code, "error": "No offline dictionary for this language"})
        return
    emit({"status": "downloading", "code": code})
    D.cmd_install(code)


def cmd_remove(code):
    if code in MODELS:
        module = MODELS[code][0]
        module.stop_server()
        for path in (module.MODEL_DIR, module.MODEL_DIR + ".part"):
            shutil.rmtree(path, ignore_errors=True)
    else:
        for path in (D.db_path(code), D.db_path(code) + ".part"):
            if os.path.exists(path):
                os.remove(path)
    emit({"status": "done", "code": code})


def cmd_update():
    """Dictionaries with a newer Wiktionary export (the model doesn't change)."""
    for code in sorted(D.NATIVE_EDITIONS | {"en"}):
        if D.info(code, check_updates=True)["updatable"]:
            emit({"status": "downloading", "code": code})
            D.cmd_install(code, emit_done=False)
    emit({"status": "done"})


def cancelled(*_):
    """SIGTERM (cancel from the UI): stop and let the cleanup remove partial downloads."""
    raise KeyboardInterrupt


def main():
    signal.signal(signal.SIGTERM, cancelled)
    if len(sys.argv) < 2:
        sys.exit(1)
    cmd, args = sys.argv[1], sys.argv[2:]
    try:
        if cmd == "list":
            cmd_list("--refresh" in args)
        elif cmd == "install":
            cmd_install(args[0])
        elif cmd == "remove":
            cmd_remove(args[0])
        elif cmd == "update":
            cmd_update()
        elif cmd == "translate":
            emit(nllb.translate(*args[:3]))
    except KeyboardInterrupt:
        emit({"status": "cancelled"})
    except Exception as e:
        emit({"status": "error", "error": f"{type(e).__name__}: {e}"})


if __name__ == "__main__":
    main()
