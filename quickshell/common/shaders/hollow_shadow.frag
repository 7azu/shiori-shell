#version 440

// qsb --glsl "300 es,150,330" -o hollow_shadow.frag.qsb hollow_shadow.frag
layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec2 tileSize;
    vec2 effectSize;
    vec2 shadowOffset;
    float cornerRadius;
    float blurRadius;
    float strength;
};

float roundedRectDistance(vec2 position, vec2 halfSize, float radius) {
    vec2 edge = abs(position) - halfSize + radius;
    return length(max(edge, 0.0)) + min(max(edge.x, edge.y), 0.0) - radius;
}

void main() {
    vec2 position = (qt_TexCoord0 - 0.5) * effectSize;
    vec2 halfSize = 0.5 * tileSize;
    float radius = clamp(cornerRadius, 0.0, min(halfSize.x, halfSize.y));

    float shadowDistance = roundedRectDistance(position - shadowOffset, halfSize, radius);
    float falloff = 1.0 - smoothstep(-0.5 * blurRadius, blurRadius, shadowDistance);

    // Cut out the tile with an antialiased edge at the current screen scale.
    float tileDistance = roundedRectDistance(position, halfSize, radius);
    float edgeWidth = max(0.5 * fwidth(tileDistance), 0.001);
    float outsideTile = smoothstep(-edgeWidth, edgeWidth, tileDistance);

    fragColor = vec4(0.0, 0.0, 0.0, falloff * outsideTile * strength * qt_Opacity);
}
