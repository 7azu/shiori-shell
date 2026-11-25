import QtQml
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Mpris
pragma Singleton

QtObject {
    id: root

    // Audio dropdown open? (for the mpd volume, which is only queried then)
    readonly property bool dropdownOpen: DropdownState.current === "audio"
    // ==== MPRIS players ====
    // Shown is what started playing last (_updatePlaying sets lastActivePlayer);
    // if nothing plays, the last one stays. Several tabs in Zen are only ONE player: there
    // the browser itself reports the tab that was started last.
    property MprisPlayer lastActivePlayer: null
    // dbusName -> time since which the player has been playing without a break
    property var _playingSince: ({})
    // All players you can switch between with the arrows in the dropdown
    // (playerctld only mirrors another player)
    readonly property var players: Mpris.players.values.filter((p) => {
        return !(p.dbusName || "").includes("playerctld");
    })
    // When the arrows were last used to switch: the choice holds until a player starts playing afterwards
    property double _manualAt: 0
    readonly property MprisPlayer activePlayer: {
        const players = Mpris.players.values;
        if (root.lastActivePlayer && players.indexOf(root.lastActivePlayer) !== -1)
            return root.lastActivePlayer;

        for (const p of players) {
            if (p.playbackState === MprisPlaybackState.Playing)
                return p;

        }
        return players.length > 0 ? players[0] : null;
    }
    readonly property bool hasPlayer: activePlayer !== null
    readonly property bool isPlaying: hasPlayer && activePlayer.playbackState === MprisPlaybackState.Playing
    readonly property string title: hasPlayer ? (activePlayer.trackTitle ?? "") : ""
    readonly property string artist: hasPlayer ? (activePlayer.trackArtist ?? "") : ""
    readonly property string artUrl: {
        if (!hasPlayer)
            return "";

        var url = activePlayer.trackArtUrl ?? "";
        if (!url && activePlayer.metadata && activePlayer.metadata["mpris:artUrl"])
            url = activePlayer.metadata["mpris:artUrl"];

        return url;
    }
    // ==== Volume of the player ====
    // Follows the player through its change notifications (_syncVolume).
    property real volume: 0
    // ==== Position/length (seconds) ====
    // Own clock instead of MprisPlayer.position: Quickshell's value is often wrong with mpd-mpris
    // (after a track ended it stayed at the old position, notifications arrive in the wrong
    // order). The clock runs on from an anchor point and, while the dropdown is open, is
    // queried directly from the player every second (busctl, positionProc). Closed it costs nothing.
    property real position: 0
    readonly property real length: {
        if (!hasPlayer || !activePlayer.lengthSupported)
            return 0;

        const l = activePlayer.length;
        // Livestreams sometimes report 0 or nonsense
        return Number.isFinite(l) && l > 0 && l < 360000 ? l : 0;
    }
    readonly property bool positionKnown: hasPlayer && activePlayer.positionSupported
    readonly property bool canSeek: positionKnown && length > 0 && activePlayer.canSeek
    property real _anchorPos: 0
    property double _anchorAt: 0
    property bool _clockRunning: false
    // Drop queries until then: shortly after a track change/seek mpd-mpris still returns the old position
    property double _quietUntil: 0
    property MprisPlayer _seenPlayer: null
    property string _seenKey: ""
    // How a new track is detected: track ID (mpd), in the browser the URL (there the ID is always the same)
    readonly property string _trackKey: hasPlayer ? (activePlayer.uniqueId + "|" + (mediaUrl !== "" ? mediaUrl : title)) : ""
    property string _pollFor: ""
    property bool _pollAgain: false
    property Timer positionTimer
    property Timer positionPollTimer
    property Process positionProc
    property Connections _volumeWatch
    property Instantiator _playerWatch
    // ==== Website in the browser (from xesam:url) ====
    readonly property string mediaUrl: hasPlayer && activePlayer.metadata && activePlayer.metadata["xesam:url"] ? String(activePlayer.metadata["xesam:url"]) : ""
    readonly property string siteDomain: hasPlayer && isBrowser(activePlayer) && /^https?:/.test(mediaUrl) ? extractDomain(mediaUrl).replace(/^(m|mobile)\./, "") : ""
    // Sites with their own cover: YouTube/Twitch -> channel picture, music sites -> album cover of the player
    readonly property string site: {
        const d = siteDomain;
        if (d === "youtube.com" || d === "youtu.be")
            return "youtube";

        if (d === "twitch.tv")
            return "twitch";

        if (d === "music.youtube.com" || d === "open.spotify.com" || d === "soundcloud.com")
            return "music";

        return "";
    }
    readonly property var siteNames: ({
        "youtube.com": "YouTube",
        "youtu.be": "YouTube",
        "music.youtube.com": "YouTube Music",
        "twitch.tv": "Twitch",
        "tiktok.com": "TikTok",
        "reddit.com": "Reddit",
        "instagram.com": "Instagram",
        "x.com": "X",
        "twitter.com": "X",
        "facebook.com": "Facebook",
        "kick.com": "Kick",
        "soundcloud.com": "SoundCloud",
        "open.spotify.com": "Spotify",
        "netflix.com": "Netflix",
        "crunchyroll.com": "Crunchyroll",
        "vimeo.com": "Vimeo",
        "dailymotion.com": "Dailymotion",
        "bsky.app": "Bluesky",
        "9gag.com": "9GAG"
    })
    // "YouTube", otherwise e.g. "Example" for example.com; empty = no browser/no site
    readonly property string siteName: {
        const d = siteDomain;
        if (d === "")
            return "";

        if (siteNames[d])
            return siteNames[d];

        const parts = d.split(".");
        let i = Math.max(0, parts.length - 2);
        // bbc.co.uk -> "Bbc" instead of "Co"
        if (i > 0 && ["co", "com", "org", "net", "ac", "gov"].indexOf(parts[i]) !== -1)
            i--;

        const n = parts[i];
        return n.charAt(0).toUpperCase() + n.slice(1);
    }
    // Original (colored) icon of the site, via scripts/site_icon.py (cache per domain)
    property string siteIcon: ""
    property string _siteIconFor: ""
    readonly property string siteIconScript: Qt.resolvedUrl("../scripts/site_icon.py").toString().replace("file://", "")
    property Process siteIconProc
    readonly property string browserIcon: {
        if (!hasPlayer)
            return "";

        const id = (activePlayer.identity || "").toLowerCase() + " " + (activePlayer.desktopEntry || "").toLowerCase();
        // Own icon from the settings ("browser:zen" ...), else the icon theme
        const icons = [["zen", "zen-browser"], ["firefox", "firefox"], ["chrome", "google-chrome"], ["chromium", "chromium"]];
        for (const [name, theme] of icons) {
            if (!id.includes(name))
                continue;

            const own = Settings.icon("browser:" + name);
            if (own !== "")
                return own;

            return Quickshell.iconPath(theme, true) !== "" ? "image://icon/" + theme : "";
        }
        return "";
    }
    // Static icon in the middle when there is no cover: the site, while it is still loading the browser
    readonly property string websiteIconSource: siteIcon !== "" ? siteIcon : browserIcon
    // ==== Cover: for YouTube/Twitch the creator's profile picture (spins like a record) ====
    // Twitch: Zen already gives the streamer's profile picture as mpris:artUrl.
    // YouTube: there it is the video thumbnail -> channel picture via scripts/creator_avatar.py (cache per channel).
    // Other sites (TikTok, Reddit, Instagram ...): deliberately no cover, it would change with every
    // short video -> website icon (also for YouTube while the channel picture is still loading).
    property string creatorArt: ""
    property string _creatorFor: ""
    // Channel (xesam:artist) that creatorArt belongs to: for another channel do not show the old picture
    property string _creatorArtist: ""
    // Failed fetches (network, rate limit) for the same video are tried again later
    property int _creatorTries: 0
    property Timer creatorRetry
    readonly property string creatorScript: Qt.resolvedUrl("../scripts/creator_avatar.py").toString().replace("file://", "")
    property Process creatorProc
    readonly property string coverSource: {
        if (!hasPlayer)
            return "";

        if (!isBrowser(activePlayer))
            return artUrl;

        if (site === "youtube")
            return creatorArt;

        if (site === "twitch" || site === "music")
            return artUrl;

        return "";
    }
    readonly property bool showWebsiteIcon: hasPlayer && isBrowser(activePlayer) && coverSource === ""
    // ==== mpd: read the volume directly from mpd ====
    // After a restart mpd-mpris often reports 0 until the volume
    // changes. So we ask mpd for the real volume with `mpc`.
    readonly property bool isMpd: {
        if (!hasPlayer)
            return false;

        const id = (activePlayer.identity || "").toLowerCase();
        const de = (activePlayer.desktopEntry || "").toLowerCase();
        return id.includes("music player daemon") || id === "mpd" || de === "mpd";
    }
    property real mpdVolume: -1 // -1 = unknown
    property var _pendingMpdVol: null
    property Timer mpdPollTimer
    property Process mpdGetProc
    property Process mpdSetProc

    function refreshMpd() {
        if (isMpd && !mpdGetProc.running)
            mpdGetProc.running = true;

    }

    function _runMpdVol(v) {
        mpdSetProc.command = ["mpc", "volume", String(Math.round(v * 100))];
        mpdSetProc.running = true;
    }

    function _setMpdVolume(v) {
        root.mpdVolume = v;
        if (mpdSetProc.running)
            root._pendingMpdVol = v;
        else
            root._runMpdVol(v);
    }

    function isBrowser(player) {
        if (!player)
            return false;

        var identity = player.identity.toLowerCase();
        var desktopEntry = player.desktopEntry ? player.desktopEntry.toLowerCase() : "";
        return identity.includes("firefox") || identity.includes("zen") || identity.includes("chrome") || identity.includes("chromium") || desktopEntry.includes("firefox") || desktopEntry.includes("zen") || desktopEntry.includes("chrome") || desktopEntry.includes("chromium");
    }

    // Fetch the YouTube channel picture for the current video (if one is already running: afterwards for the new URL)
    function fetchCreatorArt() {
        if (site !== "youtube") {
            creatorArt = "";
            _creatorFor = "";
            return ;
        }
        if (mediaUrl === _creatorFor || creatorProc.running)
            return ;

        if (artist !== _creatorArtist)
            creatorArt = "";

        _creatorFor = mediaUrl;
        _creatorArtist = artist;
        creatorProc.command = ["python3", "-I", creatorScript, mediaUrl];
        creatorProc.running = true;
    }

    // Fetch the icon of the current site (if one is already running: afterwards for the new domain)
    function fetchSiteIcon() {
        if (siteDomain === _siteIconFor)
            return ;

        siteIcon = "";
        if (siteIconProc.running)
            return ;

        _siteIconFor = siteDomain;
        if (siteDomain === "")
            return ;

        siteIconProc.command = ["python3", "-I", siteIconScript, siteDomain];
        siteIconProc.running = true;
    }

    // Arrows in the dropdown: to the next (dir = 1) / previous (-1) player
    function cyclePlayer(dir) {
        const list = players;
        if (list.length < 2)
            return ;

        const i = list.indexOf(activePlayer);
        lastActivePlayer = list[((i < 0 ? 0 : i + dir) % list.length + list.length) % list.length];
        _manualAt = Date.now();
    }

    function extractDomain(url) {
        if (!url)
            return "";

        var s = url.toString().replace(/^https?:\/\//, "").split('/')[0].split(':')[0].replace(/^www\./, "");
        return s.toLowerCase();
    }

    function togglePlay() {
        if (hasPlayer)
            activePlayer.togglePlaying();

    }

    function next() {
        if (hasPlayer && activePlayer.canGoNext)
            activePlayer.next();

    }

    function previous() {
        if (hasPlayer && activePlayer.canGoPrevious)
            activePlayer.previous();

    }

    // Take the volume from the active player; for mpd the directly queried value counts (if known)
    function _syncVolume() {
        // A player that just went away (e.g. the browser's MPRIS instance) can still be counted for a moment
        if (!hasPlayer || !activePlayer) {
            volume = 0;
            return ;
        }
        const v = activePlayer.volume;
        const playerVol = (v !== undefined && Number.isFinite(v)) ? v : 0;
        volume = (isMpd && mpdVolume >= 0) ? mpdVolume : playerVol;
    }

    // The playing player started last wins (after switching with the arrows only again
    // when a player starts playing afterwards)
    function _updatePlaying() {
        const since = _playingSince;
        let newest = null;
        for (const p of Mpris.players.values) {
            const k = p.dbusName;
            if (p.playbackState !== MprisPlaybackState.Playing) {
                delete since[k];
                continue;
            }
            if (!(k in since))
                since[k] = Date.now();

            if (!newest || since[k] > since[newest.dbusName])
                newest = p;

        }
        if (newest && lastActivePlayer !== newest && since[newest.dbusName] > _manualAt)
            lastActivePlayer = newest;

    }

    function _clockNow() {
        if (!_clockRunning)
            return _anchorPos;

        const r = hasPlayer ? activePlayer.rate : 1;
        return _anchorPos + (Date.now() - _anchorAt) / 1000 * (Number.isFinite(r) && r > 0 ? r : 1);
    }

    function _tick() {
        const p = _clockNow();
        position = Math.max(0, length > 0 ? Math.min(p, length) : p);
    }

    function _anchor(p) {
        _anchorPos = p;
        _anchorAt = Date.now();
        _clockRunning = isPlaying;
        _tick();
    }

    function _busName(player) {
        const n = player.dbusName || "";
        return n.startsWith("org.mpris.") ? n : "org.mpris.MediaPlayer2." + n;
    }

    // Ask the player for the real position (only with the dropdown open)
    function _poll() {
        if (!dropdownOpen || !positionKnown)
            return ;

        if (positionProc.running) {
            _pollAgain = true;
            return ;
        }
        _pollFor = _busName(activePlayer);
        positionProc.command = ["busctl", "--user", "get-property", _pollFor, "/org/mpris/MediaPlayer2", "org.mpris.MediaPlayer2.Player", "Position"];
        positionProc.running = true;
    }

    function _pollResult(text) {
        if (!hasPlayer || _busName(activePlayer) !== _pollFor || Date.now() < _quietUntil)
            return ;

        const m = text.match(/^x (-?\d+)/);
        if (!m)
            return ;

        const p = parseInt(m[1]) / 1e+06;
        // mpd-mpris only reports whole seconds: only reset the running clock on a real difference,
        // otherwise the display would jitter every second. When paused, the reported value counts exactly.
        if (!_clockRunning || Math.abs(p - _clockNow()) > 1.5)
            _anchor(p);

    }

    // Another player or a new track? (called delayed: on a change ID, URL and
    // title change one after another)
    function _checkTrack() {
        if (activePlayer !== _seenPlayer) {
            _seenPlayer = activePlayer;
            _seenKey = _trackKey;
            _quietUntil = 0;
            // First state from Quickshell, the query corrects it right away
            const p = positionKnown ? activePlayer.position : 0;
            _anchor(Number.isFinite(p) ? p : 0);
            _poll();
            return ;
        }
        if (_trackKey === _seenKey)
            return ;

        // A new track starts at the beginning; if the player resumes elsewhere, the next query sets the clock
        _seenKey = _trackKey;
        _quietUntil = Date.now() + 1000;
        _anchor(0);
    }

    // Jump to a position (seconds). Not quite to the end: that would skip the track
    function seekTo(sec) {
        if (!canSeek)
            return ;

        const t = Math.max(0, Math.min(sec, length - 0.5));
        activePlayer.position = t;
        _quietUntil = Date.now() + 1000;
        _anchor(t);
    }

    function setVolume(val) {
        if (hasPlayer) {
            const safeVal = Math.max(0, Math.min(val, 1));
            if (isMpd)
                _setMpdVolume(safeVal);
            else
                activePlayer.volume = safeVal;
            root.volume = safeVal;
        }
    }

    onDropdownOpenChanged: {
        refreshMpd();
    }
    onIsMpdChanged: {
        refreshMpd();
        _syncVolume();
    }

    onActivePlayerChanged: {
        _syncVolume();
        Qt.callLater(_checkTrack);
    }
    on_TrackKeyChanged: Qt.callLater(_checkTrack)
    // Pause/resume: stop the clock at the current state or let it run on from there
    onIsPlayingChanged: {
        _anchor(_clockNow());
        _poll();
    }
    onLengthChanged: _tick()

    positionTimer: Timer {
        interval: 250
        running: root.dropdownOpen && root.positionKnown
        repeat: true
        onTriggered: root._tick()
    }

    positionPollTimer: Timer {
        interval: 1000
        running: root.dropdownOpen && root.positionKnown
        repeat: true
        triggeredOnStart: true
        onTriggered: root._poll()
    }

    positionProc: Process {
        onRunningChanged: {
            if (!running && root._pollAgain) {
                root._pollAgain = false;
                root._poll();
            }
        }

        stdout: StdioCollector {
            onStreamFinished: root._pollResult(text)
        }

    }

    onMpdVolumeChanged: _syncVolume()

    _volumeWatch: Connections {
        function onVolumeChanged() {
            root._syncVolume();
        }

        target: root.activePlayer
    }

    // Listen to start/stop per player instead of querying all players every 200 ms
    _playerWatch: Instantiator {
        model: Mpris.players
        onObjectAdded: root._updatePlaying()
        onObjectRemoved: root._updatePlaying()

        delegate: QtObject {
            id: watch

            required property MprisPlayer modelData
            property Connections state: Connections {
                function onPlaybackStateChanged() {
                    root._updatePlaying();
                }

                target: watch.modelData
            }
        }

    }

    mpdPollTimer: Timer {
        // Only while the dropdown is open and mpd is active
        interval: 1000
        running: root.isMpd && root.dropdownOpen
        repeat: true
        onTriggered: root.refreshMpd()
    }

    // Only in the next pass: on a player change mediaUrlChanged comes before site is recomputed
    onMediaUrlChanged: {
        _creatorTries = 0;
        Qt.callLater(fetchCreatorArt);
    }
    onSiteChanged: Qt.callLater(fetchCreatorArt)
    onSiteDomainChanged: Qt.callLater(fetchSiteIcon)
    Component.onCompleted: {
        Qt.callLater(_checkTrack);
        Qt.callLater(fetchCreatorArt);
        Qt.callLater(fetchSiteIcon);
    }

    creatorRetry: Timer {
        interval: 15000
        onTriggered: {
            if (root._creatorFor === root.mediaUrl && root.creatorArt === "") {
                root._creatorFor = "";
                root.fetchCreatorArt();
            }
        }
    }

    siteIconProc: Process {
        onRunningChanged: {
            if (!running && root.siteDomain !== root._siteIconFor)
                Qt.callLater(root.fetchSiteIcon);

        }

        stdout: StdioCollector {
            onStreamFinished: {
                const path = text.trim();
                if (root._siteIconFor === root.siteDomain && path !== "")
                    root.siteIcon = "file://" + path;

            }
        }

    }

    creatorProc: Process {
        onRunningChanged: {
            // Switched to another video meanwhile -> once more right away
            if (!running && root.site === "youtube" && root.mediaUrl !== root._creatorFor)
                Qt.callLater(root.fetchCreatorArt);

        }

        stdout: StdioCollector {
            onStreamFinished: {
                const path = text.trim();
                // Only take it if it still belongs to the playing video
                if (root._creatorFor !== root.mediaUrl)
                    return ;

                root.creatorArt = path !== "" ? "file://" + path : "";
                if (path === "" && root._creatorTries < 3) {
                    root._creatorTries++;
                    root.creatorRetry.restart();
                }

            }
        }

    }

    mpdGetProc: Process {
        command: ["mpc", "volume"]

        stdout: StdioCollector {
            onStreamFinished: {
                // Do not take an outdated value while dragging
                if (root.mpdSetProc.running || root._pendingMpdVol !== null)
                    return ;

                const m = text.match(/volume:\s*(\d+)%/);
                root.mpdVolume = m ? Math.max(0, Math.min(1, parseInt(m[1]) / 100)) : -1;
            }
        }

    }

    mpdSetProc: Process {
        onRunningChanged: {
            if (!running && root._pendingMpdVol !== null) {
                const v = root._pendingMpdVol;
                root._pendingMpdVol = null;
                root._runMpdVol(v);
            }
        }
    }

}
