package graphics

import vk "vendor:vulkan"

/**
* The swapchain.odin file handles all data and functions necessary for managing the
* swapchain, such as querying support and 
* 
* In Vulkan, a swapchain is a queue of images that are ready to be displayed on a screen.
* Vulkan needs to acquire an Image from the OS, draw to it, then present, in that order.
* The primary purpose of using the swap chain is to synchronize with the monitor
* refresh rate.
*/
Swapchain :: struct
{
    handle: vk.SwapchainKHR,
    images: []vk.Image,
    image_views: []vk.ImageView,
    format: vk.SurfaceFormatKHR,
    extent: vk.Extent2D,
    present_mode: vk.PresentModeKHR,
    image_count: u32,
    support: SwapChainDetails,
    framebuffers: []vk.Framebuffer,
}

SwapChainDetails :: struct
{
    capabilities: vk.SurfaceCapabilitiesKHR,
    formats: []vk.SurfaceFormatKHR,
    present_modes: []vk.PresentModeKHR,
}

// Check if the swapchain is supported. Ignores VK errors for convenience.
swapchain_is_supported :: proc(device: vk.PhysicalDevice) -> (bool) {
    count: u32
    vk.EnumerateDeviceExtensionProperties(device, nil, &count, nil)
    extensions := make([]vk.ExtensionProperties, count)
    defer delete(extensions)
    vk.EnumerateDeviceExtensionProperties(device, nil, &count, raw_data(extensions))

    for extension in extensions {
            e := extension
            if cstring(raw_data(&e.extensionName)) == vk.KHR_SWAPCHAIN_EXTENSION_NAME {
                    return true
            }
    }
    return false
}


