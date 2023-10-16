package graphics

import "core:fmt"
import "core:log"
import "core:os"
import "core:mem"

import la "core:math/linalg"
import vk "vendor:vulkan"

import "builders"

MaterialCache :: struct {
    buffer: []u8,
    arena: mem.Arena,

    effects: map[string]ShaderEffect,
    materials: map[string]Material,
}

VertexLayout :: struct {
    bindings: []vk.VertexInputBindingDescription,
    attributes: []vk.VertexInputAttributeDescription,
}

ShaderStage :: struct {
    module:  vk.ShaderModule,
    stage:   vk.ShaderStageFlag,
}

ShaderEffect :: struct {
    pipeline:         vk.Pipeline,
    pipeline_layout:  vk.PipelineLayout,
    resource_layout:  LayoutType,
    vertex_layout:    VertexLayout,
    desc_layouts:     [4]vk.DescriptorSetLayout,
    shader_stages:    []ShaderStage,
}

Material :: struct {
    effect:      ^ShaderEffect,
    descriptors: [4]vk.DescriptorSet,
    uniforms:    Buffer,
}

mats_init :: proc(cache: ^MaterialCache) {
    buffer, err := make([]byte, mem.Megabyte)
    assert(err == nil)
    cache.buffer = buffer

    mem.arena_init(&cache.arena, cache.buffer)
    context.allocator = mem.arena_allocator(&cache.arena)

    cache.effects =   make(map[string]ShaderEffect, 4)
    cache.materials = make(map[string]Material, 4)
}

mats_shutdown :: proc(cache: ^MaterialCache, device: vk.Device) {
    cache := cache
    for _, effect in cache.effects {
        mats_destroy(device, effect)
    }
    for _, mat in cache.materials {
        mats_destroy(device, mat)
    }
    delete(cache.effects)
    delete(cache.materials)
    delete(cache.buffer)
}

mats_get_mat :: proc(cache: ^MaterialCache, name: string) -> ^Material {
    return &cache.materials[name]
}

mats_create_shader_effect :: proc(cache:            ^MaterialCache,
                                  name:             string,
                                  device:           vk.Device,
                                  render_pass:      vk.RenderPass,
                                  resource_layout:  LayoutType,
                                  vertex_layout:    VertexLayout,
                                  vert_path:        string,
                                  frag_path:        string) ->
(^ShaderEffect) {
    effect: ShaderEffect

    vert := builders.create_shader_module(device, read_spirv(vert_path))
    frag := builders.create_shader_module(device, read_spirv(frag_path))

    effect.shader_stages = {
        ShaderStage {
            module = vert,
            stage = .VERTEX,
        },
        ShaderStage {
            module = frag,
            stage = .FRAGMENT,
        },
    };
    effect.desc_layouts = layout_create_descriptor_layout(device, resource_layout)

    effect.pipeline_layout = builders.create_pipeline_layout(device, effect.desc_layouts[:])

    effect.resource_layout = resource_layout

    effect.vertex_layout = vertex_layout

    stage_count := len(effect.shader_stages)
    shader_stages := make([]vk.PipelineShaderStageCreateInfo, stage_count)
    defer delete(shader_stages)

    for stage, i in effect.shader_stages {
        shader_stages[i] = {
            sType = .PIPELINE_SHADER_STAGE_CREATE_INFO,
            pName = "main",
            stage = { stage.stage },
            module = stage.module,
        }
    }

    vertex_input := builders.get_vertex_input(effect.vertex_layout.bindings, effect.vertex_layout.attributes)
    
    effect.pipeline = builders.create_pipeline(device,
                                               layout = effect.pipeline_layout,
                                               render_pass = render_pass,
                                               vertex_input = &vertex_input,
                                               stages = shader_stages)

    cache.effects[name] = effect

    return &cache.effects[name]
}

