package graphics

import "core:mem"
import vk "vendor:vulkan"

Buffer :: struct {
        buffer: vk.Buffer,
        memory: vk.DeviceMemory,
        item_count: u32,
        buffer_size: vk.DeviceSize,
}


create_buffer :: proc(
device: vk.Device,
gpu: vk.PhysicalDevice,
item_size: u32,
count: u32) ->
(buffer: Buffer, result: vk.Result) {

        buffer.item_count = count
        buffer.buffer_size = vk.DeviceSize(item_size * count)

        buffer_info: vk.BufferCreateInfo = {
                sType = .BUFFER_CREATE_INFO,
                size = vk.DeviceSize(item_size * count),
                usage = { .VERTEX_BUFFER },
                sharingMode = .EXCLUSIVE,
        }

        vk.CreateBuffer(device, &buffer_info, nil, &buffer.buffer) or_return

        requirements: vk.MemoryRequirements
        vk.GetBufferMemoryRequirements(device, buffer.buffer, &requirements)

        allocate_info: vk.MemoryAllocateInfo = {
                sType = .MEMORY_ALLOCATE_INFO,
                allocationSize = requirements.size,
                memoryTypeIndex = find_memory_type(gpu, { .HOST_VISIBLE })
        }

        vk.AllocateMemory(device, &allocate_info, nil, &buffer.memory) or_return
        vk.BindBufferMemory(device, buffer.buffer, buffer.memory, 0)
        
        return buffer, .SUCCESS
}

// Map CPU memory into buffer.
allocate_buffer :: proc(device: vk.Device, buffer: Buffer, data: rawptr) -> vk.Result {
        mapped_ptr : rawptr

        vk.MapMemory(device, buffer.memory, 0, buffer.buffer_size, {}, &mapped_ptr)

        mem.copy(mapped_ptr, data, int(buffer.buffer_size))
        flush_buffer(device, buffer) or_return

        vk.UnmapMemory(device, buffer.memory)

        return .SUCCESS
        
}

// Destroy a buffer.
destroy_buffer :: proc(device: vk.Device, buffer: Buffer) {
        vk.DestroyBuffer(device, buffer.buffer, nil)
        vk.FreeMemory(device, buffer.memory, nil)
}

// Quick and dirty explicit flushing.
flush_buffer :: proc(device: vk.Device, buffer: Buffer) -> vk.Result {
        mapped_memory_range: vk.MappedMemoryRange = {
                sType = .MAPPED_MEMORY_RANGE,
                memory = buffer.memory,
                size = buffer.buffer_size,
                offset = 0,
        }

        vk.FlushMappedMemoryRanges(device, 1, &mapped_memory_range) or_return

        vk.InvalidateMappedMemoryRanges(device, 1, &mapped_memory_range) or_return

        return .SUCCESS
}

// Find a suitable memory type.
find_memory_type :: proc(
gpu: vk.PhysicalDevice,
typeMask: vk.MemoryPropertyFlags) -> u32 {
        properties: vk.PhysicalDeviceMemoryProperties
        vk.GetPhysicalDeviceMemoryProperties(gpu, &properties)

        for type, i in properties.memoryTypes {
                if typeMask <= type.propertyFlags {
                        return u32(i)
                }
        }

        return 0
}
