package graphics

import vk "vendor:vulkan"
import mem "../memory"

StagingBuffer :: struct {
    device: vk.Device,
    queue: vk.Queue,
    buffer: Buffer,
    command_pool: vk.CommandPool,
    command_buffer: vk.CommandBuffer,
    fence: vk.Fence,
    submission_in_flight: bool,
}

STAGING_BUFFER_SIZE :: mem.MEGABYTE 

staging_buffer: StagingBuffer