init_swapchain :: proc(using ctx: ^RenderContext) -> vk.Result {
    vk.GetPhysicalDeviceSurfaceCapabilitiesKHR(gpu, surface, &swapchain.support.capabilities) or_return

    // Get the preferred format for the device.
    count: u32
    vk.GetPhysicalDeviceSurfaceFormatsKHR(gpu, surface, &count, nil) or_return
    formats := make([]vk.SurfaceFormatKHR, count)
    defer delete(formats)
    vk.GetPhysicalDeviceSurfaceFormatsKHR(gpu, surface, &count, raw_data(formats)) or_return
    

    // If there is no preferred format, pick whatever
    if len(formats) == 1 && formats[0].format == .UNDEFINED {
            swapchain.format = formats[0]
            swapchain.format.format = .B8G8R8A8_UNORM
    }

    assert(len(formats) > 0)

    for candidate in formats {
            #partial switch candidate.format {
                    case .R8G8B8A8_UNORM, .B8G8R8A8_UNORM, .A8B8G8R8_UNORM_PACK32:
                            swapchain.format = candidate
                            break 
                    case:
                            break
            }
            if swapchain.format.format != .UNDEFINED do break
    }

    if swapchain.format.format == .UNDEFINED do swapchain.format = formats[0]

    caps := swapchain.support.capabilities
    if caps.currentExtent.width != max(u32) {
            swapchain.extent = caps.currentExtent
    }
    else {
            swapchain.extent.width = clamp(
                    swapchain.extent.width,
                    caps.minImageExtent.width,
                    caps.maxImageExtent.width,
            )
            swapchain.extent.height = clamp(
                    swapchain.extent.height,
                    caps.minImageExtent.height,
                    caps.maxImageExtent.height,
            )
    }

    vk.GetPhysicalDeviceSurfacePresentModesKHR(gpu, surface, &count, nil) or_return
    present_modes := make([]vk.PresentModeKHR, count)
    defer delete(present_modes)

    swapchain.present_mode = .IMMEDIATE
    for mode in present_modes {
            if mode == .MAILBOX do swapchain.present_mode = mode
    }


    // Determine the number of [vk.Image]s to use in the swapchain.
    // Ideally, we desire to own 1 image at a time, the rest of the images can
    // either be rendered to and/or being queued up for display.
    // Simply sticking to this minimum means that we may sometimes have to wait on the driver to
    // complete internal operations before we can acquire another image to render to.
    // Therefore it is recommended to request at least one more image than the minimum.
    preferred := swapchain.support.capabilities.minImageCount + 1
    swapchain.image_count = preferred if swapchain.support.capabilities.maxImageCount == 0 \
            else min(preferred, swapchain.support.capabilities.maxImageCount)

    // Find the right queue families
    all_in_one_queue := queue_indices[.GRAPHICS] == queue_indices[.PRESENT]
    queue_family_indices := []u32{ u32(queue_indices[.GRAPHICS]), u32(queue_indices[.PRESENT]) }

    old_swapchain := swapchain
    swapchain_create_info : vk.SwapchainCreateInfoKHR = {
        sType = .SWAPCHAIN_CREATE_INFO_KHR,
        surface = surface,
        minImageCount = swapchain.image_count,
        imageFormat = swapchain.format.format,
        imageColorSpace = swapchain.format.colorSpace,
        imageExtent = swapchain.extent,
        imageArrayLayers = 1,
        imageUsage =  { .COLOR_ATTACHMENT },
        imageSharingMode = .EXCLUSIVE if all_in_one_queue else .CONCURRENT,
        queueFamilyIndexCount = 0 if all_in_one_queue else 2,
        pQueueFamilyIndices = nil if all_in_one_queue else raw_data(queue_family_indices),
        preTransform = swapchain.support.capabilities.currentTransform,
        compositeAlpha = { .OPAQUE },
        presentMode = swapchain.present_mode,
        clipped = true,
        oldSwapchain = old_swapchain.handle,
    }

    vk.CreateSwapchainKHR(device, &swapchain_create_info, nil, &swapchain.handle) or_return

    if &old_swapchain.handle != nil {
            /* TODO: Tear down old swapchain */
    }

    vk.GetSwapchainImagesKHR(device, swapchain.handle, &count, nil) or_return
    swapchain.images = make([]vk.Image, count)
    vk.GetSwapchainImagesKHR(device, swapchain.handle, &count, raw_data(swapchain.images)) or_return

    swapchain.image_views = make([]vk.ImageView, count)

    for i in 0..<count {
        image_view_create_info : vk.ImageViewCreateInfo = {
            sType = .IMAGE_VIEW_CREATE_INFO,
            image = swapchain.images[i],
            viewType = .D2,
            format = swapchain.format.format,
            components = { r = .IDENTITY, g = .IDENTITY, b = .IDENTITY, a = .IDENTITY },

            // A subresource range specifies which aspect of the image we desire to operate on.
            subresourceRange = {
                aspectMask = { .COLOR },
                baseMipLevel = 0,
                levelCount = 1,
                baseArrayLayer = 0,
                layerCount = 1,
            },
        }

        vk.CreateImageView(device, &image_view_create_info, nil, &(swapchain.image_views[i])) or_return
    }

    return .SUCCESS
}

cleanup_swapchain :: proc(using ctx: ^RenderContext) {
    cleanup_swapchain_framebuffers(ctx)

    for image_view in swapchain.image_views {
            vk.DestroyImageView(device, image_view, nil)
    }

    vk.DestroySwapchainKHR(device, swapchain.handle, nil)

    delete(swapchain.image_views)
    delete(swapchain.images)
}

init_swapchain_framebuffers :: proc(using ctx: ^RenderContext) -> vk.Result {
    swapchain.framebuffers = make([]vk.Framebuffer, len(swapchain.image_views)) 

    for i in 0..<len(swapchain.image_views) {
            attachments: []vk.ImageView = { swapchain.image_views[i] }

            framebuffer_create_info: vk.FramebufferCreateInfo = {
                    sType = .FRAMEBUFFER_CREATE_INFO,
                    renderPass = render_data.render_pass,
                    attachmentCount = 1,
                    pAttachments = raw_data(attachments),
                    width = swapchain.extent.width,
                    height = swapchain.extent.height,
                    layers = 1,
            }

            vk.CreateFramebuffer(device, &framebuffer_create_info, nil, &swapchain.framebuffers[i]) or_return
    }

    return .SUCCESS
}

cleanup_swapchain_framebuffers :: proc(this: ^RenderContext) {
    vk.QueueWaitIdle(this.queues[.GRAPHICS])

    for framebuffer in this.swapchain.framebuffers {
            vk.DestroyFramebuffer(this.device, framebuffer, nil)
    }

    delete(this.swapchain.framebuffers)
}

