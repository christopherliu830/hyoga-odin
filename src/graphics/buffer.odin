package graphics

import vk "vendor:vulkan"

Buffer :: struct {

}


create_buffer :: proc(size: vk.DeviceSize) {
        buffer_info : vk.BufferCreateInfo = {
                sType = .BUFFER_CREATE_INFO,
                size = size,
                usage = { .VERTEX_BUFFER },
                sharingMode = .EXCLUSIVE,
        }
}

// Find a suitable memory type.
find_memory_type :: proc(
gpu: vk.PhysicalDevice,
typeMask: vk.MemoryPropertyFlags) -> int {
        properties: vk.PhysicalDeviceMemoryProperties
        vk.GetPhysicalDeviceMemoryProperties(gpu, &properties)

        for type, i in properties.memoryTypes {
                if typeMask <= type.propertyFlags {
                        return i
                }
        }

        return -1
}
