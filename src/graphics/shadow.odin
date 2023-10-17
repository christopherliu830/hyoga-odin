package graphics

import la "core:math/linalg"
import vk "vendor:vulkan"
import "pkgs:vma"

import "builders"

Shadow :: struct{
    view: mat4,
    proj: mat4,
}

ShadowContext :: struct{
    // Pipeline
    mat: ^Material,

    // Uniforms
    data: []Shadow,
    buffer: Buffer,

    // Rendering
    images: []Image,
    framebuffers: []vk.Framebuffer,
    render_pass: vk.RenderPass,
    
    // Constants
    frame_count: int,
    extent: vk.Extent2D,
}

shadow_create_shadow_pass :: proc(device: vk.Device) ->
(render_pass: vk.RenderPass) {
    depth_attachment := vk.AttachmentDescription {
        format         = .D32_SFLOAT,
        flags		   = {},
        samples        = { ._1 },
        loadOp         = .CLEAR,
        storeOp        = .STORE,
        stencilLoadOp  = .DONT_CARE,
        stencilStoreOp = .DONT_CARE,
        initialLayout  = .UNDEFINED,
        finalLayout    = .DEPTH_STENCIL_READ_ONLY_OPTIMAL,
    }
    
    depth_attachment_ref := vk.AttachmentReference  {
        attachment = 0,
        layout = .DEPTH_STENCIL_ATTACHMENT_OPTIMAL,
    }

    subpass := vk.SubpassDescription {
        pipelineBindPoint       = .GRAPHICS,
        flags 					= {},
        colorAttachmentCount 	= 0,
        pColorAttachments 		= nil,
        inputAttachmentCount	= 0,
        pInputAttachments		= nil,
        pResolveAttachments		= nil,
        preserveAttachmentCount	= 0,
        pPreserveAttachments	= nil,
        pDepthStencilAttachment = &depth_attachment_ref,
    }

    depth_dependency := vk.SubpassDependency {
        srcSubpass    = vk.SUBPASS_EXTERNAL,
        dstSubpass    = .0,
        srcStageMask  = { .EARLY_FRAGMENT_TESTS, .LATE_FRAGMENT_TESTS },
        srcAccessMask = {},
        dstStageMask  = { .EARLY_FRAGMENT_TESTS, .LATE_FRAGMENT_TESTS },
        dstAccessMask = { .DEPTH_STENCIL_ATTACHMENT_WRITE },
    }

    render_pass_create_info: vk.RenderPassCreateInfo = {
        sType           = .RENDER_PASS_CREATE_INFO,
        flags 			= {},
        attachmentCount = 1,
        pAttachments    = &depth_attachment,
        subpassCount    = 1,
        pSubpasses      = &subpass,
        dependencyCount = 1,
        pDependencies   = &depth_dependency,
    }

    result := vk.CreateRenderPass(device, &render_pass_create_info, nil, &render_pass)
    assert(result == .SUCCESS)

    return render_pass
}

shadow_init :: proc(device: vk.Device, 
                    ctx: ^RenderContext,
                    frame_count: int,
                    extent: vk.Extent2D) -> 
ShadowContext{
    extent3D := vk.Extent3D{
        extent.width, extent.height, 1,
    }
    render_pass := 
            shadow_create_shadow_pass(device)
    shadows := ShadowContext{ nil, nil, buffers_create_dubo(Shadow, frame_count), // should be light_count * frame_count?
            make([]Image, frame_count),
            make([]vk.Framebuffer, frame_count),
            render_pass,
            frame_count,
            extent,
        }
    shadow_init_mat(device, &shadows, &ctx.mat_cache, ctx.descriptor_pool)
    shadow_fill_buffer(device, &shadows, &ctx.scene, &LightData{}, frame_count)
    shadow_init_images(device, &shadows, frame_count, extent3D)

    return shadows
}

shadow_init_images :: proc(device: vk.Device, shadows: ^ShadowContext, frame_count: int, extent: vk.Extent3D) {
    for i in 0..<frame_count {
        shadows.images[i] = 
            buffers_create_image(device, extent)
        shadows.framebuffers[i] = 
            builders.create_framebuffer(device, 
                shadows.render_pass, 
                &shadows.images[i].view,
                extent,
            )
    }

    return
}

