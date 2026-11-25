#!/usr/bin/env python3
"""Helper for the video editor (services/VideoEditorState.qml).

  info <file>                          JSON with duration, size, rotation, audio
  thumbs <file> <folder> <count> <duration>   preview images, one line "<index> <path>" per finished image
  gallery <folder> <current>           videos in the folder: "F <path>" per file, then "E", then
                                       "T <preview>\\t<path>" (near the current video first, in the cache)
  export <file> <copy|overwrite> <start> <end> <rotation> <speed> <bright> <contrast> <sat> <mute>
         lines: "P <0..1>" progress, at the end "OK <path>" or "ERR <text>"
  compress <file> <low|medium|high> <start> <end> <rotation> <mute> <replace>
         HandBrakeCLI (x265). Lines: "P <0..1>", at the end "OK <copy|replaced|kept> <before> <after> <path>",
         "BIGGER <before> <after>" (did not get smaller, nothing changed) or "ERR <text>"

The original is never written directly: the export goes to a hidden file next to it and replaces
the target only when ffmpeg has finished successfully. SIGTERM (cancel in the editor) removes it.
"""
import hashlib
import json
import os
import re
import shutil
import signal
import subprocess
import sys
import tempfile
import threading

# Container -> (video encoder arguments, audio encoder arguments)
X264 = ["-c:v", "libx264", "-preset", "fast", "-crf", "18"]
AAC = ["-c:a", "aac", "-b:a", "192k"]
ENCODERS = {
    ".mp4": (X264, AAC),
    ".m4v": (X264, AAC),
    ".mov": (X264, AAC),
    ".mkv": (X264, AAC),
    ".webm": (["-c:v", "libvpx-vp9", "-crf", "30", "-b:v", "0", "-row-mt", "1", "-cpu-used", "4"],
              ["-c:a", "libopus", "-b:a", "160k"]),
}


# ffprobe name -> name for the scale filter, where they differ
SCALE_MATRIX = {"bt2020nc": "bt2020", "bt470bg": "bt470"}


def color_filter(brightness, contrast, saturation, matrix):
    """Computes exactly like MultiEffect in the preview (measured):
    x' = 0.5 + (S*x - 0.5) * (1 + contrast) + brightness, S = saturation around Rec.601 gray, without
    clipping in between. So in floating point (there the mixers do not clip): first saturation, then
    contrast + brightness; with alpha = 1, ra/ga/ba give the constant part. In 8 bit the
    error would be up to 54/255. Two mixers, because one only allows -2..2 per value."""
    if brightness == 0 and contrast == 0 and saturation == 0:
        return None
    # Color matrix like the preview: otherwise even the conversion to RGB differs visibly
    source = SCALE_MATRIX.get(matrix, matrix)
    weights = (0.299, 0.587, 0.114)
    k = 1 + saturation
    gain = 1 + contrast
    offset = 0.5 - 0.5 * gain + brightness
    names = "rgb"
    sat, tone = [], []
    for row in range(3):
        for col in range(3):
            sat.append(f"{names[row]}{names[col]}={(1 - k) * weights[col] + (k if row == col else 0):.6f}")
            tone.append(f"{names[row]}{names[col]}={gain if row == col else 0:.6f}")
        tone.append(f"{names[row]}a={offset:.6f}")
    return (f"scale=in_color_matrix={source},format=gbrapf32le,colorchannelmixer=" + ":".join(sat)
            + ",colorchannelmixer=" + ":".join(tone) + f",scale=out_color_matrix={source}:out_range=tv")


def probe(path):
    out = subprocess.run(
        ["ffprobe", "-v", "error", "-show_format", "-show_streams", "-of", "json", path],
        check=True, capture_output=True, text=True).stdout
    data = json.loads(out)
    video = next((s for s in data["streams"] if s.get("codec_type") == "video"
                  and not s.get("disposition", {}).get("attached_pic")), None)
    if video is None:
        raise ValueError("no video stream")
    rotation = 0
    for side in video.get("side_data_list", []):
        if "rotation" in side:
            rotation = int(side["rotation"])
    # Without a tag every program guesses: like Qt in the preview, by the image height (measured)
    matrix = video.get("color_space")
    if matrix in (None, "unknown", "reserved", "gbr"):
        matrix = "bt709" if int(video["height"]) > 576 else "smpte170m"
    return {
        "matrix": matrix,
        "duration": float(data["format"].get("duration") or video.get("duration") or 0),
        "width": int(video["width"]),
        "height": int(video["height"]),
        "rotation": (-rotation) % 360,
        "hasAudio": any(s.get("codec_type") == "audio" for s in data["streams"]),
    }


