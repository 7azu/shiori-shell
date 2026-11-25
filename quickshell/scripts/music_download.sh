#!/usr/bin/env bash
# Downloads a song from SoundCloud, YouTube (Music) or Spotify as mp3 into the music folder.
#   Usage: music_download.sh <link> <music folder>
#
# SoundCloud -> yt-dlp
# YouTube    -> yt-dlp (music.youtube.com, youtube.com, youtu.be)
# Spotify    -> 1) spotdl (title/artist/cover from Spotify, audio from YouTube Music)
#               2) fallback if spotdl fails (e.g. AudioProviderError):
#                  spotdl only gives the song data, the audio is fetched by plain
#                  yt-dlp via a YouTube search (duration match), tags + cover are
#                  set afterwards with ffmpeg. The Spotify file itself is
#                  DRM-protected and never used.
#
# Output (one line per event, read by MusicPickerState):
#   STATUS|text      status message
#   PROG|percent     progress 0-100
#   DONE|name        done (file name without .mp3, for several "N Songs")
#   ERR|text         error
# The log (also the normal output of yt-dlp) is in /tmp/qs_music_dl.log
#
# Always exactly ONE song per link (once a single link loaded 166 songs into the library, and the download
# "hung" forever): YouTube/SoundCloud links are checked first (playlist, mix, channel, profile, likes ->
# rejected), yt-dlp stops after one song (--max-downloads 1), and if several files still
# come out (e.g. a Spotify short link to an album), nothing is taken. Time limit per download: DL_TIMEOUT.

url="$1"
dir="${2%/}"
log=/tmp/qs_music_dl.log
DL_TIMEOUT=900   # s; a single song never takes longer

emit() { printf '%s|%s\n' "$1" "$2"; }
fail() { emit ERR "$1"; exit 1; }
need() { command -v "$1" > /dev/null 2>&1 || fail "$1 missing ($2)"; }

# YouTube login: yt-dlp reads the cookies fresh from Zen on every download (zen_cookies.sh),
# that avoids most bot checks. Without a Zen profile it downloads without cookies.
# Another source by environment variable, e.g. QS_COOKIE_BROWSER=chromium.
cookie_spec="${QS_COOKIE_BROWSER:-$("$(dirname "$0")/zen_cookies.sh")}"
ytdlp_extra=()
[ -n "$cookie_spec" ] && ytdlp_extra=(--cookies-from-browser "$cookie_spec")
botcheck_re='not a bot|confirm you.re not|sign in to confirm'

# yt-dlp with a progress display; the rest of the arguments goes straight to yt-dlp
run_ytdlp() {
    timeout "$DL_TIMEOUT" yt-dlp --ignore-config --newline "${ytdlp_extra[@]}" \
        --progress-template "download:PROG|%(progress._percent_str)s" "$@" 2>> "$log" | while IFS= read -r line; do
        case "$line" in
            PROG\|*)
                p="${line#PROG|}"
                p="${p//[^0-9.]/}"
                if [ -n "$p" ]; then
                    emit PROG "$p"
                    case "$p" in 100*) emit STATUS "Converting …" ;; esac
                fi
                ;;
            *) printf '%s\n' "$line" >> "$log" ;;   # e.g. "[download] Downloading item 3 of 166"
        esac
    done
    return "${PIPESTATUS[0]}"
}

# Is the link a single song? yt-dlp only reads the metadata (1-3 s). --no-playlist: "watch?v=X&list=..."
# counts as the one song. -> 0 single, 1 playlist/mix/channel/profile, 2 cannot be checked (then the
# safeguards below still load at most one song)
link_kind() {
    local type
    type=$(timeout 60 yt-dlp --ignore-config --no-warnings "${ytdlp_extra[@]}" --no-playlist --flat-playlist \
        --playlist-end 1 -J -- "$url" 2>> "$log" \
        | python3 -c 'import json, sys; print(json.load(sys.stdin).get("_type") or "video")' 2>> "$log")
    echo "Link check: ${type:-not checkable}" >> "$log"
    case "$type" in
        video | url) return 0 ;;
        playlist | multi_video) return 1 ;;
        *) return 2 ;;
    esac
}

