package graphics

import "core:fmt"
import "core:log"
import "core:runtime"
import "core:c"
import "core:math"
import "core:mem"
import "core:container/intrusive/list"
import la "core:math/linalg"

import "vendor:glfw"
import vk "vendor:vulkan"
import "pkgs:vma"

import "builders"

RenderContext :: struct {

    // Vulkan instance.
    instance:             vk.Instance,

    // Handle to GLFW window.
    window:               glfw.WindowHandle,

    // GPU handle and a struct of its properties.
    gpu:                  vk.PhysicalDevice,
    gpu_properties:       vk.PhysicalDeviceProperties,

    // Desired queue indices of the GPU and handles to those queues.
    queue_indices:        [QueueFamily]int,
    queues:               [QueueFamily]vk.Queue,

    // Vulkan device context.
    device:               vk.Device,

    // Vulkan display handles.
    surface:              vk.SurfaceKHR,
    swapchain:            Swapchain,

    // Render passes (shadow, forward) and their respective data.
    passes:               [PassType]PassInfo,

    descriptor_pool:      vk.DescriptorPool,

    // Global stage buffer. Use this and associated buffers module for
    // moving buffers to GPU.
    stage:                StagingPlatform,

    // The sync objects and command buffer are stored together
    // in a Perframe object and duplicated for each swapchain image.
    perframes:            []Perframe,

    // Used to synchronize acquire -> present
    semaphore_pool:       []SemaphoreLink,
    semaphore_list:       list.List,

    // Holds data for scene.
    scene:                Scene,

    mat_cache:            MaterialCache,

    window_needs_resize:  bool,
}

WINDOW_HEIGHT :: 720
WINDOW_WIDTH :: 1280
WINDOW_TITLE :: "Hyoga"

@private
g_time : f32 = 0

g_render_context : RenderContext
g_frame_index : int = -1

get_context :: proc() -> ^RenderContext {
    return &g_render_context
}

get_frame :: proc() -> ^Perframe {
    return &get_context().perframes[g_frame_index]
}

begin :: proc() {
    ctx := get_context()
    result: vk.Result
    index: u32

    result = acquire_image(ctx, &index)
    g_frame_index = int(index)
    if result == .SUBOPTIMAL_KHR || result == .ERROR_OUT_OF_DATE_KHR {
        resize(ctx)
    }
}

end :: proc() -> bool {
    ctx := get_context()
    index := u32(g_frame_index)
    result: vk.Result

    perframe := &ctx.perframes[index]

    vk_assert(draw(ctx, perframe))

    submit_queue(perframe, ctx.queues[.GRAPHICS])

    // If window is resized, result is non-success so need to handle manually.
    result = present_image(ctx, index)
    if result == .SUBOPTIMAL_KHR || result == .ERROR_OUT_OF_DATE_KHR {
        resize(ctx)
    } else do vk_assert(result)

    if ctx.window_needs_resize do resize(ctx)

    return result != .SUCCESS
}

