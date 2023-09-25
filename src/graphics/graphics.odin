package graphics

import "core:fmt"
import "core:log"
import "core:runtime"
import "core:c"
import la "core:math/linalg"

import "vendor:glfw"
import vk "vendor:vulkan"

import "vma"
import "buffers"
import "materials"
import "builders"
import "common"

RenderContext :: struct {
    debug_messenger: vk.DebugUtilsMessengerEXT,

    // Nested structs
    swapchain:       Swapchain,
    perframes:       []Perframe,
    allocator:       vma.Allocator,

    // Handles
    instance:        vk.Instance,
    device:          vk.Device,
    gpu:             vk.PhysicalDevice,
    surface:         vk.SurfaceKHR,
    window:          glfw.WindowHandle,
    descriptor_pool: vk.DescriptorPool,

    render_data:     RenderData,
    camera_data:     CameraData,
    unlit_effect:    materials.ShaderEffect,
    unlit_pass:      materials.ShaderPass,
    unlit_mat:       materials.Material,

    // Queues
    queue_indices:   [QueueFamily]int,
    queues:          [QueueFamily]vk.Queue,

    window_needs_resize: bool,
}

Perframe :: struct {
    device:          vk.Device,
    queue_index:     uint,
    in_flight_fence: vk.Fence,
    command_pool:    vk.CommandPool,
    command_buffer:  vk.CommandBuffer,
    image_available: vk.Semaphore,
    render_finished: vk.Semaphore,
}

QueueFamily :: enum {
    GRAPHICS,
    PRESENT,
}

@private
RenderData :: struct {
    cube:            Cube,
    tetra:           Tetrahedron,
    render_pass:     vk.RenderPass,
    camera_ubo:      buffers.Buffer,
    object_ubo:      buffers.Buffer,
    model:           [OBJECT_COUNT]la.Matrix4f32,
    vertex_buffers:  [OBJECT_COUNT]buffers.Buffer,
    index_buffers:   [OBJECT_COUNT]buffers.Buffer,
    materials:       [OBJECT_COUNT]^materials.Material,
}

