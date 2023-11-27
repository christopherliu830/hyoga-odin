package graphics

import la "core:math/linalg"
import vk "vendor:vulkan"
import "pkgs:vma"

import "builders"

SHADOW_MAP_WIDTH :: 1024
SHADOW_MAP_HEIGHT :: 1024

shadow_create_render_pass :: proc(device:       vk.Device,
                                  image_count:  int) ->
(pass: PassInfo) {
    attachment, ref := builders.create_depth_attachment(0)
	attachment.finalLayout = .READ_ONLY_OPTIMAL;
    
    subpass := vk.SubpassDescription {
        pipelineBindPoint       = .GRAPHICS,
        flags 					= {},
        pDepthStencilAttachment = &ref,
    }

    dependency := vk.SubpassDependency {
        srcSubpass    = vk.SUBPASS_EXTERNAL,
        dstSubpass    = .0,
        srcStageMask  = { .EARLY_FRAGMENT_TESTS, .LATE_FRAGMENT_TESTS },
        srcAccessMask = {},
        dstStageMask  = { .EARLY_FRAGMENT_TESTS, .LATE_FRAGMENT_TESTS },
        dstAccessMask = { .DEPTH_STENCIL_ATTACHMENT_WRITE },
    }

    extent := vk.Extent3D { SHADOW_MAP_WIDTH, SHADOW_MAP_HEIGHT, 1 }
    
    pass.pass = builders.create_render_pass(device, { attachment }, { subpass }, { dependency })
    pass.type = .SHADOW

    pass.images = make([]Image, image_count)
    pass.framebuffers = make([]vk.Framebuffer, image_count)
    for i in 0..<image_count {
        pass.images[i] = buffers_create_image(.D32_SFLOAT, extent, { .SAMPLED, .DEPTH_STENCIL_ATTACHMENT })
        pass.framebuffers[i] = builders.create_framebuffer(device, pass.pass, { pass.images[i].view }, extent)
    }

    pass.clear_values = {{ depthStencil = { depth = 1 }}, {}}

    pass.extent = extent

    pass.in_layouts = layout_get_pass_resources(.SHADOW)

    pass.mat_buffer = buffers_create_tbuffer(MaterialUBO, UNIFORM_BUFFER_SIZE, .UNIFORM_DYNAMIC)
    // pass.mat_descriptor = descriptors_get(pass.in_layouts.descriptors[MATERIAL_SET])

    pass.object_buffer = buffers_create_tbuffer(ObjectUBO, UNIFORM_BUFFER_SIZE, .UNIFORM_DYNAMIC)
    // pass.object_descriptor = descriptors_get(pass.in_layouts.descriptors[OBJECT_SET])

    return pass
}

shadow_prepare :: proc(scene: ^Scene, pass: ^PassInfo) {

    rd := DEFAULT_RESOURCES[.SHADOW]

    descriptors : [4]vk.DescriptorSet

    for bindings, set_num in rd {
        if len(bindings) == 0 do continue 
        descriptors[set_num] = descriptors_get(pass.in_layouts.descriptors[set_num])
        desc := descriptors[set_num]
        for resource, binding_num in bindings {
            buffer := transmute(^Buffer)scene_find_resource(scene, pass, resource.name)
            descriptors_bind(desc, resource.name, rd, buffer^)
        }
    }

    for i in 0..<OBJECT_COUNT do scene_prepare_obj(scene, pass, i)

    pass.descriptors = descriptors
}


shadow_draw_object :: proc(scene: ^Scene,
                           pass: ^PassInfo,
                           object_num: int,
                           last_material:  ^^ShaderEffect)
{
    frame_num := get_frame().index
    cmd := get_frame().command_buffer
    device := get_context().device

    object := &pass.renderables[object_num]

    // BIND PER MATERIAL DATA
    if object.prog != last_material^ {
        vk.CmdBindPipeline(cmd, .GRAPHICS, object.prog.pipeline)
    }

    last_material^ = object.prog

    dynamic_offset := u32(object.object_offset)
    builders.cmd_bind_descriptor_set(cmd, pass.in_layouts.pipeline, OBJECT_SET, { pass.descriptors[OBJECT_SET] }, { dynamic_offset })
                  
    offset : vk.DeviceSize = 0

    vk.CmdBindVertexBuffers(cmd, 0, 1, &object.vertex_buffer.handle, &offset)
    vk.CmdBindIndexBuffer(cmd, object.index_buffer.handle, 0, .UINT16)
    vk.CmdDrawIndexed(cmd, u32(object.index_buffer.size / size_of(u16)), 1, 0, 0, 0)
}

shadow_exec_shadow_pass :: proc(scene: ^Scene, perframe: ^Perframe, pass: ^PassInfo) {
    begin_render_pass(pass)

    cmd := perframe.command_buffer
    frame_num := g_frame_index

    builders.cmd_bind_descriptor_set(cmd, pass.in_layouts.pipeline,
                                     GLOBAL_SET, { pass.descriptors[GLOBAL_SET] },
                                    { u32(size_of(Camera) * frame_num)})

    last_material: ^ShaderEffect = nil
    for i in 0..<OBJECT_COUNT do shadow_draw_object(scene, pass, i, &last_material)

    end_render_pass()
}

