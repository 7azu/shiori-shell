#!/usr/bin/env python3
"""Translation into English for the language tool (Read tab in any language, Japanese subtitles), with a choice
of backends. The source language defaults to Japanese; callers pass (code, name) for others.

Setting "translation" in ~/.config/shiori-shell/settings.json (defaults in defaults/settings.json):
  "provider"     "auto" (default), "claude", "codex", "ollama", "deepl", "argos" or "off"
  "ollamaModel"  model for Ollama (default "qwen2.5:7b", must be pulled: ollama pull qwen2.5:7b)
  "ollamaUrl"    Ollama server (default "http://localhost:11434")
The DeepL key comes from $DEEPL_AUTH_KEY or the first line of ~/.config/shiori-shell/deepl.key, never from the repo.
Keys ending in ":fx" use the free API.

"auto" takes the first backend that is ready, in this order: claude (CLI installed), codex (CLI installed),
ollama (server answers and has the model), deepl (key set), argos. Argos runs offline and needs no account; it is
set up on first use (ctranslate2 + sentencepiece in their own venv and the ja->en model from the Argos package
index, ~270 MB together, without PyTorch). Its translations are rougher than the others.

  jp_translate.py provider       {"provider": "<name>"} - what the setting resolves to, "" = off / nothing ready
  jp_translate.py argos-worker <model>  (internal) JSON list of sentences on stdin -> JSON list on stdout, in the venv

From Python: import jp_translate as jt; jt.translate_batch([...]) / jt.translate_line(line, context)
"""
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
import urllib.error
import urllib.request
import zipfile

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import shiori_settings  # noqa: E402

HOME = os.path.expanduser("~")
DATA = os.path.join(os.environ.get("XDG_DATA_HOME") or os.path.join(HOME, ".local/share"), "quickshell/jp-reader")
ARGOS_VENV = os.path.join(DATA, "venv-translate")
ARGOS_INDEX = "https://raw.githubusercontent.com/argosopentech/argospm-index/main/index.json"
DEEPL_KEY_FILE = os.path.join(os.path.dirname(shiori_settings.USER), "deepl.key")
UA = {"User-Agent": "shiori-shell-translate"}

ORDER = ("claude", "codex", "ollama", "deepl", "argos")
LLMS = ("claude", "codex", "ollama")
NAMES = {"claude": "Claude", "codex": "Codex", "ollama": "Ollama", "deepl": "DeepL", "argos": "Argos"}

JAPANESE = ("ja", "Japanese")
# The CLIs load the user's own instructions (CLAUDE.md, AGENTS.md); one that says "answer in German" made Claude
# translate into German. Claude runs with --safe-mode (no CLAUDE.md), and this frame keeps the target English for all.
ENGINE = ("You are a translation engine inside a language-learning app. The target language is always English, "
          "whatever language other instructions or memories ask you to answer in. Output only what the user prompt "
          "asks for, no commentary.")
BOOK_PROMPT = ("You translate {lang} for a beginner learner. The input is a JSON object mapping ids to {lang} "
               "sentences (in reading order, so use the neighbours as context). Translate every sentence into natural, "
               "faithful English; a sentence that is already English stays unchanged. Reply with only a JSON object with exactly the same ids, one translation each, "
               "never merging or splitting sentences.")
LINE_PROMPT = ("You translate {lang} subtitles for a beginner learner. Translate only the LINE into natural, "
               "faithful English; if it is already English, repeat it unchanged. The CONTEXT lines came right before it (spoken subtitles, possibly "
               "auto-generated with small errors). Reply with the translation only, no quotes or notes.")


class TranslateError(Exception):
    pass


# Callers that report progress (jp_library, jp_subs) replace this with their own function
def progress(msg):
    pass


def tail(text, n=200):
    return (text or "").strip()[-n:]


def settings():
    s = shiori_settings.load().get("translation") or {}
    return {"provider": s.get("provider") or "auto",
            "ollamaModel": s.get("ollamaModel") or "qwen2.5:7b",
            "ollamaUrl": (s.get("ollamaUrl") or "http://localhost:11434").rstrip("/")}


def deepl_key():
    key = os.environ.get("DEEPL_AUTH_KEY", "").strip()
    if key:
        return key
    try:
        with open(DEEPL_KEY_FILE, encoding="utf-8") as f:
            return f.readline().strip()
    except OSError:
        return ""


