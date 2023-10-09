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
   vec4 pos = vec4(position.x, position.y, position.z, 1.0);
   vec4 world_pos = _model.model * pos;
   gl_Position = _view.proj * _view.view * world_pos;
}
