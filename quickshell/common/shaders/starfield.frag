#version 440

// Thin starry sky as an overlay (common/StarField.qml): draws ONLY the light of the stars
// (premultiplied, without its own background) and so can be put over any background - power menu,
// lock screen, workspace overview. Stars as in the background of the Wi-Fi/Bluetooth picker
// (pickers/shaders/galaxy.frag, there with a search beam and swirl): two layers with parallax (far: small,
// little offset; near: bigger, full offset). Every star is integrated over the pixel area (Gaussian
// via erf): when shifted by fractions of a pixel its light stays the same -> no flicker.
// Recompile after changes:
//   /usr/lib/qt6/bin/qsb --glsl "300 es,150,330" -o starfield.frag.qsb starfield.frag

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    float time;       // seconds, only for twinkling
    float strength;   // Overall brightness
    float twinkle;    // 0 = calm (e.g. lock screen: the handover must be pixel identical), 1 = quiet twinkling
    float cellScale;  // spacing/size of the stars (1 = as in the Bluetooth picker)
    float starSize;   // additionally only the size (1 = unchanged): few but bigger stars
    vec2 size;        // Size in pixels
    vec2 pan;         // parallax offset of the near layer in pixels (the far one proportionally)
    vec4 starColor;
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

// Gaussian star integrated over the pixel area (total light 2 pi sig^2 like a point Gaussian)
float starPx(vec2 d, float sig) {
    float k = 1.0 / (sig * 1.41421356);
    float ix = 0.5 * (erfA((d.x + 0.5) * k) - erfA((d.x - 0.5) * k));
    float iy = 0.5 * (erfA((d.y + 0.5) * k) - erfA((d.y - 0.5) * k));
    return ix * iy * 6.2831853 * sig * sig;
}

// One layer: density = share of cells with a star; neighbor cells included (soft edge)
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
            if (dot(dd, dd) > (3.0 * sig + 1.2) * (3.0 * sig + 1.2))
                continue;

            float b = pow(hash12(c * 2.11 + seed * 1.3), 2.0);
            float tw = mix(1.0, 0.85 + 0.15 * sin(time * (0.3 + 0.6 * hash12(c * 5.3)) + h * 61.0), twinkle);
            // Bigger stars (starSize > 1) get a small bright core, otherwise they only look blurry
            // (like the stars around the VPN globe, space.frag)
            float core = clamp(starSize - 1.0, 0.0, 1.0) * 0.55;
            v += (starPx(dd, sig) + core * starPx(dd, 0.55)) * (0.25 + 0.75 * b) * tw;
        }
    }
    return v;
}

void main() {
    vec2 px = qt_TexCoord0 * size;
    float cs = max(cellScale, 0.25);
    float sz = max(starSize, 0.25);
    float s = stars(px, pan * 0.45, 34.0 * cs, 0.22, 0.6 * sqrt(cs) * sz, 7.0) * 0.45
            + stars(px, pan, 90.0 * cs, 0.4, 0.8 * sqrt(cs) * sz, 13.0) * 0.7;
    float a = clamp(s * strength, 0.0, 1.0);
    // premultiplied: only light, the background stays below
    fragColor = vec4(starColor.rgb * a, a) * qt_Opacity;
}
