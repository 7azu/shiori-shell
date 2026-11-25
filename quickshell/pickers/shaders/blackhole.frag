#version 440

// Black hole in the middle of the Wi-Fi and Bluetooth pickers (the PC, pickers/parts/RadarPicker.qml).
// Ported from the Obsidian plugin "Galaxie" (vault-galaxy/src/shaders.js, BH_FRAG): per pixel a
// light ray is traced backwards through the Schwarzschild field (d2x/dl2 = -3/2 h^2 x / r^5, rs = 1). This
// creates the shadow, the photon ring and the image of the back of the disc bent over/under the shadow.
// The disc is thin glowing gas (Gaussian column perpendicular to the disc, integrated analytically with erf),
// with filaments and knots that rotate by Kepler, and Doppler beaming. Plasma and column integration after
// github.com/williamwasen/second-brain-black-hole (MIT).
// Gas, colors and tone mapping as in the plugin: filaments and knots from multi-layer noise, fixed warm colors
// (orange outside, cream white inside, only a touch of the pywal accent), ACES filmic like three.js.
// Unlike the plugin:
// - fixed camera just above the disc, image section view (half width in rs)
// - hover: orbit ring in the disc plane with a comet (lensed like the disc)
// - soft glow in the shader instead of a bloom pass
// - radio off: the disc stays, but cools down (desaturated, dark, without glow)
// - on/off: a bright front ignites the disc from the inside out (like the start in the plugin), when
//   turning off a faint ember front pulls back from the outside to the hole (ignite)
// Recompile after changes:
//   /usr/lib/qt6/bin/qsb --glsl "300 es,150,330" -o blackhole.frag.qsb blackhole.frag

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    float time;     // disc clock (seconds, runs faster on hover)
    float power;    // 0 = radio off (disc extinguished: gray, faint), 1 = disc active
    float glow;     // extra glow (connected, transmitting during the scan)
    float hover;    // 0..1, mouse over the PC
    float pulse;    // 0..1, slow breathing of the brightness (idle)
    float view;     // half the image width in rs
    float elev;     // view height above the disc (radians)
    vec4 nrm;       // normal of the disc (xyz, wobbles slightly)
    vec4 accent;    // pywal accent (only a touch, ACCENT_MIX)
    vec4 hot;       // color inside while extinguishing
    vec4 shade;     // color of the shadow
    float ignite;   // 0..1 position of the ignition/cooling front (on: 0 -> 1, from the inside out; off: 1 -> 0)
};

const float TAU = 6.28318530718;
const float RIN = 3.0;
const float ROUT = 12.0;
const float RBOUND = 14.0;
// Orbit ring on hover, just at the edge of the disc
const float RING = 12.4;
// Shadow: every ray with an impact parameter b < 3 sqrt(3)/2 rs is captured
const float B_CRIT = 2.598;
const float CAM_D = 40.0;
// Share of the pywal color in the disc (plugin: uAccentMix)
const float ACCENT_MIX = 0.05;

float hash31(vec3 p) {
    p = fract(p * vec3(0.1031, 0.1030, 0.0973));
    p += dot(p, p.yxz + 33.33);
    return fract((p.x + p.y) * p.z);
}

float vn(vec3 x) {
    vec3 i = floor(x);
    vec3 f = fract(x);
    f = f * f * (3.0 - 2.0 * f);
    float n000 = hash31(i);
    float n100 = hash31(i + vec3(1.0, 0.0, 0.0));
    float n010 = hash31(i + vec3(0.0, 1.0, 0.0));
    float n110 = hash31(i + vec3(1.0, 1.0, 0.0));
    float n001 = hash31(i + vec3(0.0, 0.0, 1.0));
    float n101 = hash31(i + vec3(1.0, 0.0, 1.0));
    float n011 = hash31(i + vec3(0.0, 1.0, 1.0));
    float n111 = hash31(i + vec3(1.0, 1.0, 1.0));
    return mix(mix(mix(n000, n100, f.x), mix(n010, n110, f.x), f.y), mix(mix(n001, n101, f.x), mix(n011, n111, f.x), f.y), f.z);
}

float fbm3(vec3 p) {
    return 0.56 * vn(p) + 0.28 * vn(p * 2.03 + 7.1) + 0.16 * vn(p * 4.07 - 3.8);
}

