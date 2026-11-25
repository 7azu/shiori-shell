#version 440

// Clean crossfade of the desktop visualizer on a wallpaper change (windows/DesktopVisualizer.qml):
// the same wave in the old and new palette, mixed exactly. Simply fading the old one out and the new one
// in (two layers with 1-t and t) made the semi-transparent wave thinner in the middle,
// because opacities do not add up; mix() of the two (premultiplied) images does not have that problem.
// Recompile after changes:
//   /usr/lib/qt6/bin/qsb --glsl "300 es,150,330" -o visualizer_mix.frag.qsb visualizer_mix.frag

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    float mixT;
};

layout(binding = 1) uniform sampler2D fromTex;
layout(binding = 2) uniform sampler2D toTex;

void main() {
    fragColor = mix(texture(fromTex, qt_TexCoord0), texture(toTex, qt_TexCoord0), mixT) * qt_Opacity;
}
