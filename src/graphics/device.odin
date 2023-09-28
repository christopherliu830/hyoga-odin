package graphics 

import vk "vendor:vulkan"

import "builders"

device_create :: proc(gpu: vk.PhysicalDevice, q_idxs: [QueueFamily]int ) ->
(device: vk.Device, queues: [QueueFamily]vk.Queue) {

    n_exts := 1
    extensions := [2]cstring { vk.KHR_SWAPCHAIN_EXTENSION_NAME, nil }
    if device_find_portability(gpu) {
        extensions[1] = "VK_KHR_portability_subset"
        n_exts = 2
    }

    queue_infos := [len(QueueFamily)]vk.DeviceQueueCreateInfo {}
    queue_priorities := [len(QueueFamily)]f32 {}

    n_queues := 0
    for queue_idx in q_idxs {
        // Skip a repeated queue
        if n_queues > 0 && u32(queue_idx) == queue_infos[n_queues-1].queueFamilyIndex {
            continue
        }

        queue_priorities[n_queues] = 1
        queue_infos[n_queues] = {
            sType            = .DEVICE_QUEUE_CREATE_INFO,
            queueFamilyIndex = u32(queue_idx),
            queueCount       = 1,
            pQueuePriorities = &queue_priorities[n_queues],
        }

        n_queues += 1
    }
    
    device = builders.create_device(gpu, queue_infos[:n_queues], extensions[:n_exts])

    for index, family in q_idxs {
        vk.GetDeviceQueue(device, u32(index), 0, &queues[family])
    }

    return device, queues
}

device_find_portability :: proc(gpu: vk.PhysicalDevice) -> (found: bool) {
    count: u32
    vk.EnumerateDeviceExtensionProperties(gpu, nil, &count, nil)
    ext_props := make([]vk.ExtensionProperties, count)
    vk.EnumerateDeviceExtensionProperties(gpu, nil, &count, raw_data(ext_props))

    portability_found := false
    for properties in ext_props {
        p := properties
        switch transmute(string)p.extensionName[:] {
            case "VK_KHR_portability_subset":
                portability_found = true
                break
        }
    }
    return portability_found
}
