#version 450

layout(set = 0, binding = 0) uniform View {
    mat4 view;
    mat4 proj;
} _view;

layout(set = 3, binding = 0) uniform Model {
    mat4 model;
} _model;

layout(location = 0) in vec3 position;

void main()
{
    gl_Position = _view.proj * _view.view * _model.model * vec4(position, 1);
    gl_Position.z = gl_Position.z * 0.5 + 0.5;
}
