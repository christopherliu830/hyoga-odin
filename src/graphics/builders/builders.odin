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


	vk13_features := vk.PhysicalDeviceVulkan13Features {
		sType = .PHYSICAL_DEVICE_VULKAN_1_3_FEATURES,
		pNext = nil,
		synchronization2 = true,
	}

    // Create Device features and chain to indexing features,
    // then populate values.
    indexing_features := vk.PhysicalDeviceDescriptorIndexingFeatures { sType = .PHYSICAL_DEVICE_DESCRIPTOR_INDEXING_FEATURES }
    gpu_features := vk.PhysicalDeviceFeatures2 { sType = .PHYSICAL_DEVICE_FEATURES_2 }
    gpu_features.pNext = &indexing_features
    vk.GetPhysicalDeviceFeatures2(gpu, &gpu_features)

    indexing_features.pNext = &vk13_features

	shader_features: vk.PhysicalDeviceShaderDrawParametersFeatures = {
        sType                = .PHYSICAL_DEVICE_SHADER_DRAW_PARAMETERS_FEATURES,
		pNext				 = &gpu_features,
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

create_framebuffer :: proc(device:       vk.Device,
                           render_pass:  vk.RenderPass,
                           attachments:  []vk.ImageView,
                           extent:       vk.Extent3D) ->
(framebuffer: vk.Framebuffer) {

    info := vk.FramebufferCreateInfo {
        sType           = .FRAMEBUFFER_CREATE_INFO,
        pNext           = nil,
        flags           = nil,
        renderPass      = render_pass,
        attachmentCount = u32(len(attachments)),
        pAttachments    = raw_data(attachments),
        width           = extent.width,
        height          = extent.height,
        layers          = 1,
    }

    vk_assert(vk.CreateFramebuffer(device, &info, nil, &framebuffer))
    return framebuffer
}

create_instance :: proc(extensions: []cstring, layers: []cstring = nil) ->
(instance: vk.Instance) {
    application_info := vk.ApplicationInfo {
        sType            = .APPLICATION_INFO,
        pApplicationName = "Untitled",
        pEngineName      = "Hyoga",
        apiVersion       = vk.API_VERSION_1_3,
    }

    info := vk.InstanceCreateInfo {
        sType                   = .INSTANCE_CREATE_INFO,
        flags                   = nil,
        enabledExtensionCount   = u32(len(extensions)),
        ppEnabledExtensionNames = raw_data(extensions),
        enabledLayerCount       = u32(len(layers)),
        ppEnabledLayerNames     = raw_data(layers),
        pApplicationInfo        = &application_info,
    }

    when ODIN_OS == .Darwin {
        info.flags += { .ENUMERATE_PORTABILITY_KHR }
    }

    vk_assert(vk.CreateInstance(&info, nil, &instance))

    return instance
}

create_sampler :: proc(device: vk.Device, maxAnis: f32) -> 
(sampler: vk.Sampler) {
	info := vk.SamplerCreateInfo {
		sType                   = .SAMPLER_CREATE_INFO,
		magFilter               = .LINEAR,
		minFilter               = .LINEAR,
		addressModeU            = .CLAMP_TO_BORDER,
		addressModeV            = .CLAMP_TO_BORDER,
		addressModeW            = .CLAMP_TO_BORDER,
		anisotropyEnable        = false,
		maxAnisotropy           = maxAnis,
		borderColor             = .INT_OPAQUE_WHITE,
		unnormalizedCoordinates = false,
		compareEnable           = false,
		compareOp               = .ALWAYS,
		mipmapMode              = .LINEAR,
		mipLodBias              = 0.0,
		minLod                  = 0.0,
		maxLod                  = 0.0,
	}

	vk_assert(vk.CreateSampler(device, &info, nil, &sampler))
	return
}

create_semaphore :: proc(device: vk.Device) -> (semaphore: vk.Semaphore) {
    info := vk.SemaphoreCreateInfo { sType = .SEMAPHORE_CREATE_INFO }

    vk_assert(vk.CreateSemaphore(device, &info, nil, &semaphore))
    return semaphore
}

create_shader_module :: proc(device: vk.Device, data: []u8) -> (mod: vk.ShaderModule) {
    info := vk.ShaderModuleCreateInfo {
        sType    = .SHADER_MODULE_CREATE_INFO,
        codeSize = len(data),
        pCode    = cast(^u32)(raw_data(data)),
    }

    vk_assert(vk.CreateShaderModule(device, &info, nil, &mod))
    return mod
}