def cmd_info(path):
    print(json.dumps(dict(probe(path), size=os.path.getsize(path))), flush=True)


def cmd_thumbs(path, folder, count, duration):
    os.makedirs(folder, exist_ok=True)
    count = int(count)
    duration = float(duration)
    for i in range(count):
        # Middle of the section, so the first image is not almost always black
        at = duration * (i + 0.5) / count
        out = os.path.join(folder, f"t{i:03d}.jpg")
        # Back to an already visited video: only fetch the missing images
        if os.path.exists(out):
            print(i, out, flush=True)
            continue
        # -ss before -i jumps to the keyframe, that stays fast even for long movies
        done = subprocess.run(
            ["ffmpeg", "-nostdin", "-y", "-v", "error", "-ss", f"{at:.3f}", "-i", path,
             "-frames:v", "1", "-vf", "scale=-2:180", "-q:v", "4", out],
            capture_output=True)
        if done.returncode == 0 and os.path.exists(out):
            print(i, out, flush=True)


VIDEO_EXTENSIONS = (".mp4", ".m4v", ".mkv", ".webm", ".mov", ".avi", ".wmv", ".flv", ".mpg", ".mpeg", ".ts", ".ogv", ".3gp")


def natural_key(name):
    return [int(part) if part.isdigit() else part.lower() for part in re.split(r"(\d+)", name)]


def cmd_gallery(folder, current):
    names = sorted((n for n in os.listdir(folder)
                    if n.lower().endswith(VIDEO_EXTENSIONS) and not n.startswith(".")
                    and "\n" not in n and os.path.isfile(os.path.join(folder, n))), key=natural_key)
    paths = [os.path.join(folder, n) for n in names]
    for path in paths:
        print("F", path, flush=True)
    print("E", flush=True)
    at = paths.index(current) if current in paths else 0
    for index in sorted(range(len(paths)), key=lambda i: abs(i - at)):
        path = paths[index]
        out = cached_thumb(path)
        if out:
            print(f"T {out}\t{path}", flush=True)


ENCRYPTED_FS = ("fuse.gocryptfs", "fuse.cryfs", "fuse.encfs", "fuse.securefs")


def encrypted_mounts():
    """Mounted encrypted folders (e.g. ~/Vault with gocryptfs) according to /proc/mounts."""
    found = []
    try:
        with open("/proc/mounts", encoding="utf-8") as f:
            for line in f:
                parts = line.split()
                if len(parts) >= 3 and parts[2] in ENCRYPTED_FS:
                    # Spaces are \040 in /proc/mounts
                    found.append(parts[1].replace("\\040", " "))
    except OSError:
        pass
    return found


def in_encrypted(path):
    return any(path == m or path.startswith(m + "/") for m in encrypted_mounts())


def cached_thumb(path):
    """Preview image (10 % of the duration) in the permanent cache; also used by the folder browser
    (scripts/media_browse.py). None if the video cannot be read - and always for files in
    an unlocked vault: the cache lies unencrypted on the disk (just as yazi creates no
    previews there)."""
    if in_encrypted(os.path.abspath(path)):
        return None
    cache = os.path.join(os.environ.get("XDG_CACHE_HOME") or os.path.expanduser("~/.cache"), "quickshell-video-thumbs")
    os.makedirs(cache, exist_ok=True)
    try:
        stat = os.stat(path)
    except OSError:
        return None
    # Path + modification time + size: edited files automatically get a new image
    key = hashlib.md5(f"{path}|{stat.st_mtime_ns}|{stat.st_size}".encode()).hexdigest()
    out = os.path.join(cache, key + ".jpg")
    if not os.path.exists(out):
        try:
            at_sec = probe(path)["duration"] * 0.1
        except (subprocess.CalledProcessError, ValueError, KeyError, json.JSONDecodeError):
            return None
        subprocess.run(["ffmpeg", "-nostdin", "-y", "-v", "error", "-ss", f"{at_sec:.3f}", "-i", path,
                        "-frames:v", "1", "-vf", "scale=-2:160", "-q:v", "5", out], capture_output=True)
    return out if os.path.exists(out) else None


def free_copy_name(path, ext):
    folder, name = os.path.split(path)
    stem = os.path.splitext(name)[0]
    candidate = os.path.join(folder, f"{stem}-edited{ext}")
    n = 2
    while os.path.exists(candidate):
        candidate = os.path.join(folder, f"{stem}-edited-{n}{ext}")
        n += 1
    return candidate


