package graphics 

import la "core:math/linalg"
import "core:container/intrusive/list"

import "vendor:glfw"
import vk "vendor:vulkan"
import "pkgs:vma"

vec3 :: la.Vector3f32
vec4 :: la.Vector4f32
mat4 :: la.Matrix4f32

Perframe :: struct {
    index:     uint,
    in_flight_fence: vk.Fence,
    command_pool:    vk.CommandPool,
    command_buffer:  vk.CommandBuffer,
    image_available: ^SemaphoreLink,
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

SemaphoreLink :: struct {
    link: list.Node,
    semaphore: vk.Semaphore
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
    vertices:  [8]Vertex,
    indices:   [36]u16,
}

Tetrahedron :: struct {
    vertices:  [12]Vertex,
    indices:   [12]u16,
}

Result :: enum {
    OK,
    NEEDS_FLUSH,
    NEEDS_STAGE,
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
    type:        BufferType,
    size:        int,
    alignment:   int,
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

BufferCreateFlags:: struct {
    type:       BufferType,
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
