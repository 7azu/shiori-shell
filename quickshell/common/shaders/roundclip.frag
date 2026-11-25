#version 440
// Round corners for common/RoundedClip: background color + content (layer texture), transparent outside the
// rounded area. The shape is computed here instead of read from a mask texture
// (Quickshell's ClippingRectangle sometimes lost it after a restart -> the whole card invisible).
// Compile:
//   /usr/lib/qt6/bin/qsb --glsl "300 es,150,330" -o roundclip.frag.qsb roundclip.frag
layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec4 backgroundColor;
    vec2 size;
    float radius;
};

layout(binding = 1) uniform sampler2D source;

void main() {
    vec4 content = texture(source, qt_TexCoord0);
    // Put the content over the background (both premultiplied)
    vec4 inner = content + backgroundColor * (1.0 - content.a);

    // Distance to the rounded edge (negative = inside), in pixels of the element
    vec2 p = qt_TexCoord0 * size - size * 0.5;
    float r = min(radius, 0.5 * min(size.x, size.y));
    vec2 q = abs(p) - (size * 0.5 - vec2(r));
    float d = length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - r;
    float aa = max(fwidth(d), 0.0001);
    float alpha = 1.0 - smoothstep(-0.5 * aa, 0.5 * aa, d);

    fragColor = inner * alpha * qt_Opacity;
}