def cmd_export(path, mode, start, end, rotation, speed, brightness, contrast, saturation, mute):
    start, end, speed = float(start), float(end), float(speed)
    brightness, contrast, saturation = float(brightness), float(contrast), float(saturation)
    rotation, mute = int(rotation), mute == "1"
    source = os.path.realpath(path)
    source_ext = os.path.splitext(source)[1].lower()
    # Formats without a matching encoder (avi, wmv ...): copy as mp4, overwriting is not possible there
    ext = source_ext if source_ext in ENCODERS else ".mp4"
    if mode == "overwrite" and ext != source_ext:
        print("ERR this format can only be saved as a copy", flush=True)
        return 1
    target = source if mode == "overwrite" else free_copy_name(source, ext)
    video_enc, audio_enc = ENCODERS[ext]
    info = probe(source)
    trimmed = start > 0.01 or end < info["duration"] - 0.01

    filters = []
    if rotation == 90:
        filters.append("transpose=1")
    elif rotation == 180:
        filters.append("hflip,vflip")
    elif rotation == 270:
        filters.append("transpose=2")
    color = color_filter(brightness, contrast, saturation, info["matrix"])
    if color:
        filters.append(color)
    if speed != 1:
        filters.append(f"setpts=PTS/{speed}")
    filters.append("format=yuv420p")

    args = ["ffmpeg", "-nostdin", "-y", "-v", "error", "-progress", "pipe:1", "-nostats"]
    args += ["-ss", f"{start:.3f}", "-t", f"{end - start:.3f}", "-i", source]
    args += ["-map", "0:v:0", "-vf", ",".join(filters)] + video_enc
    if not mute:
        args += ["-map", "0:a?"]
        if speed != 1:
            args += ["-af", f"atempo={speed}"]
        # Re-encode the audio only when needed: exact cut, speed or a different container
        args += audio_enc if (trimmed or speed != 1 or ext != source_ext) else ["-c:a", "copy"]
    if speed == 1 and ext == source_ext:
        # Subtitles and fonts (anime mkv) are kept; with a different speed they would no longer fit
        args += ["-map", "0:s?", "-c:s", "copy"]
        if ext == ".mkv":
            args += ["-map", "0:t?", "-c:t", "copy"]
    if color:
        # The export is re-encoded: state the matrix, so players do not have to guess again
        args += ["-colorspace", info["matrix"]]
    args += ["-map_metadata", "0"]
    if trimmed or speed != 1:
        args += ["-map_chapters", "-1"]
    if ext in (".mp4", ".m4v", ".mov"):
        args += ["-movflags", "+faststart"]

    folder = os.path.dirname(target)
    try:
        handle, temp = tempfile.mkstemp(prefix=".qs-edit-", suffix=ext, dir=folder)
        os.close(handle)
    except OSError:
        print(f"ERR no write access to {folder}", flush=True)
        return 1
    args.append(temp)

    proc = subprocess.Popen(args, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)

    def abort(*_):
        proc.terminate()
        try:
            proc.wait(timeout=5)
        except subprocess.TimeoutExpired:
            proc.kill()
        if os.path.exists(temp):
            os.remove(temp)
        sys.exit(130)

    signal.signal(signal.SIGTERM, abort)
    signal.signal(signal.SIGINT, abort)

    length = max(0.001, (end - start) / speed)
    for line in proc.stdout:
        if line.startswith("out_time_us="):
            value = line.split("=", 1)[1].strip()
            if value.lstrip("-").isdigit():
                print(f"P {min(1.0, max(0.0, int(value) / 1e6 / length)):.4f}", flush=True)
    proc.wait()
    if proc.returncode != 0:
        message = proc.stderr.read().strip().splitlines()
        if os.path.exists(temp):
            os.remove(temp)
        print("ERR " + (message[-1] if message else "ffmpeg failed"), flush=True)
        return 1
    if os.path.exists(target):
        shutil.copymode(target, temp)
    else:
        os.chmod(temp, 0o666 & ~current_umask())
    os.replace(temp, target)
    print("OK " + target, flush=True)
    return 0


# Levels for "Compress" (HandBrakeCLI, x265 8 bit: plays everywhere, also on phones).
# short = the shorter image side at most this big (never upscaled), None = original size
COMPRESS_LEVELS = {
    "low": {"rf": 30, "short": 720, "preset": "fast", "audio": 96},
    "medium": {"rf": 26, "short": 1080, "preset": "fast", "audio": 128},
    "high": {"rf": 22, "short": None, "preset": "medium", "audio": 160},
}
PERCENT = re.compile(rb"(\d+(?:\.\d+)?) %")


