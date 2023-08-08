package graphics

import vk "vendor:vulkan"
import "vendor:glfw"

MAX_FRAMES_IN_FLIGHT :: 2

Context :: struct
{
	debug_messenger: vk.DebugUtilsMessengerEXT,

	instance: vk.Instance,
  	device:   vk.Device,
	physical_device: vk.PhysicalDevice,
	swapchain: Swapchain,
	pipeline: Pipeline,
	queue_indices:   [QueueFamily]int,
	queues:   [QueueFamily]vk.Queue,
	surface:  vk.SurfaceKHR,
	window:   glfw.WindowHandle,
	vertex_buffer: Buffer,
	index_buffer: Buffer,
	
	curr_frame: u32,
	framebuffer_resized: bool,

	perframes: []Perframe,
}

Perframe :: struct {
	device: vk.Device,
	queue_index: uint,
	in_flight_fence: vk.Fence,
	command_pool : vk.CommandPool,
	command_buffer: vk.CommandBuffer,
	image_available: vk.Semaphore,
	render_finished: vk.Semaphore,
}

Buffer :: struct
{
	buffer: vk.Buffer,
	memory: vk.DeviceMemory,
	length: int,
	size:   vk.DeviceSize,
}

QueueFamily :: enum
{
	GRAPHICS,
	PRESENT,
}

Vertex :: struct
{
	pos: [2]f32,
	color: [3]f32,
}

DEVICE_EXTENSIONS := [?]cstring{
	"VK_KHR_swapchain",
};

VALIDATION_LAYERS := [?]cstring{"VK_LAYER_KHRONOS_validation"};