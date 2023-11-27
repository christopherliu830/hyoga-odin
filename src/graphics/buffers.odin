package graphics

import "core:mem"
import "core:log"
import "core:fmt"
import "core:strconv"

import vk "vendor:vulkan"
import bt "pkgs:obacktracing"
import "pkgs:vma"

import "builders"

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
    type:        BufferType,
    size:        int,
    alignment:   int,
    mapped_ptr:  rawptr,
}

TBuffer :: struct($Type: typeid) {
    using buffer: Buffer,
    holding: Type,
}

STAGING_BUFFER_SIZE :: 8*mem.Megabyte
UNIFORM_BUFFER_SIZE :: 1*mem.Megabyte

BufferDefaultFlags :: [BufferType]BufferCreateFlags {
    .INDEX = {
        type = .INDEX,
        usage = { .INDEX_BUFFER, .TRANSFER_DST },
        vma = { .DEDICATED_MEMORY },
    },
    .VERTEX = {
        type = .VERTEX,
        usage = { .VERTEX_BUFFER , .TRANSFER_DST },
        vma = { .DEDICATED_MEMORY },
    },
    .STAGING = {
        type = .STAGING,
        usage = { .TRANSFER_SRC },
        vma = { .HOST_ACCESS_RANDOM , .MAPPED },
        required = { .HOST_VISIBLE },
        preferred = { .HOST_COHERENT },
    },
    .UNIFORM = {
        type = .UNIFORM,
        usage = { .UNIFORM_BUFFER },
        vma = { .HOST_ACCESS_SEQUENTIAL_WRITE, .MAPPED },
        required = { .HOST_VISIBLE },
    },
    .UNIFORM_DYNAMIC = {
        type = .UNIFORM_DYNAMIC,
        usage = { .UNIFORM_BUFFER, .TRANSFER_DST },
        vma = { .HOST_ACCESS_SEQUENTIAL_WRITE, .MAPPED },
        required = { .HOST_VISIBLE },
    },
}


vma_allocator: vma.Allocator
min_dubo_alignment: int

buffers_init :: proc(info: vma.AllocatorCreateInfo,
                     transfer_queue: vk.Queue,
                     gpu_properties: vk.PhysicalDeviceProperties) {
    info := info

    vulkan_functions := vma.create_vulkan_functions()
    info.pVulkanFunctions = &vulkan_functions

    vk_assert(vma.CreateAllocator(&info, &vma_allocator))

    min_dubo_alignment = int(gpu_properties.limits.minUniformBufferOffsetAlignment)
    log.info("graphics::buffers Init")
}

buffers_shutdown :: proc() {
    vma.DestroyAllocator(vma_allocator)
    log.info("graphics::buffers Shutdown")
}

/**
* Create a buffer.
*/
buffers_create :: proc(size: int, type: BufferType, alignment: int = mem.DEFAULT_ALIGNMENT) -> Buffer {
    return buffers_create_by_flags(size, buffers_default_flags(type), alignment)
}


// Create a Tbuffer.
// size - size of buffer in bytes.
buffers_create_tbuffer :: proc($T: typeid,
                               size: int,
                               type: BufferType,
                               alignment: int = mem.DEFAULT_ALIGNMENT) -> 
(buffer: TBuffer(T)) {
    buffer.buffer = buffers_create_by_flags(size, buffers_default_flags(type), mem.DEFAULT_ALIGNMENT)
    return buffer
}

buffers_create_by_flags :: proc(size:      int,
                                flags:     BufferCreateFlags,
                                alignment: int) ->
(buffer: Buffer) {
    assert(flags.usage != nil)
    fmt.assertf(!(flags.type == .UNIFORM_DYNAMIC && alignment != min_dubo_alignment),
                "Please create dynamic uniform buffers with buffers_create_dubo")

    buffer_info: vk.BufferCreateInfo = {
        sType       = .BUFFER_CREATE_INFO,
        size        = vk.DeviceSize(size),
        usage       = flags.usage,
        sharingMode = .EXCLUSIVE,
    }

    alloc_info: vma.AllocationCreateInfo = {
        flags = flags.vma,
        usage = .AUTO,
        requiredFlags = flags.required,
        preferredFlags = flags.preferred,
    }

    allocation_info: vma.AllocationInfo

    vk_assert(vma.CreateBufferWithAlignment(vma_allocator,
                                            &buffer_info, 
                                            &alloc_info,
                                            vk.DeviceSize(alignment),
                                            &buffer.handle, 
                                            &buffer.allocation, 
                                            &allocation_info))

    buffer.size = int(allocation_info.size)
    buffer.alignment = alignment
    buffer.mapped_ptr = allocation_info.pMappedData
    buffer.type = flags.type

    return buffer
}

