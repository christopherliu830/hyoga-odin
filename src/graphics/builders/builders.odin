package builders

import "core:log"

import vma "pkgs:vma"
import vk "vendor:vulkan"

create_command_buffer :: proc(device: vk.Device, pool: vk.CommandPool) -> (cmd: vk.CommandBuffer) {
    info: vk.CommandBufferAllocateInfo = {
        sType              = .COMMAND_BUFFER_ALLOCATE_INFO,
        commandPool        = pool,
        level              = .PRIMARY,
        commandBufferCount = 1,
    }
    
    vk_assert(vk.AllocateCommandBuffers(device, &info, &cmd))
    return cmd
}

create_command_pool :: proc(device: vk.Device, 
                            flags: vk.CommandPoolCreateFlags = {}) ->
(pool: vk.CommandPool) {
    info: vk.CommandPoolCreateInfo = {
        sType = .COMMAND_POOL_CREATE_INFO,
        flags = flags,
    }

    vk_assert(vk.CreateCommandPool(device, &info, nil, &pool))
    return pool
}

create_device :: proc(gpu: vk.PhysicalDevice,
                      queues: []vk.DeviceQueueCreateInfo,
                      extensions: []cstring = {},
                      layers: []cstring = {}) ->
(device: vk.Device) {
    shader_features: vk.PhysicalDeviceShaderDrawParametersFeatures = {
        sType                = .PHYSICAL_DEVICE_SHADER_DRAW_PARAMETERS_FEATURES,
        shaderDrawParameters = true,
    }

    device_create_info: vk.DeviceCreateInfo = {
        sType                   = .DEVICE_CREATE_INFO,
        enabledExtensionCount   = u32(len(extensions)),
        ppEnabledExtensionNames = raw_data(extensions),
        enabledLayerCount       = u32(len(layers)),
        ppEnabledLayerNames     = raw_data(layers),
        queueCreateInfoCount    = u32(len(queues)),
        pQueueCreateInfos       = raw_data(queues),
        pNext                   = &shader_features,
    }

    vk_assert(vk.CreateDevice(gpu, &device_create_info, nil, &device))
    return device
}

create_fence :: proc(device: vk.Device, flags: vk.FenceCreateFlags = {}) ->
(fence: vk.Fence) {
    info := vk.FenceCreateInfo {
        sType = .FENCE_CREATE_INFO,
        flags = flags,
    }

    vk_assert(vk.CreateFence(device, &info, nil, &fence))
    return fence
}

create_instance :: proc(extensions: []cstring, layers: []cstring) ->
(instance: vk.Instance) {
    application_info: vk.ApplicationInfo = {
        sType            = .APPLICATION_INFO,
        pApplicationName = "Untitled",
        pEngineName      = "Hyoga",
        apiVersion       = vk.API_VERSION_1_3,
    }

    info: vk.InstanceCreateInfo = {
        sType                   = .INSTANCE_CREATE_INFO,
        flags                   = nil,
        enabledExtensionCount   = u32(len(extensions)),
        ppEnabledExtensionNames = raw_data(extensions),
        enabledLayerCount       = u32(len(layers)),
        ppEnabledLayerNames     = raw_data(layers),
        pApplicationInfo        = &application_info,
    }

    vk_assert(vk.CreateInstance(&info, nil, &instance))
    return instance
}

create_semaphore :: proc(device: vk.Device) -> (semaphore: vk.Semaphore) {
    info: vk.SemaphoreCreateInfo = {
        sType = .SEMAPHORE_CREATE_INFO,
    }
    vk_assert(vk.CreateSemaphore(device, &info, nil, &semaphore))
    return semaphore
}

create_shader_module :: proc(device: vk.Device, data: []u8) -> (mod: vk.ShaderModule) {
    info: vk.ShaderModuleCreateInfo = {
        sType = .SHADER_MODULE_CREATE_INFO,
        codeSize = len(data),
        pCode = cast(^u32)(raw_data(data)),
    }

    vk_assert(vk.CreateShaderModule(device, &info, nil, &mod))
    return mod
}

