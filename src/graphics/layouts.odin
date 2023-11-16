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
    stages:       vk.ShaderStageFlags,
    buffer_type:  BufferType,
    size:         int,
}

DescriptorLayout :: struct {
    resources: []ShaderResource,
    handle: vk.DescriptorSetLayout,
}

VERTEX_BINDINGS :: [LayoutType][]vk.VertexInputBindingDescription {
    .DEFAULT = BINDINGS,
    .DIFFUSE = BINDINGS,
    .SHADOW  = {{ 0, size_of(Vertex), .VERTEX }},
}

VERTEX_ATTRIBUTES :: [LayoutType][]vk.VertexInputAttributeDescription {
    .DEFAULT = ATTRIBUTES,
    .DIFFUSE = ATTRIBUTES,
    .SHADOW = {{ 0, 0, .R32G32B32_SFLOAT, 0 }},
}

RESOURCE_CAMERA :: ShaderResource {
    name        = "_camera",
    type        = .UNIFORM_BUFFER_DYNAMIC,
    stages      = { .VERTEX },
    buffer_type = .UNIFORM_DYNAMIC,
    size        = size_of(Camera),
}

RESOURCE_LIGHTS :: ShaderResource {
    name        = "_lights",
    type        = .UNIFORM_BUFFER,
    stages      = { .VERTEX, .FRAGMENT },
    buffer_type = .UNIFORM,
    size        = size_of(Light),
}

RESOURCE_OBJECT :: ShaderResource {
    name        = "_object",
    type        = .UNIFORM_BUFFER_DYNAMIC,
    stages      = { .VERTEX },
    buffer_type = .UNIFORM_DYNAMIC,
    size        = size_of(mat4),
}

RESOURCE_COLOR :: ShaderResource {
    name        = "_material",
    type        = .UNIFORM_BUFFER_DYNAMIC,
    stages      = { .FRAGMENT },
    buffer_type = .UNIFORM,
    size        = size_of(vec4),
}

RESOURCE_IMAGE_SAMPLER :: ShaderResource {
    name        = "_image_sampler",
    type        = .COMBINED_IMAGE_SAMPLER,
    stages      = { .FRAGMENT },
}

// Number denotes set number.
// Index in list is binding number.
ShaderLayouts :: [LayoutType][len(DescriptorNumber)][]ShaderResource {

    .DEFAULT = {
        0 = { RESOURCE_CAMERA, RESOURCE_LIGHTS },
    },

    .DIFFUSE = {
        0 = { RESOURCE_CAMERA, RESOURCE_LIGHTS, RESOURCE_IMAGE_SAMPLER, RESOURCE_CAMERA /* Shadows */ },
        2 = { RESOURCE_COLOR },
        3 = { RESOURCE_OBJECT },
    },

    .SHADOW = {
        0 = { RESOURCE_CAMERA },
        3 = { RESOURCE_OBJECT },
    },
}

GLOBAL_UNIFORMS :: []ShaderResource { RESOURCE_CAMERA, RESOURCE_LIGHTS }

layout_create_descriptor_layout :: proc(device: vk.Device, type: LayoutType) ->
(layouts: [len(DescriptorNumber)]vk.DescriptorSetLayout) {
    config := ShaderLayouts

    for _, set_num in DescriptorNumber {
        resources := config[type][set_num]
        layouts[set_num] = layout_create_one(device, resources).handle
    }

    // Fill in empty layouts with no bindings
    for i in 0..<len(DescriptorNumber) do if (layouts[i] == 0) {
        layouts[i] = builders.create_descriptor_set_layout(device, {})
    }
    return layouts
}

layout_create_one :: proc (device: vk.Device, resources: []ShaderResource) -> DescriptorLayout {
    bindings := make([]vk.DescriptorSetLayoutBinding, len(resources))
    defer delete(bindings)

    for binding_num in 0..<len(resources) {
        resource := resources[binding_num]
        bindings[binding_num] = {
            binding         = u32(binding_num),
            descriptorType  = resource.type,
            descriptorCount = 1,
            stageFlags      = resource.stages,
        }
    }
    return { resources, builders.create_descriptor_set_layout(device, bindings) }
}