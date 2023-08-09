package graphics

import vk "vendor:vulkan"

Vertex :: struct
{
	position: [2]f32,
	color: [3]f32,
}

VERTICES :: [?]Vertex {
	{{  0.0,  -0.5 }, {1, 0, 0}},
	{{  0.5,  -0.5 }, {0, 1, 0}},
	{{ -0.5,   0.5 }, {0, 0, 1}},
}


// Specify information about the Vertex data structure.
vertex_binding_description :: proc() ->
(binding: vk.VertexInputBindingDescription) {
        binding = {
                binding = 0,
                stride = size_of(Vertex),
                inputRate = .VERTEX,
        }
        return
}

// Specify information about the Vertex data fields.
vertex_attribute_descriptions :: proc() -> 
(attribute_descriptions: [2]vk.VertexInputAttributeDescription) {

        attribute_descriptions[0] = {
                binding = 0,
                location = 0,
                format = .R32G32_SFLOAT, // vec2
                offset = u32(offset_of(Vertex, position)),
        }

        attribute_descriptions[1] = {
                binding = 0,
                location = 1,
                format = .R32G32B32_SFLOAT, // vec3
                offset = u32(offset_of(Vertex, color)),
        }

        return attribute_descriptions
}


