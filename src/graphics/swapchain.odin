package graphics

import "core:log"

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

swapchain_create :: proc(device:         vk.Device,
                         gpu:            vk.PhysicalDevice,
                         surface:        vk.SurfaceKHR,
                         queue_indices:  [QueueFamily]int,
                         old_swapchain:  vk.SwapchainKHR = 0) ->
(swapchain: Swapchain) {
    vk.GetPhysicalDeviceSurfaceCapabilitiesKHR(gpu, surface, &swapchain.support.capabilities)

    count: u32
    vk_assert(vk.GetPhysicalDeviceSurfaceFormatsKHR(gpu, surface, &count, nil))
    formats := make([]vk.SurfaceFormatKHR, count)
    vk_assert(vk.GetPhysicalDeviceSurfaceFormatsKHR(gpu, surface, &count, raw_data(formats)))
    defer delete(formats)
    
    // If there is no preferred format, pick whatever
    if len(formats) == 1 && formats[0].format == .UNDEFINED {
        swapchain.format = formats[0]
        swapchain.format.format = .B8G8R8A8_UNORM
    }

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
    } else {
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

    vk_assert(vk.GetPhysicalDeviceSurfacePresentModesKHR(gpu, surface, &count, nil))
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
    queue_family_indices := []u32 { u32(queue_indices[.GRAPHICS]), u32(queue_indices[.PRESENT]) }

    old_swapchain := swapchain

    swapchain_create_info : vk.SwapchainCreateInfoKHR = {
        sType                 = .SWAPCHAIN_CREATE_INFO_KHR,
        surface               = surface,
        minImageCount         = swapchain.image_count,
        imageFormat           = swapchain.format.format,
        imageColorSpace       = swapchain.format.colorSpace,
        imageExtent           = swapchain.extent,
        imageArrayLayers      = 1,
        imageUsage            = { .COLOR_ATTACHMENT },
        imageSharingMode      = .EXCLUSIVE if all_in_one_queue else .CONCURRENT,
        queueFamilyIndexCount = 0 if all_in_one_queue else 2,
        pQueueFamilyIndices   = nil if all_in_one_queue else raw_data(queue_family_indices),
        preTransform          = swapchain.support.capabilities.currentTransform,
        compositeAlpha        = { .OPAQUE },
        presentMode           = swapchain.present_mode,
        clipped               = true,
        oldSwapchain          = old_swapchain.handle,
    }

    vk_assert(vk.CreateSwapchainKHR(device, &swapchain_create_info, nil, &swapchain.handle))

    if &old_swapchain.handle != nil do  swapchain_destroy(device, old_swapchain)

    vk_assert(vk.GetSwapchainImagesKHR(device, swapchain.handle, &count, nil))
    images := make([]vk.Image, count)
    defer delete(images)
    vk_assert(vk.GetSwapchainImagesKHR(device, swapchain.handle, &count, raw_data(images)))

    swapchain.images = make([]Image, count)
    for i in 0..<count do swapchain.images[i].handle = images[i]

    for i in 0..<count {
        image_view_create_info : vk.ImageViewCreateInfo = {
            sType = .IMAGE_VIEW_CREATE_INFO,
            image = images[i],
            viewType = .D2,
            format = swapchain.format.format,
            components = { r = .IDENTITY, g = .IDENTITY, b = .IDENTITY, a = .IDENTITY },
            subresourceRange = {
                aspectMask = { .COLOR },
                baseMipLevel = 0,
                levelCount = 1,
                baseArrayLayer = 0,
                layerCount = 1,
            },
        }

        vk_assert(vk.CreateImageView(device, &image_view_create_info, nil, &(swapchain.images[i].view)))
    }

    extent := vk.Extent3D { swapchain.extent.width, swapchain.extent.height, 1 }
    swapchain.depth_image = buffers_create_image(device, extent, { .DEPTH_STENCIL_ATTACHMENT })

    return swapchain
}

swapchain_destroy :: proc(device: vk.Device, swapchain: Swapchain) {

    for image in swapchain.images do vk.DestroyImageView(device, image.view, nil)

    buffers_destroy(device, swapchain.depth_image)

    // Images controlled by swapchain do not need to be destroyed

    vk.DestroySwapchainKHR(device, swapchain.handle, nil)

    delete(swapchain.images)
}

swapchain_create_framebuffers :: proc(device:      vk.Device,
                                      render_pass: vk.RenderPass,
                                      swapchain:   Swapchain) ->
(framebuffers: []vk.Framebuffer) {
    framebuffers = make([]vk.Framebuffer, swapchain.image_count) 

    for i in 0..<swapchain.image_count {
        attachments: []vk.ImageView = { swapchain.images[i].view, swapchain.depth_image.view }

        framebuffer_create_info: vk.FramebufferCreateInfo = {
            sType           = .FRAMEBUFFER_CREATE_INFO,
            renderPass      = render_pass,
            attachmentCount = u32(len(attachments)),
            pAttachments    = raw_data(attachments),
            width           = swapchain.extent.width,
            height          = swapchain.extent.height,
            layers          = 1,
        }

        vk_assert(vk.CreateFramebuffer(device, &framebuffer_create_info, nil, &framebuffers[i]))
    }

    return framebuffers
}

swapchain_destroy_framebuffers :: proc(device: vk.Device, framebuffers: []vk.Framebuffer) {
    for framebuffer in framebuffers {
        vk.DestroyFramebuffer(device, framebuffer, nil)
    }
    delete(framebuffers)
}

