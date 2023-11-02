package graphics 

import "core:container/intrusive/list"
import "core:log"

import vk "vendor:vulkan"
import "builders"

UnscaledPoolSize :: struct {
    type:  vk.DescriptorType,

    size:  f32,
}

DescriptorLink :: struct {
    link: list.Node,
    pool: vk.DescriptorPool,
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

MAX_DESCRIPTOR_POOLS :: 4

current_descriptor_pool: ^DescriptorLink
descriptor_pools: [MAX_DESCRIPTOR_POOLS]DescriptorLink
descriptor_pool_free_list: list.List

descriptors_create_pool :: proc (device: vk.Device, num_sets: int) -> DescriptorLink {
    pool_sizes : [len(DESCRIPTOR_POOL_SIZES)]vk.DescriptorPoolSize

    for unscaled_size, i in DESCRIPTOR_POOL_SIZES {
        pool_sizes[i] = { unscaled_size.type, u32(unscaled_size.size * f32(num_sets)) }
    }

    return DescriptorLink { pool = builders.create_descriptor_pool(device, num_sets, pool_sizes[:]) }
}

descriptors_init :: proc(device: vk.Device) {
    for i in 0..<len(descriptor_pools) {
        list.push_front(&descriptor_pool_free_list, &descriptor_pools[i].link)
    }

    node := list.pop_back(&descriptor_pool_free_list)
    current_descriptor_pool = container_of(node, DescriptorLink, "link")
    current_descriptor_pool^ = descriptors_create_pool(device, 1000)
}

descriptors_get_one :: proc(device: vk.Device, layout: vk.DescriptorSetLayout) -> vk.DescriptorSet {
    pool := current_descriptor_pool.pool
    descriptor, result := builders.allocate_descriptor(device, pool, layout)

    if result == .ERROR_OUT_OF_POOL_MEMORY {
        list.push_front(&descriptor_pool_free_list, &current_descriptor_pool.link)
        node := list.pop_back(&descriptor_pool_free_list)
        current_descriptor_pool = container_of(node, DescriptorLink, "link")
        if current_descriptor_pool.pool == 0 {
            current_descriptor_pool^ = descriptors_create_pool(device, 1000)
        }

        vk_assert(vk.ResetDescriptorPool(device, current_descriptor_pool.pool, {}))
        descriptor, result = builders.allocate_descriptor(device, current_descriptor_pool.pool, layout)
        return descriptor
    }


    return descriptor 
}
