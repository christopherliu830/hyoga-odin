package graphics

import "core:fmt"
import "core:log"
import "core:runtime"
import "core:c"
import la "core:math/linalg"

import "vendor:glfw"
import vk "vendor:vulkan"
import "pkgs:vma"

import "materials"
import "builders"
import "common"

RenderContext :: struct {
    window:              glfw.WindowHandle,
    instance:            vk.Instance,
    device:              vk.Device,
    gpu:                 vk.PhysicalDevice,
    surface:             vk.SurfaceKHR,

    // Queues
    queues:              [QueueFamily]vk.Queue,
    queue_indices:       [QueueFamily]int,

    // Nested structs    
    perframes:           []Perframe,
    swapchain:           Swapchain,
    depth_image:         Image,
    render_pass:         vk.RenderPass,
    framebuffers:        []vk.Framebuffer,

    // Handles
    descriptor_pool:     vk.DescriptorPool,

    render_data:         RenderData,
    camera_data:         CameraData,
    unlit_effect:        materials.ShaderEffect,
    unlit_pass:          materials.ShaderPass,
    unlit_mat:           materials.Material,

    debug_messenger:     vk.DebugUtilsMessengerEXT,
    window_needs_resize: bool,
}

WINDOW_HEIGHT :: 720
WINDOW_WIDTH :: 1280
WINDOW_TITLE :: "Hyoga"
OBJECT_COUNT :: 1

@private
g_time : f32 = 0

update :: proc(ctx: ^RenderContext) -> bool {
    index: u32
    result: vk.Result

    result = acquire_image(ctx, &index)
    if result == .SUBOPTIMAL_KHR || result == .ERROR_OUT_OF_DATE_KHR {
        resize(ctx)
    }

    result = draw(ctx, index)

    result = present_image(ctx, index)
    if result == .SUBOPTIMAL_KHR || result == .ERROR_OUT_OF_DATE_KHR {
        resize(ctx)
    }

    if ctx.window_needs_resize do resize(ctx)

    return result != .SUCCESS
}

acquire_image :: proc(using ctx: ^RenderContext, image: ^u32) -> vk.Result {
    signaled_semaphore := perframes[image^].image_available

    result := vk.AcquireNextImageKHR(
        device,
        swapchain.handle,
        max(u64),
        perframes[image^].image_available,
        0,
        image,
    )

    if (result != .SUCCESS && result != .SUBOPTIMAL_KHR) {
        return result
    }

    // If we have outstanding fences for this swapchain image, wait for them to complete first.
    // After begin frame returns, it is safe to reuse or delete resources which
    // were used previously.
    //
    // We wait for fences which completes N frames earlier, so we do not stall,
    // waiting for all GPU work to complete before this returns.
    // Normally, this doesn't really block at all,
    // since we're waiting for old frames to have been completed, but just in case.

    if perframes[image^].in_flight_fence != 0 {
        fences := []vk.Fence{perframes[image^].in_flight_fence}
        vk.WaitForFences(device, 1, raw_data(fences), true, max(u64)) or_return
        vk.ResetFences(device, 1, raw_data(fences)) or_return
    }

    if perframes[image^].command_pool != 0 {
        vk.ResetCommandPool(device, perframes[image^].command_pool, {}) or_return
    }

    perframes[image^].image_available = signaled_semaphore

    return .SUCCESS
}

