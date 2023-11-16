package graphics

import "builders"
import vk "vendor:vulkan"

Perframe :: struct {
    index:           int,
    in_flight_fence: vk.Fence,
    command_pool:    vk.CommandPool,
    command_buffer:  vk.CommandBuffer,
    descriptor_pool: vk.DescriptorPool,
    image_available: ^SemaphoreLink,
    render_finished: vk.Semaphore,
}

create_perframes :: proc(device: vk.Device, count: int) ->
(perframes: []Perframe) {
    perframes = make([]Perframe, count)

    for _, i in perframes {
        p := &perframes[i]
        p.index = i
        p.image_available = nil
        p.render_finished = builders.create_semaphore(device)
        p.in_flight_fence = builders.create_fence(device, { .SIGNALED })
        p.command_pool    = builders.create_command_pool(device, { .TRANSIENT, .RESET_COMMAND_BUFFER })
        p.command_buffer  = builders.create_command_buffer(device, p.command_pool)
    }

    return perframes
}

cleanup_perframe :: proc(device: vk.Device, perframe: Perframe) {
    vk.DestroyCommandPool(device, perframe.command_pool, nil)
    vk.DestroyFence(device, perframe.in_flight_fence, nil)
    vk.DestroySemaphore(device, perframe.render_finished, nil)
}

begin_render_pass :: proc(perframe: ^Perframe, pass: PassInfo) {
    index  := perframe.index
    cmd    := perframe.command_buffer
    clear_values := pass.clear_values
    extent := vk.Extent2D { pass.extent.width, pass.extent.height }

    rp_begin: vk.RenderPassBeginInfo = {
        sType = .RENDER_PASS_BEGIN_INFO,
        renderPass = pass.pass,
        framebuffer = pass.framebuffers[index],
        renderArea = { extent = extent },
        clearValueCount = u32(len(clear_values)),
        pClearValues = raw_data(clear_values[:]),
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
}

end_render_pass :: proc(perframe: ^Perframe) {
    vk.CmdEndRenderPass(perframe.command_buffer)
}