float erfA(float x) {
    float a = abs(x), t = 1.0 / (1.0 + 0.3275911 * a);
    float poly = (((((1.061405429 * t - 1.453152027) * t) + 1.421413741) * t - 0.284496736) * t + 0.254829592) * t;
    return sign(x) * (1.0 - poly * exp(-a * a));
}

// Glowing gas at point p. dir = direction of travel of the (backward traced) ray. As in the plugin (BH_FRAG).
// ring = 1: light that already went through the disc once (photon ring, see trace): without filaments/knots
vec3 plasma(vec3 p, vec3 dir, vec3 N, float ring, out float dens) {
    vec3 bx = normalize(vec3(N.y, -N.x, 0.0));
    vec3 by = normalize(cross(N, bx));
    float x = dot(p, bx), y = dot(p, by), r = length(vec2(x, y));
    float win = smoothstep(RIN * 0.95, RIN * 1.17, r) * (1.0 - smoothstep(ROUT * 0.71, ROUT * 1.07, r));
    if (win < 0.0001) {
        dens = 0.0;
        return vec3(0.0);
    }
    // Ignition/cooling front: inside it the gas burns (lp = 1), outside it is extinguished. During the
    // change the front lights up (trans = 0 at both ends).
    float front = mix(RIN * 0.8, ROUT * 1.25, ignite);
    float lp = smoothstep(front, front - 2.2, r);
    float trans = 4.0 * ignite * (1.0 - ignite);
    // Igniting (power already close to 1) brighter than cooling (power already close to 0): only a faint ember
    float flare = 1.0 + mix(0.5, 1.6, power) * exp(-pow((r - front + 1.1) / 1.3, 2.0)) * trans;
    float a = atan(y, x);
    // Differential rotation: one orbit in ~20 s inside, clearly slower outside
    float omega = 0.31 * pow(3.4 / r, 1.5);
    float ph = a - time * omega;
    float drift = r + time * 0.018;
    vec3 q = vec3(cos(ph), sin(ph), drift * 0.30);
    float flow = fbm3(q * vec3(4.0, 4.0, 5.0) + vec3(0.0, 0.0, time * 0.065));
    // In the picker the hole is only ~250 px wide: gas coarser and softer than in the plugin (there frequency 13/5,
    // filaments to the power of 3, base brightness 0.10), otherwise it falls apart into grains and dark gaps
    float detail = fbm3(vec3(cos(ph) * 6.0, sin(ph) * 6.0, drift * 1.6) + flow * 2.0 + time * 0.038);
    float fil = fbm3(vec3(cos(ph) * 3.0, sin(ph) * 3.0, drift * 2.2) + vec3(flow * 1.6, flow * 1.6, flow * 3.0));
    // In the photon ring (ring = 1) average values instead of filaments and knots: there the whole disc is
    // squashed into a hair-thin ring, bright and dark filaments became a dashed line
    float lanes = mix(smoothstep(0.22, 0.85, fil), 0.45, ring);
    float knots = mix(smoothstep(0.30, 0.90, detail), 0.35, ring);
    float energy = (0.55 + lanes * 1.5 + knots * 1.1) * (0.45 + 0.9 * mix(flow, 0.5, ring));
    energy *= 0.55 + 1.0 * mix(vn(vec3(cos(ph) * 2.2, sin(ph) * 2.2, time * 0.13)), 0.5, ring);
    float falloff = pow(3.8 / r, 3.0);
    dens = win * (0.22 + energy * 0.55);
    // Kepler speed, Doppler: the approaching side is brighter and whiter
    vec3 vel = normalize(cross(N, p)) * sqrt(0.5 / max(r - 1.0, 1.0));
    float dop = clamp(1.0 / (1.0 + dot(vel, dir)), 0.65, 1.65);
    float heat = clamp(0.85 - (r - 3.0) * 0.075 + knots * 0.25, 0.0, 1.0);
    vec3 tint = mix(vec3(1.0, 0.27, 0.055), vec3(1.0, 0.80, 0.49), heat);
    tint = mix(tint, vec3(1.0, 0.95, 0.82), smoothstep(0.72, 1.0, heat) * 0.62);
    tint = mix(tint, tint * accent.rgb / max(max(accent.r, accent.g), max(accent.b, 0.001)), ACCENT_MIX);
    // Extinguished: gray with a touch of the inner color
    vec3 cold = vec3(dot(tint, vec3(0.3, 0.55, 0.15))) * mix(vec3(1.0), hot.rgb, 0.35);
    cold = mix(cold, cold * vec3(1.0, 0.82, 0.68), 0.5);   // a rest of ember
    tint = mix(cold, tint, lp);
    // Extinguished: hardly any beaming, otherwise only the approaching side would stay visible as a bright stripe
    return tint * (3.8 * falloff * energy * win * pow(dop, mix(0.4, 2.3, lp)) * flare * mix(0.42, 0.92 + 0.16 * pulse, lp));
}

