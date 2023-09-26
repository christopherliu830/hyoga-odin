package graphics

import "core:log"

import vk "vendor:vulkan"
import glfw "vendor:glfw"

gpu_create :: proc(instance: vk.Instance, window: glfw.WindowHandle) ->
(gpu: vk.PhysicalDevice, surface: vk.SurfaceKHR, queues: [QueueFamily]int) {

    devices := gpu_make_devices(instance)
    defer delete(devices)

    for _, i in devices {
        gpu = devices[i]
        properties: vk.PhysicalDeviceProperties
        vk.GetPhysicalDeviceProperties(gpu, &properties)

        if surface != 0 do vk.DestroySurfaceKHR(instance, surface, nil)
        glfw.CreateWindowSurface(instance, window, nil, &surface)
        queues, qs_found := gpu_choose_queues(gpu, surface)

        if qs_found {
            log.infof("Enabled GPU: %s\n", &properties.deviceName)
            return gpu, surface, queues
        }

    }
    assert(false)
    return gpu, surface, queues
}

gpu_choose_queues :: proc(gpu: vk.PhysicalDevice, surface: vk.SurfaceKHR) ->
(queues: [QueueFamily]int, all_queues_found: bool){
    qf_props := gpu_make_queue_family_properties(gpu)
    defer delete(qf_props)

    q_indices := [QueueFamily]int { .GRAPHICS = -1, .PRESENT = -1 }

    all_queues_found = false
    for queue, index in qf_props {
        if q_indices[.PRESENT] == -1 {
            supported: b32
            vk_assert(vk.GetPhysicalDeviceSurfaceSupportKHR(
                gpu,
                u32(index),
                surface,
                &supported,
            ))
            log.debug("supported", supported)
            if supported do q_indices[.PRESENT] = index
        } 
        if q_indices[.GRAPHICS] == -1 {
            log.debug("flags", queue.queueFlags)
            if .GRAPHICS in queue.queueFlags {
                q_indices[.GRAPHICS] = index
            }
        } 
        if q_indices[.GRAPHICS] != -1 &&  q_indices[.PRESENT] != -1 {
            all_queues_found = true
            break
        }
    }

    return queues, all_queues_found
}

gpu_make_devices :: proc(instance: vk.Instance) -> (devices: []vk.PhysicalDevice) {
    count: u32
    vk.EnumeratePhysicalDevices(instance, &count, nil)
    devices = make([]vk.PhysicalDevice, count)
    vk.EnumeratePhysicalDevices(instance, &count, raw_data(devices))
    return devices
}

gpu_make_queue_family_properties :: proc(gpu: vk.PhysicalDevice) -> (properties: []vk.QueueFamilyProperties) {
    count: u32
    vk.GetPhysicalDeviceQueueFamilyProperties(gpu, &count, nil)
    properties = make([]vk.QueueFamilyProperties, count)
    vk.GetPhysicalDeviceQueueFamilyProperties(gpu, &count, raw_data(properties))
    return properties
}

