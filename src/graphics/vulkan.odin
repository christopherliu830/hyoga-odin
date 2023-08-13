package graphics

import "core:fmt"
import "core:runtime"
import "core:os"
import "core:strings"
import sa "core:container/small_array"

import "vendor:glfw"
import vk "vendor:vulkan"

WINDOW_HEIGHT :: 600
WINDOW_WIDTH :: 800
WINDOW_TITLE :: "Hyoga"
MAX_FRAMES_IN_FLIGHT :: 2

Context :: struct
{
	debug_messenger: vk.DebugUtilsMessengerEXT,

	instance: vk.Instance,
  	device:   vk.Device,
	gpu: vk.PhysicalDevice,
	swapchain: Swapchain,
	pipeline: Pipeline,
	queue_indices:   [QueueFamily]int,
	queues:   [QueueFamily]vk.Queue,
	surface:  vk.SurfaceKHR,
	window:   glfw.WindowHandle,
	vertex_buffer: Buffer,
	index_buffer: Buffer,
	
	curr_frame: u32,
	framebuffer_resized: bool,

	perframes: []Perframe,
}

Perframe :: struct {
	device: vk.Device,
	queue_index: uint,
	in_flight_fence: vk.Fence,
	command_pool : vk.CommandPool,
	command_buffer: vk.CommandBuffer,
	image_available: vk.Semaphore,
	render_finished: vk.Semaphore,
}

QueueFamily :: enum
{
	GRAPHICS,
	PRESENT,
}


update :: proc(using ctx: ^Context) -> bool {
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

        return result != .SUCCESS
}

acquire_image :: proc(using ctx: ^Context, image: ^u32) -> vk.Result {
        signaled_semaphore := perframes[image^].image_available

        result := vk.AcquireNextImageKHR(device, swapchain.handle, max(u64), perframes[image^].image_available, 0, image)
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
                fences := []vk.Fence{ perframes[image^].in_flight_fence }
                vk.WaitForFences(device, 1, raw_data(fences), true, max(u64)) or_return
                vk.ResetFences(device, 1, raw_data(fences)) or_return
        }

        if perframes[image^].command_pool != 0 {
                vk.ResetCommandPool(device, perframes[image^].command_pool, {}) or_return
        }

        perframes[image^].image_available = signaled_semaphore

        return .SUCCESS
}

draw :: proc(using ctx: ^Context, index: u32) -> vk.Result {

        cmd := perframes[index].command_buffer

        begin_info : vk.CommandBufferBeginInfo = {
                sType = .COMMAND_BUFFER_BEGIN_INFO,
                flags = { .ONE_TIME_SUBMIT },
        }

        vk.BeginCommandBuffer(cmd, &begin_info)

        clear_value: vk.ClearValue = { color = {
                float32 = [4]f32{0.01, 0.01, 0.033, 1.0},
        }}

        framebuffer: vk.Framebuffer = swapchain.framebuffers[index]

        rp_begin: vk.RenderPassBeginInfo = {
                sType = .RENDER_PASS_BEGIN_INFO,
                renderPass = pipeline.render_pass,
                framebuffer = framebuffer,
                renderArea = { extent = swapchain.extent },
                clearValueCount = 1,
                pClearValues = &clear_value,
        }

        vk.CmdBeginRenderPass(cmd, &rp_begin, vk.SubpassContents.INLINE)

        vk.CmdBindPipeline(cmd, vk.PipelineBindPoint.GRAPHICS, pipeline.handle)

        offsets := raw_data([]vk.DeviceSize { 0 })
        vk.CmdBindVertexBuffers(cmd, 0, 1, &vertex_buffer.buffer, offsets)

        viewport: vk.Viewport = {
                width = f32(swapchain.extent.width),
                height = f32(swapchain.extent.height),
                minDepth = 0,
                maxDepth = 1,
        }

        vk.CmdSetViewport(cmd, 0, 1, &viewport)

        scissor: vk.Rect2D = { extent = swapchain.extent }

        vk.CmdSetScissor(cmd, 0, 1, &scissor)

        vk.CmdDraw(cmd, vertex_buffer.item_count, 1, 0, 0)

        vk.CmdEndRenderPass(cmd)

        vk.EndCommandBuffer(cmd) or_return

        wait_stage: vk.PipelineStageFlags = { .COLOR_ATTACHMENT_OUTPUT }

        submit_info: vk.SubmitInfo = {
                sType = .SUBMIT_INFO,
                commandBufferCount = 1,
                pCommandBuffers = &cmd,
                waitSemaphoreCount = 1,
                pWaitSemaphores = &perframes[index].image_available,
                pWaitDstStageMask = &wait_stage,
                signalSemaphoreCount = 1,
                pSignalSemaphores = &perframes[index].render_finished,
        }

        vk.QueueSubmit(queues[.GRAPHICS], 1, &submit_info, perframes[index].in_flight_fence)
        return .SUCCESS
}

