#version 440

// "Ink Bloom": the new wallpaper runs like ink over the old one (windows/InkBloom.qml).
// The overlay lies above the real wallpaper; two kinds (services/WallpaperTransition.qml):
//   target image: transparent outside (oldA = 0, the old one keeps running live), inside the still image of the new one
//                 (live = 0) - an image is static, so exactly as it is live later
//   target scene: outside the old one as a frozen image (oldA = 1), transparent inside (live = 1):
//                 underneath the new scene already draws and can be seen live in the shape
// (A target video is masked by AnimatedWallpaper itself: windows/shaders/inkmask.frag, same shape)
// At the edge: a soft gradient, slight refraction (a "wet" edge) and a delicate shimmer.
// Coordinates in pixels of the whole desktop (origin relative to this monitor) -> the wave runs
// across all monitors.
// Recompile after changes:
//   /usr/lib/qt6/bin/qsb --glsl "300 es,150,330" -o inkbloom.frag.qsb inkbloom.frag

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    float cover;      // 0..1 ink front
    float live;       // inside: 0 = still image of the new one, 1 = transparent (live image underneath)
    float oldA;       // outside: 1 = frozen old image, 0 = transparent (old one live underneath)
    float maxR;       // distance to the farthest desktop corner (px)
    float time;       // seconds, for the flowing edge
    vec2 origin;      // start point relative to this monitor (px)
    vec2 size;        // monitor size (px)
    vec2 oldSize;     // size of the old still image (px)
    vec2 newSize;     // size of the new still image (px)
    vec4 glowColor;   // shimmer at the edge (accent color)
};

layout(binding = 1) uniform sampler2D oldTex;
layout(binding = 2) uniform sampler2D newTex;

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

// Like PreserveAspectCrop / awww "crop": the image fills the monitor, cropped centered
vec2 coverUv(vec2 p, vec2 tex) {
    float s = max(size.x / tex.x, size.y / tex.y);
    return clamp(((p - size * 0.5) / s + tex * 0.5) / tex, 0.0, 1.0);
}

// Distance to the ink front: < 0 inside, > 0 outside
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
    // The front runs past the last corner, otherwise the edge would get stuck there
    float reach = maxR * 1.2 + 220.0;
    float f = field(p, reach);

    // Soft edge: a wide gradient instead of a hard edge
    float feather = 60.0;
    float inside = 1.0 - smoothstep(-feather, feather * 0.35, f);

    // Small drops running ahead of the front
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

    // Wet edge: near the front the new still image is warped slightly outward
    float band = exp(-pow(f / 60.0, 2.0)) * (1.0 - step(0.999, cover));
    vec2 eps = vec2(2.0, 0.0);
    vec2 grad = vec2(field(p + eps.xy, reach) - field(p - eps.xy, reach),
                     field(p + eps.yx, reach) - field(p - eps.yx, reach));
    vec2 normal = grad / max(length(grad), 1e-4);

    vec3 oldCol = texture(oldTex, coverUv(p, oldSize)).rgb;
    vec3 newCol = texture(newTex, coverUv(p - normal * band * 14.0, newSize)).rgb;

    // Premultiplied: outside the old image or nothing, inside the new still image or nothing (live)
    float newA = 1.0 - live;
    vec3 rgb = (1.0 - mask) * oldA * oldCol + mask * newA * newCol;
    float a = (1.0 - mask) * oldA + mask * newA;

    // Delicate shimmer exactly at the edge in the accent color
    float sheen = exp(-pow((f + 6.0) / 10.0, 2.0)) * (1.0 - step(0.999, cover)) * 0.45;
    vec3 glow = glowColor.rgb * 1.15 + 0.06;
    rgb = rgb * (1.0 - sheen) + glow * sheen;
    a = a * (1.0 - sheen) + sheen;

    fragColor = vec4(rgb, a) * qt_Opacity;
}
