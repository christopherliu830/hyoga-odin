package graphics 

import la "core:math/linalg"
import "core:container/intrusive/list"
import "core:mem"

import "vendor:glfw"
import vk "vendor:vulkan"
import "pkgs:vma"

vec3 :: la.Vector3f32
vec4 :: la.Vector4f32
mat4 :: la.Matrix4f32

Handle :: u32
THandle :: struct($T: typeid) { id: int }

MaterialCache :: struct {
    buffer: []u8,
    arena: mem.Arena,

    effects: map[string]ShaderEffect,
    materials: map[string]Material,

    // Cache resource handles to descriptors that describe them.

    pipeline_descriptions: map[Handle]PassResourceLayout,

    descriptors: map[vk.NonDispatchableHandle]vk.DescriptorSet,
}

ObjectUBO :: struct {
    model: mat4,
}

MaterialUBO :: struct {
    color: mat4,
}

Renderable :: struct {
    vertex_buffer: Buffer,
    index_buffer: Buffer,
    transform: ObjectUBO,

    material_offset: int,
    object_offset: int,

    prog: ^ShaderEffect,
}

PassInfo :: struct {
    type: PassType,
    pass:           vk.RenderPass,

    descriptors: [4]vk.DescriptorSet,

    global_descriptor: vk.DescriptorSet,

    object_buffers: []TBuffer(ObjectUBO),
    object_descriptor: vk.DescriptorSet,

    // ---INPUTS---
    renderables: [100]Renderable,
    n_renderables: int,

    mat_buffer:     TBuffer(MaterialUBO),
    mat_descriptor:  vk.DescriptorSet,

    // Resources that can be accessed by this pass.
    in_layouts: PassResourceLayout,

    // ---OUTPUTS---
    framebuffers:   []vk.Framebuffer,
    images:         []Image,

    clear_values:   [2]vk.ClearValue,
    extent:         vk.Extent3D,

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