present_image :: proc(using ctx: ^Context, index: u32) -> vk.Result {
        i := index

        present_info: vk.PresentInfoKHR = {
                sType = .PRESENT_INFO_KHR,
                swapchainCount = 1,
                pSwapchains = &swapchain.handle,
                pImageIndices = &i,
                waitSemaphoreCount = 1,
                pWaitSemaphores = &perframes[index].render_finished,
        }

        return vk.QueuePresentKHR(queues[.PRESENT], &present_info)
}

resize :: proc(using ctx: ^Context) -> bool {
        fmt.println("Resizing")

        if device == nil do return false

        surface_properties: vk.SurfaceCapabilitiesKHR
        vk.GetPhysicalDeviceSurfaceCapabilitiesKHR(gpu, surface, &surface_properties)

        if surface_properties.currentExtent == swapchain.extent do return false

        for x, y := glfw.GetFramebufferSize(ctx.window); x == 0 && y == 0; {
                x, y = glfw.GetFramebufferSize(ctx.window)
                glfw.WaitEvents()
        }

        vk.DeviceWaitIdle(device)

        cleanup_swapchain_framebuffers(ctx)

        init_swapchain(ctx)
        init_swapchain_framebuffers(ctx)

        return true
}

//region Initialization functions 

init :: proc() -> (ctx: Context) {
        using ctx;
        init_window(&ctx)

        // Vulkan does not come loaded into Odin by default, 
        // so we need to begin by loading Vulkan's functions at runtime.
        // This can be achieved using glfw's GetInstanceProcAddress function.
        // the non-overloaded function is used to leverage auto_cast and avoid
        // funky rawptr type stuff.
        vk.load_proc_addresses_global(auto_cast glfw.GetInstanceProcAddress);

        // In order to get debug information while creating the 
        // Vulkan instance, the DebugCreateInfo is passed as part of the
        // InstanceCreateInfo.
        debug_info : vk.DebugUtilsMessengerCreateInfoEXT = {
                sType = vk.StructureType.DEBUG_UTILS_MESSENGER_CREATE_INFO_EXT,
                messageSeverity = vk.DebugUtilsMessageSeverityFlagsEXT {
                        .WARNING,
                        .ERROR,
                },
                messageType = vk.DebugUtilsMessageTypeFlagsEXT {
                        .GENERAL,
                        .PERFORMANCE,
                        .VALIDATION,
                },
                pfnUserCallback = debug_messenger_callback,
        }

        // Create Instance
        result: vk.Result
        result = init_vulkan_instance(&ctx, &debug_info)
        error_check(result)

        // Load the rest of Vulkan's functions.
        vk.load_proc_addresses(instance)

        result = vk.CreateDebugUtilsMessengerEXT(instance, &debug_info, nil, &debug_messenger)
        error_check(result)

        result = init_physical_device_and_surface(&ctx)
        error_check(result)

        result = init_logical_device(&ctx)
        error_check(result)

        result = init_swapchain(&ctx)
        error_check(result)

        result = init_perframes(&ctx)
        error_check(result)

        result = create_render_pass(&ctx)
        error_check(result)

        result = create_pipeline(&ctx)
        error_check(result)

        result = init_swapchain_framebuffers(&ctx)
        error_check(result)

        vertex_buffer, result = init_vertex_buffer(device, gpu)
        error_check(result)

        return ctx
}

init_window :: proc(using ctx: ^Context) {
        glfw.SetErrorCallback(error_callback)
        glfw.Init()

        glfw.WindowHint(glfw.CLIENT_API, glfw.NO_API);

        window = glfw.CreateWindow(WINDOW_WIDTH, WINDOW_HEIGHT, WINDOW_TITLE, nil, nil);
        
        if (!glfw.VulkanSupported()) {
                panic("Vulkan not supported!")
        }
}

