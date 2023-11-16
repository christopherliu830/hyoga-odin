package builders

import "core:log"

import vk "vendor:vulkan"

// Allocate multiple descriptors based on layout.
// Prefer using descriptors module.
allocate_descriptor_set :: proc(device: vk.Device,
                              pool: vk.DescriptorPool,
                              layouts: []vk.DescriptorSetLayout) ->
(sets: [4]vk.DescriptorSet, result: vk.Result) {
    info := vk.DescriptorSetAllocateInfo {
        sType = .DESCRIPTOR_SET_ALLOCATE_INFO,
        descriptorPool = pool,
        descriptorSetCount = u32(len(layouts)),
        pSetLayouts = raw_data(layouts),
    }

    result = vk.AllocateDescriptorSets(device, &info, raw_data(sets[:]))
    return sets, result
}

allocate_descriptor :: proc(device: vk.Device,
                            pool: vk.DescriptorPool,
                            layout: vk.DescriptorSetLayout) ->
(descriptor: vk.DescriptorSet, result: vk.Result) {
    layout := layout

    info := vk.DescriptorSetAllocateInfo {
        sType              = .DESCRIPTOR_SET_ALLOCATE_INFO,
        descriptorPool     = pool,
        descriptorSetCount = 1,
        pSetLayouts        = &layout,
    }

    result = vk.AllocateDescriptorSets(device, &info, &descriptor)
    return descriptor, result
}


bind_descriptor_set :: proc (device:   vk.Device,
                             info:     vk.DescriptorBufferInfo,
                             type:     vk.DescriptorType,
                             set:      vk.DescriptorSet,
                             binding:  int) {
    info := info

    write := vk.WriteDescriptorSet {
        sType           = .WRITE_DESCRIPTOR_SET,
        dstSet          = set,
        dstBinding      = u32(binding),
        descriptorCount = 1,
        descriptorType  = type,
        pBufferInfo     = &info,
    }

    vk.UpdateDescriptorSets(device, 1, &write, 0, nil)
}

bind_descriptor_set_image :: proc(device:   vk.Device,
                                  info:     vk.DescriptorImageInfo,
                                  set:      vk.DescriptorSet,
                                  binding:  int) {
    info := info

    write := vk.WriteDescriptorSet {
        sType           = .WRITE_DESCRIPTOR_SET,
        dstSet          = set,
        dstBinding      = u32(binding),
        descriptorCount = 1,
        descriptorType  = .COMBINED_IMAGE_SAMPLER,
        pImageInfo      = &info,
    }

    vk.UpdateDescriptorSets(device, 1, &write, 0, nil)

}

create_descriptor_set_layout :: proc(device: vk.Device, bindings: []vk.DescriptorSetLayoutBinding) ->
(layout: vk.DescriptorSetLayout) {
    info := vk.DescriptorSetLayoutCreateInfo {
        sType = .DESCRIPTOR_SET_LAYOUT_CREATE_INFO,
        bindingCount = u32(len(bindings)),
        pBindings = raw_data(bindings),
    }

    vk_assert(vk.CreateDescriptorSetLayout(device, &info, nil, &layout))
    return layout
}


create_descriptor_pool :: proc(device: vk.Device, num_sets: int, pool_sizes: []vk.DescriptorPoolSize) ->
(pool: vk.DescriptorPool) {
    info := vk.DescriptorPoolCreateInfo {
        sType = .DESCRIPTOR_POOL_CREATE_INFO,
        flags = {},
        maxSets = u32(num_sets),
        poolSizeCount = u32(len(pool_sizes)),
        pPoolSizes = raw_data(pool_sizes),
    }

    vk_assert(vk.CreateDescriptorPool(device, &info, nil, &pool))
    return pool
}

