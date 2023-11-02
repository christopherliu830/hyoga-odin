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

    // Cache resource handles to descriptors that describe them.
    descriptors: map[vk.NonDispatchableHandle]vk.DescriptorSet,
}

ShaderFile :: struct {
    path: string,
    stage: vk.ShaderStageFlag
}

ShaderStage :: struct{
    module:  vk.ShaderModule,
    stage:   vk.ShaderStageFlag,
}

ShaderEffect :: struct {
    pipeline:         vk.Pipeline,
    pipeline_layout:  vk.PipelineLayout,
    desc_layouts:     [4]vk.DescriptorSetLayout,
}

PassType :: enum {
    SHADOW,
    FORWARD,
}

Material :: struct {
    passes:      [PassType]^ShaderEffect,
    descriptors: [PassType][4]vk.DescriptorSet,
    uniforms:    Buffer,
}

MAX_SHADER_STAGES :: 2
MATERIAL_UNIFORM_BUFFER_SIZE :: mem.Kilobyte

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
    for key in cache.effects {
        mats_destroy(device, &cache.effects[key])
    }
    for key, mat in cache.materials {
        mats_destroy(device, &cache.materials[key])
    }
    delete(cache.effects)
    delete(cache.materials)
    delete(cache.buffer)
}

mats_get_mat :: proc(cache: ^MaterialCache, name: string) -> ^Material {
    return &cache.materials[name]
}

mats_create_shader_effect :: proc(ctx:          ^RenderContext,
                                  render_pass:  vk.RenderPass,
                                  name:         string,
                                  type:         LayoutType,
                                  paths:        []ShaderFile) ->
(^ShaderEffect) {
    effect: ShaderEffect

    device := ctx.device
    cache := ctx.mat_cache

    if name in cache.effects {
        return &cache.effects[name]
    }

    stage_count := len(paths)

    assert(stage_count <= MAX_SHADER_STAGES)

    effect.desc_layouts = layout_create_descriptor_layout(device, type)
    effect.pipeline_layout = builders.create_pipeline_layout(device, effect.desc_layouts[:])

    shader_stages := make([]vk.PipelineShaderStageCreateInfo, stage_count)
    defer delete(shader_stages)

    modules := make([]vk.ShaderModule, stage_count)
    defer delete(modules)

    for i in 0..<len(modules) {
        modules[i] = builders.create_shader_module(device, read_spirv(paths[i].path))
    }

    defer { for i in 0..<len(modules) do vk.DestroyShaderModule(device, modules[i], nil) }

    for _ , i in paths {
        shader_stages[i] = {
            sType = .PIPELINE_SHADER_STAGE_CREATE_INFO,
            pName = "main",
            stage = { paths[i].stage },
            module = modules[i],
        }
    }

    vertex_input := builders.get_vertex_input(BINDINGS, ATTRIBUTES)

    effect.pipeline = builders.create_pipeline(device,
                                               layout = effect.pipeline_layout,
                                               render_pass = render_pass,
                                               vertex_input = &vertex_input,
                                               stages = shader_stages)

    cache.effects[name] = effect

    return &cache.effects[name]
}

mats_create :: proc(ctx: ^RenderContext,
                    name: string,
                    passes: []struct { type: PassType, effect: ^ShaderEffect }) ->
(^Material) {

    if name in ctx.mat_cache.materials do return &ctx.mat_cache.materials[name]

    mat: Material

    for pass in passes {
        if pass.effect == nil do continue
        mat.passes[pass.type] = pass.effect
        mat.descriptors[pass.type], _ = builders.allocate_descriptor_set(ctx.device, ctx.descriptor_pool, pass.effect.desc_layouts[:])
    }

    mat.uniforms = buffers_create(MATERIAL_UNIFORM_BUFFER_SIZE, .UNIFORM_DYNAMIC)

    ctx.mat_cache.materials[name] = mat

    return &ctx.mat_cache.materials[name]
}

mats_bind_descriptor :: proc(cmd: vk.CommandBuffer,
                             material: ^Material,
                             pass: PassType,
                             set: int,
                             dynamics: []u32 = {}) {

    vk.CmdBindDescriptorSets(cmd, .GRAPHICS,
                             material.passes[pass].pipeline_layout, u32(set),
                             1, &material.descriptors[pass][set],
                             u32(len(dynamics)), raw_data(dynamics))

}

mats_destroy :: proc { mats_destroy_shader_effect, mats_destroy_material }

mats_destroy_shader_effect :: proc(device: vk.Device, effect: ^ShaderEffect) {
    if effect == nil do return
    if effect.pipeline != 0 do vk.DestroyPipeline(device, effect.pipeline, nil)
    if effect.pipeline_layout != 0 do vk.DestroyPipelineLayout(device, effect.pipeline_layout, nil)
    for layout in effect.desc_layouts do vk.DestroyDescriptorSetLayout(device, layout, nil)
}

mats_destroy_material :: proc(device: vk.Device, material: ^Material) {
    buffers_destroy(material.uniforms)
}

@private
read_spirv :: proc(path: string) -> []u8 {
    log.debugf("Loading SPIRV %s", path)
    data, success := os.read_entire_file(path)
    return data
}