shadow_init_mat :: proc(device: vk.Device, shadows: ^ShadowContext, mat_cache: ^MaterialCache, descriptor_pool: vk.DescriptorPool){
    shadow_effect := mats_create_shadow_effect(device, mat_cache, shadows.render_pass)
    assert(shadow_effect != nil)
    shadows.mat = mats_create(mat_cache, "default_shadow", device, descriptor_pool, shadow_effect)
    assert(shadows.mat != nil)
}

shadow_fill_buffer :: proc(device: vk.Device, shadows: ^ShadowContext, scene: ^Scene, lights: ^LightData, frame_count: int) {
    builders.bind_descriptor_set(device, 
                                {shadows.buffer.handle, 0, size_of(Shadow)},
                                .UNIFORM_BUFFER_DYNAMIC,
                                shadows.mat.descriptors[0], 0)
    builders.bind_descriptor_set(device, 
                                {scene.object_ubos.handle, 0, size_of(mat4)},
                                .UNIFORM_BUFFER_DYNAMIC,
                                shadows.mat.descriptors[3], 0)


    shadow := Shadow {
        la.matrix4_look_at(
            vec3{0, 2, 0},
            vec3{0, 0, 0},
            vec3{0, 0, -1},
        ),
        la.matrix_ortho3d_f32(-5, 5, -5, 5, 0.1, 5),
    }
    for i in 0..<frame_count { buffers_write(shadows.buffer, &shadow, Shadow, i)}
}

shadow_destroy :: proc(device: vk.Device, shadows: ^ShadowContext){
    for i in 0..<shadows.frame_count {
        vk.DestroyFramebuffer(device, shadows.framebuffers[i], nil)
        buffers_destroy_image(device, shadows.images[i])
    }
    vk.DestroyRenderPass(device, shadows.render_pass, nil)
    vk.DestroyPipeline(device, shadows.mat.effect.pipeline, nil)
    buffers_destroy(shadows.buffer)
}

shadow_draw_shadow :: proc(scene: ^Scene,
                            cmd: vk.CommandBuffer,
                            frame_num: int,
                            object_num: int,
                            shadow_mat: ^Material) 
{
    vertex_buffer := scene.vertex_buffers[object_num]
    index_buffer := scene.index_buffers[object_num]

    model := scene.offsets(object_num, scene.time, scene.model[object_num])
    buffers_write(scene.object_ubos,
                  &model,
                  mat4,
                  frame_num * OBJECT_COUNT + object_num)	
                  
    // bind object uniforms
    dynamic_offset := u32(size_of(mat4) * object_num)
    vk.CmdBindDescriptorSets(cmd, .GRAPHICS,
                             shadow_mat.effect.pipeline_layout, 3,
                             1, &shadow_mat.descriptors[3],
                             1, &dynamic_offset)

    offset : vk.DeviceSize = 0
    vk.CmdBindVertexBuffers(cmd, 0, 1, &vertex_buffer.handle, &offset)
    vk.CmdBindIndexBuffer(cmd, index_buffer.handle, 0, .UINT16)
    vk.CmdDrawIndexed(cmd, u32(index_buffer.size / size_of(u16)), 1, 0, 0, 0)
}

shadow_exec_shadow_pass :: proc(scene: ^Scene, cmd: vk.CommandBuffer, extent: vk.Extent2D, frame: int, obj_count: int){
    clear_value := vk.ClearValue{
        depthStencil = {depth = 1.0},
    }
    assert(frame < scene.shadow_context.frame_count)

    rp_begin: vk.RenderPassBeginInfo = {
        sType = .RENDER_PASS_BEGIN_INFO,
        renderPass = scene.shadow_context.render_pass,
        framebuffer = scene.shadow_context.framebuffers[frame],
        renderArea = {extent = extent},
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

    vk.CmdBindPipeline(cmd, .GRAPHICS, scene.shadow_context.mat.effect.pipeline)

    offset := size_of(Shadow) * u32(frame)

    vk.CmdBindDescriptorSets(cmd, .GRAPHICS,
                             scene.shadow_context.mat.effect.pipeline_layout, 0,
                             1, &scene.shadow_context.mat.descriptors[0],
                             1, &offset)
    
    for i in 0..<obj_count {
        shadow_draw_shadow(scene, cmd, frame, i, scene.shadow_context.mat)
    }
    

    vk.CmdEndRenderPass(cmd)
}