// Trace a light ray and collect the luminosity along its path.
vec3 trace(vec3 ro, vec3 rd, vec3 N) {
    float R = RBOUND;
    // Outside the bounding sphere straight to the sphere (there the deflection is small)
    float bq = dot(ro, rd);
    float c = dot(ro, ro) - R * R;
    if (c > 0.0) {
        float disc = bq * bq - c;
        if (disc <= 0.0 || bq > 0.0)
            return vec3(0.0);

        ro += rd * (-bq - sqrt(disc));
    }
    vec3 p = ro;
    vec3 v = rd;
    vec3 hv = cross(p, v);
    float h2 = dot(hv, hv);
    vec3 col = vec3(0.0);
    float T = 1.0;
    // How often the ray has already crossed the disc plane: from the second time on it is the photon ring
    float crossings = 0.0;
    vec3 bx = normalize(vec3(N.y, -N.x, 0.0));
    vec3 by = normalize(cross(N, bx));
    for (int i = 0; i < 300; i++) {
        float r = length(p);
        // Compute finer near the photon sphere (r = 1.5): there rays circle the hole several times
        float dt = r < 3.0 ? max(0.022 * r, 0.012) : 0.055 * r;
        float r5 = r * r * r * r * r;
        vec3 acc = -1.5 * h2 * p / r5;
        vec3 pn = p + v * dt + 0.5 * acc * dt * dt;
        float rn = length(pn);
        float rn5 = rn * rn * rn * rn * rn;
        vec3 accn = -1.5 * h2 * pn / rn5;
        vec3 vn1 = v + 0.5 * (acc + accn) * dt;
        float h0 = dot(p, N), h1 = dot(pn, N);
        float dh = h0 - h1;
        float across = clamp(h0 / (abs(dh) < 1e-5 ? 1e-5 : dh), 0.0, 1.0);
        vec3 sp = mix(p, pn, across);
        float dR = length(sp - N * dot(sp, N));
        float th = 0.075 + 0.009 * dR;
        if ((min(abs(h0), abs(h1)) < th * 3.0 || h0 * h1 < 0.0) && dR < ROUT * 1.1) {
            float dens;
            vec3 L = plasma(sp, normalize(v), N, step(0.5, crossings), dens);
            float seg = length(pn - p);
            float adh = abs(dh);
            float midHeight = (h0 + h1) * 0.5 / th;
            float column = adh > 1e-4 ? abs(erfA(h1 / th) - erfA(h0 / th)) * 0.8862269 * seg / adh : exp(-midHeight * midHeight) * seg / th;
            float optical = column * 0.22;
            col += T * L * optical;
            T *= exp(-dens * optical * 0.65);
        }
        if (h0 * h1 < 0.0)
            crossings += 1.0;
        // Orbit ring (hover): only when piercing the plane, so its lensed image appears too
        if (hover > 0.001 && h0 * h1 < 0.0) {
            float orbitDist = (dR - RING) / 0.17;
            float line = exp(-orbitDist * orbitDist);
            if (line > 0.001) {
                float a = atan(dot(sp, by), dot(sp, bx));
                float cometA = time * 0.45;
                float behind = mod(cometA - a, TAU);
                float comet = exp(-behind * 2.0) + 1.8 * exp(-min(behind, TAU - behind) * 16.0);
                col += T * vec3(1.0, 0.78, 0.52) * line * (0.12 + comet) * hover * 2.2 * mix(0.42, 0.92 + 0.16 * pulse, power);
            }
        }
        p = pn;
        v = vn1;
        if (rn < 1.0)
            break;

        if (rn > R * 1.01 && dot(p, v) > 0.0)
            break;

        if (T < 0.004)
            break;

    }
    return col;
}

// ACES filmic like three.js (ACESFilmicToneMapping): bright gas runs out to cream white
vec3 RRTAndODTFit(vec3 v) {
    vec3 a = v * (v + 0.0245786) - 0.000090537;
    vec3 b = v * (0.983729 * v + 0.4329510) + 0.238081;
    return a / b;
}

