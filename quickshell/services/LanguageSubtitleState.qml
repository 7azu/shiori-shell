import QtQuick
import Quickshell
import Quickshell.Io
pragma Singleton

// Subtitles of the language tool: the lines of the playing file and the one being spoken, translating a
// line, and preparing subtitles that were downloaded but never prepared. What plays (file, folder, position)
// belongs to LanguageAudioState; the download prepares the subtitles of a new video itself (LanguageDownloadState).
Singleton {
    id: root

    // Subtitles for videos: yt-dlp puts the .vtt into .subs/, scripts/jp_subs.py turns them into
    // <name>.json (words + dictionary) and <name>.srt (for mpv, only for timing)
    readonly property string subsDir: LanguageAudioState.playDir + "/.subs"
    readonly property string subsScript: Qt.resolvedUrl("../scripts/jp_subs.py").toString().replace("file://", "")
    // Show the subtitle bar (windows/LanguageSubtitles.qml); remembered in LanguageAudioState.prefsFile
    property bool subsShown: true
    // Subtitles of the playing file and the line being spoken (-1 = none)
    property var cues: []
    property int cueIndex: -1
    property int translatingIdx: -1
    property string translateError: ""

    // YouTube's automatic subtitles without word times show two blocks at once, so every line officially lasts
    // until the middle of the next one (up to 8 s overlap). showAt keeps a line until its end -> the next line
    // came seconds late. A line ends where the next one starts (also done by jp_subs.py build; this covers files
    // prepared before that).
    function clipCues(list) {
        const out = list.slice();
        for (let i = 0; i + 1 < out.length; i++) {
            if (out[i + 1].s < out[i].e && out[i + 1].s > out[i].s)
                out[i] = Object.assign({
                }, out[i], {
                    "e": out[i + 1].s
                });

        }
        return out;
    }

    // Position of the player (seconds, from LanguageAudioState.videoPosition) -> running subtitle line
    function showAt(sec) {
        let i = cueIndex;
        // mostly it is the same or the next line
        if (i >= 0 && i < cues.length && sec >= cues[i].s && sec < cues[i].e)
            return ;

        i = -1;
        for (let k = 0; k < cues.length; k++) {
            if (sec >= cues[k].s && sec < cues[k].e) {
                i = k;
                break;
            }
            if (cues[k].s > sec)
                break;

        }
        cueIndex = i;
    }

    function setSubsShown(on) {
        subsShown = on;
        LanguageAudioState.savePrefs();
    }

    // Videos whose .vtt is there but was never prepared (downloaded before other languages had subtitles, or a
    // failed preparation): prepare them one after the other in the background. Each one is tried once per run of
    // the shell, so a video without usable subtitles is not tried again on every opening.
    property var subsTried: ({
    })
    property var subsQueue: []

    function prepareMissingSubs(vttStems) {
        const code = LanguageAudioState.languageCodes[LanguageAudioState.language];
        if (!code)
            return ;

        const add = [];
        for (const stem in vttStems) {
            const key = LanguageAudioState.downloadDir + "/" + stem;
            if (LanguageAudioState.subbed[stem] || subsTried[key] || LanguageAudioState.library.indexOf(stem + ".mp4") < 0)
                continue;

            subsTried[key] = true;
            add.push([LanguageAudioState.downloadDir + "/" + stem + ".mp4", code, LanguageAudioState.language]);
        }
        if (add.length === 0)
            return ;

        subsQueue = subsQueue.concat(add);
        if (!lateSubsProc.running)
            nextLateSubs();
    }

    function nextLateSubs() {
        if (subsQueue.length === 0)
            return ;

        const job = subsQueue[0];
        subsQueue = subsQueue.slice(1);
        lateSubsProc.command = ["python3", subsScript, "build"].concat(job);
        lateSubsProc.running = true;
    }

    function translateCue(idx) {
        // Also covers the T key in the video player: without a translator (translation off) nothing happens
        if (idx < 0 || idx >= cues.length || cues[idx].en || translateProc.running || LanguageReadingState.translator === "")
            return ;

        translatingIdx = idx;
        translateError = "";
        // The subtitles belong to the playing file's language (playLanguage), not to the one shown in the picker
        translateProc.command = ["python3", root.subsScript, "translate", root.subsDir + "/" + LanguageAudioState.stemOf(LanguageAudioState.currentFile) + ".json", String(idx), LanguageAudioState.languageCodes[LanguageAudioState.playLanguage] || LanguageAudioState.playLanguage.toLowerCase(), LanguageAudioState.playLanguage];
        translateProc.running = true;
    }

    // Prepares subtitles that were missing (prepareMissingSubs), one video at a time; afterwards the list is read
    // again, so the player finds the new .json. A Process does not start again from its own onExited -> callLater.
    Process {
        id: lateSubsProc

        onExited: {
            if (root.subsQueue.length > 0)
                Qt.callLater(root.nextLateSubs);
            else
                LanguageAudioState.loadLibrary();
        }
    }

    // Load the subtitles of the playing file
    FileView {
        path: LanguageAudioState.currentFile !== "" && (LanguageAudioState.playDir !== LanguageAudioState.downloadDir || LanguageAudioState.hasSubs(LanguageAudioState.currentFile)) ? root.subsDir + "/" + LanguageAudioState.stemOf(LanguageAudioState.currentFile) + ".json" : ""
        onPathChanged: {
            root.cues = [];
            root.cueIndex = -1;
        }
        onLoaded: {
            try {
                root.cues = root.clipCues(JSON.parse(text()).cues || []);
            } catch (e) {
                root.cues = [];
            }
        }
    }

    Process {
        id: translateProc

        property string lastLine: ""

        onRunningChanged: {
            if (running) {
                lastLine = "";
                return ;
            }
            try {
                const res = JSON.parse(lastLine);
                if (res.ok && res.idx < root.cues.length) {
                    let arr = root.cues.slice();
                    arr[res.idx] = Object.assign({
                    }, arr[res.idx], {
                        "en": res.en
                    });
                    root.cues = arr;
                } else if (!res.ok) {
                    root.translateError = res.error || "Translation failed";
                }
            } catch (e) {
                root.translateError = "Translation failed";
            }
            root.translatingIdx = -1;
        }

        stdout: SplitParser {
            onRead: (data) => {
                translateProc.lastLine = data;
            }
        }

    }

}
