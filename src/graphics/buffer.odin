package graphics

import "core:mem"
import vk "vendor:vulkan"
import "vma"

Buffer :: struct {
        buffer: vk.Buffer,
        allocation: vma.Allocation,
        allocation_info: vma.AllocationInfo,
        item_count: u32,
        len: u32,
        buffer_size: vk.DeviceSize,
}

create_buffer :: proc(
using ctx: ^RenderContext,
size: vk.DeviceSize,
item_count: u32,
usage: vk.BufferUsageFlags,
preferred_flags: vma.AllocationCreateFlags,
memory_usage: vma.MemoryUsage = .AUTO,
memory_flags: vk.MemoryPropertyFlags = {},
) ->
(buffer: Buffer, result: vk.Result) {

        buffer.buffer_size = size
        buffer.item_count = item_count

        buffer_info: vk.BufferCreateInfo = {
                sType = .BUFFER_CREATE_INFO,
                size = size,
                usage = usage,
                sharingMode = .EXCLUSIVE,
        }

        allocation_info: vma.AllocationCreateInfo = {
                flags = preferred_flags,
                usage = memory_usage,
                requiredFlags = memory_flags,
        }

        vma.CreateBuffer(allocator,
                &buffer_info,
                &allocation_info,
                &buffer.buffer,
                &buffer.allocation,
                &buffer.allocation_info) or_return
        
        return buffer, .SUCCESS
}

// Map CPU memory into buffer.
allocate_buffer :: proc(using ctx: ^RenderContext, buffer: Buffer, data: rawptr) -> vk.Result {
        mapped_ptr : rawptr

        vma.MapMemory(allocator, buffer.allocation, &mapped_ptr)

        mem.copy(mapped_ptr, data, int(buffer.buffer_size))
        vma.FlushAllocation(allocator, buffer.allocation, buffer.buffer_size, 0) or_return
        vma.UnmapMemory(allocator, buffer.allocation)

        return .SUCCESS
        
}

// Destroy a buffer.
destroy_buffer :: proc(using ctx: ^RenderContext, buffer: Buffer) {
        vma.DestroyBuffer(allocator, buffer.buffer, buffer.allocation)
}