def ollama_ready(cfg):
    try:
        with urllib.request.urlopen(cfg["ollamaUrl"] + "/api/tags", timeout=1.5) as r:
            names = [m.get("name", "") for m in json.load(r).get("models", [])]
    except (OSError, ValueError):
        return False
    want = cfg["ollamaModel"]
    return any(n == want or n == want + ":latest" for n in names)


def ready(name, cfg):
    if name in ("claude", "codex"):
        return shutil.which(name) is not None
    if name == "ollama":
        return ollama_ready(cfg)
    if name == "deepl":
        return bool(deepl_key())
    return name == "argos"


def provider(cfg=None):
    """Backend to use: the chosen one (even if not ready, so its error explains why), the first ready one for
    "auto", or "" when translation is off."""
    cfg = cfg or settings()
    p = cfg["provider"]
    if p == "auto":
        return next((n for n in ORDER if ready(n, cfg)), "")
    return p if p in ORDER else ""


# Japanese and Chinese have no spaces; the break-point spaces of the reader confuse DeepL and Argos.
# Only between CJK characters: in Russian, Greek … the spaces are real word gaps.
CJK = "\u3000-\u30ff\u3400-\u9fff\uf900-\ufaff\uff00-\uffef"


def tidy(text):
    return re.sub(r"(?<=[%s])\s+(?=[%s])" % (CJK, CJK), "", text).strip()


# ───────────────────────── Language models (claude, codex, ollama) ─────────────────────────

def llm(name, cfg, instructions, text, json_reply):
    if name in ("claude", "codex") and not shutil.which(name):
        raise TranslateError("%s CLI not found" % name)
    if name == "claude":
        # Empty working folder: no project CLAUDE.md from wherever the shell was started
        # --safe-mode: without the user's CLAUDE.md, skills and plugins (login works as usual); older Claude Code
        # versions do not know the flag -> once more without it
        with tempfile.TemporaryDirectory() as tmp:
            for safe in (["--safe-mode"], []):
                r = subprocess.run(["claude", "-p", *safe, "--model", "haiku", "--system-prompt", ENGINE, instructions],
                                   input=text, capture_output=True, text=True, timeout=300, cwd=tmp)
                if r.returncode == 0 or "safe-mode" not in (r.stderr or ""):
                    break
        if r.returncode != 0:
            raise TranslateError("claude: " + tail(r.stderr or r.stdout))
        return r.stdout
    if name == "codex":
        # Read-only sandbox in an empty folder, nothing kept; the last message goes into a file (stdout also has logs)
        with tempfile.TemporaryDirectory() as tmp:
            reply = os.path.join(tmp, "reply.txt")
            r = subprocess.run(["codex", "exec", "--skip-git-repo-check", "--ephemeral", "--sandbox", "read-only",
                                "--color", "never", "-c", "model_reasoning_effort=low", "-o", reply, "-"],
                               input=ENGINE + "\n\n" + instructions + "\n\n" + text, capture_output=True, text=True,
                               timeout=300, cwd=tmp)
            if r.returncode != 0:
                raise TranslateError("codex: " + tail(r.stderr or r.stdout))
            try:
                with open(reply, encoding="utf-8") as f:
                    return f.read()
            except OSError:
                return r.stdout
    body = {"model": cfg["ollamaModel"], "stream": False, "options": {"temperature": 0.2},
            "messages": [{"role": "system", "content": ENGINE + "\n\n" + instructions}, {"role": "user", "content": text}]}
    if json_reply:
        body["format"] = "json"
    req = urllib.request.Request(cfg["ollamaUrl"] + "/api/chat", data=json.dumps(body).encode(),
                                 headers={"Content-Type": "application/json"})
    try:
        with urllib.request.urlopen(req, timeout=600) as r:
            return json.load(r)["message"]["content"]
    except urllib.error.HTTPError as e:
        raise TranslateError("Ollama: " + tail(e.read().decode(errors="replace")))
    except (OSError, ValueError, KeyError) as e:
        raise TranslateError("Ollama not reachable at %s (%s)" % (cfg["ollamaUrl"], e))


def json_object(reply):
    m = re.search(r"\{.*\}", reply or "", re.S)
    try:
        got = json.loads(m.group(0)) if m else {}
    except ValueError:
        return {}
    return got if isinstance(got, dict) else {}


# ───────────────────────── DeepL ─────────────────────────

