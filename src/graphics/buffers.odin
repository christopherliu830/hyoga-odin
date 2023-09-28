package graphics

import "core:mem"
import "core:log"
import "core:fmt"

import vk "vendor:vulkan"
import bt "pkgs:obacktracing"
import "pkgs:vma"

import "builders"
import "common"

STAGING_BUFFER_SIZE :: 8*mem.Megabyte

DefaultFlags :: [BufferType]CreateFlags {
    .INDEX = {
        usage = { .INDEX_BUFFER, .TRANSFER_DST },
        vma = { .DEDICATED_MEMORY },
    },
    .VERTEX = {
        usage = { .VERTEX_BUFFER , .TRANSFER_DST },
        vma = { .DEDICATED_MEMORY },
    },
    .STAGING = {
        usage = { .TRANSFER_SRC },
        vma = { .HOST_ACCESS_RANDOM , .MAPPED },
        required = { .HOST_VISIBLE },
        preferred = { .HOST_COHERENT },
    },
    .UNIFORM = {
        usage = { .UNIFORM_BUFFER },
        vma = { .HOST_ACCESS_SEQUENTIAL_WRITE, .MAPPED },
        required = { .HOST_VISIBLE , .HOST_COHERENT },
    },
    .UNIFORM_DYNAMIC = {
        usage = { .UNIFORM_BUFFER },
        vma = { .HOST_ACCESS_SEQUENTIAL_WRITE, .MAPPED },
        required = { .HOST_VISIBLE , .HOST_COHERENT },
    },
}


@private
vma_allocator: vma.Allocator

@private
staging: StagingPlatform

buffers_init :: proc(info: vma.AllocatorCreateInfo) {
    info := info

    vulkan_functions := vma.create_vulkan_functions()
    info.pVulkanFunctions = &vulkan_functions

    vk_assert(vma.CreateAllocator(&info, &vma_allocator))
}

buffers_shutdown :: proc() {
    buffers_destroy(staging.buffer)
}

/**
* Create a buffer.
*/
buffers_create :: proc(size:   int,
               flags:  CreateFlags) ->

(buffer: Buffer) {
    assert(flags.usage != nil)

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

    vk_assert(vma.CreateBuffer(vma_allocator,
                     &buffer_info, 
                     &alloc_info, 
                     &buffer.handle, 
                     &buffer.allocation, 
                     &allocation_info))

    buffer.size = size
    buffer.mapped_ptr = allocation_info.pMappedData

    return buffer
}

buffers_create_image :: proc(device: vk.Device, extent: vk.Extent3D) ->
(image: Image) {
    image_info := vk.ImageCreateInfo {
        sType       = .IMAGE_CREATE_INFO,
        imageType   = .D2,
        format      = .D32_SFLOAT,
        extent      = extent,
        mipLevels   = 1,
        arrayLayers = 1,
        samples     = { ._1 },
        tiling      = .OPTIMAL,
        usage       = { .DEPTH_STENCIL_ATTACHMENT },
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
        format = .D32_SFLOAT,
        subresourceRange = {
            aspectMask = { .DEPTH },
            baseMipLevel = 0, 
            levelCount = 1,
            baseArrayLayer =  0,
            layerCount = 1,
        },
    }
    
    vk_assert(vk.CreateImageView(device, &image_view_info, nil, &image.view))
    return image
}

buffers_destroy :: proc(buffer: Buffer) {
    vma.DestroyBuffer(vma_allocator, buffer.handle, buffer.allocation)
}

buffers_default_flags :: proc(type: BufferType) -> 
(flags: CreateFlags) {
    switch(type) {
        case .INDEX:
            flags.usage = { .INDEX_BUFFER, .TRANSFER_DST }
            flags.vma = { .DEDICATED_MEMORY }
        case .VERTEX:
            flags.usage = { .VERTEX_BUFFER , .TRANSFER_DST }
            flags.vma = { .DEDICATED_MEMORY }
        case .STAGING:
            flags.usage = { .TRANSFER_SRC }
            flags.vma = { .HOST_ACCESS_RANDOM , .MAPPED }
            flags.required = { .HOST_VISIBLE }
            flags.preferred = { .HOST_COHERENT }
        case .UNIFORM:
        case .UNIFORM_DYNAMIC:
            flags.usage = { .UNIFORM_BUFFER }
            flags.vma = { .HOST_ACCESS_SEQUENTIAL_WRITE, .MAPPED }
            flags.required = { .HOST_VISIBLE , .HOST_COHERENT }
    }
    return flags
}

