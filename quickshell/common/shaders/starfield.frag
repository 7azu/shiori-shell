#version 440

// Thin starry sky as an overlay (common/StarField.qml): draws ONLY the light of the stars
// (premultiplied, without its own background) and so can be put over any background - power menu,
// lock screen, workspace overview. Stars as in the background of the Wi-Fi/Bluetooth picker
// (pickers/shaders/galaxy.frag, there with a search beam and swirl): two layers with parallax (far: small,
// little offset; near: bigger, full offset). Every star is integrated over the pixel area (Gaussian
// via erf): when shifted by fractions of a pixel its light stays the same -> no flicker.
// particles = 1: no fixed sky any more, every star is a particle with its own slow path (direction and
// speed scattered around `flow`, a soft sideways sway) that fades in, flies for one life and fades out.
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
    float density;    // share of the stars that is drawn (1 = all)
    float particles;  // 0 = fixed sky, 1 = every star flies on its own (see above)
    vec2 size;        // Size in pixels
    vec2 pan;         // parallax offset of the near layer in pixels (the far one proportionally)
    vec2 flow;        // particles: mean flight of the near layer in pixels per second
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

// One layer: dens = share of cells with a star; neighbor cells included (soft edge).
// depth = speed of the layer in particle mode (far layer slower -> depth)
float stars(vec2 screen, vec2 off, float cell, float dens, float sig, float seed, float depth) {
    vec2 px = screen - off;
    vec2 g = floor(px / cell);
    float v = 0.0;
    for (int j = -1; j <= 1; j++) {
        for (int i = -1; i <= 1; i++) {
            vec2 c = g + vec2(float(i), float(j));
            // Key of the star. Fixed sky: the cell. Particles: a new one per life, so that the next
            // particle of the cell appears at another place, with another path and brightness
            vec2 k = c;
            float u = 0.0, life = 1.0, env = 1.0;
            if (particles > 0.5) {
                life = mix(26.0, 44.0, hash12(c * 3.71 + seed));
                float ph = time / life + hash12(c * 4.37 + seed * 0.7);
                float n = floor(ph);
                u = ph - n;
                k = c + mod(n, 97.0) * vec2(17.0, 31.0);
                // long soft fade in and out; at the change of lives the light is 0 -> nothing pops
                env = smoothstep(0.0, 0.3, u) * (1.0 - smoothstep(0.7, 1.0, u));
            }
            float h = hash12(k + seed);
            if (h > dens)
                continue;

            vec2 sp = (c + 0.15 + 0.7 * hash22(k * 1.37 + seed)) * cell;
            if (particles > 0.5) {
                // Own direction (+-43 degrees around the flow) and speed; the whole way of one life stays
                // below 1.5 cells, otherwise the star would leave the 3x3 cells that are searched
                vec2 r = hash22(k * 2.63 + seed * 1.9);
                float ang = (r.x - 0.5) * 1.5;
                float ca = cos(ang), sa = sin(ang);
                vec2 way = vec2(flow.x * ca - flow.y * sa, flow.x * sa + flow.y * ca) * depth * (0.55 + 0.9 * r.y) * life;
                float len = length(way);
                vec2 dir = len > 0.001 ? way / len : vec2(0.0, -1.0);
                way = dir * min(len, 1.5 * cell);
                float sway = sin(6.2831853 * (u * (0.5 + 0.7 * hash12(k * 7.1 + seed)) + h * 9.0)) * 0.05 * cell;
                sp += way * (u - 0.5) + vec2(-dir.y, dir.x) * sway;
            }
            vec2 dd = px - sp;
            if (dot(dd, dd) > (3.0 * sig + 1.2) * (3.0 * sig + 1.2))
                continue;

            float b = pow(hash12(k * 2.11 + seed * 1.3), 2.0);
            float tw = mix(1.0, 0.85 + 0.15 * sin(time * (0.3 + 0.6 * hash12(k * 5.3)) + h * 61.0), twinkle);
            // Bigger stars (starSize > 1) get a small bright core, otherwise they only look blurry
            // (like the stars around the VPN globe, space.frag)
            float core = clamp(starSize - 1.0, 0.0, 1.0) * 0.55;
            v += (starPx(dd, sig) + core * starPx(dd, 0.55)) * (0.25 + 0.75 * b) * tw * env;
        }
    }
    return v;
}

void main() {
    vec2 px = qt_TexCoord0 * size;
    float cs = max(cellScale, 0.25);
    float sz = max(starSize, 0.25);
    float s = stars(px, pan * 0.45, 34.0 * cs, 0.22 * density, 0.6 * sqrt(cs) * sz, 7.0, 0.45) * 0.45
            + stars(px, pan, 90.0 * cs, 0.4 * density, 0.8 * sqrt(cs) * sz, 13.0, 1.0) * 0.7;
    float a = clamp(s * strength, 0.0, 1.0);
    // premultiplied: only light, the background stays below
    fragColor = vec4(starColor.rgb * a, a) * qt_Opacity;
}
