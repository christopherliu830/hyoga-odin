package builders

import "core:log"

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

create_command_pool :: proc(device: vk.Device) -> (pool: vk.CommandPool) {
    info: vk.CommandPoolCreateInfo = {
        sType = .COMMAND_POOL_CREATE_INFO,
        flags = { .TRANSIENT },
    }

    vk_assert(vk.CreateCommandPool(device, &info, nil, &pool))
    return pool
}

create_fence :: proc(device: vk.Device) -> (fence: vk.Fence) {
    info: vk.FenceCreateInfo = { sType = .FENCE_CREATE_INFO }

    vk_assert(vk.CreateFence(device, &info, nil, &fence))
    return fence
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

