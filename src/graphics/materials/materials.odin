package materials

import "core:fmt"
import "core:log"
import "core:os"

import vk "vendor:vulkan"

import "../builders"

VertexLayout :: struct {
    bindings: []vk.VertexInputBindingDescription,
    attributes: []vk.VertexInputAttributeDescription,
}

ShaderEffect :: struct {
    pipeline_layout: vk.PipelineLayout,
    vertex_layout:   VertexLayout,
    desc_layouts:    [4]vk.DescriptorSetLayout,
    shader_stages:   [2]struct {
        module: vk.ShaderModule,
        stage:  vk.ShaderStageFlag,
    }
}

ShaderPass :: struct {
    effect:           ^ShaderEffect,
    pipeline:         vk.Pipeline,
}

Material :: struct {
    pass: ^ShaderPass,
    descriptors: [4]vk.DescriptorSet,
}

create_shader_effect :: proc(device:         vk.Device,
                             desc_layout:    LayoutType,
                             vertex_layout:  VertexLayout,
                             vert_path:      string,
                             frag_path:      string) ->
(effect: ShaderEffect) {

    vert := builders.create_shader_module(device, read_spirv(vert_path))
    frag := builders.create_shader_module(device, read_spirv(frag_path))

    effect.shader_stages[0] = {
        module = vert,
        stage = .VERTEX,
    }

    effect.shader_stages[1] = {
        module = frag,
        stage = .FRAGMENT,
    }

    effect.desc_layouts = create_descriptor_layout(device, desc_layout)

    effect.pipeline_layout = builders.create_pipeline_layout(device, effect.desc_layouts[:])

    effect.vertex_layout = vertex_layout

    return effect
}

create_shader_pass :: proc(device:  vk.Device,
                           render_pass:  vk.RenderPass,
                           effect:       ^ShaderEffect) ->
(pass: ShaderPass) {

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
    pass.pipeline = builders.create_pipeline(device,
                                             layout = effect.pipeline_layout,
                                             render_pass = render_pass,
                                             vertex_input = &vertex_input,
                                             stages = shader_stages)

    pass.effect = effect

    return pass
}

create :: proc(device: vk.Device, pool: vk.DescriptorPool, shader_pass: ^ShaderPass) ->
(mat: Material) {
    assert(shader_pass.effect != nil)

    mat.descriptors = builders.allocate_descriptor_set(device, pool, shader_pass.effect.desc_layouts[:])
    mat.pass = shader_pass
    return mat
}

@private
read_spirv :: proc(path: string) -> []u8 {
    log.debugf("Loading SPIRV %s", path)
    data, success := os.read_entire_file(path)
    return data
}

destroy :: proc { destroy_shader_effect, destroy_shader_pass }

destroy_shader_effect :: proc(device: vk.Device, effect: ShaderEffect) {
    vk.DestroyPipelineLayout(device, effect.pipeline_layout, nil)

    for layout in effect.desc_layouts {
        vk.DestroyDescriptorSetLayout(device, layout, nil)
    }

    for stage in effect.shader_stages {
        vk.DestroyShaderModule(device, stage.module, nil)
    }
}

destroy_shader_pass :: proc(device: vk.Device, pass: ShaderPass) {
    vk.DestroyPipeline(device, pass.pipeline, nil)
}

