#version 440

// Connection device -> black hole in the Wi-Fi/Bluetooth picker (pickers/parts/RadarLink.qml):
// a glowing gas stream on a direct path from the device into the hole, on it an animated sine wave
// (amp, wavelen, wphase) whose crests travel into the hole with the gas; flat at both ends.
// Toward the hole it gets thinner, brighter and hotter (accent -> hot) and disappears under the shadow.
// When connected, bright light bursts run along; while connecting a glowing head feels its way forward (reach).
// Recompile after changes:
//   /usr/lib/qt6/bin/qsb --glsl "300 es,150,330" -o stream.frag.qsb stream.frag

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec2 origin;     // top left corner of the item in the picker
    vec2 boxSize;    // size of the item
    vec2 center;     // middle of the hole
    float r0;        // distance at the device end
    float rIn;       // distance at the hole end (under the shadow)
    float theta0;    // angle to the device (screen, y down)
    float holeFade;  // fully visible from this u on (before that the stream fades out toward the hole)
    float reach;     // 0..1: how far the stream reaches from the device
    float strength;  // 0.5 connecting, 1 connected
    float flash;     // 1 -> 0 after connecting
    float live;      // 0..1 bright knots (connected)
    float time;      // Fliess-Uhr
    float len;       // approximate length in px
    float amp;       // amplitude of the wave in px
    float wavelen;   // wavelength in px
    float wphase;    // phase of the wave (counts up -> crests travel to the hole)
    vec4 accent;
    vec4 hot;
};

// More segments than without a wave, otherwise the crests get angular
const int N = 64;

// Base line: straight from the hole (u = 0) to the device (u = 1)
vec2 pathPt(float u) {
    return center + vec2(cos(theta0), sin(theta0)) * (rIn + (r0 - rIn) * u);
}

// Point on the wave: base line + amplitude perpendicular to it
vec2 wavePt(float u) {
    vec2 c = pathPt(u);
    vec2 nrm = vec2(-sin(theta0), cos(theta0));
    // flat at both ends (smoothstep on the first/last 12 %)
    float env = clamp(min(u, 1.0 - u) / 0.12, 0.0, 1.0);
    env = env * env * (3.0 - 2.0 * env);
    float off = sin(u * len / wavelen * 6.2832 + wphase) * amp * env;
    return c + nrm * off;
}

float hash(vec2 p) {
    p = fract(p * vec2(0.1031, 0.1030));
    p += dot(p, p.yx + 33.33);
    return fract((p.x + p.y) * p.x);
}

float vnoise(vec2 x) {
    vec2 i = floor(x), f = fract(x);
    f = f * f * (3.0 - 2.0 * f);
    return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}

float fbm(vec2 p) {
    return 0.55 * vnoise(p) + 0.3 * vnoise(p * 2.1 + 7.3) + 0.15 * vnoise(p * 4.3 - 2.1);
}

void main() {
    vec2 p = origin + qt_TexCoord0 * boxSize;
    // Nearest point on the curve (distance to 40 segments) and its position u
    float best = 1e5;
    float bu = 0.0;
    vec2 prev = wavePt(0.0);
    for (int i = 1; i <= N; i++) {
        vec2 cur = wavePt(float(i) / float(N));
        vec2 ba = cur - prev;
        float h = clamp(dot(p - prev, ba) / max(dot(ba, ba), 1e-4), 0.0, 1.0);
        float d = length(p - prev - ba * h);
        if (d < best) {
            best = d;
            bu = (float(i - 1) + h) / float(N);
        }
        prev = cur;
    }
    if (best > 24.0) {
        fragColor = vec4(0.0);
        return;
    }
    float u = bu;
    // Visible: disappears under the shadow at the hole, soft at the device, only the reached part
    float front = 1.0 - reach;
    float vis = smoothstep(0.0, holeFade, u) * (1.0 - smoothstep(0.93, 1.0, u)) * smoothstep(front - 0.05, front + 0.01, u);
    // Plasma that flows in: the same phase travels to smaller u over time
    float along = u * len;
    float s = along / 14.0 + time;
    float n = fbm(vec2(s, best * 0.18));
    float n2 = vnoise(vec2(along / 9.0 + time * 1.4, 3.7));
    // Width: diffuse at the device, thin toward the hole (stretched); varies with the plasma (gassy instead of a noodle)
    // Noise only in the core: in the wide glow a pixel is often almost equally far from two places of the
    // wave -> u jumps there, and noise-dependent values drew visible seams (fans)
    float w0 = mix(0.75, 2.1, u);
    float w = w0 * (0.7 + 0.6 * n2);
    float core = exp(-(best * best) / (w * w));
    float glow = exp(-(best * best) / (28.0 * w0 * w0)) * 0.22;
    float body = core * (0.25 + 1.1 * n * n) + glow * 0.65;
    // Bright knots (connected): round, soft light bursts every 46 px that travel in
    float kp = along / 46.0 + time * 0.55;
    float ka = (fract(kp) - 0.5) * 46.0;
    // Every burst its own brightness (hash of the burst number), otherwise it looks like a string of pearls
    float kv = 0.35 + 0.65 * hash(vec2(floor(kp), 5.1));
    float knot = exp(-(ka * ka + best * best) / 14.0) * live * kv;
    float knotGlow = exp(-(ka * ka + best * best) / 40.0) * live * 0.3 * kv;
    float intensity = (body + 1.4 * knot + knotGlow) * vis * (0.15 + 0.85 * strength) * (1.0 + 1.3 * flash) * (0.65 + 0.7 * (1.0 - u));
    float kn = knot;
    // Head while connecting: glows at the front of the stream
    float hd = (u - front) * len / 7.0;
    intensity += exp(-hd * hd) * exp(-(best * best) / 18.0) * (1.0 - live) * step(0.002, reach) * 0.9 * smoothstep(0.0, holeFade, u);
    // Color: accent outside (normalized to full brightness as in blackhole.frag), hot toward the hole
    vec3 outer = accent.rgb / max(max(accent.r, accent.g), max(accent.b, 0.001));
    vec3 tint = mix(outer, hot.rgb, clamp(0.15 + 0.8 * pow(1.0 - u, 2.0) + 0.5 * kn, 0.0, 1.0));
    vec3 light = tint * intensity * 1.3;
    float peak = max(max(light.r, light.g), light.b);
    light *= (1.0 - exp(-peak)) / max(peak, 1e-5);
    float alpha = max(max(light.r, light.g), light.b);
    fragColor = vec4(light, alpha) * qt_Opacity;
}
