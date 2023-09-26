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
            log.infof("Using GPU: %s\n", transmute(cstring)(&properties.deviceName))
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

    qis := [QueueFamily]int { .GRAPHICS = -1, .PRESENT = -1, .TRANSFER = -1 }

    for queue, index in qf_props {
        if qis[.PRESENT] == -1 {
            supported: b32
            vk_assert(vk.GetPhysicalDeviceSurfaceSupportKHR(
                gpu,
                u32(index),
                surface,
                &supported,
            ))
            if supported do qis[.PRESENT] = index
        } 

        if qis[.GRAPHICS] == -1 || qis[.GRAPHICS] == qis[.PRESENT] {
            if .GRAPHICS in queue.queueFlags do qis[.GRAPHICS] = index 
        } 
                
        if qis[.TRANSFER] == -1 || qis[.TRANSFER] == qis[.GRAPHICS] {
            if .TRANSFER in queue.queueFlags do qis[.TRANSFER] = index
        } 

        // break when all queues are found
        unfound_qs := 0
        for q in qis do if q == -1 do unfound_qs += 1
        if unfound_qs == 0 {
            return queues, true
        }
    }

    return queues, false
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

