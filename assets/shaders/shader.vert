#version 450

layout(binding = 0) uniform CameraBuffer {
    mat4 view;
    mat4 proj;
} _camera;

layout(set = 3, binding = 0) uniform ObjectBuffer {
		mat4 model;
} _object;

layout(location = 0) in vec3 position;
layout(location = 1) in vec3 normal;
layout(location = 2) in vec4 color;
layout(location = 3) in vec3 uv;

layout(location = 0) out vec3 fragColor;

void main() {
    gl_Position = _camera.proj * _camera.view * _object.model * vec4(position, 1.0);
    fragColor = smoothstep(-1, 1, position);
}

