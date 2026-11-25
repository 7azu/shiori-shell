#version 440

// Planet of the VPN picker (pickers/VpnGlobe.qml) in the space style of the Wi-Fi/Bluetooth pickers and the
// Obsidian plugin "Galaxie": sphere by ray intersection, map from resources/globe/earth.png
// (R = coasts/borders, G = city lights, B = land; made by scripts/make-globe-map.py).
// - day and night by the real sun position (sunDir): by day land softly lit + sun glint on the sea,
//   at night the cities sparkle
// - thin cloud layer (noise on the sphere), drifts slowly
// - countries as areas instead of border lines (country map countries.png, value = number of the country): every
//   country with a slightly own tone, server countries subtly in the accent, the selected country lights up,
//   the connected one is tinted green. Land stays clearly set off from the sea even at night.
// - atmosphere: rim at the edge and a soft glow, bright toward the sun but never fully gone
// - form light: faint fixed light from the top left (view space, like moonlight). Gives the sphere form at night too
//   and the sea a slight sheen; without it the night side was a flat black disc
// Camera at distance `dist` (in sphere radii): the closer, the smaller the visible section - the
// disc stays the same size on screen.
// Recompile after changes:
//   /usr/lib/qt6/bin/qsb --glsl "300 es,150,330" -o globe.frag.qsb globe.frag

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    float lon0;   // view center, radians
    float lat0;
    float dist;   // camera distance from the center, > 1
    float disc;   // disc radius as a share of half the item width (the rest = room for the glow)
    float px;     // size of one pixel in disc radii (anti-aliasing)
    float time;
    vec4 lineColor;    // light palette color (land, clouds, coasts)
    vec4 accentColor;  // accent (lights, atmosphere)
    vec4 bodyColor;    // dark base color (sea)
    vec4 sunDir;  // unit vector to the sun in earth coordinates (longitude relative to the view center)
    vec4 goodColor;    // color of the active connection
    float selId;       // number of the selected country (0 = none)
    float prevSelId;   // previously selected country (fades out while selId fades in)
    float selK;        // 0 -> 1: crossfade prevSelId -> selId
    float waveT;       // 0 -> 1: light wave from the server location over the selected country
    vec4 selPos;       // server location as a unit vector (earth coordinates, longitude relative to the view center)
    float activeId;    // number of the connected country
    vec4 srv0;         // numbers of the server countries, up to 24 (0 = empty)
    vec4 srv1;
    vec4 srv2;
    vec4 srv3;
    vec4 srv4;
    vec4 srv5;
    vec4 tintColor;    // strongest palette color (WalColors.vividAccent): hue of the tint
};

layout(binding = 1) uniform sampler2D map;
layout(binding = 2) uniform sampler2D countries;

const float PI = 3.14159265358979;
// Direction of the form light in view space (camera on +z): top left, slightly from the front
const vec3 KEY = vec3(-0.52, 0.56, 0.64);
// Tint by the palette: the pywal colors for land/atmosphere are often almost gray, the
// planet then looked cold and foreign. First a fixed cream orange (like blackhole.frag) - fit warm wallpapers,
// but stood out with blue ones. Now the hue of the strongest palette color (tintColor), weakened about
// by half, like the cream orange before (1.0, 0.80, 0.56). Strength: TINT_BODY (surface), TINT_AIR (atmosphere)
const float TINT_BODY = 0.38;
const float TINT_AIR = 0.35;
// Only the hue: normalized to the brightest channel, then halfway toward white (otherwise too colorful)
vec3 tintHue() {
    vec3 t = max(tintColor.rgb, vec3(0.0));
    float m = max(max(t.r, t.g), max(t.b, 1e-3));
    return mix(vec3(1.0), t / m, 0.55);
}
vec3 tintGrade(vec3 c, float k) {
    // Keep the brightness, pull the hue toward the palette (divided by the brightness of the hue)
    vec3 h = tintHue();
    const vec3 LUM = vec3(0.2126, 0.7152, 0.0722);
    float l = dot(c, LUM);
    return mix(c, l * h / max(dot(h, LUM), 0.2), k);
}

// Derivative of a value that jumps somewhere around 1 (longitude): a and b are the same value
// with a shifted jump point, the smaller derivative is the real one
float pick(float a, float b) {
    return abs(a) < abs(b) ? a : b;
}