draw :: proc(this: ^RenderContext, index: u32) -> vk.Result {
    g_time += 1

    cmd := this.perframes[index].command_buffer

    begin_info := vk.CommandBufferBeginInfo {
        sType = .COMMAND_BUFFER_BEGIN_INFO,
        flags = {.ONE_TIME_SUBMIT},
    }

    vk.BeginCommandBuffer(cmd, &begin_info) or_return

    
    clear_values := []vk.ClearValue {
        { color = { float32 = [4]f32{ 0.01, 0.01, 0.033, 1.0 }}},
        { depthStencil = { depth = 1 }},
    }

    rp_begin: vk.RenderPassBeginInfo = {
        sType = .RENDER_PASS_BEGIN_INFO,
        renderPass = this.render_pass,
        framebuffer = this.framebuffers[index],
        renderArea = {extent = this.swapchain.extent},
        clearValueCount = u32(len(clear_values)),
        pClearValues = raw_data(clear_values),
    }

    vk.CmdBeginRenderPass(cmd, &rp_begin, vk.SubpassContents.INLINE)

    viewport: vk.Viewport = {
        width    = f32(this.swapchain.extent.width),
        height   = f32(this.swapchain.extent.height),
        minDepth = 0, maxDepth = 1,
    }
    vk.CmdSetViewport(cmd, 0, 1, &viewport)

    scissor: vk.Rect2D = { extent = this.swapchain.extent }
    vk.CmdSetScissor(cmd, 0, 1, &scissor)

    camera: CameraData

    camera.view = la.matrix4_look_at(
        la.Vector3f32 {5, 5, 5},
        la.Vector3f32 {0, 0, 0},
        la.Vector3f32 {0, 0, 1},
    )

    camera.proj = la.matrix4_perspective_f32(45,
                                             f32(this.swapchain.extent.width) /
                                             f32(this.swapchain.extent.height),
                                             0.1,
                                             100)
    camera.proj[1][1] *= -1

    cam_buffer := buffers_to_mtptr(this.render_data.camera_ubo, CameraData)
    cam_buffer[index] = camera

    last_material : ^materials.Material = nil

    for i in 0..<OBJECT_COUNT {
        transform := this.render_data.model[i] * la.matrix4_rotate_f32(f32(g_time) / 1000, { 0, 0, 1 })

        object_buffer := buffers_to_mtptr(this.render_data.object_ubo, la.Matrix4f32)
        object_buffer[i] = transform

        material := this.render_data.materials[i]
        vertex_buffer := this.render_data.vertex_buffers[i]
        index_buffer := this.render_data.index_buffers[i]

        if last_material == nil {
            offset := size_of(CameraData) * index
            vk.CmdBindDescriptorSets(cmd, .GRAPHICS,
                                     material.pass.pipeline_layout, 0,
                                     1, &material.descriptors[0],
                                     1, &offset)
        }

        if material != last_material {
            vk.CmdBindPipeline(cmd, .GRAPHICS, material.pass.pipeline)

            vk.CmdBindDescriptorSets(cmd, .GRAPHICS,
                               material.pass.pipeline_layout, 2,
                               1, &material.descriptors[2],
                               0, nil)
        }

        dynamic_offset := u32(size_of(la.Matrix4f32) * i)
        vk.CmdBindDescriptorSets(cmd, .GRAPHICS,
                                 material.pass.pipeline_layout, 3,
                                 1, &material.descriptors[3],
                                 1, &dynamic_offset)

        offset : vk.DeviceSize = 0
        vk.CmdBindVertexBuffers(cmd, 0, 1, &vertex_buffer.handle, &offset)
        vk.CmdBindIndexBuffer(cmd, index_buffer.handle, 0, .UINT16)
        vk.CmdDrawIndexed(cmd, u32(index_buffer.size / size_of(u16)), 1, 0, 0, 0)
    }
    
    vk.CmdEndRenderPass(cmd)

    vk.EndCommandBuffer(cmd) or_return

    wait_stage: vk.PipelineStageFlags = {.COLOR_ATTACHMENT_OUTPUT}

    submit_info: vk.SubmitInfo = {
        sType                = .SUBMIT_INFO,
        commandBufferCount   = 1,
        pCommandBuffers      = &cmd,
        waitSemaphoreCount   = 1,
        pWaitSemaphores      = &this.perframes[index].image_available,
        pWaitDstStageMask    = &wait_stage,
        signalSemaphoreCount = 1,
        pSignalSemaphores    = &this.perframes[index].render_finished,
    }

    vk.QueueSubmit(this.queues[.GRAPHICS], 1, &submit_info, this.perframes[index].in_flight_fence)
    return .SUCCESS
}

