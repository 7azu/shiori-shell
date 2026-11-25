#version 440

// Background of the Wi-Fi and Bluetooth pickers (pickers/parts/RadarPicker.qml), deliberately plain: flat background
// (color0 like the other pickers), a thin, calm starry sky, a very faint glow around the PC and
// a subtle swirl of star dust (two soft spiral arms, turns barely noticeably).
// Parallax: the mouse (pan, from the pan of the black hole) shifts the layers by different amounts - far stars
// little, near ones more, the swirl (at the height of the hole) hardly. So stars do not flicker at pixel edges
// when shifting, each one is integrated over the area of the pixel (Gaussian via erf): its brightness stays the same
// no matter where it stands between two pixels. Size and place of the stars never change otherwise.
// Search (scan mode): a soft fan of light turns from the PC; stars it brushes light up and
// fade afterwards (like phosphor). Same angle as the finds in the radar (RadarNode.behind).
// Fills the whole panel, the shader computes the round corners itself.
// Recompile after changes:
//   /usr/lib/qt6/bin/qsb --glsl "300 es,150,330" -o galaxy.frag.qsb galaxy.frag

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    float time;      // seconds, only for sparkling
    float scan;      // 0 = tracks, 1 = radar
    float power;     // 0 = radio off, 1 = on
    float cornerR;   // corner radius of the panel in pixels
    float alpha;     // opacity of the background
    vec2 size;       // panel size in pixels
    vec2 center;     // middle (PC) in pixels
    vec2 orbit;      // semi-axes of the outer track in pixels
    vec4 bg;         // color0
    vec4 vivid;      // strongest palette color
    vec4 starColor;  // color7
    float sweep;     // angle of the search beam (radians, clockwise)
    float sweepOn;   // 0..1, beam visible
    vec2 scanAxes;   // semi-axes of the radar ellipse in pixels
    vec2 pan;        // parallax offset of the nearest layer in pixels (the others proportionally)
};

const float TAU = 6.28318530718;

// Distance to the middle, normalized to the radar ellipse (1 = outer ring)
float ellR(vec2 p) {
    vec2 d = p - center;
    d.y *= scanAxes.x / max(scanAxes.y, 1.0);
    return length(d) / max(scanAxes.x, 1.0);
}

// How far behind the beam does p lie (radians, 0 = just brushed)? Angle in the unsquashed ellipse,
// exactly like RadarNode.behind, so stars and finds light up at the same time.
float behindBeam(vec2 p) {
    vec2 d = p - center;
    float a = atan(d.y * scanAxes.x / max(scanAxes.y, 1.0), d.x);
    return mod(sweep - a, TAU);
}

float hash12(vec2 p) {
    vec3 p3 = fract(vec3(p.xyx) * 0.1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

vec2 hash22(vec2 p) {
    vec3 p3 = fract(vec3(p.xyx) * vec3(0.1031, 0.1030, 0.0973));
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.xx + p3.yz) * p3.zy);
}

float erfA(float x) {
    float a = abs(x), t = 1.0 / (1.0 + 0.3275911 * a);
    float poly = (((((1.061405429 * t - 1.453152027) * t) + 1.421413741) * t - 0.284496736) * t + 0.254829592) * t;
    return sign(x) * (1.0 - poly * exp(-a * a));
}

// Gaussian star (distance d, width sig) integrated over the pixel area, scaled so it looks like the old
// point Gaussian (factor 2 pi sig^2 = total light). Shifted by fractions of a pixel the light stays
// the same, it is only spread differently over the neighboring pixels -> no flicker with the parallax.
float starPx(vec2 d, float sig) {
    float k = 1.0 / (sig * 1.41421356);
    float ix = 0.5 * (erfA((d.x + 0.5) * k) - erfA((d.x - 0.5) * k));
    float iy = 0.5 * (erfA((d.y + 0.5) * k) - erfA((d.y - 0.5) * k));
    return ix * iy * 6.2831853 * sig * sig;
}

// One layer of stars: density = share of cells with a star. Neighbor cells are included, so the soft
// edge of a star does not break off at the cell border. off = parallax offset of this layer in pixels.
float stars(vec2 screen, vec2 off, float cell, float density, float sig, float seed) {
    vec2 px = screen - off;
    vec2 g = floor(px / cell);
    float v = 0.0;
    for (int j = -1; j <= 1; j++) {
        for (int i = -1; i <= 1; i++) {
            vec2 c = g + vec2(float(i), float(j));
            float h = hash12(c + seed);
            if (h > density)
                continue;

            vec2 sp = (c + 0.15 + 0.7 * hash22(c * 1.37 + seed)) * cell;
            // Far away (more than ~3 sig + 1 px): contributes nothing, save the expensive integration
            vec2 dd = px - sp;
            if (dot(dd, dd) > (3.0 * sig + 1.2) * (3.0 * sig + 1.2))
                continue;

            float b = pow(hash12(c * 2.11 + seed * 1.3), 2.0);
            // Slow, faint twinkling (brightness only)
            float tw = 0.85 + 0.15 * sin(time * (0.3 + 0.6 * hash12(c * 5.3)) + h * 61.0);
            // Brushed by the beam: briefly bright, then fading slowly (only inside the radar; position on
            // the screen, so with offset)
            float lit = sweepOn * exp(-behindBeam(sp + off) * 1.4) * (1.0 - smoothstep(0.98, 1.08, ellR(sp + off)));
            v += starPx(dd, sig) * (0.25 + 0.75 * b) * (tw + 2.6 * lit);
        }
    }
    return v;
}

