#version 450

layout(set = 0, binding = 0) uniform CameraBuffer {
    mat4 view;
    mat4 proj;
} _camera;

layout(set = 0, binding = 1) uniform Lights {
    vec4 direction;
    vec4 color;
} _light;


layout(set = 0, binding = 3) uniform Shadows {
    mat4 view;
    mat4 proj;
} _shadows;

layout(set = 3, binding = 0) uniform ObjectBuffer {
    mat4 model;
} _object;

layout(location = 0) in vec3 position;
layout(location = 1) in vec3 normal;
layout(location = 2) in vec4 color;
layout(location = 3) in vec3 uv;

layout(location = 0) out vec3 fragNormal;
layout(location = 1) out vec3 fragLightDir;
layout(location = 2) out vec4 fragShadowCoords;

void main() {
    mat4 mv = _camera.view * _object.model;

    gl_Position = _camera.proj * mv  * vec4(position, 1.0);

    // Interpolated values
    fragNormal = mat3(transpose(inverse(_object.model))) * normalize(normal);
    fragLightDir = _light.direction.xyz;

	fragShadowCoords = _shadows.proj * _shadows.view * _object.model * vec4(position, 1.0);

    // perspective divide - noop for orthographic projection
    vec3 coords = fragShadowCoords.xyz / fragShadowCoords.w;
    coords = coords * 0.5 + 0.5;
    fragShadowCoords.xyz = coords;
}

