package graphics

import la "core:math/linalg"
import vk "vendor:vulkan"

Vertex :: struct {
    position:  la.Vector3f32,
    normal:    la.Vector3f32,
    color:     la.Vector4f32,
    uv:        la.Vector2f32,
}

Mesh :: struct {
    vertices: Buffer,
    indices: Buffer,
}

BINDINGS :: []vk.VertexInputBindingDescription {{
    binding = 0,
    stride = size_of(Vertex),
    inputRate = .VERTEX,
}}

ATTRIBUTES :: []vk.VertexInputAttributeDescription {
    { 0, 0, .R32G32B32_SFLOAT, u32(offset_of(Vertex, position)) },
    { 1, 0, .R32G32B32_SFLOAT, u32(offset_of(Vertex, normal)) },
    { 2, 0, .R32G32B32A32_SFLOAT, u32(offset_of(Vertex, color)) },
    { 3, 0, .R32G32_SFLOAT, u32(offset_of(Vertex, uv)) },
}