float vn2(vec2 x) {
    vec2 i = floor(x);
    vec2 f = fract(x);
    f = f * f * (3.0 - 2.0 * f);
    float a = hash12(i), b = hash12(i + vec2(1.0, 0.0)), c = hash12(i + vec2(0.0, 1.0)), d = hash12(i + vec2(1.0, 1.0));
    return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

float fbm2(vec2 p) {
    return 0.55 * vn2(p) + 0.3 * vn2(p * 2.07 + 5.3) + 0.15 * vn2(p * 4.13 - 2.9);
}

// Swirl of star dust around the PC: q = position relative to the middle, squashed like the tracks, 1 = outer track.
// Two logarithmic spiral arms, broken into fibers with noise (the noise rotates along, so the
// fibers look pulled into the swirl). Free inside (the hole is there), it fades out softly outside.
float swirl(vec2 q) {
    float r = length(q);
    float a = atan(q.y, q.x);
    // ~ one turn in 7 minutes: you do not see it turn, only that it lives
    float spin = time * 0.015;
    float arm = 0.5 + 0.5 * cos(2.0 * (a - spin) + log(max(r, 0.02)) * 4.2);
    arm = pow(arm, 2.6);
    // Noise in the co-rotating space: fibers along the arms
    float tw = a - spin + log(max(r, 0.02)) * 2.1;
    vec2 sw = vec2(cos(tw), sin(tw)) * r * 3.2;
    float dust = fbm2(sw * 2.4 + 11.0);
    float env = smoothstep(0.1, 0.38, r) * (1.0 - smoothstep(0.55, 1.35, r));
    return env * (0.35 + 0.65 * arm) * smoothstep(0.32, 0.85, dust) * mix(0.5, 1.0, arm);
}

float roundBox(vec2 p, vec2 hs, float r) {
    vec2 q = abs(p) - hs + r;
    return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - r;
}

void main() {
    vec2 px = qt_TexCoord0 * size;
    vec3 col = bg.rgb;

    // Very faint glow around the PC (squashed like the tracks), even fainter in scan mode
    vec2 q = px - center;
    q.y *= orbit.x / max(orbit.y, 1.0);
    float r = length(q) / max(orbit.x, 1.0);
    col += vivid.rgb * exp(-r * r / 0.22) * 0.045 * mix(1.0, 0.5, scan) * mix(0.3, 1.0, power);

    // Swirl: hardly any parallax (it lies at the height of the hole), very faint, warm-neutral like the stars with
    // a touch of accent; plus fine dust of tiny stars, only in the arms
    vec2 sq = px - center - pan * 0.2;
    sq.y *= orbit.x / max(orbit.y, 1.0);
    sq /= max(orbit.x, 1.0);
    // Do not even compute outside the swirl (r > 1.4)
    float sw = dot(sq, sq) < 1.96 ? swirl(sq) : 0.0;
    col += mix(starColor.rgb, vivid.rgb, 0.3) * sw * 0.11 * mix(0.35, 1.0, power) * mix(1.0, 0.6, scan);
    if (sw > 0.05) {
        float dustStars = stars(px, pan * 0.2, 11.0, 0.55, 0.55, 29.0) * smoothstep(0.05, 0.35, sw);
        col += starColor.rgb * dustStars * 0.45 * mix(0.5, 1.0, power);
    }

    // Thin starry sky: two layers with parallax (far: small, little offset; near: bigger, full offset)
    float s = stars(px, pan * 0.45, 34.0, 0.22, 0.6, 7.0) * 0.45 + stars(px, pan, 90.0, 0.4, 0.8, 13.0) * 0.7;
    col += starColor.rgb * s * mix(0.6, 1.0, power);

    // Search beam: soft fan behind the edge, the edge itself a fine line of light.
    // Hidden inside (at the hole) and at the edge of the radar.
    if (sweepOn > 0.001) {
        float rn = ellR(px);
        float bb = behindBeam(px);
        float mask = (1.0 - smoothstep(0.96, 1.02, rn)) * smoothstep(0.1, 0.32, rn);
        float trail = exp(-bb * 2.2) * 0.075 * mix(1.0, 0.6, rn);
        float edge = exp(-min(bb, TAU - bb) * 70.0) * 0.07;
        col += mix(vivid.rgb, starColor.rgb, 0.35) * (trail + edge) * mask * sweepOn;
    }

    float dBox = roundBox(px - size * 0.5, size * 0.5, cornerR);
    float a = clamp(0.5 - dBox, 0.0, 1.0) * alpha;
    fragColor = vec4(col * a, a) * qt_Opacity;
}