buffers_create_image :: proc(format: vk.Format, extent: vk.Extent3D, usage: vk.ImageUsageFlags) ->
(image: Image) {
    device := get_context().device

    image_info := vk.ImageCreateInfo {
        sType       = .IMAGE_CREATE_INFO,
        imageType   = .D2,
        format      = format,
        extent      = extent,
        mipLevels   = 1,
        arrayLayers = 1,
        samples     = { ._1 },
        tiling      = .OPTIMAL,
        usage       = usage,
    }
    
    alloc_info := vma.AllocationCreateInfo {
        usage = .AUTO,
        requiredFlags = { .DEVICE_LOCAL },
    }
    
    allocation_info: vma.AllocationInfo

    vk_assert(vma.CreateImage(vma_allocator,
                    &image_info, 
                    &alloc_info, 
                    &image.handle, &image.allocation,
                    &allocation_info))

    image.size = int(allocation_info.size)
    
    image_view_info := vk.ImageViewCreateInfo {
        sType = .IMAGE_VIEW_CREATE_INFO,
        viewType = .D2,
        image = image.handle,
        format = format,
        subresourceRange = {
            aspectMask = { format == .D32_SFLOAT ? .DEPTH : .COLOR },
            baseMipLevel = 0, 
            levelCount = 1,
            baseArrayLayer =  0,
            layerCount = 1,
        },
    }
    
    vk_assert(vk.CreateImageView(device, &image_view_info, nil, &image.view))
    return image
}

buffers_create_dubo :: proc($T: typeid,
                            count: int) ->
(buffer: TBuffer(T)) {
    alignment := min_dubo_alignment
    elem_size := mem.align_formula(size_of(T), alignment)
    size := elem_size * count

    buffer.type = .UNIFORM_DYNAMIC
    buffer = buffers_create_tbuffer(T, size, .UNIFORM_DYNAMIC)
    return buffer
}

buffers_destroy :: proc { buffers_destroy_image, buffers_destroy_buffer }

buffers_destroy_image :: proc(device: vk.Device, image: Image) {
    vk.DestroyImageView(device, image.view, nil)
    vma.DestroyImage(vma_allocator, image.handle, image.allocation)
}

buffers_destroy_buffer :: proc(buffer: Buffer) {
    vma.DestroyBuffer(vma_allocator, buffer.handle, buffer.allocation)
}

buffers_create_staging :: proc(device: vk.Device, queue: vk.Queue) -> 
(staging: StagingPlatform) {
    result: vk.Result

    staging.device = device
    staging.queue = queue
    staging.submission_in_flight = false
    staging.fence = builders.create_fence(device)
    staging.command_pool = builders.create_command_pool(device, { .TRANSIENT })
    staging.command_buffer = builders.create_command_buffer(device, staging.command_pool)
    staging.buffer = buffers_create(STAGING_BUFFER_SIZE, BufferType.STAGING)

    begin_info := vk.CommandBufferBeginInfo {
        sType = .COMMAND_BUFFER_BEGIN_INFO,
        flags = { .ONE_TIME_SUBMIT },
    }

    vk_assert(vk.BeginCommandBuffer(staging.command_buffer, &begin_info))

    return staging
}

buffers_destroy_staging :: proc(staging: StagingPlatform) {
    vk.DestroyFence(staging.device, staging.fence, nil)
    vk.DestroyCommandPool(staging.device, staging.command_pool, nil)
    buffers_destroy(staging.buffer)
}

// Move device-local memory to the GPU.
buffers_write :: proc(buffer: Buffer,
                      data:   rawptr,
                      size_:  int = 0,
                      offset: uintptr = 0) ->
(Result) {
    size := size_ != 0 ? int(size_) : int(buffer.size) - int(offset)

    flags: vk.MemoryPropertyFlags
    vma.GetAllocationMemoryProperties(vma_allocator, buffer.allocation, &flags)

    if .HOST_COHERENT in flags {
        dst := transmute(rawptr)(uintptr(buffer.mapped_ptr) + uintptr(offset))
        mem.copy(dst, data, size)
        return .OK
    }
    else if .HOST_VISIBLE in flags {
        dst: rawptr
        result := vma.MapMemory(vma_allocator, buffer.allocation, &dst)
        assert(result == .SUCCESS)
        dst = transmute(rawptr)(uintptr(dst) + uintptr(offset))
        mem.copy(dst, data, size)
        return .NEEDS_FLUSH
    }

    return .NEEDS_STAGE
}

buffers_write_tbuffer :: proc(buffer:  TBuffer($T),
                              data:    rawptr,
                              index:   int) -> int {

    element_size := size_of(T)

    if buffer.type == .UNIFORM_DYNAMIC {
        element_size = mem.align_formula(element_size, min_dubo_alignment)
    }

    offset := uintptr(element_size * index)

    buffers_write(buffer, data, element_size, offset)

    return int(offset)
}