float isServer(float id) {
    if (id < 0.5)
        return 0.0;
    vec4 v = vec4(id);
    bvec4 a = equal(v, srv0), b = equal(v, srv1), c = equal(v, srv2), d = equal(v, srv3), e = equal(v, srv4), f = equal(v, srv5);
    return (any(a) || any(b) || any(c) || any(d) || any(e) || any(f)) ? 1.0 : 0.0;
}

float hash11(float x) {
    return fract(sin(x * 91.3458) * 47453.5453);
}

float hash31(vec3 p) {
    p = fract(p * vec3(0.1031, 0.1030, 0.0973));
    p += dot(p, p.yxz + 33.33);
    return fract((p.x + p.y) * p.z);
}

float vn(vec3 x) {
    vec3 i = floor(x);
    vec3 f = fract(x);
    f = f * f * (3.0 - 2.0 * f);
    return mix(mix(mix(hash31(i), hash31(i + vec3(1, 0, 0)), f.x), mix(hash31(i + vec3(0, 1, 0)), hash31(i + vec3(1, 1, 0)), f.x), f.y),
               mix(mix(hash31(i + vec3(0, 0, 1)), hash31(i + vec3(1, 0, 1)), f.x), mix(hash31(i + vec3(0, 1, 1)), hash31(i + vec3(1, 1, 1)), f.x), f.y), f.z);
}

float fbm(vec3 p) {
    return 0.5 * vn(p) + 0.27 * vn(p * 2.03 + 3.1) + 0.15 * vn(p * 4.1 - 1.7) + 0.08 * vn(p * 8.3 + 5.2);
}