mats_create_shadow_effect :: proc(device: vk.Device, cache: ^MaterialCache, render_pass: vk.RenderPass) -> (^ShaderEffect){
    vert := builders.create_shader_module(device, read_spirv("assets/shaders/shadow_pass.vert.spv"));

    effect: ShaderEffect

    effect.shader_stages = {
        ShaderStage {
            module = vert,
            stage = .VERTEX,
        },
    }

    // Shadow descriptor sets
    effect.resource_layout = .SHADOW;

    effect.desc_layouts = layout_create_descriptor_layout(device, effect.resource_layout);

    effect.pipeline_layout = builders.create_pipeline_layout(device, effect.desc_layouts[:]);
    
    bindings := []vk.VertexInputBindingDescription	{ vk.VertexInputBindingDescription {0, size_of(la.Vector3f32), .VERTEX} }
    attributes := []vk.VertexInputAttributeDescription { vk.VertexInputAttributeDescription {0, 0, .R32G32B32_SFLOAT, 0} }

    shader_stages := []vk.PipelineShaderStageCreateInfo {
        vk.PipelineShaderStageCreateInfo {
            sType = .PIPELINE_SHADER_STAGE_CREATE_INFO,
            stage = { .VERTEX },
            pName = "main",
            module = vert,
        },
    }

    vertex_input := builders.get_vertex_input(bindings, attributes)	
    input_assembly := builders.get_input_assembly()
    color_blend := vk.PipelineColorBlendStateCreateInfo{
        sType           = .PIPELINE_COLOR_BLEND_STATE_CREATE_INFO,
        logicOpEnable   = false,
        logicOp         = .COPY,
        attachmentCount = 0,
    }
    
    //pipeline stuff
    
    effect.pipeline = builders.create_pipeline(device,
                                               layout = effect.pipeline_layout,
                                               render_pass = render_pass,
                                               vertex_input = &vertex_input,
                                               color_blend = &color_blend,
                                               stages = shader_stages)
    
    cache.effects["shadow_pass"] = effect

    return &cache.effects["shadow_pass"]
}

mats_create :: proc(cache: ^MaterialCache,
                    name: string,
                    device: vk.Device,
                    pool: vk.DescriptorPool,
                    shader_effect: ^ShaderEffect) ->
(^Material) {
    mat: Material
    mat.descriptors = builders.allocate_descriptor_set(device, pool, shader_effect.desc_layouts[:])

    mat.effect = shader_effect

    layouts := ShaderLayouts
    layout := layouts[mat.effect.resource_layout]
    if layout[2] != nil {
        resource := layout[2][0]
        mat.uniforms = buffers_create(resource.size, resource.buffer_type)
        builders.bind_descriptor_set(device,
                                     { mat.uniforms.handle, 0, vk.DeviceSize(mat.uniforms.size) },
                                     resource.type,
                                     mat.descriptors[2], 0)


    }

    cache.materials[name] = mat

    return &cache.materials[name]
}

mats_clone :: proc(cache:   ^MaterialCache,
                   device:  vk.Device,
                   pool:    vk.DescriptorPool,
                   parent:  string,
                   name:    string) -> (^Material) {
    mat := cache.materials[parent]
    mat.descriptors[2] = builders.allocate_descriptor_set(device, pool, mat.effect.desc_layouts[2:3])[0]

    layouts := ShaderLayouts
    layout := layouts[mat.effect.resource_layout]
    if layout[2] != nil {
        resource := layout[2][0]
        mat.uniforms = buffers_create(resource.size, resource.buffer_type)
        builders.bind_descriptor_set(device,
                                     { mat.uniforms.handle, 0, vk.DeviceSize(mat.uniforms.size) },
                                     resource.type,
                                     mat.descriptors[2], 0)


    }

    cache.materials[name] = mat

    return &cache.materials[name]
}


mats_destroy :: proc { mats_destroy_shader_effect, mats_destroy_material }

mats_destroy_shader_effect :: proc(device: vk.Device, effect: ShaderEffect) {
    vk.DestroyPipeline(device, effect.pipeline, nil)
    vk.DestroyPipelineLayout(device, effect.pipeline_layout, nil)

    for layout in effect.desc_layouts {
        vk.DestroyDescriptorSetLayout(device, layout, nil)
    }

    for stage in effect.shader_stages {
        vk.DestroyShaderModule(device, stage.module, nil)
    }
}

mats_destroy_material :: proc(device: vk.Device, material: Material) {
    buffers_destroy(material.uniforms)
}

@private
read_spirv :: proc(path: string) -> []u8 {
    log.debugf("Loading SPIRV %s", path)
    data, success := os.read_entire_file(path)
    return data
}