# Spotify fallback: song data from spotdl, audio via a yt-dlp search
spotify_fallback() {
    command -v yt-dlp > /dev/null 2>&1 || return 1
    command -v python3 > /dev/null 2>&1 || return 1

    emit STATUS "Fetching song info …"
    timeout 60 spotdl save "$url" --save-file "$tmp/meta.spotdl" >> "$log" 2>&1
    [ -s "$tmp/meta.spotdl" ] || return 1

    local title artist album dur cover
    IFS=$'\t' read -r title artist album dur cover < <(python3 - "$tmp/meta.spotdl" << 'PY'
import json, sys
d = json.load(open(sys.argv[1]))
s = d[0] if isinstance(d, list) else d
arts = s.get("artists") or ([s["artist"]] if s.get("artist") else [])
clean = lambda x: str(x or "").replace("\t", " ").replace("\n", " ").strip()
print("\t".join([
    clean(s.get("name")),
    clean(", ".join(arts)),
    clean(s.get("album_name")),
    str(int(s.get("duration") or 0)),
    clean(s.get("cover_url")),
]))
PY
)
    [ -n "$title" ] || return 1
    local first="${artist%%,*}"

    emit STATUS "Searching YouTube …"
    local filter=()
    if [ "${dur:-0}" -gt 0 ] 2> /dev/null; then
        filter=(--match-filter "duration>=$((dur - 6)) & duration<=$((dur + 10))")
    fi
    rm -f "$tmp"/dl.*
    # --max-downloads 1 ends yt-dlp with code 101, that is not an error here
    run_ytdlp -f "bestaudio/best" -x --audio-format mp3 --audio-quality 0 \
        "${filter[@]}" --max-downloads 1 -o "dl.%(ext)s" "ytsearch5:$first $title"
    if [ ! -s "$tmp/dl.mp3" ] && [ ${#filter[@]} -gt 0 ]; then
        # No hit with a matching length -> take the first hit
        emit STATUS "Searching again …"
        run_ytdlp -f "bestaudio/best" -x --audio-format mp3 --audio-quality 0 \
            --max-downloads 1 -o "dl.%(ext)s" "ytsearch1:$first $title"
    fi
    [ -s "$tmp/dl.mp3" ] || return 1

    # Set tags + cover
    emit STATUS "Writing tags …"
    [ -n "$cover" ] && curl -fsSL --max-time 20 "$cover" -o "$tmp/cover.jpg" 2>> "$log"
    local fname="$artist - $title"
    fname="${fname//\//_}"
    fname="${fname#.}"
    local ok=1
    if [ -s "$tmp/cover.jpg" ]; then
        ffmpeg -y -loglevel error -i "$tmp/dl.mp3" -i "$tmp/cover.jpg" -map 0:a -map 1:v -c copy -id3v2_version 3 \
            -metadata title="$title" -metadata artist="$artist" -metadata album="$album" \
            -metadata:s:v title="Album cover" -metadata:s:v comment="Cover (front)" \
            "$tmp/final.mp3" 2>> "$log" && ok=0
    fi
    if [ "$ok" -ne 0 ]; then
        ffmpeg -y -loglevel error -i "$tmp/dl.mp3" -c copy -id3v2_version 3 \
            -metadata title="$title" -metadata artist="$artist" -metadata album="$album" \
            "$tmp/final.mp3" 2>> "$log" || return 1
    fi
    rm -f "$tmp/dl.mp3"
    mv -f "$tmp/final.mp3" "$tmp/$fname.mp3"
    return 0
}

[ -n "$url" ] && [ -n "$dir" ] || fail "Link or folder missing"
mkdir -p "$dir" 2> /dev/null || fail "Folder is not writable"

# ---- Detect the service (only these link forms are accepted) ----
case "$url" in
    https://open.spotify.com/* | https://spotify.link/* | spotify:track:*) svc=spotify ;;
    https://soundcloud.com/* | https://www.soundcloud.com/* | https://m.soundcloud.com/* | https://on.soundcloud.com/* | https://snd.sc/*) svc=soundcloud ;;
    https://music.youtube.com/* | https://www.youtube.com/* | https://m.youtube.com/* | https://youtube.com/* | https://youtu.be/*) svc=youtube ;;
    *) fail "Only Spotify, SoundCloud or YouTube links" ;;
esac

case "$svc:$url" in
    spotify:*/album/* | spotify:*/playlist/* | spotify:*/artist/*) fail "Please link a single song" ;;
    soundcloud:*/sets/*) fail "Please link a single song" ;;
    youtube:*/playlist\?* | youtube:*/browse/* | youtube:*/channel/*) fail "Please link a single song" ;;
esac

need ffmpeg "sudo pacman -S ffmpeg"

tmp=$(mktemp -d /tmp/qs_dl.XXXXXX) || fail "Could not create temp folder"
trap 'rm -rf "$tmp"' EXIT
cd "$tmp" || fail "Temp folder not reachable"
: > "$log"
shopt -s nullglob

# ---- Download ----
if [ "$svc" = soundcloud ] || [ "$svc" = youtube ]; then
    need yt-dlp "sudo pacman -S yt-dlp"
    emit STATUS "Checking link …"
    link_kind
    [ $? -eq 1 ] && fail "This link is a playlist, mix or channel – please link a single song"
    if [ "$svc" = youtube ]; then
        emit STATUS "Downloading from YouTube …"
    else
        emit STATUS "Downloading from SoundCloud …"
    fi
    # --no-playlist: for links like watch?v=...&list=... load only the one song
    # --max-downloads 1: hard limit, in case the check above misses something (code 101 is not an error then)
    download_direct() {
        run_ytdlp --no-playlist --no-warnings --max-downloads 1 \
            -f "bestaudio/best" -x --audio-format mp3 --audio-quality 0 \
            --embed-thumbnail --convert-thumbnails jpg --embed-metadata \
            -o "%(artist,uploader)s - %(title)s.%(ext)s" -- "$url"
    }
    download_direct
    dl_rc=$?
else
    need spotdl "pipx install spotdl"
    emit STATUS "Searching song …"
    timeout 60 spotdl download "$url" --format mp3 \
        --output "{artists} - {title}.{output-ext}" 2>&1 | tr '\r' '\n' | tee -a "$log" | while IFS= read -r line; do
        case "$line" in
            *ownloading*) emit STATUS "Downloading …" ;;
            *onverting* | *Processing*) emit STATUS "Converting …" ;;
        esac
    done
    files=("$tmp"/*.mp3)
    if [ ${#files[@]} -eq 0 ]; then
        emit STATUS "spotdl failed, trying another way …"
        spotify_fallback
    fi
fi

# ---- Collect the result ----
files=("$tmp"/*.mp3)
if [ ${#files[@]} -eq 0 ]; then
    [ "${dl_rc:-0}" -eq 124 ] && fail "Download took longer than $((DL_TIMEOUT / 60)) min – aborted"
    if grep -qiE 'javascript runtime|js runtime|n challenge|challenge solving' "$log"; then
        fail "yt-dlp needs a JavaScript runtime (sudo pacman -S deno)"
    fi
    if grep -qiE "$botcheck_re" "$log"; then
        fail "YouTube bot check: log in to YouTube in Zen or wait a moment"
    fi
    reason=$(grep -iE 'error|failed|unable|rate' "$log" | tail -n1 | cut -c1-80)
    fail "Download failed${reason:+: $reason}"
fi

# One link = one song. More means: the link was a collection after all -> nothing into the library
if [ ${#files[@]} -gt 1 ]; then
    printf 'Several files (%d), nothing taken:\n' "${#files[@]}" >> "$log"
    printf '  %s\n' "${files[@]##*/}" >> "$log"
    fail "The link contained ${#files[@]} songs – nothing was added. Please link a single song"
fi

moved=0
last=""
for f in "${files[@]}"; do
    b=$(basename "$f")
    if [ -e "$dir/$b" ]; then
        last="$b"
        continue
    fi
    if mv -n -- "$f" "$dir/"; then
        moved=$((moved + 1))
        last="$b"
    fi
done
[ "$moved" -gt 0 ] || fail "Song is already in your library"

emit STATUS "Updating library …"
command -v mpc > /dev/null 2>&1 && mpc update --wait > /dev/null 2>&1

name="${last%.mp3}"
[ "$moved" -gt 1 ] && name="$moved Songs"
emit DONE "$name"
