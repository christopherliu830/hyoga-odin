package graphics

import "core:log" 

import vk "vendor:vulkan"
import "builders"

LayoutType:: enum {
    DEFAULT,
    DIFFUSE,
	SHADOW,
}

DescriptorNumber :: enum {
    GLOBAL,
    RESERVED,
    PER_MATERIAL,
    PER_OBJECT,
}

ShaderResource :: struct {
    name:         string,
    type:         vk.DescriptorType,
    buffer_type:  BufferType,
    size:         int,
}

RESOURCE_CAMERA :: ShaderResource {
    name        = "_camera",
    type        = .UNIFORM_BUFFER_DYNAMIC,
    buffer_type = .UNIFORM_DYNAMIC,
    size        = size_of(Camera),
}

RESOURCE_LIGHTS :: ShaderResource {
    name        = "_lights",
    type        = .UNIFORM_BUFFER,
    buffer_type = .UNIFORM,
    size        = size_of(Light),
}

RESOURCE_OBJECT :: ShaderResource {
    name        = "_object",
    type        = .UNIFORM_BUFFER_DYNAMIC,
    buffer_type = .UNIFORM_DYNAMIC,
    size        = size_of(mat4),
}

RESOURCE_COLOR :: ShaderResource {
    name        = "_material",
    type        = .UNIFORM_BUFFER,
    buffer_type = .UNIFORM,
    size        = size_of(vec4),
}

ShaderLayouts :: [LayoutType][len(DescriptorNumber)][]ShaderResource {
    .DEFAULT = {
        0 = { RESOURCE_CAMERA, RESOURCE_LIGHTS },
        3 = { RESOURCE_OBJECT },
    },
    .DIFFUSE = {
        0 = { RESOURCE_CAMERA, RESOURCE_LIGHTS },
        2 = { RESOURCE_COLOR },
        3 = { RESOURCE_OBJECT },
    },
	.SHADOW = {
		0 = { RESOURCE_CAMERA },
		3 = { RESOURCE_OBJECT },
	},
}

layout_create_descriptor_layout_2 :: proc(device: vk.Device, type: LayoutType) {
    layouts := ShaderLayouts
    for binding_list, i in layouts {
    }
}

// Big switch statement for manual vertex layouts.
layout_create_descriptor_layout :: proc(device: vk.Device, type: LayoutType) -> 
(layouts: [4]vk.DescriptorSetLayout) {

	switch(type){
		case .DEFAULT, .DIFFUSE:
			layouts[DescriptorNumber.GLOBAL] = builders.create_descriptor_set_layout(device, {
				{
					binding         = 0,
					descriptorType  = .UNIFORM_BUFFER_DYNAMIC,
					descriptorCount = 1,
					stageFlags      = { .VERTEX },
				},
				{
					binding = 1,
					descriptorType = .UNIFORM_BUFFER,
					descriptorCount = 1,
					stageFlags = { .VERTEX, .FRAGMENT },
				},
			})
		case .SHADOW:
			layouts[DescriptorNumber.GLOBAL] = builders.create_descriptor_set_layout(device, {
				{
					binding         = 0,
					descriptorType  = .UNIFORM_BUFFER_DYNAMIC,
					descriptorCount = 1,
					stageFlags      = { .VERTEX },
				},
			})
	}

    switch(type) {
        case .DEFAULT, .SHADOW:
            layouts[DescriptorNumber.PER_OBJECT] = builders.create_descriptor_set_layout(device, {{
                binding = 0,
                descriptorType = .UNIFORM_BUFFER_DYNAMIC,
                descriptorCount = 1,
                stageFlags = { .VERTEX },
            }})

        case .DIFFUSE:
            layouts[DescriptorNumber.PER_MATERIAL] = builders.create_descriptor_set_layout(device, {{
                binding = 0,
                descriptorType = .UNIFORM_BUFFER,
                descriptorCount = 1,
                stageFlags = { .FRAGMENT },
            }})

            layouts[DescriptorNumber.PER_OBJECT] = builders.create_descriptor_set_layout(device, {{
                binding = 0,
                descriptorType = .UNIFORM_BUFFER_DYNAMIC,
                descriptorCount = 1,
                stageFlags = { .VERTEX },
            }})
    }

    // Fill in empty layouts with no bindings
    for i in 0..<len(DescriptorNumber) do if (layouts[i] == 0) {
        layouts[i] = builders.create_descriptor_set_layout(device, {})
    }
    return layouts
}