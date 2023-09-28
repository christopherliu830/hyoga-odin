package graphics 

import vk "vendor:vulkan"
import "builders"

UnscaledPoolSize :: struct {
    type:  vk.DescriptorType,

    size:  f32,
}

DESCRIPTOR_POOL_SIZES :: [?]UnscaledPoolSize {
    { .SAMPLER, 0.5 },
    { .COMBINED_IMAGE_SAMPLER, 4 },
    { .SAMPLED_IMAGE, 4 },
    { .STORAGE_IMAGE, 1 },
    { .UNIFORM_TEXEL_BUFFER, 1 },
    { .STORAGE_TEXEL_BUFFER, 1 },
    { .UNIFORM_BUFFER, 2 },
    { .STORAGE_BUFFER, 2 },
    { .UNIFORM_BUFFER_DYNAMIC, 1 },
    { .STORAGE_BUFFER_DYNAMIC, 1 },
    { .INPUT_ATTACHMENT, 0.5 },
}

descriptors_create_pool :: proc (device: vk.Device, num_sets: int) -> vk.DescriptorPool {
    pool_sizes : [len(DESCRIPTOR_POOL_SIZES)]vk.DescriptorPoolSize

    for unscaled_size, i in DESCRIPTOR_POOL_SIZES {
        pool_sizes[i] = { unscaled_size.type, u32(unscaled_size.size * f32(num_sets)) }
    }

    return builders.create_descriptor_pool(device, num_sets, pool_sizes[:]) 
}