vec3 toneMap(vec3 color) {
    const mat3 ACESInputMat = mat3(vec3(0.59719, 0.07600, 0.02840), vec3(0.35458, 0.90834, 0.13383), vec3(0.04823, 0.01566, 0.83777));
    const mat3 ACESOutputMat = mat3(vec3(1.60475, -0.10208, -0.00327), vec3(-0.53108, 1.10813, -0.07276), vec3(-0.07367, -0.00605, 1.07602));
    color *= 1.05 / 0.6;   // exposure as in the plugin (toneMappingExposure 1.05)
    color = ACESInputMat * color;
    color = RRTAndODTFit(color);
    color = ACESOutputMat * color;
    return clamp(color, 0.0, 1.0);
}

void main() {
    vec3 N = normalize(nrm.xyz);
    // Fixed camera just above the disc, looking at the middle
    vec3 cam = vec3(0.0, sin(elev), cos(elev)) * CAM_D;
    vec3 f = normalize(-cam);
    vec3 rgt = normalize(cross(f, vec3(0.0, 1.0, 0.0)));
    vec3 up = cross(rgt, f);
    vec2 uv = qt_TexCoord0 * 2.0 - 1.0;
    uv.y = -uv.y;
    vec3 rd = normalize(rgt * uv.x * view + up * uv.y * view - cam);
    // Derivatives first (uniform control flow)
    vec3 dx = dFdx(rd);
    vec3 dy = dFdy(rd);
    float b0 = length(cross(cam, rd));
    float fw = max(fwidth(b0), 1e-5);
    float shadow = 1.0 - smoothstep(B_CRIT - fw * 0.6, B_CRIT + fw * 0.6, b0);

    // Average several rays per pixel: 4 directly at the photon ring (images thinner than a pixel, points
    // on a spiral), otherwise 2 (diagonally offset) - with only one the gas filaments were jagged and
    // grainy. Deep in the shadow one is enough (everything is black there). More rays at the ring (16) did
    // nothing against its gaps (they came from scaling down, see textureSize in RadarPicker), but cost
    // a lot: exactly these rays circle the hole the longest.
    float near = abs(b0 - B_CRIT);
    int n = near < max(0.12, 3.0 * fw) ? 4 : (b0 < B_CRIT - 4.0 * fw ? 1 : 2);
    vec3 light = vec3(0.0);
    for (int k = 0; k < 4; k++) {
        if (k >= n)
            break;

        float sa = float(k) * 2.39996 + 0.3;
        vec2 o = n == 4 ? vec2(cos(sa), sin(sa)) * 0.35 : (n == 2 ? vec2(0.25, -0.25) * (float(k) * 2.0 - 1.0) : vec2(0.0));
        vec3 dir = normalize(rd + dx * o.x + dy * o.y);
        light += trace(cam, dir, N);
    }

    // Extinguished, the disc only glows faintly
    // Base brightness as in the plugin (uBright 0.42)
    // (the on/off share is in the gas per radius, see ignite in plasma())
    float exposure = 0.42 * (1.0 + 0.25 * hover + 0.28 * glow);
    light *= exposure / float(n);

    // The glow is wider along the tilted disc plane and stronger toward the bright side.
    vec2 screen = uv * view;
    float diskHeight = dot(N, rgt * screen.x + up * screen.y) / 1.8;
    float halo = exp(-max(b0 - B_CRIT, 0.0) * 0.62) * (0.022 + 0.035 * glow + 0.02 * hover);
    float band = exp(-diskHeight * diskHeight - abs(screen.x) * 0.21) * (0.062 - 0.038 * uv.x);
    float edge = 1.0 - smoothstep(0.75, 1.0, length(uv));
    // warm glow like the glow sprite in the plugin
    light += vec3(0.95, 0.62, 0.32) * (halo + band) * edge * (1.0 - shadow) * mix(0.15, 1.0, power);

    // Light above the deep shadow can come from the front of the disc.
    vec3 emission = toneMap(light);
    float alpha = max(max(emission.r, emission.g), emission.b);
    vec3 color = emission + shade.rgb * shadow * (1.0 - alpha);
    vec4 litHole = vec4(color, alpha + shadow * (1.0 - alpha));
    fragColor = litHole * qt_Opacity;
}
