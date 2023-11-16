package graphics 

import la "core:math/linalg"
import "core:container/intrusive/list"

import "vendor:glfw"
import vk "vendor:vulkan"
import "pkgs:vma"

vec3 :: la.Vector3f32
vec4 :: la.Vector4f32
mat4 :: la.Matrix4f32

PassInfo :: struct {
    pass:           vk.RenderPass,
    framebuffers:   []vk.Framebuffer,
    images:         []Image,
    clear_values:   [2]vk.ClearValue,
    extent:         vk.Extent3D,
    render_objects: []Mesh,
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
    handle:       vk.SwapchainKHR,
    images:       []Image,
    depth_image:  Image,
    format:       vk.SurfaceFormatKHR,
    extent:       vk.Extent2D,
    present_mode: vk.PresentModeKHR,
    image_count:  u32,
    support:      SwapChainDetails,
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
    vertices:  [24]Vertex,
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
