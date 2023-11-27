package graphics

import "core:log" 

import vk "vendor:vulkan"

import "builders"

MAX_BINDINGS :: 8
GLOBAL_SET :: 0
MATERIAL_SET :: 2
OBJECT_SET :: 3

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

// RESOURCES builds DESCRIPTORS builds PIPELINE_LAYOUT
PassResourceLayout :: struct {
    pipeline: vk.PipelineLayout,
    descriptors: [4]vk.DescriptorSetLayout
}

ResourceDescription :: distinct [4][]ShaderResource

VERTEX_BINDINGS :: [PassType][]vk.VertexInputBindingDescription {
    .FORWARD = BINDINGS,
    .SHADOW  = {{ 0, size_of(Vertex), .VERTEX }},
}

VERTEX_ATTRIBUTES :: [PassType][]vk.VertexInputAttributeDescription {
    .FORWARD = ATTRIBUTES,
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

RESOURCE_SHADOW :: ShaderResource {
    name        = "_shadow_cam",
    type        = .UNIFORM_BUFFER_DYNAMIC,
    stages      = { .VERTEX },
    buffer_type = .UNIFORM_DYNAMIC,
    size        = size_of(Camera),
}

RESOURCE_IMAGE_SAMPLER :: ShaderResource {
    name        = "_image_sampler",
    type        = .COMBINED_IMAGE_SAMPLER,
    stages      = { .FRAGMENT },
}

// Number denotes set number.
// Index in list is binding number.
DEFAULT_RESOURCES :: [PassType]ResourceDescription {
    .FORWARD = {
        0 = { RESOURCE_CAMERA, RESOURCE_LIGHTS, RESOURCE_IMAGE_SAMPLER, RESOURCE_SHADOW },
        2 = { RESOURCE_COLOR },
        3 = { RESOURCE_OBJECT },
    },

    .SHADOW = {
        0 = { RESOURCE_CAMERA },
        3 = { RESOURCE_OBJECT },
    },
}

GLOBAL_UNIFORMS :: []ShaderResource { RESOURCE_CAMERA, RESOURCE_LIGHTS }

layout_get_pass_resources :: proc(pass: PassType) ->
(PassResourceLayout) {
    ctx := get_context()
    device := ctx.device
    cache := ctx.mat_cache

    id := Handle(pass)

    if id in cache.pipeline_descriptions do return cache.pipeline_descriptions[id]

    default_layouts := DEFAULT_RESOURCES 
    layouts := layout_create_descriptor_layout(default_layouts[pass])

    pipeline_desc := PassResourceLayout {
        pipeline = builders.create_pipeline_layout(device, layouts[:]),
        descriptors = layouts,
    }

    cache.pipeline_descriptions[id] = pipeline_desc
    return pipeline_desc
}

layout_create_descriptor_layout :: proc(rd: ResourceDescription) ->
(layouts: [len(DescriptorNumber)]vk.DescriptorSetLayout) {
    device := get_context().device

    for _, set_num in DescriptorNumber {
        descriptor_set := rd[set_num]
        bindings := make([]vk.DescriptorSetLayoutBinding, len(descriptor_set))
        defer delete(bindings)

        for binding_num in 0..<len(descriptor_set) {
            resource := descriptor_set[binding_num]
            bindings[binding_num] = {
                binding         = u32(binding_num),
                descriptorType  = resource.type,
                descriptorCount = 1,
                stageFlags      = resource.stages,
            }
        }

        layouts[set_num] = builders.create_descriptor_set_layout(device, bindings)
    }

    // Fill in empty layouts with no bindings
    for i in 0..<len(DescriptorNumber) do if (layouts[i] == 0) {
        layouts[i] = builders.create_descriptor_set_layout(device, {})
    }
    return layouts
}

layout_get_location :: proc(rd: ResourceDescription, id: string) -> (int, int) {
    for resource_set, set_num in rd {
        for resource, binding_num in resource_set {
            if resource.name == id do return set_num, binding_num
        }
    }
    return -1, -1
}

layout_get :: proc(rd: ResourceDescription, id: string) -> (ShaderResource, int, int) {
    s, b := layout_get_location(rd, id)
    return rd[s][b], s, b
}