package graphics 

import la "core:math/linalg"

import "vendor:glfw"
import vk "vendor:vulkan"
import "pkgs:vma"

import "materials"
import "common"

Perframe :: struct {
    index:     uint,
    in_flight_fence: vk.Fence,
    command_pool:    vk.CommandPool,
    command_buffer:  vk.CommandBuffer,
    image_available: vk.Semaphore,
    render_finished: vk.Semaphore,
}

QueueFamily :: enum {
    GRAPHICS,
    PRESENT,
    TRANSFER,
}

Queue :: struct {
    index: int,
    handle: vk.Queue
}

RenderData :: struct {
    cube:            Cube,
    tetra:           Tetrahedron,
    camera_ubo:      Buffer,
    object_ubo:      Buffer,
    model:           [OBJECT_COUNT]la.Matrix4f32,
    vertex_buffers:  [OBJECT_COUNT]Buffer,
    index_buffers:   [OBJECT_COUNT]Buffer,
    materials:       [OBJECT_COUNT]^materials.Material,
}

CameraData :: struct {
    view: la.Matrix4f32,
    proj: la.Matrix4f32,
}

Swapchain :: struct
{
    handle: vk.SwapchainKHR,
    images: []vk.Image,
    image_views: []vk.ImageView,
    format: vk.SurfaceFormatKHR,
    extent: vk.Extent2D,
    present_mode: vk.PresentModeKHR,
    image_count: u32,
    support: SwapChainDetails,
    framebuffers: []vk.Framebuffer,
}

SwapChainDetails :: struct
{
    capabilities: vk.SurfaceCapabilitiesKHR,
    formats: []vk.SurfaceFormatKHR,
    present_modes: []vk.PresentModeKHR,
}

ShapeType :: enum {
    CUBE,
    TETRAHEDRON,
}

Cube :: struct {
    vertices:  [24]common.Vertex,
    indices:   [36]u16,
}

Tetrahedron :: struct {
    vertices:  [12]common.Vertex,
    indices:   [12]u16,
}

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

Image :: struct {
    handle:      vk.Image,
    view:        vk.ImageView,
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
