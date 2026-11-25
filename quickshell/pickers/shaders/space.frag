#version 440

// Space around the planet of the VPN picker (pickers/VpnGlobe.qml): thin, calm starry sky as in the
// Wi-Fi/Bluetooth picker (galaxy.frag: at most one star per grid cell, only the brightness twinkles)
// and a dark halo around the planet. Both fade out softly outward, so there is no hard edge to the
// dimmed desktop of the picker window. Dithering against rings in the flat, dark halo.
// Parallax (pan, mouse relative to the planet): the near star layer shifts fully, the far one at 45 %,
// planet and halo stay. Every star is integrated over the pixel area (like galaxy.frag), so it does not
// flicker at pixel edges when shifting.
// Recompile after changes:
//   /usr/lib/qt6/bin/qsb --glsl "300 es,150,330" -o space.frag.qsb space.frag

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    float time;
    float radius;    // Planetenradius in Pixeln
    vec2 size;       // item size in pixels
    vec2 center;     // Planetenmitte in Pixeln
    vec4 bg;         // color0
    vec4 vivid;      // strongest palette color
    vec4 starColor;  // color7
    vec2 pan;        // parallax offset of the near layer in pixels
};

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

// Gaussian star integrated over the pixel area, scaled like the point Gaussian (2 pi sig^2 = total light)
float starPx(vec2 d, float sig) {
    float k = 1.0 / (sig * 1.41421356);
    float ix = 0.5 * (erfA((d.x + 0.5) * k) - erfA((d.x - 0.5) * k));
    float iy = 0.5 * (erfA((d.y + 0.5) * k) - erfA((d.y - 0.5) * k));
    return ix * iy * 6.2831853 * sig * sig;
}

const float STAR_SCALE = 2.2;
const float STAR_CELL = 1.25;

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
            vec2 dd = px - sp;
            // Far away: contributes nothing, save the integration
            if (dot(dd, dd) > (3.0 * sig + 1.2) * (3.0 * sig + 1.2))
                continue;
            float b = pow(hash12(c * 2.11 + seed * 1.3), 2.0);
            float tw = 0.8 + 0.2 * sin(time * (0.3 + 0.6 * hash12(c * 5.3)) + h * 61.0);
            // Soft halo plus a small bright core (~0.7 px): big stars otherwise only look blurry
            float sc = max(0.7, sig * 0.35);
            v += (starPx(dd, sig) * 0.75 + starPx(dd, sc) * 0.6) * (0.25 + 0.75 * b) * tw;
        }
    }
    return v;
}

void main() {
    vec2 px = qt_TexCoord0 * size;
    float d = length(px - center) / radius;
    // Dark halo: makes the space around the planet deeper, fades out softly
    float hof = exp(-pow(max(d - 0.6, 0.0) / 1.25, 2.0)) * 0.55;
    // Stars only in the space around the planet, faded out toward the outside
    float mask = 1.0 - smoothstep(1.5, 2.7, d);
    // Stars 2.2 times as big as in the Wi-Fi/Bluetooth picker (sigma 0.6/0.8 px): the VPN window is more than
    // twice as big, stars of the same size looked tiny in it. Spacing only 1.25 times (with 1.6 there were
    // too few), a bit brighter, otherwise the softer stars look pale.
    float s = (stars(px, pan * 0.45, 34.0 * STAR_CELL, 0.22, 0.6 * STAR_SCALE, 7.0) * 0.45 + stars(px, pan, 90.0 * STAR_CELL, 0.4, 0.8 * STAR_SCALE, 13.0) * 0.7) * mask * 1.5;
    // Very faint shimmer in the accent color close to the planet
    float shimmer = exp(-pow(max(d - 1.0, 0.0) / 0.6, 2.0)) * 0.035;
    vec3 light = starColor.rgb * s + vivid.rgb * shimmer;
    float la = clamp(max(max(light.r, light.g), light.b), 0.0, 1.0);
    // premultiplied: dark halo below, light above
    vec3 rgb = bg.rgb * hof * (1.0 - la) + light;
    float a = clamp(hof + la * (1.0 - hof), 0.0, 1.0);
    // Fade out softly toward all edges of the item, otherwise a straight edge stays there
    float edgeD = min(min(px.x, px.y), min(size.x - px.x, size.y - px.y));
    float edge = smoothstep(0.0, 140.0, edgeD);
    // Dithering (+-1 step of noise) directly on the color: otherwise the flat, dark halo showed rings
    // (banding). Noise on the opacity did not help - a dark halo over a dark background hardly changes the
    // brightness that way.
    float nz = (hash12(gl_FragCoord.xy) + hash12(gl_FragCoord.xy + 17.17) - 1.0) / 255.0;
    a *= edge;
    rgb = max(rgb * edge + vec3(nz) * step(0.002, a), vec3(0.0));
    fragColor = vec4(rgb, a) * qt_Opacity;
}