acquire_image :: proc(using this: ^RenderContext, image: ^u32) -> vk.Result {
    assert(!list.is_empty(&semaphore_list))
    semaphore := container_of(list.pop_front(&semaphore_list), SemaphoreLink, "link")

    result := vk.AcquireNextImageKHR(
        device,
        swapchain.handle,
        max(u64),
        semaphore.semaphore,
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

    if perframes[image^].image_available != nil {
        list.push_front(&semaphore_list, &perframes[image^].image_available.link)
    }

    perframes[image^].image_available = semaphore

    cmd := perframes[image^].command_buffer

    begin_info := vk.CommandBufferBeginInfo {
        sType = .COMMAND_BUFFER_BEGIN_INFO,
        flags = { .ONE_TIME_SUBMIT },
    }

    vk_assert(vk.BeginCommandBuffer(cmd, &begin_info))

    return .SUCCESS
}

draw :: proc(this: ^RenderContext, perframe: ^Perframe) -> vk.Result {
    g_time += 1

    cmd := perframe.command_buffer
    index := perframe.index

    shadow_prepare(&this.scene, &this.passes[.SHADOW])
    shadow_exec_shadow_pass(&this.scene, perframe, &this.passes[.SHADOW])

    scene_prepare(&this.scene, &this.passes[.FORWARD])
    scene_do_forward_pass(&this.scene, &this.passes[.FORWARD])

    return .SUCCESS
}

submit_queue :: proc(perframe: ^Perframe, queue: vk.Queue) {
    cmd := perframe.command_buffer

    vk.EndCommandBuffer(cmd)

    wait_stage: vk.PipelineStageFlags = { .COLOR_ATTACHMENT_OUTPUT }

    submit_info: vk.SubmitInfo = {
        sType                = .SUBMIT_INFO,
        commandBufferCount   = 1,
        pCommandBuffers      = &cmd,
        waitSemaphoreCount   = 1,
        pWaitSemaphores      = &perframe.image_available.semaphore,
        pWaitDstStageMask    = &wait_stage,
        signalSemaphoreCount = 1,
        pSignalSemaphores    = &perframe.render_finished,
    }

    vk.QueueSubmit(queue, 1, &submit_info, perframe.in_flight_fence)
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

    vk_assert(vk.QueueWaitIdle(this.queues[.GRAPHICS]))

    swapchain_destroy_framebuffers(this.device, this.passes[.FORWARD].framebuffers)

    buffers_destroy(this.device, this.swapchain.depth_image)

    // TODO: is this needed?
    this.swapchain = swapchain_create(this.device,
                                      this.gpu, 
                                      this.surface, 
                                      this.queue_indices,
                                      this.swapchain.handle)

    extent := vk.Extent3D { this.swapchain.extent.width, this.swapchain.extent.height, 1 }
    this.passes[.FORWARD].extent = extent

    this.passes[.FORWARD].framebuffers = swapchain_create_framebuffers(this.device,
                                                                       this.passes[.FORWARD].pass,
                                                                       this.swapchain)

    this.window_needs_resize = false

    return true
}

init :: proc() {
    this := get_context()
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

    when ODIN_OS == .Darwin {
        append(&extensions, vk.KHR_PORTABILITY_ENUMERATION_EXTENSION_NAME)
    }

    this.instance = builders.create_instance(extensions[:])

    // Load the rest of Vulkan's functions.
    vk.load_proc_addresses(this.instance)
    
    this.gpu,
    this.gpu_properties,
    this.surface,
    this.queue_indices = gpu_create(this.instance, this.window)

    this.device, this.queues = device_create(this.gpu, this.queue_indices)

    buffers_init({
        physicalDevice = this.gpu,
        instance = this.instance,
        device = this.device,
        vulkanApiVersion = vk.API_VERSION_1_3,
    },  this.queues[.TRANSFER], 
        this.gpu_properties)

    this.swapchain = swapchain_create(this.device,
                                      this.gpu, 
                                      this.surface, 
                                      this.queue_indices)


    descriptors_init(this.device)
    
    extent := vk.Extent3D {
        this.swapchain.extent.width, 
        this.swapchain.extent.height,
        1,
    }

    this.passes[.FORWARD] = create_forward_pass(this)
    this.passes[.SHADOW] = shadow_create_render_pass(this.device, len(this.swapchain.images))

    this.perframes = create_perframes(this.device, len(this.swapchain.images))

    this.descriptor_pool = descriptors_create_pool(this.device, 1000).pool

    this.semaphore_pool, this.semaphore_list = create_sync_objects(this.device, int(this.swapchain.image_count) + 1)

    this.stage = buffers_create_staging(this.device, this.queues[.TRANSFER])

    mats_init(&this.mat_cache)

    scene_init(&this.scene)
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

create_forward_pass :: proc(ctx: ^RenderContext) -> (pass: PassInfo) {
    color_attachment, color_ref := builders.create_color_attachment(0, ctx.swapchain.format.format)
    depth_attachment, depth_ref := builders.create_depth_attachment(1)

    subpass := vk.SubpassDescription {
        pipelineBindPoint       = .GRAPHICS,
        colorAttachmentCount    = 1,
        pColorAttachments       = &color_ref,
        pDepthStencilAttachment = &depth_ref,
    }

    dependency := vk.SubpassDependency {
        srcSubpass    = vk.SUBPASS_EXTERNAL,
        dstSubpass    = .0,
        srcStageMask  = { .COLOR_ATTACHMENT_OUTPUT },
        srcAccessMask = { },
        dstStageMask  = { .COLOR_ATTACHMENT_OUTPUT },
        dstAccessMask = { .COLOR_ATTACHMENT_READ, .COLOR_ATTACHMENT_WRITE },
    }
    
    depth_dependency := vk.SubpassDependency {
        srcSubpass    = vk.SUBPASS_EXTERNAL,
        dstSubpass    = .0,
        srcStageMask  = { .EARLY_FRAGMENT_TESTS, .LATE_FRAGMENT_TESTS },
        srcAccessMask = {},
        dstStageMask  = { .EARLY_FRAGMENT_TESTS, .LATE_FRAGMENT_TESTS },
        dstAccessMask = { .DEPTH_STENCIL_ATTACHMENT_WRITE },
    }

    subpasses := []vk.SubpassDescription { subpass }
    attachments := []vk.AttachmentDescription { color_attachment, depth_attachment }
    dependencies := []vk.SubpassDependency { dependency, depth_dependency }

    pass.pass = builders.create_render_pass(ctx.device, attachments, subpasses, dependencies) 
    pass.type = .FORWARD

    extent := vk.Extent3D { ctx.swapchain.extent.width, ctx.swapchain.extent.height, 1 }
    count := ctx.swapchain.image_count

    pass.images = ctx.swapchain.images
    pass.framebuffers = swapchain_create_framebuffers(ctx.device, pass.pass, ctx.swapchain) 
    pass.extent = extent

    pass.clear_values = {
        { color = { float32 = [4]f32{ 0.01, 0.01, 0.01, 1.0 }}},
        { depthStencil = { depth = 1 }},
    }

    pass.in_layouts = layout_get_pass_resources(.FORWARD)

    pass.mat_buffer = buffers_create_tbuffer(MaterialUBO, UNIFORM_BUFFER_SIZE, .UNIFORM_DYNAMIC)
    // pass.mat_descriptor = descriptors_get(pass.in_layouts.descriptors[MATERIAL_SET])

    pass.object_buffers = make([]TBuffer(ObjectUBO), count)
    for i in 0..<count {
        pass.object_buffers[i] = buffers_create_tbuffer(ObjectUBO, UNIFORM_BUFFER_SIZE, .UNIFORM_DYNAMIC)
    }
    // pass.object_descriptor = descriptors_get(pass.in_layouts.descriptors[OBJECT_SET])

    return pass
}

create_sync_objects :: proc(device: vk.Device, count: int) ->
(semaphores: []SemaphoreLink, sem_list: list.List) {
    semaphores = make([]SemaphoreLink, count)[0:count]
    for _, i in semaphores {
        semaphores[i] = { semaphore = builders.create_semaphore(device) }
        list.push_front(&sem_list, &semaphores[i].link)
    }
    return semaphores, sem_list
}

cleanup :: proc(this: ^RenderContext) {
    vk.DeviceWaitIdle(this.device)

    scene_shutdown(&this.scene)

    mats_shutdown(&this.mat_cache, this.device)

    buffers_destroy_staging(this.stage)

    vk.DestroyDescriptorPool(this.device, this.descriptor_pool, nil)

    cleanup_render_pass(this.device, this.passes[.SHADOW])

    // Forward pass is cleaned up by swapchain functions

    swapchain_destroy(this.device, this.swapchain)

    for sem in this.semaphore_pool do vk.DestroySemaphore(this.device, sem.semaphore, nil)
    delete(this.semaphore_pool)

    for perframe in this.perframes do  cleanup_perframe(this.device, perframe)

    buffers_shutdown()

    vk.DestroyDevice(this.device, nil)
    vk.DestroySurfaceKHR(this.instance, this.surface, nil)
    vk.DestroyInstance(this.instance, nil)

    glfw.DestroyWindow(this.window)
    glfw.Terminate()
}

cleanup_render_pass :: proc(device: vk.Device, pass: PassInfo) {
    vk.DestroyRenderPass(device, pass.pass, nil)

    for image in pass.images {
        buffers_destroy(device, image)
    }
    delete(pass.images)

    for framebuffer in pass.framebuffers {
        vk.DestroyFramebuffer(device, framebuffer, nil) 
    }
    delete(pass.framebuffers)
}

key_callback :: proc "c" (window: glfw.WindowHandle, key, scancode, action, mods: i32) {
    if key == glfw.KEY_ESCAPE && action == glfw.PRESS {
        glfw.SetWindowShouldClose(window, glfw.TRUE)
    }
}
