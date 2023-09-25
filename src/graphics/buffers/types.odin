package buffer

import vk "vendor:vulkan"
import "../vma"

Result :: enum {
    OK,
    NEEDS_FLUSH,
    STAGED,
}

BufferType :: enum {
    INDEX,
    VERTEX,
    STAGING,
    UNIFORM,
    UNIFORM_DYNAMIC
}

Buffer :: struct {
    handle:      vk.Buffer,
    allocation:  vma.Allocation,
    size:        int,
    mapped_ptr:  rawptr,
}

Slice :: struct {
    ptr:  u32,
    size: u32
}

CreateFlags:: struct {
    usage:      vk.BufferUsageFlags,
    vma:        vma.AllocationCreateFlags,
    required:   vk.MemoryPropertyFlags,
    preferred:  vk.MemoryPropertyFlags,
}

UploadContext :: struct {
    command_buffer:  vk.CommandBuffer,
    buffer:          Buffer,
    offset:          uintptr,
}

UnflushedArea :: struct {
    ptr: rawptr,
    size: int
}

StagingPlatform :: struct {
    device:                vk.Device,
    queue:                 vk.Queue,
    buffer:                Buffer,
    offset:                uintptr,
    command_pool:          vk.CommandPool,
    command_buffer:        vk.CommandBuffer,
    fence:                 vk.Fence,
    submission_in_flight:  bool,
}
