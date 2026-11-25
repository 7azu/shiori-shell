#version 440

// Soft glow in the accent color behind the dock of the power menu (windows/PowerMenu.qml).
// Replaces a RadialGradient: that ran out linearly from 16 % opacity to 0. On the almost black
// background those are only some 40 brightness steps -> visible rings (banding), plus a kink at the edge.
// Here: a gradient without a kink (smoothstep, flat at the middle and edge) and dithering (+-1 step of noise per
// pixel), which blurs the steps for the eye.
// Recompile after changes:
//   /usr/lib/qt6/bin/qsb --glsl "300 es,150,330" -o glow.frag.qsb glow.frag

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec4 tint;       // color of the glow (alpha is ignored)
    float strength;  // opacity in the middle
};

float hash(vec2 p) {
    p = fract(p * vec2(0.1031, 0.1030));
    p += dot(p, p.yx + 33.33);
    return fract((p.x + p.y) * p.x);
}

void main() {
    // 0 in the middle, 1 at the edge of the ellipse (the item is the bounding box)
    vec2 d = (qt_TexCoord0 - 0.5) * 2.0;
    float r = clamp(length(d), 0.0, 1.0);
    float a = strength * (1.0 - smoothstep(0.0, 1.0, r));
    // Triangularly distributed noise (two random values) around 0, about one 8-bit step wide
    float n = (hash(gl_FragCoord.xy) + hash(gl_FragCoord.xy + 17.17) - 1.0) / 255.0;
    // Only where the glow is; output premultiplied
    float alpha = max(0.0, a + n * step(0.0005, a));
    fragColor = vec4(tint.rgb * alpha, alpha) * qt_Opacity;
}