void main() {
    vec2 p = (qt_TexCoord0 * 2.0 - 1.0) / disc;
    p.y = -p.y;
    float r = length(p);
    // Clamp at the edge, so no NaN runs into the derivatives outside the disc
    vec2 q = p * min(1.0, 0.9995 / max(r, 1e-5));

    float tanA = 1.0 / sqrt(dist * dist - 1.0);
    vec3 dir = normalize(vec3(q * tanA, -1.0));
    float b = dist * dir.z;
    float h = max(b * b - (dist * dist - 1.0), 0.0);
    vec3 n = vec3(0.0, 0.0, dist) + (-b - sqrt(h)) * dir;
    float facing = clamp(dot(n, -dir), 0.0, 1.0);

    // Earth coordinates (longitude relative to the view center)
    float s0 = sin(lat0);
    float c0 = cos(lat0);
    vec3 g = vec3(n.x, n.y * c0 + n.z * s0, -n.y * s0 + n.z * c0);
    vec3 eye = -dir;
    vec3 eyeE = vec3(eye.x, eye.y * c0 + eye.z * s0, -eye.y * s0 + eye.z * c0);
    float lat = asin(clamp(g.y, -1.0, 1.0));
    float u = atan(g.x, g.z) / (2.0 * PI);   // -0.5 .. 0.5 relative to the view center
    float u2 = fract(u + 0.5);
    float v = 0.5 - lat / PI;
    vec2 dx = vec2(pick(dFdx(u), dFdx(u2)), dFdx(v));
    vec2 dy = vec2(pick(dFdy(u), dFdy(u2)), dFdy(v));
    vec2 uv = vec2(fract(u + lon0 / (2.0 * PI) + 0.5), v);
    vec3 tex = textureGrad(map, uv, dx, dy).rgb;
    // Absolute position on the earth (not relative to the view center): noise/clouds turn with the globe
    float lonA = atan(g.x, g.z) + lon0;
    vec3 ge = vec3(cos(lat) * sin(lonA), g.y, cos(lat) * cos(lonA));

    vec3 sun = normalize(sunDir.xyz);
    float ndl = dot(g, sun);
    float lambert = max(ndl, 0.0);
    float day = smoothstep(-0.1, 0.25, ndl);
    // Form light (view space: normal n): soft, works mostly on the night side
    vec3 key = normalize(KEY);
    float keyL = max(dot(n, key), 0.0);
    float night = 1.0 - day;

    // ---- Countries: bilinearly filtered by hand over the four nearest texels. The properties are mixed
    // (selected, server, tone), never the numbers - otherwise mixed numbers would appear at borders
    // that belong to a completely different country ----
    vec2 csz = vec2(textureSize(countries, 0));
    vec2 fpos = vec2(fract(uv.x), uv.y) * csz - 0.5;
    vec2 ipos = floor(fpos);
    vec2 fw = fpos - ipos;
    float tone = 0.0, srv = 0.0, sel = 0.0, act = 0.0, selB = 0.0;
    for (int k = 0; k < 4; k++) {
        vec2 o = vec2(float(k & 1), float((k >> 1) & 1));
        vec2 tc = ipos + o;
        // Wrap the longitude, clamp the latitude
        tc.x = mod(tc.x, csz.x);
        tc.y = clamp(tc.y, 0.0, csz.y - 1.0);
        float id = floor(texelFetch(countries, ivec2(tc), 0).r * 255.0 + 0.5);
        float wgt = (o.x > 0.5 ? fw.x : 1.0 - fw.x) * (o.y > 0.5 ? fw.y : 1.0 - fw.y);
        tone += wgt * (id > 0.5 ? hash11(id) : 0.5);
        srv += wgt * isServer(id);
        sel += wgt * ((id > 0.5 && abs(id - selId) < 0.5) ? 1.0 : 0.0);
        selB += wgt * ((id > 0.5 && abs(id - prevSelId) < 0.5) ? 1.0 : 0.0);
        act += wgt * ((id > 0.5 && abs(id - activeId) < 0.5) ? 1.0 : 0.0);
    }

    // ---- Surface ----
    float land = smoothstep(0.3, 0.7, tex.b);
    float relief = fbm(ge * 7.0);
    // Every country with a slightly own tone: so countries can be told apart without border lines
    float landTone = mix(0.62, 1.38, tone);
    vec3 ocean = bodyColor.rgb * 0.35 + accentColor.rgb * 0.012;
    vec3 ground = mix(lineColor.rgb * 0.2, mix(lineColor.rgb, accentColor.rgb, 0.45) * 0.3, relief) * landTone;
    vec3 surface = mix(ocean, ground, land);
    // Light: soft by day; at night the form light from the top left instead of a flat ambient light, so the
    // sphere stays round (brighter at the top left, darker toward the edge at the bottom right)
    vec3 col = surface * (0.07 + 1.05 * lambert + night * (0.05 + 0.42 * keyL));
    // Earthshine: the land stays clearly set off from the sea at night too, stronger toward the light side
    col += lineColor.rgb * land * 0.075 * landTone * night * (0.45 + 0.9 * keyL);
    // Own faint light of the form light: sea and land are too dark for a pure brightening
    // (surface * light) to show the curvature
    col += mix(bodyColor.rgb, lineColor.rgb, 0.5) * night * pow(keyL, 1.6) * 0.08;
    // Sheen of the form light on the sea (at night): wide and faint, shows the curvature
    vec3 keyH = normalize(key + eye);
    float keyGlint = pow(max(dot(n, keyH), 0.0), 10.0) * (1.0 - land) * night;
    col += mix(lineColor.rgb, accentColor.rgb, 0.4) * keyGlint * 0.13;
    // Twilight: narrow, warm stripe at the day-night border
    float dusk = exp(-pow(ndl / 0.13, 2.0));
    col += mix(accentColor.rgb, vec3(1.0, 0.72, 0.45), 0.4) * dusk * 0.05 * (0.4 + 0.6 * land);
    // Sun glint on the sea
    vec3 hv = normalize(sun + eyeE);
    float glint = pow(max(dot(g, hv), 0.0), 60.0) * (1.0 - land) * day;
    col += mix(lineColor.rgb, accentColor.rgb, 0.3) * glint * 0.35;

    // ---- Coast: only a touch of light at the edge of the land (no border lines) ----
    float coast = smoothstep(0.58, 0.84, tex.r);
    col += lineColor.rgb * coast * 0.07;

    // ---- Server countries, selection, active connection (before the clouds, so they drift over them) ----
    col += accentColor.rgb * 0.13 * srv * land;
    // Selection: the old country fades out, the new one in (selK)
    float selMix = sel * selK + selB * (1.0 - selK);
    col = mix(col, accentColor.rgb * mix(0.45, 0.7, day), 0.6 * selMix);
    col = mix(col, goodColor.rgb * mix(0.35, 0.55, day), 0.45 * act * (1.0 - selMix));
    // Fine glowing outline: exactly at the 50 % border, always ~1 screen pixel wide; both countries crossfaded
    float edgeA = 1.0 - smoothstep(0.0, max(fwidth(sel), 1e-4) * 1.2, abs(sel - 0.5));
    float edgeB = 1.0 - smoothstep(0.0, max(fwidth(selB), 1e-4) * 1.2, abs(selB - 0.5));
    col += accentColor.rgb * (edgeA * selK + edgeB * (1.0 - selK)) * 0.9;
    // Light wave: a wide, soft shimmer that runs from the server location over the country and
    // fades evenly meanwhile (deliberately subtle: no narrow bright ring, no afterglow)
    float ang = acos(clamp(dot(g, normalize(selPos.xyz)), -1.0, 1.0));
    float waveR = waveT * 0.24;
    float ringD = (ang - waveR) / 0.06;
    float fadeW = (1.0 - waveT) * (1.0 - waveT);
    float wave = exp(-ringD * ringD) * fadeW * sel * step(0.001, waveT);
    col += accentColor.rgb * wave * 0.22;

    // ---- Clouds: drift slowly east ----
    float ct = time * 0.006;
    vec3 cp = ge * 2.6 + vec3(ct, 0.0, -ct * 0.6);
    float cloud = smoothstep(0.52, 0.78, fbm(cp) + 0.12 * vn(ge * 11.0 + ct * 3.0));
    cloud *= 0.55 * smoothstep(0.98, 0.6, abs(g.y));
    col = mix(col, lineColor.rgb * (0.05 + 0.75 * lambert), cloud);

    // ---- City lights (night side), twinkle slightly, dimmed under clouds ----
    vec2 cell = floor(uv * vec2(720.0, 360.0));
    float phase = fract(sin(dot(cell, vec2(12.9898, 78.233))) * 43758.5453);
    float twinkle = 0.75 + 0.25 * sin(time * 1.6 + phase * 6.2832);
    float lights = tex.g * (1.0 - day) * twinkle * (1.0 - 0.7 * cloud);
    vec3 warm = mix(accentColor.rgb, vec3(1.0, 0.92, 0.78), 0.35);
    col += warm * lights * 1.1;

    // ---- Atmosphere inside: rim at the edge, mostly on the day side ----
    float rim = pow(1.0 - facing, 2.6);
    vec3 air = tintGrade(mix(accentColor.rgb, lineColor.rgb, 0.45), TINT_AIR);
    // Light side of the edge: the sun or (at night) the form light, so the rim never disappears completely
    vec2 np = p / max(r, 1e-5);
    float keySide = clamp(0.5 + 0.5 * dot(np, normalize(key.xy)), 0.0, 1.0);
    float airLit = max(smoothstep(-0.35, 0.45, ndl), 0.45 * keySide);
    col = mix(col, air * (0.25 + 0.9 * airLit), rim * (0.25 + 0.6 * airLit));
    // Edge darkening (the sphere looks round)
    col *= mix(0.65, 1.0, smoothstep(0.0, 0.5, facing));
    col = tintGrade(col, TINT_BODY);

    float inside = smoothstep(1.0 + px, 1.0 - px, r);

    // ---- Atmosphere outside: soft glow, stronger toward the sun side ----
    // Sun in the view coordinate system (inverse of the rotation above)
    vec3 sunV = vec3(sun.x, sun.y * c0 - sun.z * s0, sun.y * s0 + sun.z * c0);
    float side = clamp(0.2 + 0.9 * dot(np, sunV.xy) + 0.4 * sunV.z, 0.08, 1.0);
    // never fully gone: at least a calm glow toward the side of the form light
    side = max(side, 0.3 + 0.4 * keySide);
    float d = max(r - 1.0, 0.0);
    // To 0 before the edge of the (square) item, otherwise the glow draws an edge there
    float fadeOut = 1.0 - smoothstep(1.0 / disc - 0.2, 1.0 / disc - 0.02, r);
    float halo = (exp(-d * 9.0) * 0.55 + exp(-d * 3.2) * 0.12) * side * (1.0 - inside) * fadeOut;
    // fine bright edge exactly at the rim (atmosphere from the side)
    float edge = (1.0 - smoothstep(0.0, px * 1.8, abs(r - 1.0))) * (0.1 + 0.4 * side);

    vec3 rgb = col * inside + air * (halo + edge);
    float a = clamp(inside + (halo + edge) * 0.9, 0.0, 1.0);
    // Dithering (+-1 step on the color): otherwise the soft glow and dark sea showed rings (banding)
    vec2 fc = gl_FragCoord.xy;
    float nz = (fract(sin(dot(fc, vec2(12.9898, 78.233))) * 43758.5453) + fract(sin(dot(fc + 17.17, vec2(12.9898, 78.233))) * 43758.5453) - 1.0) / 255.0;
    rgb = max(rgb + vec3(nz) * step(0.002, a), vec3(0.0));
    // premultiplied: outside, rgb is already weighted with the opacity of the glow
    fragColor = vec4(rgb, a) * qt_Opacity;
}
