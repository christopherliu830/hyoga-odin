//+private
package materials

import vk "vendor:vulkan"
import "../builders"

LayoutType:: enum {
    DEFAULT,
    ONE_COLOR,
}

DescriptorNumber :: enum {
    GLOBAL,
    RESERVED,
    PER_MATERIAL,
    PER_OBJECT,
    COUNT,
}

// Big switch statement for manual vertex layouts.
create_descriptor_layout:: proc(device: vk.Device, type: LayoutType) -> 
(layouts: [DescriptorNumber.COUNT]vk.DescriptorSetLayout) {

    // Global:
    //  camera_buffer: ubo
    layouts[DescriptorNumber.GLOBAL] = builders.create_descriptor_set_layout(device, {
        {
            binding         = 0,
            descriptorType  = .UNIFORM_BUFFER_DYNAMIC,
            descriptorCount = 1,
            stageFlags      = { .VERTEX },
        },
    })

    switch(type) {

        // Objects:
        //  object_buffer: ubo
        case .DEFAULT:
            layouts[DescriptorNumber.PER_OBJECT] = builders.create_descriptor_set_layout(device, {
                {
                    binding = 0,
                    descriptorType = .UNIFORM_BUFFER_DYNAMIC,
                    descriptorCount = 1,
                    stageFlags = { .VERTEX },
                },
            })

        // Materials:
        //  material_buffer: ubo
        // Objects:
        //  object_buffer: ubo
        case .ONE_COLOR:
            layouts[DescriptorNumber.PER_MATERIAL] = builders.create_descriptor_set_layout(device, {
                {
                    binding = 0,
                    descriptorType = .UNIFORM_BUFFER,
                    descriptorCount = 1,
                    stageFlags = { .VERTEX },
                },
            })

            layouts[DescriptorNumber.PER_OBJECT] = builders.create_descriptor_set_layout(device, {
                {
                    binding = 0,
                    descriptorType = .UNIFORM_BUFFER_DYNAMIC,
                    descriptorCount = 1,
                    stageFlags = { .VERTEX },
                },
            })
    }

    for i in 0..<int(DescriptorNumber.COUNT) do if (layouts[i] == 0) {
        layouts[i] = builders.create_descriptor_set_layout(device, {})
    }

    return layouts
}