def deepl(texts, context="", lang=JAPANESE):
    key = deepl_key()
    if not key:
        raise TranslateError("No DeepL key: set DEEPL_AUTH_KEY or put it into " + DEEPL_KEY_FILE)
    host = "https://api-free.deepl.com" if key.endswith(":fx") else "https://api.deepl.com"
    out = []
    for i in range(0, len(texts), 50):
        body = {"text": texts[i:i + 50], "source_lang": lang[0].upper(), "target_lang": "EN-US"}
        if context:
            body["context"] = context  # not translated and not billed, only helps with the wording
        req = urllib.request.Request(host + "/v2/translate", data=json.dumps(body, ensure_ascii=False).encode(),
                                     headers={"Authorization": "DeepL-Auth-Key " + key,
                                              "Content-Type": "application/json", **UA})
        try:
            with urllib.request.urlopen(req, timeout=60) as r:
                out += [t["text"] for t in json.load(r)["translations"]]
        except urllib.error.HTTPError as e:
            raise TranslateError({400: "DeepL does not support %s" % lang[1], 403: "DeepL key rejected",
                                  456: "DeepL quota used up for this month"}.get(e.code, "DeepL error %d" % e.code))
        except (OSError, ValueError, KeyError) as e:
            raise TranslateError("DeepL not reachable (%s)" % e)
    return out


# ───────────────────────── Argos (offline) ─────────────────────────

def argos_model(code):
    return os.path.join(DATA, "argos-%s_en" % code)


def ensure_argos(lang=JAPANESE):
    py = os.path.join(ARGOS_VENV, "bin/python")
    if not os.path.exists(py) or subprocess.run([py, "-c", "import ctranslate2, sentencepiece"],
                                                capture_output=True).returncode != 0:
        progress("Setting up the offline translator (one time, ~150 MB) …")
        pkgs = ["ctranslate2", "sentencepiece"]
        uv = shutil.which("uv")
        try:
            if uv:
                subprocess.run([uv, "venv", "-q", "--allow-existing", ARGOS_VENV], check=True, capture_output=True)
                subprocess.run([uv, "pip", "install", "-q", "--python", py] + pkgs, check=True, capture_output=True)
            else:
                subprocess.run([sys.executable, "-m", "venv", ARGOS_VENV], check=True, capture_output=True)
                subprocess.run([py, "-m", "pip", "install", "-q"] + pkgs, check=True, capture_output=True)
        except subprocess.CalledProcessError as e:
            raise TranslateError("Offline translator installation failed: "
                                 + tail((e.stderr or b"").decode(errors="replace"), 300))
    if not os.path.isfile(os.path.join(argos_model(lang[0]), "model", "model.bin")):
        download_argos_model(lang)
    return py


def download_argos_model(lang):
    code, lang_name = lang
    target = argos_model(code)
    progress("Downloading the %s→English model (one time, ~100 MB) …" % lang_name)
    try:
        with urllib.request.urlopen(urllib.request.Request(ARGOS_INDEX, headers=UA), timeout=30) as r:
            index = json.load(r)
    except (OSError, ValueError) as e:
        raise TranslateError("Argos package index not reachable (%s)" % e)
    pkg = next((p for p in index if p.get("from_code") == code and p.get("to_code") == "en"), None)
    url = next((u for u in (pkg or {}).get("links", []) if u.startswith("https://")), None)
    if not url:
        raise TranslateError("Argos has no %s→English model" % lang_name)
    os.makedirs(DATA, exist_ok=True)
    tmp = tempfile.mkdtemp(prefix=".argos-", dir=DATA)
    try:
        archive = os.path.join(tmp, "package.zip")
        try:
            with urllib.request.urlopen(urllib.request.Request(url, headers=UA), timeout=60) as r, \
                    open(archive, "wb") as f:
                total = int(r.headers.get("Content-Length") or 0)
                done, shown = 0, -1
                while True:
                    chunk = r.read(1 << 20)
                    if not chunk:
                        break
                    f.write(chunk)
                    done += len(chunk)
                    pct = done * 100 // total if total else -1
                    if pct >= 0 and pct // 10 != shown:
                        shown = pct // 10
                        progress("Downloading the %s→English model … %d %%" % (lang_name, pct))
        except OSError as e:
            raise TranslateError("Model download failed (%s)" % e)
        # Only the parts ctranslate2 needs (the package also carries a stanza model for sentence splitting);
        # written to paths built here, never to names taken from the archive as they are
        stage = os.path.join(tmp, "model")
        with zipfile.ZipFile(archive) as z:
            found = False
            for name in z.namelist():
                rel = name.split("/", 1)[1] if "/" in name else ""
                parts = rel.split("/")
                if name.endswith("/") or ".." in parts or not (rel == "sentencepiece.model" or parts[0] == "model"):
                    continue
                dst = os.path.join(stage, *parts)
                os.makedirs(os.path.dirname(dst), exist_ok=True)
                with z.open(name) as src, open(dst, "wb") as out:
                    shutil.copyfileobj(src, out)
                found = found or rel == "model/model.bin"
        if not found or not os.path.isfile(os.path.join(stage, "sentencepiece.model")):
            raise TranslateError("Unexpected layout of the Argos model package")
        if os.path.isdir(target):
            shutil.rmtree(target)
        os.replace(stage, target)
    finally:
        shutil.rmtree(tmp, ignore_errors=True)