present_image :: proc(using ctx: ^RenderContext, index: u32) -> vk.Result {
    i := index

    present_info: vk.PresentInfoKHR = {
        sType              = .PRESENT_INFO_KHR,
        swapchainCount     = 1,
        pSwapchains        = &swapchain.handle,
        pImageIndices      = &i,
        waitSemaphoreCount = 1,
        pWaitSemaphores    = &perframes[index].render_finished,
    }

    return vk.QueuePresentKHR(queues[.PRESENT], &present_info)
}

resize :: proc(this: ^RenderContext) -> bool {

    surface_properties: vk.SurfaceCapabilitiesKHR
    vk.GetPhysicalDeviceSurfaceCapabilitiesKHR(this.gpu, this.surface, &surface_properties)
    if surface_properties.currentExtent == this.swapchain.extent do return false

    for x, y : i32; x == 0 && y == 0; {
        x, y = glfw.GetFramebufferSize(this.window)
        glfw.WaitEvents()
    }

    swapchain_destroy_framebuffers(this.device, this.framebuffers)

    this.swapchain = swapchain_create(this.device,
                                      this.gpu, 
                                      this.surface, 
                                      this.queue_indices,
                                      this.swapchain.handle)

    this.framebuffers = swapchain_create_framebuffers(this.device,
                                                      this.render_pass,
                                                      this.swapchain,
                                                      this.depth_image)

    this.window_needs_resize = false

    return true
}

init :: proc(this: ^RenderContext) {
    this.window = init_window(this)

    // Vulkan does not come loaded into Odin by default, 
    // so we need to begin by loading Vulkan's functions at runtime.
    // This can be achieved using glfw's GetInstanceProcAddress function.
    // the non-overloaded function is used to leverage auto_cast and avoid
    // funky rawptr type stuff.
    vk.load_proc_addresses_global(auto_cast glfw.GetInstanceProcAddress)
    
    extensions: [dynamic]cstring
    defer delete(extensions)
    append(&extensions, ..glfw.GetRequiredInstanceExtensions())
    append(&extensions, vk.EXT_DEBUG_UTILS_EXTENSION_NAME)
    layers := []cstring { "VK_LAYER_KHRONOS_validation" }
    this.instance = builders.create_instance(extensions[:], layers)

    // Load the rest of Vulkan's functions.
    vk.load_proc_addresses(this.instance)
    
    this.debug_messenger = builders.create_debug_utils_messenger(this.instance, debug_messenger_callback)

    this.gpu, this.surface, this.queue_indices = gpu_create(this.instance, this.window)

    this.device, this.queues = device_create(this.gpu, this.queue_indices)

    this.swapchain = swapchain_create(this.device,
                                      this.gpu, 
                                      this.surface, 
                                      this.queue_indices)

    this.render_pass = builders.create_render_pass(this.device,
                                                   this.swapchain.format.format) 

    this.perframes = create_perframes(this.device, len(this.swapchain.images))

    buffers_init({
        physicalDevice = this.gpu,
        instance = this.instance,
        device = this.device,
        vulkanApiVersion = vk.API_VERSION_1_3,
    })

    buffers_init_staging(this.device, this.queues[.GRAPHICS])

    this.descriptor_pool = descriptors_create_pool(this.device, 1000)

    this.render_data = init_render_data(this)
    
    extent := vk.Extent3D {
        this.swapchain.extent.width, 
        this.swapchain.extent.height,
        1,
    }
    this.depth_image = buffers_create_image(this.device, extent)

    this.framebuffers = swapchain_create_framebuffers(this.device,
                                                      this.render_pass,
                                                      this.swapchain,
                                                      this.depth_image)
}

init_window :: proc(this: ^RenderContext) -> glfw.WindowHandle {
    glfw.SetErrorCallback(glfw_error_callback)
    glfw.Init()

    glfw.WindowHint(glfw.CLIENT_API, glfw.NO_API)

    window := glfw.CreateWindow(WINDOW_WIDTH, WINDOW_HEIGHT, WINDOW_TITLE, nil, nil)
    glfw.SetWindowUserPointer(window, this);

    glfw.SetWindowSizeCallback(window, proc "c" (win: glfw.WindowHandle, w, h: c.int) {
        ctx := cast(^RenderContext)glfw.GetWindowUserPointer(win)
        ctx.window_needs_resize = true
    })

    if (!glfw.VulkanSupported()) {
        panic("Vulkan not supported!")
    }

    return window;
}

