package graphics

import la "core:math/linalg"
import vk "vendor:vulkan"
import "pkgs:vma"

import "builders"

Shadow :: struct {
    view: mat4,
    proj: mat4,
}

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
    pass.images = make([]Image, image_count)
    pass.framebuffers = make([]vk.Framebuffer, image_count)
    pass.extent = extent

    for i in 0..<image_count {
        pass.images[i] = buffers_create_image(device, extent, { .SAMPLED, .DEPTH_STENCIL_ATTACHMENT })
        pass.framebuffers[i] = builders.create_framebuffer(device, pass.pass, { pass.images[i].view }, extent)
    }

    return pass
}

shadow_draw_object :: proc(scene:          ^Scene,
                           cmd:            vk.CommandBuffer,
                           frame_num:      int,
                           object_num:     int,
                           last_material:  ^^Material)
{
    vertex_buffer := scene.vertex_buffers[object_num]
    index_buffer := scene.index_buffers[object_num]
    material := scene.materials[object_num]

    if material.passes[.SHADOW] == nil do return

    if last_material^ == nil {
        mats_bind_descriptor(cmd, material, .SHADOW, 0, { size_of(Shadow) * u32(frame_num) })
    }

    if last_material^ != material {
        vk.CmdBindPipeline(cmd, .GRAPHICS, material.passes[.SHADOW].pipeline)
    }
                  
    dynamic_offset := u32(size_of(mat4) * object_num)
    mats_bind_descriptor(cmd, material, .SHADOW, 3, { dynamic_offset })

    offset : vk.DeviceSize = 0
    vk.CmdBindVertexBuffers(cmd, 0, 1, &vertex_buffer.handle, &offset)
    vk.CmdBindIndexBuffer(cmd, index_buffer.handle, 0, .UINT16)
    vk.CmdDrawIndexed(cmd, u32(index_buffer.size / size_of(u16)), 1, 0, 0, 0)

    last_material^ = material
}


shadow_exec_shadow_pass :: proc(scene: ^Scene, perframe: ^Perframe, pass: PassInfo) {
    clear_value := vk.ClearValue { depthStencil = { depth = 1.0 }}

    index := perframe.index
    cmd := perframe.command_buffer
    extent := vk.Extent2D { pass.extent.width, pass.extent.height }

    rp_begin: vk.RenderPassBeginInfo = {
        sType = .RENDER_PASS_BEGIN_INFO,
        renderPass = pass.pass,
        framebuffer = pass.framebuffers[index],
        renderArea = { extent = extent },
        clearValueCount = 1,
        pClearValues = &clear_value,
    }

    vk.CmdBeginRenderPass(cmd, &rp_begin, vk.SubpassContents.INLINE)

    viewport: vk.Viewport = {
        width    = f32(extent.width),
        height   = f32(extent.height),
        minDepth = 0, maxDepth = 1,
    }
    vk.CmdSetViewport(cmd, 0, 1, &viewport)

    scissor: vk.Rect2D = { extent = extent }
    vk.CmdSetScissor(cmd, 0, 1, &scissor)

    last_material: ^Material = nil
    for i in 0..<OBJECT_COUNT do shadow_draw_object(scene, cmd, perframe.index, i, &last_material)

    vk.CmdEndRenderPass(cmd)
}

