#version 440

// Ink shape as a mask for content that should stay live (windows/AnimatedWallpaper.qml):
//   invert = 0: only visible inside the shape  (the new video spreads over the old one)
//   invert = 1: transparent inside the shape   (the old video reveals the new scene underneath)
// Shape, edge and shimmer must match inkbloom.frag (same field() function).
// Recompile after changes:
//   /usr/lib/qt6/bin/qsb --glsl "300 es,150,330" -o inkmask.frag.qsb inkmask.frag

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    float cover;      // 0..1 ink front
    float invert;     // 0 = visible inside, 1 = transparent inside
    float maxR;       // distance to the farthest desktop corner (px)
    float time;       // seconds, for the flowing edge
    vec2 origin;      // start point relative to this monitor (px)
    vec2 size;        // monitor size (px)
    vec4 glowColor;   // shimmer at the edge (accent color)
};

layout(binding = 1) uniform sampler2D source;

float hash(vec2 p) {
    p = fract(p * vec2(123.34, 456.21));
    p += dot(p, p + 45.32);
    return fract(p.x * p.y);
}

float noise(vec2 p) {
    vec2 i = floor(p), f = fract(p);
    vec2 u = f * f * (3.0 - 2.0 * f);
    return mix(mix(hash(i), hash(i + vec2(1, 0)), u.x),
               mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), u.x), u.y);
}

float fbm(vec2 p) {
    float v = 0.0, a = 0.5;
    for (int i = 0; i < 5; ++i) {
        v += a * noise(p);
        p = p * 2.03 + vec2(17.1, 9.2);
        a *= 0.5;
    }
    return v;
}

// Distance to the ink front: < 0 inside, > 0 outside (like inkbloom.frag)
float field(vec2 p, float reach) {
    vec2 rel = p - origin;
    float d = length(rel);
    vec2 dir = rel / max(d, 1.0);
    float edge = fbm(dir * 2.4 + p / 520.0 + time * 0.18) - 0.5;
    float fine = fbm(p / 46.0 - time * 0.35) - 0.5;
    float front = cover * reach + edge * 240.0 + fine * 16.0;
    return d - front;
}

void main() {
    vec2 p = qt_TexCoord0 * size;
    float reach = maxR * 1.2 + 220.0;
    float f = field(p, reach);

    float feather = 60.0;
    float inside = 1.0 - smoothstep(-feather, feather * 0.35, f);

    vec2 cell = floor(p / 72.0);
    vec2 dotPos = (cell + 0.2 + vec2(hash(cell), hash(cell + 7.7)) * 0.6) * 72.0;
    float lead = hash(cell + 3.1) * 110.0;
    float rad = mix(2.0, 12.0, pow(hash(cell + 5.3), 3.0));
    float dotFront = field(dotPos, reach) - lead;
    float drop = (1.0 - smoothstep(rad - 2.0, rad + 2.0, length(p - dotPos)))
               * step(dotFront, 0.0) * smoothstep(0.0, 0.12, cover);
    float mask = max(inside, drop);
    if (cover >= 0.999)
        mask = 1.0;
    if (cover <= 0.0)
        mask = 0.0;

    float keep = mix(mask, 1.0 - mask, invert);
    vec4 src = texture(source, qt_TexCoord0); // premultiplied
    vec4 col = src * keep;

    // Delicate shimmer at the edge (only while the front runs)
    float sheen = exp(-pow((f + 6.0) / 10.0, 2.0)) * step(0.001, cover) * (1.0 - step(0.999, cover)) * 0.45;
    vec3 glow = glowColor.rgb * 1.15 + 0.06;
    col = vec4(col.rgb * (1.0 - sheen) + glow * sheen, col.a * (1.0 - sheen) + sheen);

    fragColor = col * qt_Opacity;
}