init_vulkan_instance :: proc(using ctx: ^Context, debug_create_info: ^vk.DebugUtilsMessengerCreateInfoEXT) -> vk.Result {
        application_info: vk.ApplicationInfo = {
                sType = vk.StructureType.APPLICATION_INFO,
                pApplicationName = "Untitled",
                pEngineName = "Odinpi",
                apiVersion = vk.API_VERSION_1_3,
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
        layers := []cstring { "VK_LAYER_KHRONOS_validation" }

        fmt.print("Enabled Extensions: ")
        for extension in required_extensions do fmt.printf("%s ", extension); fmt.println()

        fmt.print("Enabled Layers: ")
        for layer in layers do fmt.printf("%s ", layer); fmt.println()

        instance_create_info: vk.InstanceCreateInfo = {
                sType = vk.StructureType.INSTANCE_CREATE_INFO,
                flags = nil,
                enabledExtensionCount = u32(len(required_extensions)),
                ppEnabledExtensionNames = raw_data(required_extensions),
                enabledLayerCount = u32(len(layers)),
                ppEnabledLayerNames = raw_data(layers),
                pApplicationInfo = &application_info,
                pNext = debug_create_info,
        }

        vk.CreateInstance(&instance_create_info, nil, &instance) or_return

        return .SUCCESS
}

init_physical_device_and_surface :: proc(using ctx: ^Context) -> vk.Result {
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
                vk.GetPhysicalDeviceQueueFamilyProperties(physical_device, &count, raw_data(queue_family_properties))

                queue_indices[.GRAPHICS] = -1;
                queue_indices[.PRESENT] = -1;

                for queue, index in queue_family_properties {
                        supported: b32
                        vk.GetPhysicalDeviceSurfaceSupportKHR(physical_device, u32(index), surface, &supported) or_return
                        if queue_indices[.PRESENT] == -1 && supported {
                                queue_indices[.PRESENT] = index
                        }

                        if queue_indices[.GRAPHICS] == -1 && .GRAPHICS in queue.queueFlags {
                                queue_indices[.GRAPHICS] = index
                        }
                }
                fmt.printf("Enabled GPU: %s\n", cstring(raw_data(&properties.deviceName)))
                gpu = physical_device
                break
        }
        return .SUCCESS
}