create_perframes :: proc(device: vk.Device, count: int) ->
(perframes: []Perframe) {
    perframes = make([]Perframe, count)

    for _, i in perframes {
        p := &perframes[i]
        p.index = uint(i)
        p.image_available = builders.create_semaphore(device)
        p.render_finished = builders.create_semaphore(device)
        p.in_flight_fence = builders.create_fence(device, { .SIGNALED })
        p.command_pool    = builders.create_command_pool(device, { .TRANSIENT, .RESET_COMMAND_BUFFER })
        p.command_buffer  = builders.create_command_buffer(device, p.command_pool)
    }

    return perframes
}

init_render_data :: proc(this: ^RenderContext) -> (render_data: RenderData) {
    render_data.camera_ubo = buffers_create(size_of(CameraData) * int(this.swapchain.image_count), buffers_default_flags(.UNIFORM_DYNAMIC))
    render_data.object_ubo = buffers_create(size_of(la.Matrix4f32) * OBJECT_COUNT, buffers_default_flags(.UNIFORM_DYNAMIC))

    render_data.cube = create_cube()
    render_data.tetra = create_tetrahedron()

    cube := create_cube()
    
    this.unlit_effect = materials.create_shader_effect(this.device,
                                                   .DEFAULT,
                                                   "assets/shaders/shader.vert.spv",
                                                   "assets/shaders/shader.frag.spv")

    this.unlit_pass = materials.create_shader_pass(this.device, this.render_pass, &this.unlit_effect)
    this.unlit_mat = materials.create_material(this.device, this.descriptor_pool, &this.unlit_pass)

    builders.bind_descriptor_set(this.device,
                                 { render_data.camera_ubo.handle, 0, size_of(CameraData) },
                                 .UNIFORM_BUFFER_DYNAMIC, 
                                 this.unlit_mat.descriptors[0])

    builders.bind_descriptor_set(this.device,
                                 { render_data.object_ubo.handle, 0, size_of(la.Matrix4f32) },
                                 .UNIFORM_BUFFER_DYNAMIC, 
                                 this.unlit_mat.descriptors[3])

    render_data.model[0] = la.matrix4_translate_f32(la.Vector3f32 {1, 0, 0})
    render_data.materials[0] = &this.unlit_mat

    render_data.vertex_buffers[0] = buffers_create(size_of(cube.vertices), buffers_default_flags(.VERTEX))
    buffers_write(render_data.vertex_buffers[0], &cube.vertices)

    render_data.index_buffers[0] = buffers_create(size_of(cube.indices), buffers_default_flags(.INDEX))
    buffers_write(render_data.index_buffers[0], &cube.indices)
    
    buffers_flush_stage()
    return render_data
}

cleanup :: proc(this: ^RenderContext) {
    vk.DeviceWaitIdle(this.device)

    cleanup_perframes(this)
    swapchain_destroy(this.device, this.swapchain)

    vk.DestroySurfaceKHR(this.instance, this.surface, nil)
    vk.DestroyDebugUtilsMessengerEXT(this.instance, this.debug_messenger, nil)
    vk.DestroyInstance(nil, nil)

    glfw.DestroyWindow(this.window)
    glfw.Terminate()
}

cleanup_perframes :: proc(using ctx: ^RenderContext) {
    for perframe in perframes {
        vk.DestroyCommandPool(device, perframe.command_pool, nil)
        vk.DestroyFence(device, perframe.in_flight_fence, nil)
        vk.DestroySemaphore(device, perframe.render_finished, nil)
    }
    delete(perframes)
}

key_callback :: proc "c" (window: glfw.WindowHandle, key, scancode, action, mods: i32) {
    if key == glfw.KEY_ESCAPE && action == glfw.PRESS {
        glfw.SetWindowShouldClose(window, glfw.TRUE)
    }
}