buffers_init_staging :: proc(device: vk.Device, queue: vk.Queue) {
    result: vk.Result

    staging.device = device
    staging.queue = queue
    staging.submission_in_flight = false
    staging.fence = builders.create_fence(device)
    staging.command_pool = builders.create_command_pool(device, { .TRANSIENT })
    staging.command_buffer = builders.create_command_buffer(device, staging.command_pool)
    staging.buffer = buffers_create(STAGING_BUFFER_SIZE, buffers_default_flags(.STAGING))

    begin_info := vk.CommandBufferBeginInfo {
        sType = .COMMAND_BUFFER_BEGIN_INFO,
        flags = { .ONE_TIME_SUBMIT },
    }

    vk_assert(vk.BeginCommandBuffer(staging.command_buffer, &begin_info))
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

    coherent: bool = .HOST_COHERENT in flags

    if .HOST_COHERENT in flags {
        // Odin disallows pointer arithmetic
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
    else {
        ctx := buffers_stage(data, size);
        region := vk.BufferCopy { vk.DeviceSize(ctx.offset), vk.DeviceSize(offset), vk.DeviceSize(size) }
        vk.CmdCopyBuffer(staging.command_buffer, staging.buffer.handle, buffer.handle, 1, &region)
        return .STAGED
    }
}
            
buffers_stage :: proc(data:       rawptr,
              size:       int,
              alignment:  int = mem.DEFAULT_ALIGNMENT) -> UploadContext {
    max_size := staging.buffer.size
    assert(size < max_size)

    if staging.offset + uintptr(size) > uintptr(max_size) do buffers_flush_stage()

    result := buffers_wait_stage_submission()
    fmt.assertf(result == .SUCCESS, "stage failed with error %v", result)

    staging.offset = uintptr(mem.align_forward(rawptr(staging.offset), uintptr(alignment)))

    log.debug(size, staging.offset)
    buffers_write(staging.buffer, data, size, staging.offset)

    ctx: UploadContext

    ctx.buffer = staging.buffer
    ctx.command_buffer = staging.command_buffer
    ctx.offset = staging.offset

    staging.offset += uintptr(size)

    return ctx
}

buffers_flush_stage :: proc() {
    if staging.submission_in_flight || staging.offset == 0 do return

    staging.submission_in_flight = true

    flags: vk.MemoryPropertyFlags
    vma.GetAllocationMemoryProperties(vma_allocator, staging.buffer.allocation, &flags)

    if .HOST_COHERENT not_in flags do vma.FlushAllocation(vma_allocator, 
                                                         staging.buffer.allocation, 
                                                         0, 
                                                         vk.DeviceSize(staging.buffer.size))

    result := vk.EndCommandBuffer(staging.command_buffer)
    fmt.assertf(result == .SUCCESS, "Assert failed with error %v", result)

    info: vk.SubmitInfo = {
        sType = .SUBMIT_INFO,
        commandBufferCount = 1,
        pCommandBuffers = &staging.command_buffer,
    }

    result = vk.QueueSubmit(staging.queue, 1, &info, staging.fence)
    fmt.assertf(result == .SUCCESS, "Assert failed with error %v", result)
}

buffers_wait_stage_submission :: proc() -> vk.Result {
    if !staging.submission_in_flight do return .SUCCESS

    vk.WaitForFences(staging.device, 1, &staging.fence, true, max(u64)) or_return
    vk.ResetFences(staging.device, 1, &staging.fence) or_return
    staging.offset = 0
    staging.submission_in_flight = false
    vk.ResetCommandPool(staging.device, staging.command_pool, nil) or_return
    info: vk.CommandBufferBeginInfo = { sType = .COMMAND_BUFFER_BEGIN_INFO }
    vk.BeginCommandBuffer(staging.command_buffer, &info) or_return
    return .SUCCESS
}

buffers_to_mtptr :: proc(buffer: Buffer, $T: typeid) -> []T {
    assert(buffer.mapped_ptr != nil)

    mtp := transmute([^]T)buffer.mapped_ptr
    return mtp[0:buffer.size/size_of(T)]
}