@private
CameraData :: struct {
    view: la.Matrix4f32,
    proj: la.Matrix4f32,
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

    clear_value: vk.ClearValue = { color = { float32 = [4]f32{ 0.01, 0.01, 0.033, 1.0 }}}

    rp_begin: vk.RenderPassBeginInfo = {
        sType = .RENDER_PASS_BEGIN_INFO,
        renderPass = this.render_data.render_pass,
        framebuffer = this.swapchain.framebuffers[index],
        renderArea = {extent = this.swapchain.extent},
        clearValueCount = 1,
        pClearValues = &clear_value,
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

    buffers.write(this.render_data.camera_ubo, &camera, size_of(CameraData), uintptr(size_of(CameraData) * index))

    last_material : ^materials.Material = nil

    for i in 0..<OBJECT_COUNT {
        transform := this.render_data.model[i] * la.matrix4_rotate_f32(f32(g_time) / 1000, { 0, 0, 1 })
        buffers.write(this.render_data.object_ubo, &transform, size_of(la.Matrix4f32), uintptr(i * size_of(la.Matrix4f32)))

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

    cleanup_swapchain_framebuffers(this)

    init_swapchain(this)
    init_swapchain_framebuffers(this)

    this.window_needs_resize = false;

    return true
}


init :: proc(this: ^RenderContext) {
    common.vk_assert(init_all(this))
}

init_all :: proc(this: ^RenderContext) -> vk.Result {
    this.window = init_window(this)

    // Vulkan does not come loaded into Odin by default, 
    // so we need to begin by loading Vulkan's functions at runtime.
    // This can be achieved using glfw's GetInstanceProcAddress function.
    // the non-overloaded function is used to leverage auto_cast and avoid
    // funky rawptr type stuff.
    vk.load_proc_addresses_global(auto_cast glfw.GetInstanceProcAddress)

    // In order to get debug information while creating the 
    // Vulkan instance, the DebugCreateInfo is passed as part of the
    // InstanceCreateInfo.
    debug_info: vk.DebugUtilsMessengerCreateInfoEXT = {
        sType = vk.StructureType.DEBUG_UTILS_MESSENGER_CREATE_INFO_EXT,
        messageSeverity = vk.DebugUtilsMessageSeverityFlagsEXT{.WARNING, .ERROR},
        messageType = vk.DebugUtilsMessageTypeFlagsEXT{.GENERAL, .PERFORMANCE, .VALIDATION},
        pfnUserCallback = debug_messenger_callback,
    }

    this.instance = init_vulkan_instance(&debug_info) or_return

    // Load the rest of Vulkan's functions.
    vk.load_proc_addresses(this.instance)

    vk.CreateDebugUtilsMessengerEXT(this.instance, &debug_info, nil, &this.debug_messenger) or_return

    init_physical_device_and_surface(this) or_return
    init_logical_device(this) or_return
    init_swapchain(this) or_return
    init_perframes(this) or_return

    buffers.init({
        physicalDevice = this.gpu,
        instance = this.instance,
        device = this.device,
        vulkanApiVersion = vk.API_VERSION_1_3,
    })

    buffers.init_staging(this.device, this.queues[.GRAPHICS])

    buffers.create(int(size_of(CameraData) * this.swapchain.image_count),
                   buffers.DefaultFlags[.UNIFORM_DYNAMIC])

    this.descriptor_pool = create_descriptor_pool(this.device, 1000)
    this.render_data = init_render_data(this)

    init_swapchain_framebuffers(this) or_return
    return .SUCCESS
}

init_window :: proc(this: ^RenderContext) -> glfw.WindowHandle {
    glfw.SetErrorCallback(error_callback)
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

init_vulkan_instance :: proc(debug_create_info: ^vk.DebugUtilsMessengerCreateInfoEXT) ->
(instance: vk.Instance, result: vk.Result) {
    application_info: vk.ApplicationInfo = {
        sType            = vk.StructureType.APPLICATION_INFO,
        pApplicationName = "Untitled",
        pEngineName      = "Hyoga",
        apiVersion       = vk.API_VERSION_1_3,
    }

    // Available Extensions
    count: u32
    vk.EnumerateInstanceExtensionProperties(nil, &count, nil) or_return
    extensions := make([]vk.ExtensionProperties, count)
    defer delete(extensions)
    vk.EnumerateInstanceExtensionProperties(nil, &count, raw_data(extensions)) or_return

    // Required Extensions
    required_extensions: [dynamic]cstring
    defer delete(required_extensions)
    glfw_required_extensions := glfw.GetRequiredInstanceExtensions()
    append(&required_extensions, ..glfw_required_extensions)
    append(&required_extensions, vk.EXT_DEBUG_UTILS_EXTENSION_NAME)

    for required_extension in required_extensions {
        found := false
        for extension in extensions {
            e := extension
            extension_name := cstring(raw_data(&e.extensionName))
            if required_extension == extension_name {
                found = true
                break
            }
        }
        fmt.assertf(found, "%s not found", required_extension)
    }

    // Enabled Layers
    layers := []cstring{"VK_LAYER_KHRONOS_validation"}

    log.info("Enabled Extensions: ")
    for extension in required_extensions do log.infof(string(extension))

    log.info("Enabled Layers: ")
    for layer in layers do log.infof(string(layer))

    instance_create_info: vk.InstanceCreateInfo = {
        sType                   = vk.StructureType.INSTANCE_CREATE_INFO,
        flags                   = nil,
        enabledExtensionCount   = u32(len(required_extensions)),
        ppEnabledExtensionNames = raw_data(required_extensions),
        enabledLayerCount       = u32(len(layers)),
        ppEnabledLayerNames     = raw_data(layers),
        pApplicationInfo        = &application_info,
        pNext                   = debug_create_info,
    }

    vk.CreateInstance(&instance_create_info, nil, &instance) or_return

    return instance, .SUCCESS
}

init_physical_device_and_surface :: proc(using ctx: ^RenderContext) -> vk.Result {
    count: u32
    vk.EnumeratePhysicalDevices(instance, &count, nil) or_return
    devices := make([]vk.PhysicalDevice, count)
    defer delete(devices)
    vk.EnumeratePhysicalDevices(instance, &count, raw_data(devices)) or_return

    for physical_device in devices {
        // Properties
        properties: vk.PhysicalDeviceProperties
        vk.GetPhysicalDeviceProperties(physical_device, &properties)

        if surface != 0 {
            vk.DestroySurfaceKHR(instance, surface, nil)
        }

        glfw.CreateWindowSurface(instance, window, nil, &ctx.surface)

        // Locate a device with the GRAPHICS queue flag
        // as well as surface support.
        vk.GetPhysicalDeviceQueueFamilyProperties(physical_device, &count, nil)
        queue_family_properties := make([]vk.QueueFamilyProperties, count)
        defer delete(queue_family_properties)
        vk.GetPhysicalDeviceQueueFamilyProperties(
            physical_device,
            &count,
            raw_data(queue_family_properties),
        )

        queue_indices[.GRAPHICS] = -1
        queue_indices[.PRESENT] = -1

        for queue, index in queue_family_properties {
            supported: b32
            vk.GetPhysicalDeviceSurfaceSupportKHR(
                physical_device,
                u32(index),
                surface,
                &supported,
            ) or_return
            if queue_indices[.PRESENT] == -1 && supported {
                queue_indices[.PRESENT] = index
            }

            if queue_indices[.GRAPHICS] == -1 && .GRAPHICS in queue.queueFlags {
                queue_indices[.GRAPHICS] = index
            }
        }
        log.infof("Enabled GPU: %s\n", cstring(raw_data(&properties.deviceName)))
        gpu = physical_device
        break
    }
    return .SUCCESS
}

init_logical_device :: proc(using ctx: ^RenderContext) -> vk.Result {
    count: u32
    vk.EnumerateDeviceExtensionProperties(gpu, nil, &count, nil) or_return
    extensions := make([]vk.ExtensionProperties, count)
    defer delete(extensions)
    vk.EnumerateDeviceExtensionProperties(gpu, nil, &count, raw_data(extensions)) or_return

    required_extensions := make([dynamic]cstring, 0, 2)
    defer delete(required_extensions)


    // If portability subset is found in device extensions,
    // it must be enabled.
    portability_found := false
    for extension in extensions {
        e := extension
        switch (cstring(raw_data(&e.extensionName))) {
        case "VK_KHR_portability_subset":
            portability_found = true
            break

        }
    }

    if portability_found {
        append(&required_extensions, "VK_KHR_portability_subset")
    }

    if swapchain_is_supported(gpu) {
        append(&required_extensions, vk.KHR_SWAPCHAIN_EXTENSION_NAME)
    } else {
        fmt.panicf("Swapchain is not supported!\n")
    }

    // Unused
    queuePriority: f32 = 1

    queue_create_info: vk.DeviceQueueCreateInfo = {
        sType            = vk.StructureType.DEVICE_QUEUE_CREATE_INFO,
        queueFamilyIndex = u32(queue_indices[.GRAPHICS]),
        queueCount       = 1,
        pQueuePriorities = &queuePriority,
    }

    shader_features: vk.PhysicalDeviceShaderDrawParametersFeatures = {
        sType                = .PHYSICAL_DEVICE_SHADER_DRAW_PARAMETERS_FEATURES,
        shaderDrawParameters = true,
    }

    device_create_info: vk.DeviceCreateInfo = {
        sType                   = .DEVICE_CREATE_INFO,
        enabledExtensionCount   = u32(len(required_extensions)),
        ppEnabledExtensionNames = raw_data(required_extensions),
        queueCreateInfoCount    = 1,
        pQueueCreateInfos       = &queue_create_info,
        pNext                   = &shader_features,
    }

    vk.CreateDevice(gpu, &device_create_info, nil, &device) or_return

    vk.GetDeviceQueue(device, u32(queue_indices[.GRAPHICS]), 0, &queues[.GRAPHICS])
    vk.GetDeviceQueue(device, u32(queue_indices[.PRESENT]), 0, &queues[.PRESENT])

    return .SUCCESS
}

init_perframes :: proc(using ctx: ^RenderContext) -> vk.Result {
    perframes = make([]Perframe, len(ctx.swapchain.images))

    for _, i in perframes {
        p := &perframes[i]
        p.queue_index = uint(i)

        create_info: vk.SemaphoreCreateInfo = {
            sType = .SEMAPHORE_CREATE_INFO,
        }
        vk.CreateSemaphore(device, &create_info, nil, &perframes[i].image_available)
        vk.CreateSemaphore(device, &create_info, nil, &perframes[i].render_finished)

        fence_info: vk.FenceCreateInfo = {.FENCE_CREATE_INFO, nil, {.SIGNALED}}
        vk.CreateFence(device, &fence_info, nil, &p.in_flight_fence) or_return

        command_pool_create_info: vk.CommandPoolCreateInfo = {
            sType = .COMMAND_POOL_CREATE_INFO,
            flags = {.TRANSIENT, .RESET_COMMAND_BUFFER},
            queueFamilyIndex = u32(queue_indices[.GRAPHICS]),
        }

        vk.CreateCommandPool(device, &command_pool_create_info, nil, &p.command_pool) or_return

        command_buffer_info: vk.CommandBufferAllocateInfo = {
            sType              = .COMMAND_BUFFER_ALLOCATE_INFO,
            commandPool        = p.command_pool,
            level              = .PRIMARY,
            commandBufferCount = 1,
        }

        vk.AllocateCommandBuffers(device, &command_buffer_info, &p.command_buffer) or_return

    }

    return .SUCCESS
}

init_render_data :: proc(this: ^RenderContext) -> (render_data: RenderData) {
    render_data.render_pass = builders.create_render_pass(this.device, this.swapchain.format.format)

    render_data.camera_ubo = buffers.create(size_of(CameraData) * int(this.swapchain.image_count), buffers.default_flags(.UNIFORM_DYNAMIC))
    render_data.object_ubo = buffers.create(size_of(la.Matrix4f32) * OBJECT_COUNT, buffers.default_flags(.UNIFORM_DYNAMIC))

    render_data.cube = create_cube()
    render_data.tetra = create_tetrahedron()

    cube := create_cube()
    
    this.unlit_effect = materials.create_shader_effect(this.device,
                                                   .DEFAULT,
                                                   "assets/shaders/shader.vert.spv",
                                                   "assets/shaders/shader.frag.spv")

    this.unlit_pass = materials.create_shader_pass(this.device, render_data.render_pass, &this.unlit_effect)
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

    render_data.vertex_buffers[0] = buffers.create(size_of(cube.vertices), buffers.default_flags(.VERTEX))
    buffers.write(render_data.vertex_buffers[0], &cube.vertices)

    render_data.index_buffers[0] = buffers.create(size_of(cube.indices), buffers.default_flags(.INDEX))
    buffers.write(render_data.index_buffers[0], &cube.indices)
    
    buffers.flush_stage()

    

    return render_data
}

cleanup :: proc(using ctx: ^RenderContext) {
    vk.DeviceWaitIdle(device)

    cleanup_perframes(ctx)
    cleanup_swapchain(ctx)

    vk.DestroySurfaceKHR(instance, surface, nil)
    vk.DestroyDebugUtilsMessengerEXT(instance, debug_messenger, nil)
    vk.DestroyInstance(nil, nil)

    glfw.DestroyWindow(window)
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


debug_messenger_callback :: proc "system" (
    messageSeverity: vk.DebugUtilsMessageSeverityFlagsEXT,
    messageTypes: vk.DebugUtilsMessageTypeFlagsEXT,
    pCallbackData: ^vk.DebugUtilsMessengerCallbackDataEXT,
    pUserData: rawptr,
) -> b32 {
    context = runtime.default_context()

    fmt.printf("%v: %v:\n", messageSeverity, messageTypes)
    fmt.printf("\tmessageIDName   = <%v>\n", pCallbackData.pMessageIdName)
    fmt.printf("\tmessageIDNumber = <%v>\n", pCallbackData.messageIdNumber)
    fmt.printf("\tmessage         = <%v>\n", pCallbackData.pMessage)

    if 0 < pCallbackData.queueLabelCount {
        fmt.printf("\tQueue Labels: \n")
        for i in 0 ..< pCallbackData.queueLabelCount {
            fmt.printf("\t\tlabelName = <%v>\n", pCallbackData.pQueueLabels[i].pLabelName)
        }
    }
    if 0 < pCallbackData.cmdBufLabelCount {
        fmt.printf("\tCommandBuffer Labels: \n")
        for i in 0 ..< pCallbackData.cmdBufLabelCount {
            fmt.printf("\t\tlabelName = <%v>\n", pCallbackData.pCmdBufLabels[i].pLabelName)
        }
    }
    if 0 < pCallbackData.objectCount {
        fmt.printf("Objects:\n")
        for i in 0 ..< pCallbackData.objectCount {
            fmt.printf("\t\tObject %d\n", pCallbackData.pObjects[i].objectType)
            fmt.printf("\t\t\tobjectType   = %s\n", pCallbackData.pObjects[i].objectType)
            fmt.printf("\t\t\tobjectHandle = %d\n", pCallbackData.pObjects[i].objectHandle)
            if pCallbackData.pObjects[i].pObjectName != nil {
                fmt.printf("\t\t\tobjectName   = <%v>\n", pCallbackData.pObjects[i].pObjectName)
            }
        }
    }
    return true
}

error_callback :: proc "c" (code: i32, desc: cstring) {
    context = runtime.default_context()
    fmt.println(desc, code)
}

key_callback :: proc "c" (window: glfw.WindowHandle, key, scancode, action, mods: i32) {
    if key == glfw.KEY_ESCAPE && action == glfw.PRESS {
        glfw.SetWindowShouldClose(window, glfw.TRUE)
    }
}
