package graphics

import vk "vendor:vulkan"
import "core:fmt"

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

Perframe :: struct {
        device: vk.Device,
        queue_submit_fence: vk.Fence,
        primary_command_buffer: vk.CommandBuffer,
        primary_command_pool: vk.CommandPool,

        swapchain_acquire: vk.Semaphore,
        swapchain_release: vk.Semaphore,
}

SwapChainDetails :: struct
{
	capabilities: vk.SurfaceCapabilitiesKHR,
	formats: []vk.SurfaceFormatKHR,
	present_modes: []vk.PresentModeKHR,
}

/**
* Check if the swapchain is supported. Ignores VK errors for convenience.
*/
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

/**
* Create a swapchain.
*/
create_swapchain :: proc(using ctx: ^Context) -> (sc: Swapchain, result: vk.Result) {
        using sc

        vk.GetPhysicalDeviceSurfaceCapabilitiesKHR(physical_device, surface, &support.capabilities) or_return

        // Get the preferred format for the device.
        count: u32
        vk.GetPhysicalDeviceSurfaceFormatsKHR(physical_device, surface, &count, nil) or_return
        formats := make([]vk.SurfaceFormatKHR, count)
        defer delete(formats)
        vk.GetPhysicalDeviceSurfaceFormatsKHR(physical_device, surface, &count, raw_data(formats)) or_return

        // If there is no preferred format, pick whatever
        if len(formats) == 1 && formats[0].format == .UNDEFINED {
                sc.format = formats[0]
                sc.format.format = .B8G8R8A8_UNORM
        }

        assert(len(formats) > 0)

        for candidate in formats {
                #partial switch candidate.format {
                        case .R8G8B8A8_UNORM, .B8G8R8A8_UNORM, .A8B8G8R8_UNORM_PACK32:
                                format = candidate
                                break 
                        case:
                                break
                }
                if format.format != .UNDEFINED do break
        }

        if format.format == .UNDEFINED do format = formats[0]

        window_width, window_height := get_frame_buffer_size(ctx)
        extent = choose_swapchain_extents(support.capabilities, window_width, window_height)

        vk.GetPhysicalDeviceSurfacePresentModesKHR(physical_device, surface, &count, nil) or_return
        present_modes := make([]vk.PresentModeKHR, count)
        defer delete(present_modes)

        present_mode = choose_swapchain_present_mode(present_modes)

        // Determine the number of [vk.Image]s to use in the swapchain.
        // Ideally, we desire to own 1 image at a time, the rest of the images can
        // either be rendered to and/or being queued up for display.
        // Simply sticking to this minimum means that we may sometimes have to wait on the driver to
        // complete internal operations before we can acquire another image to render to.
        // Therefore it is recommended to request at least one more image than the minimum.
        preferred := support.capabilities.minImageCount + 1
        image_count = preferred if support.capabilities.maxImageCount == 0 \
                else min(preferred, support.capabilities.maxImageCount)

        // Find the right queue families
        
        all_in_one_queue := queue_indices[.GRAPHICS] == queue_indices[.PRESENT]
        queue_family_indices := []u32{ u32(queue_indices[.GRAPHICS]), u32(queue_indices[.PRESENT]) }

        old_swapchain := swapchain
        swapchain_create_info : vk.SwapchainCreateInfoKHR = {
                sType = .SWAPCHAIN_CREATE_INFO_KHR,
                surface = surface,
                minImageCount = image_count,
                imageFormat = format.format,
                imageColorSpace = format.colorSpace,
                imageExtent = extent,
                imageArrayLayers = 1,
                imageUsage =  { .COLOR_ATTACHMENT },
                imageSharingMode = .EXCLUSIVE if all_in_one_queue else .CONCURRENT,
                queueFamilyIndexCount = 0 if all_in_one_queue else 2,
                pQueueFamilyIndices = nil if all_in_one_queue else raw_data(queue_family_indices),
                preTransform = support.capabilities.currentTransform,
                compositeAlpha = { .OPAQUE },
                presentMode = present_mode,
                clipped = true,
                oldSwapchain = old_swapchain.handle,
        }

        vk.CreateSwapchainKHR(device, &swapchain_create_info, nil, &handle) or_return

        if &old_swapchain.handle != nil {
                /* TODO: Tear down old swapchain */
        }

        vk.GetSwapchainImagesKHR(device, handle, &count, nil) or_return
        images = make([]vk.Image, count)
        vk.GetSwapchainImagesKHR(device, handle, &count, raw_data(images)) or_return

        image_views = make([]vk.ImageView, count)

        for i in 0..<count {
                image_view_create_info : vk.ImageViewCreateInfo = {
                        sType = .IMAGE_VIEW_CREATE_INFO,
                        image = images[i],
                        viewType = .D2,
                        format = format.format,
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

                vk.CreateImageView(device, &image_view_create_info, nil, &(image_views[i])) or_return
        }

        return sc, .SUCCESS
}

/**
* Cleanup the swapchain.
*/

cleanup_swapchain :: proc(using ctx: ^Context) {
        for image_view in swapchain.image_views {
                vk.DestroyImageView(device, image_view, nil)
        }

        vk.DestroySwapchainKHR(device, swapchain.handle, nil)
}

/**
* The swap extent is the resolution of the swap chain images and
* it's almost always exactly equal to the resolution of the window
* that we're drawing to in pixels. If the swap extent is set to max(u32)
* then try to match the window resolution.
*/
choose_swapchain_extents :: proc(caps: vk.SurfaceCapabilitiesKHR, w, h: u32) -> vk.Extent2D {
        if caps.currentExtent.width != max(u32) do return caps.currentExtent
        else {
                extent: vk.Extent2D = { width = w, height = h }
                extent.width = clamp(extent.width, caps.minImageExtent.width, caps.maxImageExtent.width)
                extent.height = clamp(extent.height, caps.minImageExtent.height, caps.maxImageExtent.height)
                return extent
        }
}

/**
* A summary of swapchain present modes from 
* https://vulkan-tutorial.com/Drawing_a_triangle/Presentation/Swap_chain#page_Presentation-mode
* 
*   VK_PRESENT_MODE_IMMEDIATE_KHR: Images submitted by your application are
*   transferred to the screen right away, which may result in tearing.

*   VK_PRESENT_MODE_FIFO_KHR: The swap chain is a queue where the display takes
*   an image from the front of the queue when the display is refreshed and the program
*   inserts rendered images at the back of the queue. If the queue is full then the program has
*   to wait. This is most similar to vertical sync as found in modern games. The moment that the
*   display is refreshed is known as "vertical blank".

*   VK_PRESENT_MODE_FIFO_RELAXED_KHR: This mode only differs from the previous one if the
*   application is late and the queue was empty at the last vertical blank. Instead of waiting
*   for the next vertical blank, the image is transferred right away when it finally arrives.
*   This may result in visible tearing.
*
*   VK_PRESENT_MODE_MAILBOX_KHR: This is another variation of the second mode. Instead of
*   blocking the application when the queue is full, the images that are already queued are simply
*   replaced with the newer ones. This mode can be used to render frames as fast as possible while
*   still avoiding tearing, resulting in fewer latency issues than standard vertical sync. This is
*   commonly known as "triple buffering", although the existence of three buffers alone does not
*   necessarily mean that the framerate is unlocked.
*/
choose_swapchain_present_mode :: proc(available_present_modes: []vk.PresentModeKHR) -> vk.PresentModeKHR {
        for present_mode in available_present_modes {
                if present_mode == .MAILBOX {
                        return present_mode
                }
        }
        return .IMMEDIATE
}