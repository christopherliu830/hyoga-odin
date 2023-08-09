package graphics

import vk "vendor:vulkan"
import "vendor:glfw"

MAX_FRAMES_IN_FLIGHT :: 2

Context :: struct
{
	debug_messenger: vk.DebugUtilsMessengerEXT,

	instance: vk.Instance,
  	device:   vk.Device,
	gpu: vk.PhysicalDevice,
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

QueueFamily :: enum
{
	GRAPHICS,
	PRESENT,
}