init_logical_device :: proc(using ctx: ^Context) -> vk.Result {
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
                switch(cstring(raw_data(&e.extensionName))) {
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

        queue_create_info : vk.DeviceQueueCreateInfo = {
                sType = vk.StructureType.DEVICE_QUEUE_CREATE_INFO,
                queueFamilyIndex = u32(queue_indices[.GRAPHICS]),
                queueCount = 1,
                pQueuePriorities = &queuePriority,
        }

        shader_features: vk.PhysicalDeviceShaderDrawParametersFeatures = {
                sType = .PHYSICAL_DEVICE_SHADER_DRAW_PARAMETERS_FEATURES,
                shaderDrawParameters = true,
        }

        device_create_info: vk.DeviceCreateInfo = {
                sType = .DEVICE_CREATE_INFO,
                enabledExtensionCount = u32(len(required_extensions)),
                ppEnabledExtensionNames = raw_data(required_extensions),
                queueCreateInfoCount = 1,
                pQueueCreateInfos = &queue_create_info,
                pNext = &shader_features,
        }

        vk.CreateDevice(gpu, &device_create_info, nil, &device) or_return

        vk.GetDeviceQueue(device, u32(queue_indices[.GRAPHICS]), 0, &queues[.GRAPHICS])
        vk.GetDeviceQueue(device, u32(queue_indices[.PRESENT]), 0, &queues[.PRESENT])

        return .SUCCESS
}

init_allocator :: proc(using ctx: ^Context) -> vk.Result {
        /* To be implemented */
        return .SUCCESS
}

init_perframes :: proc(using ctx: ^Context) -> vk.Result {
        perframes = make([]Perframe, len(ctx.swapchain.images))

        for _, i in perframes {
                p := &perframes[i]
                p.queue_index = uint(i)

                create_info: vk.SemaphoreCreateInfo = { sType = .SEMAPHORE_CREATE_INFO }
                vk.CreateSemaphore(device, &create_info, nil, &perframes[i].image_available)
                vk.CreateSemaphore(device, &create_info, nil, &perframes[i].render_finished)

                fence_info : vk.FenceCreateInfo = { .FENCE_CREATE_INFO, nil, { .SIGNALED } }
                vk.CreateFence(device, &fence_info, nil, &p.in_flight_fence) or_return

                command_pool_create_info: vk.CommandPoolCreateInfo = {
                        sType = .COMMAND_POOL_CREATE_INFO,
                        flags = { .TRANSIENT, .RESET_COMMAND_BUFFER },
                        queueFamilyIndex = u32(queue_indices[.GRAPHICS]),
                }

                vk.CreateCommandPool(device, &command_pool_create_info, nil, &p.command_pool) or_return

                command_buffer_info: vk.CommandBufferAllocateInfo = {
                        sType = .COMMAND_BUFFER_ALLOCATE_INFO,
                        commandPool = p.command_pool,
                        level = .PRIMARY,
                        commandBufferCount = 1,
                }

                vk.AllocateCommandBuffers(device, &command_buffer_info, &p.command_buffer) or_return

        }

        return .SUCCESS
}

// Temporary
init_vertex_buffer :: proc(device: vk.Device, gpu: vk.PhysicalDevice) ->
(buffer: Buffer, result: vk.Result) {
        v := VERTICES
        buffer = create_buffer(device, gpu, size_of(Vertex), len(VERTICES)) or_return
        allocate_buffer(device, buffer, &v)
        return buffer, .SUCCESS
}

//endregion Initialization functions

//region Cleanup functions

cleanup :: proc(using ctx: ^Context) {
        vk.DeviceWaitIdle(device)

        destroy_buffer(device, vertex_buffer)

        cleanup_perframes(ctx)
        cleanup_pipeline(ctx)
        cleanup_swapchain(ctx)

        vk.DestroySurfaceKHR(instance, surface, nil)
        vk.DestroyDebugUtilsMessengerEXT(instance, debug_messenger, nil)
        vk.DestroyInstance(nil, nil)

        glfw.DestroyWindow(window)
        glfw.Terminate()
}

cleanup_perframes :: proc(using ctx: ^Context) {
        for perframe in perframes {
                vk.DestroyCommandPool(device, perframe.command_pool, nil)
                vk.DestroyFence(device, perframe.in_flight_fence, nil)
                // Skip deleting the other semaphore since it's already deleted from the semaphore pool.
                vk.DestroySemaphore(device, perframe.render_finished, nil)
        }
        delete(perframes)
}

//endregion Cleanup functions

//region Debug

debug_messenger_callback :: proc "system" (
messageSeverity: vk.DebugUtilsMessageSeverityFlagsEXT,
messageTypes: vk.DebugUtilsMessageTypeFlagsEXT,
pCallbackData: ^vk.DebugUtilsMessengerCallbackDataEXT,
pUserData: rawptr) -> b32 {
        context = runtime.default_context()

        fmt.printf("%v: %v:\n", messageSeverity, messageTypes)
        fmt.printf("\tmessageIDName   = <%v>\n", pCallbackData.pMessageIdName)
        fmt.printf("\tmessageIDNumber = <%v>\n", pCallbackData.messageIdNumber)
        fmt.printf("\tmessage         = <%v>\n", pCallbackData.pMessage)

        if 0 < pCallbackData.queueLabelCount {
                fmt.printf("\tQueue Labels: \n")
                for i in 0..<pCallbackData.queueLabelCount {
                        fmt.printf("\t\tlabelName = <%v>\n", pCallbackData.pQueueLabels[i].pLabelName)
                }
        }
        if 0 < pCallbackData.cmdBufLabelCount {
                fmt.printf("\tCommandBuffer Labels: \n")
                for i in 0..<pCallbackData.cmdBufLabelCount {
                        fmt.printf("\t\tlabelName = <%v>\n", pCallbackData.pCmdBufLabels[i].pLabelName)
                }
        }
        if 0 < pCallbackData.objectCount {
                fmt.printf("Objects:\n")
                for i in 0..<pCallbackData.objectCount {
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

error_check :: proc(result: vk.Result) {
        if (result != .SUCCESS) {
                fmt.panicf("VULKAN: %s\n", result)
        }
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
//endregion Debug