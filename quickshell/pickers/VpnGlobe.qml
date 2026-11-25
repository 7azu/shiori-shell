import "../common"
import "../services"
import "./parts"
import QtQuick
import QtQuick.Effects
import QtQuick.Shapes
import Quickshell
import Quickshell.Widgets
import Quickshell.Io

// Globe view of the VPN picker: the earth as a glowing wireframe (shader), every server a
// dot at its location. On the left and right the servers stand as pills, with a line to their
// dot. Dragging rotates the globe, the mouse wheel flies closer, arrow keys/hover select,
// and the camera flies to the selection.
Item {
    id: globe

    // Filtered servers [{ name, code, label }] and all of them (for a page split that stays stable
    // while typing)
    property var servers: []
    property var allServers: []
    property string activeName: ""
    property string selectedName: ""
    readonly property var selectedEntry: layout.map[selectedName] ?? null
    // ---- Camera ----
    property real lonC: 10
    property real latC: 48
    // View center = camera + a small tilt toward the mouse (panX/panY, like the parallax): the planet turns the side
    // you point at a few degrees closer (up to ~4.5 % of the visible cap, so equally strong at every zoom).
    // Drawing and hit testing use latV/lonV everywhere; dragging, momentum and flights control latC/lonC.
    readonly property real capDeg: Math.acos(1 / dist) / rad
    readonly property real latV: Math.max(-85, Math.min(85, latC - panY * capDeg * 0.045))
    readonly property real lonV: lonC + panX * capDeg * 0.045 / Math.max(0.3, Math.cos(latC * rad))
    // 0 = whole hemisphere, 1 = close above the ground
    // Zoom when opening and on "reset view" (double click). 0.72 was too close:
    // 0.52 shows almost 30 % more (scale in the middle sqrt((d+1)/(d-1)) with d = dist: 3.06 -> 2.19)
    // matched against a reference screenshot
    readonly property real homeZoom: 0.52
    property real zoom: homeZoom
    property real zoomShown: zoom
    // On far flights the camera rises on the way (like a jump)
    property real zoomDip: 0
    // 0 -> 1 when opening: globe and pills fade in staggered, the camera moves in
    property real appear: 1
    // Evenly running clock of the fade-in (0 -> 1): pills and lines depend on this instead of on
    // `appear`, whose curve is so steep at the start that all pills popped up almost at the same time
    property real introT: 1
    readonly property real zoomEff: Math.max(0, Math.min(1, (zoomShown - zoomDip) * (0.5 + 0.5 * appear)))
    // Camera distance in sphere radii: the cap with the angle acos(1 / dist) is visible
    readonly property real dist: 1 + 4 * Math.pow(0.02, zoomEff)
    // ---- Build ----
    readonly property real pillW: 196
    readonly property real pillH: 40
    // Status line below the globe (the standalone VPN picker shows the status in the header and hides it)
    property bool showStatus: true
    // Share of the height for the radius (without a status line there is more room)
    property real radiusFactor: 0.365
    readonly property real radius: Math.max(120, Math.min(height * radiusFactor, width / 2 - pillW - 120))
    readonly property real gap: Math.min(110, radius * 0.32)
    readonly property real cx: width / 2
    readonly property real cy: height / 2 - (showStatus ? 14 : 0)
    readonly property real colH: radius * 2 * 0.94
    readonly property int maxRows: Math.max(1, Math.floor(colH / 42))
    readonly property real rad: Math.PI / 180
    // Longitude that splits the servers into the left and right column
    readonly property real splitLon: {
        const lons = allServers.map((s) => {
            return VpnPickerState.countryCoords[s.code];
        }).filter((c) => {
            return c !== undefined;
        }).map((c) => {
            return c[1];
        }).sort((a, b) => {
            return a - b;
        });
        return lons.length > 0 ? lons[Math.floor(lons.length / 2)] : 0;
    }
    // Distribute the servers to the columns: west of the center on the left, east on the right, each from north to
    // south - so the lines hardly cross. If a column does not fit, the rest stay just dots.
    readonly property var layout: {
        const left = [];
        const right = [];
        const loose = [];
        for (const s of servers) {
            const c = VpnPickerState.countryCoords[s.code];
            const n = {
                "name": s.name,
                "code": s.code,
                "label": s.label,
                "geo": c !== undefined,
                "lat": c ? c[0] : 0,
                "lon": c ? c[1] : 0,
                "side": 0,
                "row": 0,
                "rows": 1
            };
            if (!n.geo)
                loose.push(n);
            else if (n.lon < splitLon)
                left.push(n);
            else
                right.push(n);
        }
        const byLat = (a, b) => {
            return b.lat - a.lat || a.lon - b.lon;
        };
        left.sort(byLat);
        right.sort(byLat);
        // Connections without a recognizable country: at the bottom of the shorter column, without a dot
        for (const n of loose) (left.length <= right.length ? left : right).push(n)
        const map = {
        };
        const dots = [];
        const place = (list, side) => {
            const shown = list.slice(0, maxRows);
            shown.forEach((n, i) => {
                n.side = side;
                n.row = i;
                n.rows = shown.length;
            });
            for (const n of list) {
                map[n.name] = n;
                if (n.geo)
                    dots.push(n.name);

            }
            return shown;
        };
        const l = place(left, -1);
        const r = place(right, 1);
        return {
            "map": map,
            "left": l,
            "right": r,
            "pills": l.concat(r).map((n) => {
                return n.name;
            }),
            "dots": dots
        };
    }
    // ---- Space: orbit with a satellite (like the dotted orbits in the Wi-Fi/Bluetooth picker) ----
    // Tilted ellipse around the planet; the back half below, the front half above the planet
    readonly property real orbitRx: radius * 1.22
    readonly property real orbitRy: radius * 0.3
    readonly property real orbitTilt: -0.2
    readonly property var orbitBack: orbitArc(Math.PI, 2 * Math.PI)
    readonly property var orbitFront: orbitArc(0, Math.PI)
    // Satellite: one round in 45 s; glows in the accent color while the VPN is connected
    property real satT: 0
    readonly property bool satFront: Math.sin(satT) > 0
    // ---- Parallax of the starry sky (like Wi-Fi/Bluetooth): mouse relative to the planet, -1..1 relative to
    // twice the radius, saturated outside. panX/panY follow softly (tau ~0.2 s). The near star layer
    // moves away by up to parallaxPx, the far one less, the sparkle stars a bit more; planet and pills stay.
    property real panTX: 0
    property real panTY: 0
    property real panX: 0
    property real panY: 0
    readonly property real parallaxPx: 7

    // ---- Connection arc: from your own location to the connected server ----
    // Location from ~/.config/quickshell-local/location.json ({"lat": .., "lon": ..}, machine-specific, not
    // synced), otherwise roughly by the time zone. Nothing is queried on the network.
    property var homeFile: null
    property string timezone: ""
    readonly property var tzHome: ({
        "Europe/Berlin": [51.2, 10.4], "Europe/Vienna": [47.6, 14.1], "Europe/Zurich": [46.8, 8.2],
        "Europe/Amsterdam": [52.1, 5.3], "Europe/Paris": [46.6, 2.4], "Europe/London": [52.4, -1.5],
        "Europe/Warsaw": [52.0, 19.4], "Europe/Prague": [49.8, 15.5], "Europe/Rome": [42.8, 12.5],
        "Europe/Madrid": [40.4, -3.7], "Asia/Tokyo": [35.7, 139.7], "America/New_York": [40.7, -74.0]
    })
    readonly property var homeLL: homeFile ?? tzHome[timezone] ?? null
    readonly property var activeEntry: layout.map[activeName] ?? null
    // Points of the arc (great circle, slightly raised above the ground in the middle) as pixels relative to the
    // globe center: {x, y, t (0 = location, 1 = server), vis (0 = behind the sphere)}. Same camera as project().
    readonly property var arcPts: {
        const a = homeLL, e = activeEntry;
        if (!a || !e)
            return [];
        const toV = (lat, lon) => [Math.cos(lat * rad) * Math.sin(lon * rad), Math.sin(lat * rad), Math.cos(lat * rad) * Math.cos(lon * rad)];
        const A = toV(a[0], a[1]), B = toV(e.lat, e.lon);
        const om = Math.acos(Math.max(-1, Math.min(1, A[0] * B[0] + A[1] * B[1] + A[2] * B[2])));
        if (om < 0.004)
            return [];
        const so = Math.sin(om), d = dist;
        // Height: short arcs flat, long ones up to 0.16 radii; never up to the camera (zoomed in a lot)
        const lift = Math.min(0.16, 0.45 * om, (d - 1) * 0.5);
        const p0 = latV * rad;
        const out = [];
        // Point spacing ~7 px like the dotted orbit (length roughly from angle x radius x zoom)
        const n = Math.max(8, Math.min(64, Math.round(om * radius * Math.sqrt(d * d - 1) / (d - 1) / 7)));
        for (let i = 0; i < n; i++) {
            const t = i / (n - 1);
            const w1 = Math.sin((1 - t) * om) / so, w2 = Math.sin(t * om) / so;
            const P = [w1 * A[0] + w2 * B[0], w1 * A[1] + w2 * B[1], w1 * A[2] + w2 * B[2]];
            const lat = Math.asin(Math.max(-1, Math.min(1, P[1])));
            const l = Math.atan2(P[0], P[2]) - lonV * rad;
            const R = 1 + lift * Math.sin(Math.PI * t);
            const x = R * Math.cos(lat) * Math.sin(l);
            const y0 = R * Math.sin(lat), z0 = R * Math.cos(lat) * Math.cos(l);
            const y = y0 * Math.cos(p0) - z0 * Math.sin(p0);
            const z = y0 * Math.sin(p0) + z0 * Math.cos(p0);
            // Hidden? The ray camera (0, 0, d) -> point hits the unit sphere before
            const vx = x, vy = y, vz = z - d;
            const vv = vx * vx + vy * vy + vz * vz;
            const disc = d * vz * d * vz - vv * (d * d - 1);
            const s1 = disc > 0 ? (-d * vz - Math.sqrt(disc)) / vv : 2;
            const hidden = (s1 > 0 && s1 < 0.999) || d - z < 0.05;
            const k = Math.sqrt(d * d - 1) / Math.max(0.05, d - z);
            out.push({
                "x": x * k * radius,
                "y": -y * k * radius,
                "t": t,
                "vis": hidden ? 0 : 1
            });
        }
        return out;
    }
    // Light dot that travels from the location to the server (a bit beyond 1: a short pause at the target)
    property real arcPulse: 0

    // Mouse anywhere in the picker (header, search bar, edge; point in coordinates of item): the tilt keeps following
    // steadily, saturated outside the globe. No jump between globe and header.
    function trackPointer(item, p) {
        updateParallax(item.mapToItem(globe, p.x, p.y));
        Qt.callLater(hoverFallback);
    }

    function updateParallax(p) {
        panTX = Math.max(-1, Math.min(1, (p.x - cx) / Math.max(1, 2 * radius)));
        panTY = Math.max(-1, Math.min(1, (p.y - cy) / Math.max(1, 2 * radius)));
    }

    // Clock for the twinkling of the fixed stars
    property real starTime: 0
    // ---- Countries as areas: country code -> number in resources/globe/countries.png ----
    property var countryIds: ({})
    function countryId(code) {
        return code ? (countryIds[String(code).toLowerCase()] || 0) : 0;
    }
    readonly property real selCountry: countryId(selectedEntry ? selectedEntry.code : "")
    readonly property real activeCountry: {
        const e = layout.map[activeName];
        return countryId(e ? e.code : "");
    }
    // Up to 24 server countries (of the filtered list, so the search only highlights hits) for the shader
    readonly property var serverCountries: {
        const ids = [];
        for (let i = 0; i < servers.length && ids.length < 24; i++) {
            const id = countryId(servers[i].code);
            if (id > 0 && ids.indexOf(id) < 0)
                ids.push(id);
        }
        while (ids.length < 24)
            ids.push(0);
        return ids;
    }
    // Transition when the selection changes: the old country fades out, the new one in (selK), plus a light wave
    // from the server location over the country (waveT). Both run in the shader.
    property real prevSel: 0
    property real shownSel: 0
    property real selK: 1
    property real waveT: 1
    // Server location for the wave (earth coordinates, longitude relative to the view center like sunDir)
    readonly property vector4d selPos: {
        const e = selectedEntry;
        if (!e)
            return Qt.vector4d(0, 0, 1, 0);
        const p = e.lat * rad;
        const l = (e.lon - lonV) * rad;
        return Qt.vector4d(Math.cos(p) * Math.sin(l), Math.sin(p), Math.cos(p) * Math.cos(l), 0);
    }
    onSelCountryChanged: {
        if (selCountry === shownSel)
            return ;
        // In the middle of a crossfade: the country that is more visible right now is the one fading out
        prevSel = selK >= 0.5 ? shownSel : prevSel;
        shownSel = selCountry;
        selFade.restart();
        if (selCountry > 0)
            selWave.restart();
    }
    // Country -> first server in it (filtered list): hover/click on a country selects this server
    readonly property var countryServer: {
        const m = {};
        for (let i = 0; i < servers.length; i++) {
            const id = countryId(servers[i].code);
            if (id > 0 && m[id] === undefined)
                m[id] = servers[i].name;
        }
        return m;
    }
    // Country grid for hovering (resources/globe/countries-grid.json, 1/4 degree, rows run-length encoded).
    // Only unpacked on the first hover, so opening the picker does not wait.
    property var gridRaw: null
    property var grid: null
    property int gridW: 0
    property int gridH: 0
    // Server of the country under the mouse ("" = none)
    property string hoverCountryServer: ""
    // Server dot under the mouse (dotMouse); together with hoverCountryServer and dockEntry: is there anything
    // selectable under the pointer at all?
    property string hoverDot: ""
    readonly property bool hoveringServer: hoverCountryServer !== "" || hoverDot !== "" || dockEntry !== null

    // If nothing selectable is under the pointer after a mouse move, the active connection counts as
    // selected again (otherwise the last hovered country stayed). The keyboard selection stays until
    // the mouse moves. Via callLater: first the country/dot/column hovers must have set their state.
    function hoverFallback() {
        if (!hoveringServer && activeName !== "" && selectedName !== activeName && layout.map[activeName])
            select(activeName, false);
    }
    // ---- Sun position (day/night on the globe), new every minute ----
    property real sunLat: 0
    property real sunLon: 0
    // ---- Mouse ----
    property real lastMouseX: -1
    property real lastMouseY: -1
    readonly property string icCheck: String.fromCodePoint(983340)
    readonly property string icShield: String.fromCodePoint(984216)
    readonly property string icShieldOff: String.fromCodePoint(985502)

    // Pills and dots are created spread over a few frames instead of all in the same one: 40 elements
    // at once held up the opening of the picker for a noticeable moment (measured ~10 ms)
    property int built: 0

    signal activated(var entry)

    // Point on the orbit at angle t (0 = right, pi/2 = front bottom)
    function orbitPt(t) {
        const x = Math.cos(t) * orbitRx, y = Math.sin(t) * orbitRy;
        const c = Math.cos(orbitTilt), s = Math.sin(orbitTilt);
        return Qt.point(cx + x * c - y * s, cy + x * s + y * c);
    }

    function orbitArc(a, b) {
        const pts = [];
        for (let i = 0; i <= 72; i++)
            pts.push(orbitPt(a + (b - a) * i / 72));
        return pts;
    }

    function wrapLon(l) {
        return ((l + 540) % 360 + 360) % 360 - 180;
    }

    // Location -> pixel relative to the globe center. z = visibility (0 behind the horizon, then
    // the point lies on the edge in the direction of the location), 1 = clearly visible
    function project(lat, lon) {
        const p = lat * rad;
        const l = (lon - lonV) * rad;
        const p0 = latV * rad;
        const x = Math.cos(p) * Math.sin(l);
        const y0 = Math.sin(p);
        const z0 = Math.cos(p) * Math.cos(l);
        const y = y0 * Math.cos(p0) - z0 * Math.sin(p0);
        const z = y0 * Math.sin(p0) + z0 * Math.cos(p0);
        const horizon = 1 / dist;
        if (z <= horizon) {
            const len = Math.hypot(x, y) || 1;
            return Qt.vector3d(x / len * radius, -y / len * radius, 0);
        }
        const k = Math.sqrt(dist * dist - 1) / (dist - z);
        return Qt.vector3d(x * k * radius, -y * k * radius, Math.min(1, (z - horizon) / (1 - horizon) / 0.1));
    }

    // Inverse of project(): pixel (relative to the globe center) -> { lat, lon } or null next to the sphere.
    // Same math as in the shader (ray from the camera at distance dist).
    function unproject(sx, sy) {
        const X = sx / radius, Y = -sy / radius;
        if (X * X + Y * Y > 1)
            return null;
        const tanA = 1 / Math.sqrt(dist * dist - 1);
        let dx = X * tanA, dy = Y * tanA, dz = -1;
        const dl = Math.hypot(dx, dy, dz);
        dx /= dl;
        dy /= dl;
        dz /= dl;
        const b = dist * dz;
        const h = b * b - (dist * dist - 1);
        if (h < 0)
            return null;
        const t = -b - Math.sqrt(h);
        const x = t * dx, y = t * dy, z = dist + t * dz;
        const p0 = latV * rad;
        const y0 = y * Math.cos(p0) + z * Math.sin(p0);
        const z0 = -y * Math.sin(p0) + z * Math.cos(p0);
        return {
            "lat": Math.asin(Math.max(-1, Math.min(1, y0))) / rad,
            "lon": wrapLon(Math.atan2(x, z0) / rad + lonV)
        };
    }

    function ensureGrid() {
        if (grid || !gridRaw)
            return;
        const g = gridRaw;
        const arr = new Uint8Array(g.w * g.h);
        for (let r = 0; r < g.h; r++) {
            let x = r * g.w;
            const runs = g.rows[r].split(",");
            for (let i = 0; i < runs.length; i++) {
                const c = runs[i].indexOf(":");
                const v = parseInt(runs[i].slice(0, c));
                const n = parseInt(runs[i].slice(c + 1));
                if (v > 0)
                    arr.fill(v, x, x + n);
                x += n;
            }
        }
        gridW = g.w;
        gridH = g.h;
        grid = arr;
    }

    // Country number under a pixel relative to the globe center (0 = sea/beside)
    function countryAtScreen(sx, sy) {
        ensureGrid();
        const ll = unproject(sx, sy);
        if (!ll || !grid)
            return 0;
        const r = Math.min(gridH - 1, Math.max(0, Math.floor((90 - ll.lat) / 180 * gridH)));
        const c = Math.min(gridW - 1, Math.max(0, Math.floor((ll.lon + 180) / 360 * gridW)));
        return grid[r * gridW + c];
    }

    // Vertical position of a pill row relative to the globe center
    function rowY(row, rows) {
        return (row - (rows - 1) / 2) * Math.min(50, colH / rows);
    }

    // The columns hug the globe: at the top and bottom the pills move closer to the center
    function arcX(dy) {
        const r = radius + gap;
        return Math.sqrt(Math.max(r * r - dy * dy, r * r * 0.2));
    }

    function panBy(dx, dy) {
        const scale = radius * Math.sqrt((dist + 1) / (dist - 1)) * rad;
        latC = Math.max(-80, Math.min(80, latC + dy / scale));
        lonC = wrapLon(lonC - dx / scale / Math.max(0.3, Math.cos(latC * rad)));
    }

    function flyTo(lat, lon, instant) {
        const toLat = Math.max(-75, Math.min(75, lat));
        // If it is already flying there: keep flying. The search selects the first hit again on every
        // key press; every restart braked the globe to 0 and accelerated again -> stutter while typing
        if (!instant && flyAnim.running && Math.abs(fly.fromLat + fly.dLat - toLat) < 0.01
                && Math.abs(wrapLon(fly.fromLon + fly.dLon - lon)) < 0.01)
            return ;
        // New target in mid-flight: stay in motion (curve below) instead of starting again at speed 0
        const midFlight = flyAnim.running;
        // Take along the zoom kink of the cancelled flight (onStopped otherwise sets it hard to 0 -> zoom jump)
        const keepDip = midFlight ? zoomDip : 0;
        flyAnim.stop();
        inertia.stop();
        zoomDip = keepDip;
        const dLon = wrapLon(lon - lonC);
        const a = Math.sin((toLat - latC) * rad / 2) ** 2 + Math.cos(latC * rad) * Math.cos(toLat * rad) * Math.sin(dLon * rad / 2) ** 2;
        const angle = 2 * Math.asin(Math.min(1, Math.sqrt(a))) / rad;
        if (instant || angle < 0.3) {
            lonC = wrapLon(lon);
            latC = toLat;
            zoomDip = 0;
            return ;
        }
        fly.dip0 = keepDip;
        fly.fromLon = lonC;
        fly.fromLat = latC;
        fly.dLon = dLon;
        fly.dLat = toLat - latC;
        fly.dip = Math.min(0.34, Math.max(0, angle - 12) / 180 * 0.7);
        flyAnim.duration = Math.min(1300, 420 + angle * 7);
        // Target change: starts at about average speed (no standstill, but also no leap forward
        // as with outQuint, which felt too hectic when typing fast), easing out softly
        flyAnim.easing.bezierCurve = midFlight ? [0.3, 0.3, 0.25, 1, 1, 1] : Appearance.anim.curves.inOutSoft;
        fly.t = 0;
        flyAnim.start();
    }

    function select(name, fly) {
        selectedName = name;
        const n = layout.map[name];
        if (fly && n && n.geo)
            flyTo(n.lat, n.lon, false);

    }

    // Arrow keys: up/down in the column, left/right to the row opposite
    function navigate(key) {
        const cur = layout.map[selectedName];
        const first = layout.left[0] ?? layout.right[0];
        if (!first)
            return ;

        if (!cur || cur.side === 0) {
            select(first.name, true);
            return ;
        }
        const own = cur.side < 0 ? layout.left : layout.right;
        const other = cur.side < 0 ? layout.right : layout.left;
        let next = cur;
        if (key === Qt.Key_Down)
            next = own[Math.min(own.length - 1, cur.row + 1)];
        else if (key === Qt.Key_Up)
            next = own[Math.max(0, cur.row - 1)];
        else if ((key === Qt.Key_Right) === (cur.side < 0) && other.length > 0) {
            const y = rowY(cur.row, cur.rows);
            next = other.reduce((best, n) => {
                return Math.abs(rowY(n.row, n.rows) - y) < Math.abs(rowY(best.row, best.rows) - y) ? n : best;
            });
        }
        select(next.name, true);
    }

    // When opening: select the active connection and fly in from afar
    function open() {
        lastMouseX = -1;
        lastMouseY = -1;
        const n = layout.map[activeName] ?? layout.map[selectedName] ?? layout.left[0] ?? layout.right[0];
        selectedName = n ? n.name : "";
        zoom = homeZoom;
        const lat = n && n.geo ? n.lat : 48;
        const lon = n && n.geo ? n.lon : 10;
        lonC = wrapLon(lon - 70);
        latC = lat * 0.3;
        appearAnim.restart();
        introAnim.restart();
        flyTo(lat, lon, false);
        // Approach when opening: always the same length and without a jump (the camera moves in anyway)
        flyAnim.stop();
        flyAnim.duration = 1100;
        fly.dip = 0;
        fly.t = 0;
        flyAnim.start();
    }

    function resetView() {
        zoom = homeZoom;
        const n = selectedEntry ?? layout.map[activeName];
        if (n && n.geo)
            flyTo(n.lat, n.lon, false);

    }

    // A real mouse move (>= 3 px) selects; only remember the first report after opening
    function hoverMoved(target, mouse) {
        const p = target.mapToItem(null, mouse.x, mouse.y);
        if (Math.abs(p.x - lastMouseX) < 3 && Math.abs(p.y - lastMouseY) < 3)
            return false;

        const first = lastMouseX < 0;
        lastMouseX = p.x;
        lastMouseY = p.y;
        return !first;
    }

    function updateSun() {
        const now = new Date();
        const day = (Date.UTC(now.getUTCFullYear(), now.getUTCMonth(), now.getUTCDate()) - Date.UTC(now.getUTCFullYear(), 0, 0)) / 8.64e+07;
        sunLat = -23.44 * Math.cos(2 * Math.PI / 365 * (day + 10));
        sunLon = wrapLon(-15 * (now.getUTCHours() + now.getUTCMinutes() / 60 - 12));
    }

    Component.onCompleted: {
        updateSun();
        VpnPickerState.globeUsed = true;
    }

    Timer {
        interval: 60000
        running: globe.visible
        repeat: true
        triggeredOnStart: true
        onTriggered: globe.updateSun()
    }

    QtObject {
        id: fly

        property real fromLon: 0
        property real fromLat: 0
        property real dLon: 0
        property real dLat: 0
        property real dip: 0
        // Zoom kink at the start (target change in mid-flight), fades out over the flight
        property real dip0: 0
        property real t: 1

        onTChanged: {
            if (!flyAnim.running)
                return ;

            globe.lonC = globe.wrapLon(fromLon + dLon * t);
            globe.latC = fromLat + dLat * t;
            globe.zoomDip = Math.sin(Math.PI * t) * dip + dip0 * (1 - t);
        }
    }

    NumberAnimation {
        id: flyAnim

        target: fly
        property: "t"
        to: 1
        duration: 800
        easing.type: Easing.BezierSpline
        easing.bezierCurve: Appearance.anim.curves.inOutSoft
        onStopped: globe.zoomDip = 0
    }

    NumberAnimation {
        id: appearAnim

        target: globe
        property: "appear"
        from: 0
        to: 1
        duration: 1000
        easing.type: Easing.BezierSpline
        easing.bezierCurve: Appearance.anim.curves.outQuint
    }

    NumberAnimation {
        id: introAnim

        target: globe
        property: "introT"
        from: 0
        to: 1
        duration: 1100
    }

    // After releasing the globe keeps turning with momentum and slows down
    FrameAnimation {
        id: inertia

        property real vx: 0
        property real vy: 0

        onTriggered: {
            globe.panBy(vx * frameTime, vy * frameTime);
            const k = Math.exp(-frameTime * 4.5);
            vx *= k;
            vy *= k;
            if (Math.hypot(vx, vy) < 10)
                stop();

        }
    }

    FrameAnimation {
        running: globe.built < Math.max(globe.layout.pills.length, globe.layout.dots.length)
        onTriggered: globe.built += Math.max(2, Math.ceil(frameTime * 600))
    }

    NumberAnimation on satT {
        from: 0
        to: 2 * Math.PI
        duration: 45000
        loops: Animation.Infinite
        running: globe.visible
    }

    NumberAnimation on starTime {
        from: 0
        to: 3600
        duration: 3.6e+06
        loops: Animation.Infinite
        running: globe.visible
    }

    FileView {
        path: Quickshell.env("HOME") + "/.config/quickshell-local/location.json"
        printErrors: false
        onLoaded: {
            try {
                const j = JSON.parse(text());
                if (typeof j.lat === "number" && typeof j.lon === "number")
                    globe.homeFile = [j.lat, j.lon];

            } catch (e) {
            }
        }
    }

    Process {
        running: true
        command: ["timedatectl", "show", "-p", "Timezone", "--value"]

        stdout: StdioCollector {
            onStreamFinished: globe.timezone = text.trim()
        }

    }

    // Mouse anywhere in the globe (takes nothing away): target for the parallax. If it leaves, the tilt
    // STAYS: before, the target went hard to 0, the globe swung back on every move into the search bar (which lies
    // over the globe area) or out of the panel and over again on returning (measured in a screen
    // recording: tilting every 0.5 s). Over the header and edge VpnPicker carries the tilt on (trackPointer).
    HoverHandler {
        onPointChanged: {
            if (hovered) {
                globe.updateParallax(point.position);
                Qt.callLater(globe.hoverFallback);
            }
        }
        onHoveredChanged: {
            if (!hovered) {
                // The mouse has left the globe: back to the active connection
                globe.hoverCountryServer = "";
                globe.hoverDot = "";
                Qt.callLater(globe.hoverFallback);
            }
        }
    }

    // Only follow while target and state differ (otherwise the animation stands)
    FrameAnimation {
        running: globe.visible && Math.abs(globe.panTX - globe.panX) + Math.abs(globe.panTY - globe.panY) > 0.0005
        onTriggered: {
            const k = 1 - Math.exp(-frameTime * 5);
            globe.panX += (globe.panTX - globe.panX) * k;
            globe.panY += (globe.panTY - globe.panY) * k;
        }
    }

    // ==== Space behind the planet: stars + dark halo (pickers/shaders/space.frag) ====
    ShaderEffect {
        // Stars move away from the mouse (the near layer fully, the far one at 45 % in the shader)
        property point pan: Qt.point(-globe.panX * globe.parallaxPx, -globe.panY * globe.parallaxPx)
        property real time: globe.starTime
        property real radius: globe.radius
        property point size: Qt.point(width, height)
        property point center: Qt.point(globe.cx, globe.cy)
        property color bg: WalColors.color0
        property color vivid: WalColors.vividAccent
        property color starColor: WalColors.color7

        anchors.fill: parent
        z: -2
        opacity: Math.min(1, globe.appear * 1.5)
        fragmentShader: Qt.resolvedUrl("shaders/space.frag.qsb")
    }

    // Back half of the orbit (lies below the planet)
    Shape {
        anchors.fill: parent
        z: -1
        opacity: globe.appear * 0.8
        preferredRendererType: Shape.CurveRenderer

        ShapePath {
            strokeColor: WalColors.withAlpha(WalColors.color7, 0.5)
            strokeWidth: 1.8
            strokeStyle: ShapePath.DashLine
            dashPattern: [0.01, 4]
            capStyle: ShapePath.RoundCap
            fillColor: "transparent"

            PathPolyline {
                path: globe.orbitBack
            }

        }

    }

    NumberAnimation {
        id: selFade

        target: globe
        property: "selK"
        from: 0
        to: 1
        duration: 380
        easing.type: Easing.OutCubic
    }

    NumberAnimation {
        id: selWave

        target: globe
        property: "waveT"
        from: 0
        to: 1
        duration: 1600
        easing.type: Easing.InOutSine
    }

    FileView {
        path: String(Qt.resolvedUrl("../resources/globe/countries.json")).replace("file://", "")
        onLoaded: {
            try {
                globe.countryIds = JSON.parse(text());
            } catch (e) {
                globe.countryIds = {};
            }
        }
    }

    FileView {
        path: String(Qt.resolvedUrl("../resources/globe/countries-grid.json")).replace("file://", "")
        onLoaded: {
            try {
                globe.gridRaw = JSON.parse(text());
            } catch (e) {
                globe.gridRaw = null;
            }
        }
    }

    // Country map for the shader: numbers must stay exact -> no smoothing, no mipmap
    Image {
        id: countryImage

        source: "../resources/globe/countries.png"
        visible: false
        smooth: false
        mipmap: false
        asynchronous: true
    }

    // Map for the shader (invisible, only serves as a texture)
    Image {
        id: mapImage

        source: "../resources/globe/earth.png"
        visible: false
        mipmap: true
        smooth: true
        asynchronous: true
    }

    ShaderEffect {
        id: sphere

        // Disc = 78 % of the item, the rest is room for the glow around the edge
        readonly property real disc: 0.78
        property var map: mapImage
        property var countries: countryImage
        property color goodColor: Theme.good
        property real selId: globe.shownSel
        property real prevSelId: globe.prevSel
        property real selK: globe.selK
        property real waveT: globe.waveT
        property vector4d selPos: globe.selPos
        property real activeId: globe.activeCountry
        readonly property var sc: globe.serverCountries
        property vector4d srv0: Qt.vector4d(sc[0], sc[1], sc[2], sc[3])
        property vector4d srv1: Qt.vector4d(sc[4], sc[5], sc[6], sc[7])
        property vector4d srv2: Qt.vector4d(sc[8], sc[9], sc[10], sc[11])
        property vector4d srv3: Qt.vector4d(sc[12], sc[13], sc[14], sc[15])
        property vector4d srv4: Qt.vector4d(sc[16], sc[17], sc[18], sc[19])
        property vector4d srv5: Qt.vector4d(sc[20], sc[21], sc[22], sc[23])
        property real lon0: globe.lonV * globe.rad
        property real lat0: globe.latV * globe.rad
        property real dist: globe.dist
        property real px: 1 / globe.radius
        property real time: 0
        property color lineColor: WalColors.color7
        property color accentColor: WalColors.color4
        property color bodyColor: WalColors.withAlpha(WalColors.color0, 0.62)
        // Hue of the tint of surface and atmosphere (fades along on a wallpaper change)
        property color tintColor: WalColors.vividAccent
        // Sun direction in the shader's coordinate system (longitude relative to the view center)
        property vector4d sunDir: {
            const p = globe.sunLat * globe.rad;
            const l = (globe.sunLon - globe.lonV) * globe.rad;
            return Qt.vector4d(Math.cos(p) * Math.sin(l), Math.sin(p), Math.cos(p) * Math.cos(l), 0);
        }

        x: globe.cx - width / 2
        y: globe.cy - height / 2
        width: globe.radius * 2 / disc
        height: width
        visible: mapImage.status === Image.Ready && countryImage.status === Image.Ready
        opacity: Math.min(1, globe.appear * 2.5)
        scale: 0.9 + 0.1 * globe.appear
        fragmentShader: Qt.resolvedUrl("shaders/globe.frag.qsb")

        NumberAnimation on time {
            from: 0
            to: 3600
            duration: 3.6e+06
            loops: Animation.Infinite
            running: globe.visible
        }

    }

    // Front half of the orbit (lies above the planet)
    Shape {
        anchors.fill: parent
        z: 0.5
        opacity: globe.appear * 0.8
        preferredRendererType: Shape.CurveRenderer

        ShapePath {
            strokeColor: WalColors.withAlpha(WalColors.color7, 0.75)
            strokeWidth: 1.8
            strokeStyle: ShapePath.DashLine
            dashPattern: [0.01, 4]
            capStyle: ShapePath.RoundCap
            fillColor: "transparent"

            PathPolyline {
                path: globe.orbitFront
            }

        }

    }

    // Satellite with a short tail (like the comet at the black hole). In front above, behind below the planet.
    // Only position and opacity change, never the size.
    Item {
        readonly property bool live: globe.activeName !== ""
        readonly property color tone: live ? Qt.lighter(WalColors.vividAccent, 1.2) : WalColors.withAlpha(WalColors.color7, 0.7)

        anchors.fill: parent
        z: globe.satFront ? 0.6 : -0.5
        opacity: globe.appear

        Repeater {
            model: 7

            Rectangle {
                required property int index
                readonly property point p: globe.orbitPt(globe.satT - (index + 1) * 0.035)

                x: p.x - 1.5
                y: p.y - 1.5
                width: 3
                height: 3
                radius: 1.5
                color: parent.tone
                opacity: 0.6 * (1 - index / 7)
            }

        }

        Sparkle {
            readonly property point p: globe.orbitPt(globe.satT)

            x: Math.round(p.x - width / 2)
            y: Math.round(p.y - height / 2)
            size: 5
            color: parent.tone
            glowColor: parent.live ? WalColors.vividAccent : WalColors.color7
            twinkle: 0.5 + 0.5 * Math.sin(globe.starTime * 2.2)
        }

    }

    // Three fixed sparkle stars in the space around the planet (as in the Wi-Fi/Bluetooth picker)
    Repeater {
        // [x, y] relative to the planet center in radii, size, phase
        model: [[-1.75, -0.95, 6, 0], [1.62, -1.02, 4.5, 2.1], [1.38, 1.12, 5, 4.3]]

        Sparkle {
            required property var modelData

            x: Math.round(globe.cx + globe.radius * modelData[0] - width / 2)
            y: Math.round(globe.cy + globe.radius * modelData[1] - height / 2)
            z: -1
            // Front stars: parallax a bit stronger; shifted as a finished image (softly filtered),
            // so they glide smoothly and the fine rays do not flicker
            layer.enabled: true
            layer.smooth: true
            transform: Translate {
                x: -globe.panX * globe.parallaxPx * 1.3
                y: -globe.panY * globe.parallaxPx * 1.3
            }
            size: modelData[2]
            color: Qt.lighter(WalColors.color7, 1.05)
            glowColor: WalColors.vividAccent
            twinkle: 0.5 + 0.5 * Math.sin(globe.starTime * (0.5 + modelData[3] * 0.06) + modelData[3])
            opacity: 0.75 * globe.appear
        }

    }

    // Dragging rotates, double click resets the view
    MouseArea {
        id: dragArea

        property real lastX: 0
        property real lastY: 0
        property real lastT: 0
        // Distance since pressing: whoever drags (rotates) does not trigger a click on release
        property real moved: 0

        x: globe.cx - globe.radius
        y: globe.cy - globe.radius
        width: globe.radius * 2
        height: width
        hoverEnabled: true
        cursorShape: pressed ? Qt.ClosedHandCursor : (globe.hoverCountryServer !== "" ? Qt.PointingHandCursor : Qt.OpenHandCursor)
        onExited: globe.hoverCountryServer = ""
        // A click on a country with a server connects (like a click on the dot)
        onClicked: {
            if (moved > 5 || globe.hoverCountryServer === "")
                return ;

            globe.select(globe.hoverCountryServer, false);
            globe.activated(globe.selectedEntry);
        }
        onPressed: (mouse) => {
            moved = 0;
            if (Math.hypot(mouse.x - globe.radius, mouse.y - globe.radius) > globe.radius) {
                mouse.accepted = false;
                return ;
            }
            flyAnim.stop();
            inertia.stop();
            inertia.vx = 0;
            inertia.vy = 0;
            lastX = mouse.x;
            lastY = mouse.y;
            lastT = Date.now();
        }
        onPositionChanged: (mouse) => {
            if (!pressed) {
                // Hover on countries: if a country with a server is under the pointer, it is selected
                const id = globe.countryAtScreen(mouse.x - globe.radius, mouse.y - globe.radius);
                const name = globe.countryServer[id] || "";
                globe.hoverCountryServer = name;
                if (name !== "" && name !== globe.selectedName && globe.hoverMoved(dragArea, mouse))
                    globe.select(name, false);

                return ;
            }
            const dx = mouse.x - lastX;
            moved += Math.hypot(dx, mouse.y - lastY);
            const dy = mouse.y - lastY;
            const now = Date.now();
            const dt = Math.max(1, now - lastT) / 1000;
            globe.panBy(dx, dy);
            inertia.vx = 0.55 * inertia.vx + 0.45 * dx / dt;
            inertia.vy = 0.55 * inertia.vy + 0.45 * dy / dt;
            lastX = mouse.x;
            lastY = mouse.y;
            lastT = now;
        }
        onReleased: {
            // Held still briefly before releasing: no momentum
            if (Date.now() - lastT < 70 && Math.hypot(inertia.vx, inertia.vy) > 80)
                inertia.start();

        }
        onDoubleClicked: globe.resetView()
    }

    WheelHandler {
        acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
        onWheel: (event) => {
            globe.zoom = Math.max(0, Math.min(1, globe.zoom + event.angleDelta.y / 120 * 0.07));
            event.accepted = true;
        }
    }

    // Continuous row zones up to the middle of the gap: no dip
    // in the enlargement between two countries. The mouse only selects the target row.
    function dockEntryAt(x, y) {
        const side = x < cx ? -1 : 1;
        const entries = side < 0 ? layout.left : layout.right;
        if (entries.length === 0)
            return null;
        const stride = Math.min(50, colH / entries.length);
        const row = Math.floor((y - cy) / stride + entries.length / 2);
        if (row < 0 || row >= entries.length)
            return null;
        // Arc at the mouse height: the zone also stays continuous horizontally in the gap.
        const edge = cx + side * arcX(y - cy);
        const left = side < 0 ? edge - pillW : edge;
        const rowEdge = cx + side * arcX(rowY(row, entries.length));
        const rowLeft = side < 0 ? rowEdge - pillW : rowEdge;
        return x >= Math.min(left, rowLeft) - 6
            && x <= Math.max(left, rowLeft) + pillW + 6 ? entries[row] : null;
    }

    readonly property var dockEntry: columnHover.hovered && enabled
        ? dockEntryAt(columnHover.point.position.x, columnHover.point.position.y) : null

    HoverHandler {
        id: columnHover
        onPointChanged: {
            if (!hovered || !globe.dockEntry)
                return;
            // The same target row for color and size, also in the gap.
            if (globe.hoverMoved(globe, {x: point.position.x, y: point.position.y}))
                globe.select(globe.dockEntry.name, false);
        }
    }

    // ==== Connection arc (only when connected): dotted like the orbit, a light dot travels on it ====
    Item {
        id: arc

        readonly property color tone: Qt.tint(Qt.lighter(WalColors.color7, 1.1), Qt.rgba(Theme.good.r, Theme.good.g, Theme.good.b, 0.55))

        anchors.fill: parent
        opacity: globe.activeName !== "" && globe.arcPts.length > 0 ? globe.appear : 0
        visible: opacity > 0.01

        Repeater {
            model: globe.arcPts.length

            Rectangle {
                id: arcDot

                required property int index
                readonly property var pt: globe.arcPts[index] ?? ({ "x": 0, "y": 0, "t": 0, "vis": 0 })
                readonly property real head: Math.exp(-Math.pow((pt.t - globe.arcPulse) / 0.07, 2))

                x: globe.cx + pt.x - width / 2
                y: globe.cy + pt.y - height / 2
                width: 3
                height: 3
                radius: 1.5
                color: arc.tone
                opacity: pt.vis * (0.5 + 0.5 * head)
            }

        }

        // Own location: small dot with a softly breathing ring
        Item {
            readonly property vector3d p: globe.homeLL ? globe.project(globe.homeLL[0], globe.homeLL[1]) : Qt.vector3d(0, 0, 0)

            x: globe.cx + p.x
            y: globe.cy + p.y
            opacity: p.z

            Rectangle {
                x: -3
                y: -3
                width: 6
                height: 6
                radius: 3
                color: arc.tone
            }

            Rectangle {
                x: -7
                y: -7
                width: 14
                height: 14
                radius: 7
                color: "transparent"
                border.width: 1
                border.color: arc.tone
                opacity: 0.25 + 0.35 * (0.5 + 0.5 * Math.sin(globe.starTime * 1.6))
            }

        }

        Behavior on opacity {
            NumberAnimation {
                duration: 400
            }

        }

    }

    NumberAnimation on arcPulse {
        from: -0.1
        to: 1.25
        duration: 2800
        loops: Animation.Infinite
        running: globe.visible && arc.visible
    }

    // ==== Lines + pills ====
    Repeater {
        model: ScriptModel {
            values: globe.layout.pills.slice(0, globe.built)
        }

        delegate: Item {
            id: call

            required property string modelData
            readonly property var node: globe.layout.map[modelData] ?? null
            readonly property bool ok: node !== null && node.side !== 0
            readonly property int side: ok ? node.side : -1
            readonly property bool isSelected: globe.selectedName === modelData
            readonly property bool isActive: globe.activeName === modelData
            readonly property bool hasDot: ok && node.geo
            readonly property bool switching: VpnPickerState.busy && (VpnPickerState.pendingFrom === modelData || VpnPickerState.pendingTo === modelData)
            readonly property vector3d pos: hasDot ? globe.project(node.lat, node.lon) : Qt.vector3d(0, 0, 0)
            readonly property real targetDy: ok ? globe.rowY(node.row, node.rows) : 0
            // The row glides to its new place when filtering (not when created)
            property real dy: targetDy
            property bool ready: false
            // Anchor point of the line at the pill (inner edge, middle)
            readonly property real ax: globe.cx + side * globe.arcX(dy)
            readonly property real dockY: globe.cy + dy
            readonly property bool dockColumn: ok && globe.dockEntry !== null
                && globe.dockEntry.side === side
            readonly property real dockDistance: dockColumn ? node.row - globe.dockEntry.row : 0
            // Constant target value on the whole row; neighbors grow along softly.
            readonly property real dockWeight: dockColumn ? Math.exp(-dockDistance * dockDistance / 0.98) : 0
            property real magnify: dockWeight
            property real dockShift: dockColumn ? Math.sign(dockDistance) * 2 * (1 - dockWeight) : 0
            readonly property real ay: dockY + dockShift

            Behavior on magnify {
                NumberAnimation { duration: 140; easing.type: Easing.OutCubic }
            }
            Behavior on dockShift {
                NumberAnimation { duration: 140; easing.type: Easing.OutCubic }
            }
            readonly property real px: globe.cx + pos.x
            // Line start: on the left the content (flag, name, check mark) ends before the edge of the invisible pill,
            // there the line begins, otherwise it would hang in the void with a gap. With a selection background (hot)
            // the start glides to the edge of the background. On the right the flag sits at the edge, there it stays ax.
            readonly property real contentEdge: side < 0
                ? ax - globe.pillW + (activeMark.active || activeMark.busy ? activeMark.x + activeMark.width : label.x + label.width) + 6
                : ax
            readonly property real lineX: contentEdge + (ax - contentEdge) * hot
            readonly property real py: globe.cy + pos.y
            property real hot: isSelected ? 1 : 0
            property real press: pillMouse.pressed ? 1 : 0
            // Pills glide in one after another from outside (from top to bottom), each softly on its own
            readonly property real shownRaw: Math.max(0, Math.min(1, (globe.introT - 0.1 - (ok ? node.row : 0) * 0.022) / 0.26))
            readonly property real shown: shownRaw * shownRaw * (3 - 2 * shownRaw)
            // Lines only when the camera has almost arrived: before, their ends would sweep over
            // the globe with the approach
            readonly property real lineRaw: Math.max(0, Math.min(1, (globe.introT - 0.66) / 0.3))
            readonly property real lineShown: lineRaw * lineRaw * (3 - 2 * lineRaw)
            // A line only for the selection (= hover) and the active connection: all 22 at once ran together
            // into a net over central Europe, the important line got lost in it
            property real lineK: isSelected || isActive || switching ? 1 : 0
            // Flag and extra line full only on selection/connection; otherwise the flag desaturated, the line gone
            property real focusK: isSelected || isActive || switching ? 1 : 0

            Behavior on lineK {
                NumberAnimation { duration: 220; easing.type: Easing.OutCubic }
            }
            Behavior on focusK {
                NumberAnimation { duration: 180; easing.type: Easing.OutCubic }
            }

            anchors.fill: parent
            visible: ok
            z: isSelected ? 2 : 1
            Component.onCompleted: ready = true

            Shape {
                anchors.fill: parent
                visible: call.hasDot && call.lineK > 0.001
                // Behind the horizon: no line (otherwise they all run together at the edge)
                opacity: call.lineShown * call.pos.z * call.lineK
                preferredRendererType: Shape.CurveRenderer

                ShapePath {
                    strokeWidth: 1.2 + 0.8 * call.hot
                    strokeColor: call.isActive ? WalColors.withAlpha(Theme.good, 0.45 + 0.45 * call.hot) : Qt.tint(WalColors.withAlpha(WalColors.color7, 0.24), WalColors.withAlpha(WalColors.color4, call.hot))
                    fillColor: "transparent"
                    capStyle: ShapePath.RoundCap
                    startX: call.lineX
                    startY: call.ay

                    PathCubic {
                        x: call.px
                        y: call.py
                        control1X: call.lineX - call.side * Math.abs(call.px - call.lineX) * 0.5
                        control1Y: call.ay
                        control2X: call.px + call.side * Math.abs(call.px - call.lineX) * 0.3
                        control2Y: call.py
                    }

                }

            }

            // No effect geometry per country when opening. Only the new target
            // loads the tail; after the last pulse it is released again.
            Loader {
                id: connectionEnergy
                readonly property bool requested: VpnPickerState.busy && VpnPickerState.pendingTo === call.modelData
                readonly property real arrival: item ? item.arrival : 0
                readonly property real arrivalProgress: item ? item.arrivalProgress : 0
                readonly property color tone: call.isActive && !call.switching ? Theme.good : WalColors.color4
                property bool retained: false
                function releaseWhenFinished() {
                    if (!requested && (!item || !item.playing))
                        retained = false;
                }
                onRequestedChanged: {
                    if (requested)
                        retained = true;
                    else
                        Qt.callLater(releaseWhenFinished);
                }
                onLoaded: retained = true
                onVisibleChanged: {
                    if (!visible)
                        retained = false;
                }
                anchors.fill: parent
                visible: call.hasDot && call.pos.z > 0.01 && call.lineShown > 0.01
                active: visible && (requested || retained)
                opacity: call.lineShown * call.pos.z
                Connections {
                    target: connectionEnergy.item
                    function onPlayingChanged() {
                        Qt.callLater(connectionEnergy.releaseWhenFinished);
                    }
                }
                sourceComponent: ConnectionEnergy {
                    busy: connectionEnergy.requested
                    allowed: !VpnPickerState.busy || VpnPickerState.pendingTo === call.modelData
                    tone: connectionEnergy.tone
                    // From the location on the globe to the line connection at the tile.
                    startPoint: Qt.point(call.px, call.py)
                    control1: Qt.point(call.px + call.side * Math.abs(call.px - call.lineX) * 0.3, call.py)
                    control2: Qt.point(call.lineX - call.side * Math.abs(call.px - call.lineX) * 0.5, call.ay)
                    endPoint: Qt.point(call.lineX, call.ay)
                }
            }

            Rectangle {
                id: pill

                x: call.side < 0 ? call.ax - width : call.ax
                y: call.ay - height / 2
                width: globe.pillW
                height: globe.pillH
                radius: height / 2
                // No frame, no box: outlined buttons looked glued onto space (like the Bluetooth devices
                // before). Only the selection gets a touch of background; the connection shows text + check mark
                color: WalColors.withAlpha(WalColors.color4, 0.13 * call.hot)
                opacity: call.shown * (call.hasDot && call.pos.z <= 0 ? 0.55 + 0.45 * call.hot : 1)
                scale: 1 + 0.045 * call.magnify - 0.012 * call.press
                transformOrigin: call.side < 0 ? Item.Right : Item.Left

                transform: Translate {
                    x: call.side * (1 - call.shown) * 22
                }

                Loader {
                    anchors.fill: parent
                    active: connectionEnergy.item !== null
                    sourceComponent: Item {
                        // The arrival only plays on the new target: a bright edge pulse
                        // and a wider, short shine from the connection to the outer edge.
                        Rectangle {
                            anchors.fill: parent
                            anchors.margins: -7 * connectionEnergy.arrivalProgress
                            radius: pill.radius + 7 * connectionEnergy.arrivalProgress
                            color: "transparent"
                            border.width: 1.5
                            border.color: connectionEnergy.tone
                            opacity: connectionEnergy.arrival * 0.85
                        }
                        Rectangle {
                            anchors.fill: parent
                            radius: pill.radius
                            color: "transparent"
                            border.width: 2
                            border.color: Qt.lighter(connectionEnergy.tone, 1.35)
                            opacity: connectionEnergy.arrival * 0.75
                        }
                        ClippingRectangle {
                            anchors.fill: parent
                            radius: pill.radius
                            color: "transparent"
                            visible: connectionEnergy.arrival > 0.001
                            Rectangle {
                                width: 85
                                height: parent.height
                                x: call.side > 0
                                    ? -width + (parent.width + width) * connectionEnergy.arrivalProgress
                                    : parent.width - (parent.width + width) * connectionEnergy.arrivalProgress
                                opacity: connectionEnergy.arrival * 0.28
                                gradient: Gradient {
                                    orientation: Gradient.Horizontal
                                    GradientStop { position: 0; color: "transparent" }
                                    GradientStop { position: 0.5; color: Qt.lighter(connectionEnergy.tone, 1.4) }
                                    GradientStop { position: 1; color: "transparent" }
                                }
                            }
                        }
                    }
                }

                // Round flag (drawn twice as big and scaled down: smooth rounding)
                Item {
                    id: flag

                    anchors.left: parent.left
                    anchors.leftMargin: 7
                    anchors.verticalCenter: parent.verticalCenter
                    width: 26
                    height: 26
                    layer.enabled: true
                    layer.smooth: true
                    layer.mipmap: true
                    layer.textureSize: Qt.size(width * 2, height * 2)
                    // Colorful flags were the only saturated thing in the scene: gray when idle (half desaturated they looked
                    // dirty brown), on selection/connection the color fades in
                    layer.effect: MultiEffect {
                        saturation: -(1 - call.focusK)
                    }
                    opacity: 0.6 + 0.4 * call.focusK

                    ClippingRectangle {
                        anchors.fill: parent
                        radius: width / 2
                        color: WalColors.withAlpha(WalColors.color7, 0.1)

                        Image {
                            id: flagImg

                            anchors.fill: parent
                            source: call.ok && call.node.code !== "" ? "../resources/flags/" + call.node.code + ".svg" : ""
                            sourceSize: Qt.size(70, 52)
                            fillMode: Image.PreserveAspectCrop
                            asynchronous: true
                        }

                        Text {
                            anchors.centerIn: parent
                            visible: flagImg.status !== Image.Ready
                            text: call.ok && call.node.code !== "" ? call.node.code.toUpperCase() : globe.icShield
                            font.family: Theme.font
                            font.pixelSize: 10
                            font.bold: true
                            color: WalColors.color4
                        }

                    }

                }

                // As wide as the text (at most up to the room for the check mark): without a frame a check mark at the
                // outer edge would have floated lost in the void, now it stands right after the name
                Column {
                    id: label

                    anchors.left: flag.right
                    anchors.leftMargin: 10
                    anchors.verticalCenter: parent.verticalCenter
                    width: Math.min(Math.max(nameText.implicitWidth, subText.implicitWidth), pill.width - 7 - flag.width - 10 - activeMark.width - 8 - 9)
                    spacing: 0

                    Text {
                        id: nameText

                        width: parent.width
                        text: call.ok ? call.node.label : ""
                        font.family: Theme.fontUi
                        font.pixelSize: 13
                        font.weight: Font.Medium
                        color: WalColors.withAlpha(WalColors.color7, 0.8 + 0.2 * call.hot)
                        elide: Text.ElideRight
                    }

                    Text {
                        id: subText

                        width: parent.width
                        // Only on selection/connection (proton-xx in every row said nothing new); opens softly,
                        // the name glides up from the middle meanwhile
                        height: implicitHeight * call.focusK
                        opacity: call.focusK
                        visible: call.focusK > 0.01
                        // Active + selected pill: click/Enter disconnects -> show that too
                        // During the switch (the picker stays open) the pill shows what is happening right now
                        text: call.switching ? (call.modelData === VpnPickerState.pendingTo ? "Connecting…" : "Disconnecting…") : (call.isActive ? (call.isSelected ? "Disconnect" : "Connected") : call.modelData)
                        font.family: Theme.fontUi
                        font.pixelSize: 10
                        color: call.switching ? WalColors.color4 : (call.isActive ? (call.isSelected ? Theme.bad : Theme.good) : WalColors.withAlpha(WalColors.color7, 0.42))
                        elide: Text.ElideRight
                    }

                }

                VpnConnectionIndicator {
                    id: activeMark
                    anchors.left: label.right
                    anchors.leftMargin: 8
                    anchors.verticalCenter: parent.verticalCenter
                    active: call.isActive
                    busy: call.switching
                    pulseEnabled: !call.hasDot || call.pos.z <= 0.01
                }

            }

            // Fixed hit zone, independent of the subtle enlargement.
            MouseArea {
                id: pillMouse
                x: call.side < 0 ? call.ax - width : call.ax
                y: call.dockY - height / 2
                width: globe.pillW
                height: globe.pillH
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                    globe.select(call.modelData, false);
                    globe.activated(call.node);
                }
            }

            Behavior on dy {
                enabled: call.ready

                NumberAnimation {
                    duration: 360
                    easing.type: Easing.BezierSpline
                    easing.bezierCurve: Appearance.anim.curves.outQuint
                }

            }

            // Short color reaction matching the direct dock movement.
            Behavior on hot {
                NumberAnimation {
                    duration: 120
                    easing.type: Easing.OutCubic
                }
            }

            Behavior on press {
                NumberAnimation {
                    duration: 110
                    easing.type: Easing.OutCubic
                }
            }

        }

    }

    // ==== Dots on the globe ====
    Repeater {
        model: ScriptModel {
            values: globe.layout.dots.slice(0, globe.built)
        }

        delegate: Item {
            id: dot

            required property string modelData
            readonly property var node: globe.layout.map[modelData] ?? null
            readonly property vector3d pos: node ? globe.project(node.lat, node.lon) : Qt.vector3d(0, 0, 0)
            readonly property bool isSelected: globe.selectedName === modelData
            readonly property bool isActive: globe.activeName === modelData
            readonly property color tone: isActive ? Theme.good : WalColors.color4
            property real hot: isSelected ? 1 : 0

            x: globe.cx + pos.x
            y: globe.cy + pos.y
            z: isSelected ? 3 : (isActive ? 2 : 1)
            opacity: pos.z * Math.min(1, globe.appear * 2)
            visible: opacity > 0.01

            // The active connection sends out rings
            Repeater {
                model: dot.isActive ? 2 : 0

                Rectangle {
                    id: ping

                    required property int index

                    anchors.centerIn: parent
                    width: 12
                    height: 12
                    radius: height / 2
                    color: "transparent"
                    border.width: 1.5
                    border.color: Theme.good
                    opacity: 0

                    SequentialAnimation {
                        running: dot.visible
                        loops: Animation.Infinite

                        PauseAnimation {
                            duration: ping.index * 900
                        }

                        ParallelAnimation {
                            NumberAnimation {
                                target: ping
                                property: "scale"
                                from: 1
                                to: 4.2
                                duration: 1800
                                easing.type: Easing.OutCubic
                            }

                            NumberAnimation {
                                target: ping
                                property: "opacity"
                                from: 0.7
                                to: 0
                                duration: 1800
                                easing.type: Easing.OutCubic
                            }

                        }

                        PauseAnimation {
                            duration: (1 - ping.index) * 900
                        }

                    }

                }

            }

            // Server as a ring with a bright core: stands out from the round city lights. The middle is
            // darkened, so no city lights shine through. Fixed size, the selection only raises
            // brightness and glow (the selection ring is drawn by the marker).
            Rectangle {
                anchors.centerIn: parent
                width: 22
                height: 22
                radius: height / 2
                color: WalColors.withAlpha(dot.isActive ? Theme.good : WalColors.vividAccent, 0.1 + 0.14 * dot.hot)
            }

            // Grows slightly on hover: via scale (transform), not via the width - so the middle stays
            // fixed and the fine ring does not tremble
            Rectangle {
                anchors.centerIn: parent
                width: 12
                height: 12
                radius: height / 2
                scale: 1 + 0.3 * dot.hot
                color: WalColors.withAlpha(WalColors.color0, 0.75)
                border.width: 1.6
                border.color: dot.isActive ? Theme.good : Qt.lighter(WalColors.vividAccent, 1.1 + 0.3 * dot.hot)
            }

            Rectangle {
                anchors.centerIn: parent
                width: 4
                height: 4
                radius: height / 2
                color: dot.isActive ? Qt.lighter(Theme.good, 1.3) : Qt.lighter(WalColors.color7, 1.1 + 0.15 * dot.hot)
            }

            MouseArea {
                id: dotMouse

                anchors.centerIn: parent
                width: 24
                height: 24
                enabled: dot.pos.z > 0.3
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onContainsMouseChanged: {
                    if (containsMouse)
                        globe.hoverDot = dot.modelData;
                    else if (globe.hoverDot === dot.modelData)
                        globe.hoverDot = "";
                }
                // If the dot under the mouse disappears (filter), hoverDot must not get stuck
                Component.onDestruction: {
                    if (globe.hoverDot === dot.modelData)
                        globe.hoverDot = "";
                }
                onPositionChanged: (mouse) => {
                    if (globe.hoverMoved(dotMouse, mouse))
                        globe.select(dot.modelData, false);

                }
                onClicked: {
                    globe.select(dot.modelData, false);
                    globe.activated(dot.node);
                }
            }

            // Slight overshoot: the ring "pops" briefly on hover
            Behavior on hot {
                NumberAnimation {
                    duration: 260
                    easing.type: Easing.OutBack
                    easing.overshoot: 1.6
                }

            }

        }

    }

    // ==== Selection on the globe: ONE ring + name for all dots (instead of shapes in every dot -
    // that held up the build noticeably when opening). Plain: the ring contracts, the name fades in.
    Item {
        id: marker

        readonly property var node: globe.selectedEntry
        readonly property bool shown: node !== null && node.geo
        readonly property vector3d pos: shown ? globe.project(node.lat, node.lon) : Qt.vector3d(0, 0, 0)
        readonly property color tone: shown && node.name === globe.activeName ? Theme.good : WalColors.color7
        property real pop: 1

        x: globe.cx + pos.x
        y: globe.cy + pos.y
        visible: shown && pos.z > 0.01
        opacity: pos.z * Math.min(1, globe.appear * 2)

        Connections {
            function onSelectedNameChanged() {
                popAnim.restart();
            }

            target: globe
        }

        NumberAnimation {
            id: popAnim

            target: marker
            property: "pop"
            from: 0
            to: 1
            duration: 200
            easing.type: Easing.OutCubic
        }

        Rectangle {
            anchors.centerIn: parent
            width: 22
            height: 22
            radius: height / 2
            color: "transparent"
            border.width: 1.5
            border.color: marker.tone
            scale: 1.7 - 0.7 * marker.pop
            opacity: marker.pop
        }

        Text {
            x: -width / 2
            y: -32 + 4 * (1 - marker.pop)
            text: marker.shown ? marker.node.label : ""
            font.family: Theme.fontUi
            font.pixelSize: 12
            font.weight: Font.DemiBold
            color: marker.tone
            style: Text.Outline
            styleColor: WalColors.withAlpha(WalColors.color0, 0.9)
            opacity: marker.pop
        }

    }

    // ==== Status below the globe ====
    Column {
        visible: globe.showStatus
        anchors.horizontalCenter: parent.horizontalCenter
        y: globe.cy + globe.radius + 26
        spacing: 8
        opacity: Math.max(0, globe.appear * 2 - 1)

        Rectangle {
            readonly property var active: VpnPickerState.connections.find((c) => {
                return c.name === globe.activeName;
            })

            anchors.horizontalCenter: parent.horizontalCenter
            width: statusRow.implicitWidth + 26
            height: 28
            radius: height / 2
            color: WalColors.withAlpha(active ? Theme.good : Theme.bad, 0.1)
            border.width: 1
            border.color: WalColors.withAlpha(active ? Theme.good : Theme.bad, 0.4)

            Row {
                id: statusRow

                anchors.centerIn: parent
                spacing: 8

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: parent.parent.active ? globe.icShield : globe.icShieldOff
                    font.family: Theme.font
                    font.pixelSize: 13
                    color: parent.parent.active ? Theme.good : Theme.bad
                }

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: VpnPickerState.busy ? "Switching…" : (parent.parent.active ? "Connected · " + parent.parent.active.label : "Exposed")
                    font.family: Theme.fontUi
                    font.pixelSize: 12
                    font.weight: Font.Medium
                    color: parent.parent.active ? Theme.good : Theme.bad
                }

            }

        }

    }

    Text {
        anchors.horizontalCenter: parent.horizontalCenter
        y: globe.cy - globe.radius - 34
        horizontalAlignment: Text.AlignHCenter
        visible: globe.servers.length === 0
        text: VpnPickerState.connections.length === 0 ? "No WireGuard connections found – use + to add a config" : "No country found"
        font.family: Theme.fontUi
        font.pixelSize: 13
        color: WalColors.withAlpha(WalColors.color7, 0.5)
    }

    Behavior on zoomShown {
        NumberAnimation {
            duration: 260
            easing.type: Easing.OutCubic
        }

    }

}