buffers_stage :: proc(stage:      ^StagingPlatform,
                      data:       rawptr,
                      size:       int,
                      alignment:  int = mem.DEFAULT_ALIGNMENT) -> UploadContext {
    
    max_size := stage.buffer.size
    assert(size < max_size)

    if stage.offset + uintptr(size) > uintptr(max_size) do buffers_flush_stage(stage)

    result := buffers_wait_stage_submission(stage)
    fmt.assertf(result == .SUCCESS, "stage failed with error %v", result)

    stage.offset = uintptr(mem.align_forward(rawptr(stage.offset), uintptr(alignment)))

    buffers_write(stage.buffer, data, size, stage.offset)

    ctx: UploadContext

    ctx.buffer = stage.buffer
    ctx.command_buffer = stage.command_buffer
    ctx.offset = stage.offset

    stage.offset += uintptr(size)

    return ctx
}

buffers_flush_stage :: proc(stage: ^StagingPlatform) {
    if stage.submission_in_flight || stage.offset == 0 do return

    stage.submission_in_flight = true

    flags: vk.MemoryPropertyFlags
    vma.GetAllocationMemoryProperties(vma_allocator, stage.buffer.allocation, &flags)

    if .HOST_COHERENT not_in flags do vma.FlushAllocation(vma_allocator, 
                                                          stage.buffer.allocation, 
                                                          0, 
                                                          vk.DeviceSize(stage.buffer.size))

    result := vk.EndCommandBuffer(stage.command_buffer)
    fmt.assertf(result == .SUCCESS, "Assert failed with error %v", result)

    info: vk.SubmitInfo = {
        sType = .SUBMIT_INFO,
        commandBufferCount = 1,
        pCommandBuffers = &stage.command_buffer,
    }

    result = vk.QueueSubmit(stage.queue, 1, &info, stage.fence)
    fmt.assertf(result == .SUCCESS, "Assert failed with error %v", result)
}

buffers_wait_stage_submission :: proc(stage: ^StagingPlatform) -> vk.Result {
    if !stage.submission_in_flight do return .SUCCESS

    vk.WaitForFences(stage.device, 1, &stage.fence, true, max(u64)) or_return
    vk.ResetFences(stage.device, 1, &stage.fence) or_return
    stage.offset = 0
    stage.submission_in_flight = false
    vk.ResetCommandPool(stage.device, stage.command_pool, nil) or_return
    info: vk.CommandBufferBeginInfo = { sType = .COMMAND_BUFFER_BEGIN_INFO }
    vk.BeginCommandBuffer(stage.command_buffer, &info) or_return
    return .SUCCESS
}

buffers_copy :: proc(up:    UploadContext,
                     size:  int,
                     dst:   Buffer) {
    copy_op := vk.BufferCopy {
        srcOffset = vk.DeviceSize(up.offset),
        dstOffset = 0,
        size = vk.DeviceSize(size),
    }

    vk.CmdCopyBuffer(up.command_buffer, up.buffer.handle, dst.handle, 1, &copy_op)
}

buffers_copy_image :: proc(up:     UploadContext,
                           extent: vk.Extent3D,
                           dst:    Image) {

    barrier := vk.ImageMemoryBarrier {
        sType = .IMAGE_MEMORY_BARRIER,
        oldLayout = .UNDEFINED,
        newLayout = .TRANSFER_DST_OPTIMAL,
        image = dst.handle,
        subresourceRange = {
            aspectMask = { .COLOR },
            baseMipLevel = 0,
            levelCount = 1,
            baseArrayLayer = 0,
            layerCount = 1,
        },
        srcAccessMask = {},
        dstAccessMask = { .TRANSFER_WRITE },
    }

    builders.cmd_pipeline_barrier(up.command_buffer,
                                  { .TOP_OF_PIPE },
                                  { .TRANSFER },
                                  image_memory_barriers = { barrier })
    
    region := vk.BufferImageCopy {
        bufferOffset = vk.DeviceSize(up.offset),
        imageSubresource = {
            aspectMask = { .COLOR },
            mipLevel = 0,
            baseArrayLayer = 0,
            layerCount = 1,
        },
        imageExtent = extent,
    }

    vk.CmdCopyBufferToImage(up.command_buffer, up.buffer.handle, dst.handle, .TRANSFER_DST_OPTIMAL, 1, &region)

    to_shader_barrier := vk.ImageMemoryBarrier {
        sType = .IMAGE_MEMORY_BARRIER,
        oldLayout = .TRANSFER_DST_OPTIMAL,
        newLayout = .SHADER_READ_ONLY_OPTIMAL,
        srcAccessMask = { .TRANSFER_WRITE },
        dstAccessMask = { .SHADER_READ },
        subresourceRange = {
            aspectMask = { .COLOR },
            baseMipLevel = 0,
            levelCount = 1,
            baseArrayLayer = 0,
            layerCount = 1,
        },
        image = dst.handle,
    }

    builders.cmd_pipeline_barrier(up.command_buffer,
                                  { .TRANSFER },
                                  { .FRAGMENT_SHADER },
                                  image_memory_barriers = { to_shader_barrier })
}

buffers_default_flags :: proc(type: BufferType) -> BufferCreateFlags {
    flags := BufferDefaultFlags
    return flags[type]
}
