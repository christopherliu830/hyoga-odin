package graphics

import "core:fmt"
import "core:log"
import "core:os"
import "core:mem"

import la "core:math/linalg"
import vk "vendor:vulkan"

import "builders"


ShaderFile :: struct {
    path: string,
    stage: vk.ShaderStageFlag
}

ShaderStage :: struct{
    module:  vk.ShaderModule,
    stage:   vk.ShaderStageFlag,
}

ShaderEffectIn :: struct {
    name:         string,
    pass_type:    PassType,
    paths:        []ShaderFile
}

ShaderEffect :: struct {
    type:             PassType,
    pipeline:         vk.Pipeline,
}

PassType :: enum {
    SHADOW,
    FORWARD,
}

Material :: struct {
    passes:      [PassType]^ShaderEffect,
    descriptors: [PassType]vk.DescriptorSet,
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

mats_create_shader_effect :: proc(args: ShaderEffectIn) ->
(^ShaderEffect) {
    effect: ShaderEffect

    ctx := get_context()
    device := ctx.device
    cache := ctx.mat_cache
    name := args.name
    paths := args.paths
    pass := ctx.passes[args.pass_type]

    if name in cache.effects {
        return &cache.effects[name]
    }

    stage_count := len(args.paths)

    assert(stage_count <= MAX_SHADER_STAGES)

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

    bindings := VERTEX_BINDINGS
    attributes := VERTEX_ATTRIBUTES

    vertex_input := builders.get_vertex_input(bindings[args.pass_type], attributes[args.pass_type])

    effect.type = args.pass_type

    effect.pipeline = builders.create_pipeline(device,
                                               layout = pass.in_layouts.pipeline,
                                               render_pass = pass.pass,
                                               vertex_input = &vertex_input,
                                               stages = shader_stages)

    cache.effects[name] = effect

    return &cache.effects[name]
}

mats_create :: proc(name: string,
                    effects: []^ShaderEffect) ->
(^Material) {

    cache := &get_context().mat_cache
    device := get_context().device
    passes := &get_context().passes

    if name in cache.materials do return &cache.materials[name]

    mat: Material

    for effect in effects {
        pass_type := effect.type
        pass := passes[pass_type].in_layouts
        assert(mat.passes[pass_type] == nil)

        mat.passes[pass_type] = effect
        descriptor_layouts := passes[pass_type].in_layouts.descriptors
        mat.descriptors[pass_type] = descriptors_get(descriptor_layouts[MATERIAL_SET])
    }

    cache.materials[name] = mat

    return &cache.materials[name]
}

mats_destroy :: proc { mats_destroy_shader_effect, mats_destroy_material }

mats_destroy_shader_effect :: proc(device: vk.Device, effect: ^ShaderEffect) {
    if effect == nil do return
    if effect.pipeline != 0 do vk.DestroyPipeline(device, effect.pipeline, nil)
}

mats_destroy_material :: proc(device: vk.Device, material: ^Material) {
}

@private
read_spirv :: proc(path: string) -> []u8 {
    log.debugf("Loading SPIRV %s", path)
    data, success := os.read_entire_file(path)
    return data
}