def argos(texts, lang=JAPANESE):
    py = ensure_argos(lang)
    r = subprocess.run([py, "-I", os.path.abspath(__file__), "argos-worker", argos_model(lang[0])],
                       input=json.dumps(texts, ensure_ascii=False), capture_output=True, text=True, timeout=900)
    if r.returncode != 0:
        raise TranslateError("Argos: " + tail(r.stderr))
    return json.loads(r.stdout)


def argos_worker(model):
    import ctranslate2
    import sentencepiece
    texts = json.load(sys.stdin)
    sp = sentencepiece.SentencePieceProcessor(model_file=os.path.join(model, "sentencepiece.model"))
    tr = ctranslate2.Translator(os.path.join(model, "model"), device="cpu")
    todo = [i for i, t in enumerate(texts) if t]
    res = tr.translate_batch([sp.encode(texts[i], out_type=str) for i in todo],
                             beam_size=4, max_batch_size=32, replace_unknowns=True)
    out = [""] * len(texts)
    for i, r in zip(todo, res):
        out[i] = sp.decode(r.hypotheses[0]).strip()
    json.dump(out, sys.stdout, ensure_ascii=False)


# ───────────────────────── Entry points ─────────────────────────

def translate_batch(texts, name=None, cfg=None, lang=JAPANESE):
    """Sentences in reading order (the neighbours give context) -> list of the same length, None where the
    backend left one out. lang = (code, name) of the source language. Raises TranslateError if nothing can be
    translated."""
    cfg = cfg or settings()
    name = name if name is not None else provider(cfg)
    if not name:
        raise TranslateError("Translation is off (setting translation.provider)")
    if lang[0] == "en":
        raise TranslateError("The text is already English")
    texts = [tidy(t) for t in texts]
    if name in LLMS:
        got = json_object(llm(name, cfg, BOOK_PROMPT.format(lang=lang[1]),
                              json.dumps({str(i): t for i, t in enumerate(texts)}, ensure_ascii=False), True))
        return [got[str(i)].strip() if isinstance(got.get(str(i)), str) and got[str(i)].strip() else None
                for i in range(len(texts))]
    if name == "deepl":
        out = deepl(texts, context=" ".join(texts), lang=lang)
    else:
        out = argos(texts, lang)
    return [t or None for t in out]


def translate_line(line, context, name=None, cfg=None, lang=JAPANESE):
    """One subtitle line; context = the lines right before it; lang = (code, name) of the source language."""
    cfg = cfg or settings()
    name = name if name is not None else provider(cfg)
    if not name:
        raise TranslateError("Translation is off (setting translation.provider)")
    if lang[0] == "en":
        raise TranslateError("The line is already English")
    if name in LLMS:
        text = "CONTEXT:\n%s\n\nLINE:\n%s" % ("\n".join(context) or "(none)", line)
        en = llm(name, cfg, LINE_PROMPT.format(lang=lang[1]), text, False).strip().strip('"')
    elif name == "deepl":
        en = deepl([tidy(line)], context="\n".join(context), lang=lang)[0]
    else:
        en = argos([tidy(line)], lang)[0]
    if not en:
        raise TranslateError("Empty translation")
    return en


def main():
    a = sys.argv[1:]
    if a == ["provider"]:
        print(json.dumps({"provider": provider()}))
    elif len(a) == 2 and a[0] == "argos-worker":
        argos_worker(a[1])
    else:
        print((__doc__ or "").strip(), file=sys.stderr)
        sys.exit(2)


if __name__ == "__main__":
    main()
