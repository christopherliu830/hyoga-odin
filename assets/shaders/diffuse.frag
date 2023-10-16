#version 450

layout(set = 0, binding = 1) uniform Lights {
    vec4 direction;
    vec4 color;
} _light;

layout(set = 2, binding = 0) uniform MaterialBuffer {
    vec4 color;
} _material;

layout(location = 0) in vec3 fragNormal;
layout(location = 1) in vec3 fragLightDir;

layout(location = 0) out vec4 outColor;

void main() {
    vec3 normal = normalize(fragNormal);
    vec3 lightDir = normalize(-fragLightDir);

    float ambient_const = 0.05;
    vec3 ambient = vec3(ambient_const, ambient_const, ambient_const) * _material.color.xyz;

    float diff = clamp(dot(normal, lightDir), 0.0, 1.0);
    vec3 diffuse = _material.color.xyz * _light.color.xyz * diff;

    vec3 result = clamp(ambient + diffuse, 0.0, 1.0);

    outColor = vec4(result, 1.0);
}

