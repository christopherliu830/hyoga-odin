#version 450

layout(set = 0, binding = 0) uniform CameraBuffer {
    mat4 view;
    mat4 proj;
} _camera;

layout(set = 0, binding = 1) uniform Lights {
    vec4 direction;
    vec4 color;
} _light;

layout(set = 3, binding = 0) uniform ObjectBuffer {
    mat4 model;
} _object;

layout(location = 0) in vec3 position;
layout(location = 1) in vec3 normal;
layout(location = 2) in vec4 color;
layout(location = 3) in vec3 uv;

layout(location = 0) out vec3 fragNormal;
layout(location = 1) out vec3 fragLightDir;

void main() {
    mat4 mv = _camera.view * _object.model;

    gl_Position = _camera.proj * mv  * vec4(position, 1.0);

    // Interpolated values
    fragNormal = mat3(transpose(inverse(_object.model))) * normal;
    fragLightDir = _light.direction.xyz;
}