def creation_time(path):
    out = subprocess.run(
        ["ffprobe", "-v", "error", "-show_entries", "format_tags=creation_time", "-of", "default=nw=1:nk=1", path],
        capture_output=True, text=True).stdout.strip()
    return out or None


def free_name(folder, stem, ext):
    candidate = os.path.join(folder, stem + ext)
    n = 2
    while os.path.exists(candidate):
        candidate = os.path.join(folder, f"{stem}-{n}{ext}")
        n += 1
    return candidate


def die_with_parent():
    """Quickshell simply leaves child processes running when it quits (shell restart), the script
    would then die at the next print into the closed pipe without cleaning up (measured). This way
    SIGTERM comes instead, and the cancel handler removes the half-written file. Linux only."""
    try:
        import ctypes
        libc = ctypes.CDLL(None, use_errno=True)
        libc.prctl(1, signal.SIGTERM)  # PR_SET_PDEATHSIG
        if os.getppid() == 1:  # parent already gone before prctl took effect
            os.kill(os.getpid(), signal.SIGTERM)
    except (OSError, AttributeError):
        pass


def cmd_compress(path, level, start, end, rotation, mute, replace):
    """Shrinks with HandBrakeCLI. Copy "<name>-compressed.mp4" or (replace=1) instead of the original,
    which then goes to the trash. Capture date (creation_time) and modification time stay as in the
    original - otherwise HandBrake puts in the date of the conversion. If the file does not get smaller,
    everything stays as it was ("BIGGER")."""
    if level not in COMPRESS_LEVELS:
        print("ERR unknown level", flush=True)
        return 1
    if shutil.which("HandBrakeCLI") is None:
        print("ERR HandBrakeCLI is not installed", flush=True)
        return 1
    cfg = COMPRESS_LEVELS[level]
    start, end, rotation = float(start), float(end), int(rotation) % 360
    mute, replace = mute == "1", replace == "1"
    source = os.path.realpath(path)
    folder, name = os.path.split(source)
    stem = os.path.splitext(name)[0]
    try:
        info = probe(source)
    except (subprocess.CalledProcessError, ValueError, KeyError, json.JSONDecodeError):
        print("ERR could not read this video", flush=True)
        return 1
    trimmed = start > 0.01 or end < info["duration"] - 0.01
    # Do not squeeze portrait videos (phone) to 720 px height: the limit applies to the shorter side.
    # info has the dimensions without the metadata rotation that HandBrake applies itself -> both rotations count
    turned = (info["rotation"] + rotation) % 180 != 0
    out_w, out_h = (info["height"], info["width"]) if turned else (info["width"], info["height"])

    args = ["HandBrakeCLI", "-i", source, "--format", "av_mp4", "--optimize",
            "-e", "x265", "-q", str(cfg["rf"]), "--encoder-preset", cfg["preset"],
            "--crop-mode", "none", "--non-anamorphic", "--keep-metadata"]
    if cfg["short"]:
        if out_w >= out_h:
            args += ["--maxHeight", str(cfg["short"])]
        else:
            args += ["--maxWidth", str(cfg["short"])]
    if rotation:
        # Optional argument: only attached with "=", otherwise HandBrake silently ignores it
        args += [f"--rotate=angle={rotation}"]
    if trimmed:
        args += ["--start-at", f"seconds:{start:.3f}", "--stop-at", f"seconds:{end - start:.3f}"]
    if mute or not info["hasAudio"]:
        args += ["-a", "none"]
    else:
        args += ["-E", "av_aac", "-B", str(cfg["audio"]), "--mixdown", "stereo"]

    try:
        handle, temp = tempfile.mkstemp(prefix=".qs-compress-", suffix=".mp4", dir=folder)
        os.close(handle)
    except OSError:
        print(f"ERR no write access to {folder}", flush=True)
        return 1
    args += ["-o", temp]
    # Watchdog: if this script is killed hard (SIGKILL, e.g. when Quickshell quits normally), no
    # signal handler helps anymore. A detached mini process deletes the half-written file as soon as it is gone;
    # after success the file no longer exists under this name, then it deletes nothing
    subprocess.Popen(
        ["sh", "-c", 'while kill -0 "$1" 2>/dev/null; do sleep 1; done; rm -f -- "$2" "$2.meta.mp4"',
         "sh", str(os.getpid()), temp],
        stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, start_new_session=True)

    # HandBrake dies along with it if this script is killed hard (otherwise it would keep computing for nothing)
    def handbrake_setup():
        try:
            import ctypes
            ctypes.CDLL(None).prctl(1, signal.SIGKILL)  # PR_SET_PDEATHSIG
        except (OSError, AttributeError):
            pass

    proc = subprocess.Popen(args, stdin=subprocess.DEVNULL, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                            preexec_fn=handbrake_setup)
    # stderr (HandBrake's log) only in memory: a log file would lie unencrypted next to a vault
    log_tail = []

    def drain():
        for raw in proc.stderr:
            log_tail.append(raw.decode(errors="replace").strip())
            del log_tail[:-20]

    reader = threading.Thread(target=drain, daemon=True)
    reader.start()

    def cleanup_temp():
        for leftover in (temp, temp + ".meta.mp4"):
            if os.path.exists(leftover):
                os.remove(leftover)

    def abort(*_):
        proc.terminate()
        try:
            proc.wait(timeout=5)
        except subprocess.TimeoutExpired:
            proc.kill()
        cleanup_temp()
        sys.exit(130)

    signal.signal(signal.SIGTERM, abort)
    signal.signal(signal.SIGINT, abort)
    signal.signal(signal.SIGHUP, abort)
    die_with_parent()

    def emit(text):
        try:
            print(text, flush=True)
        except BrokenPipeError:
            abort()

    # Progress comes as "Encoding: task 1 of 1, 12.34 % (...)" with \r instead of a line end
    out_fd = proc.stdout.fileno()  # type: ignore[union-attr]
    buffer = b""
    last = -1.0
    while True:
        chunk = os.read(out_fd, 4096)
        if not chunk:
            break
        buffer = (buffer + chunk)[-512:]
        found = PERCENT.findall(buffer)
        if found:
            value = min(1.0, float(found[-1]) / 100)
            if value - last >= 0.002:
                last = value
                emit(f"P {value:.4f}")
    proc.wait()
    reader.join(timeout=2)
    if proc.returncode != 0 or not os.path.exists(temp) or os.path.getsize(temp) == 0:
        cleanup_temp()
        lines = [l for l in log_tail if l]
        print("ERR " + (lines[-1] if lines else "HandBrake failed"), flush=True)
        return 1

    before = os.path.getsize(source)
    after = os.path.getsize(temp)
    if after >= before:
        cleanup_temp()
        print(f"BIGGER {before} {after}", flush=True)
        return 0

    # Put the capture date back: only remux (-c copy), takes fractions of a second
    # If the original had none, better none at all than today's date (it would sort wrong otherwise)
    stamp = creation_time(source) or ""
    fixed = temp + ".meta.mp4"
    done = subprocess.run(
        ["ffmpeg", "-nostdin", "-y", "-v", "error", "-i", temp, "-map", "0", "-c", "copy",
         "-map_metadata", "0", "-metadata", f"creation_time={stamp}", "-movflags", "+faststart", fixed],
        capture_output=True)
    if done.returncode == 0 and os.path.getsize(fixed) > 0:
        os.replace(fixed, temp)
    elif os.path.exists(fixed):
        os.remove(fixed)

    shutil.copymode(source, temp)
    stat = os.stat(source)
    os.utime(temp, ns=(stat.st_atime_ns, stat.st_mtime_ns))

    if replace:
        # First the original to the trash (recoverable), then the new file in its place
        trashed = subprocess.run(["gio", "trash", "--", source], capture_output=True).returncode == 0
        if trashed:
            target = source if source.lower().endswith(".mp4") else free_name(folder, stem, ".mp4")
            os.replace(temp, target)
            print(f"OK replaced {before} {os.path.getsize(target)} {target}", flush=True)
            return 0
        # Trash does not work (e.g. a drive without a trash): delete nothing, keep it as a copy
    target = free_name(folder, stem + "-compressed", ".mp4")
    os.replace(temp, target)
    print(f"OK {'copy' if not replace else 'kept'} {before} {os.path.getsize(target)} {target}", flush=True)
    return 0


def current_umask():
    mask = os.umask(0)
    os.umask(mask)
    return mask


def main():
    commands = {"info": cmd_info, "thumbs": cmd_thumbs, "gallery": cmd_gallery, "export": cmd_export,
                "compress": cmd_compress}
    if len(sys.argv) < 2 or sys.argv[1] not in commands:
        print(__doc__, file=sys.stderr)
        return 2
    try:
        return commands[sys.argv[1]](*sys.argv[2:]) or 0
    except (subprocess.CalledProcessError, ValueError, KeyError, json.JSONDecodeError) as error:
        print(f"ERR {error}", flush=True)
        return 1


if __name__ == "__main__":
    sys.exit(main())
