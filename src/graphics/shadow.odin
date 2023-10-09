package graphics

import vk "vendor:vulkan"

shadow_create_image :: proc(device: vk.Device, shadow_image_width: u32 = 500, shadow_image_height: u32 = 500) -> (image: vk.Image) {
	image_create_info := vk.ImageCreateInfo {
		sType = .IMAGE_CREATE_INFO,
		pNext = nil,
		imageType = .D2,
		extent = {
			width = shadow_image_width,
			height = shadow_image_height,
			depth = 1,
		},
		mipLevels = 1,
		arrayLayers = 1,
		samples = { ._1 },
		initialLayout = .UNDEFINED,
		usage = { .DEPTH_STENCIL_ATTACHMENT | .SAMPLED },
		queueFamilyIndexCount = 0,
		pQueueFamilyIndices = nil,
		sharingMode = .EXCLUSIVE,
	}

	img := vk.Image {};
	vk_assert(vk.CreateImage(device, &image_create_info, nil, &img))

	return img
}

shadow_create_image_view :: proc(device: vk.Device, img: vk.Image) -> (image_view: vk.ImageView) {
	img_view := vk.ImageView {};

	image_view_create_info : vk.ImageViewCreateInfo = {
		sType = .IMAGE_VIEW_CREATE_INFO,
		image = img,
		viewType = .D2,
		format = .D32_SFLOAT,
		components = { r = .IDENTITY, g = .IDENTITY, b = .IDENTITY, a = .IDENTITY },

		subresourceRange = {
			aspectMask = { .DEPTH },
			baseMipLevel = 0,
			levelCount = 1,
			baseArrayLayer = 0,
			layerCount = 1,
		},
	}

	vk_assert(vk.CreateImageView(device, &image_view_create_info, nil, &img_view))

	return image_view
}

shadow_create_framebuffer :: proc(device: vk.Device, 
								render_pass: vk.RenderPass, 
								image_view: vk.ImageView, 
								shadow_image_width: u32 = 500, 
								shadow_image_height: u32 = 500) -> 
(framebuffer: vk.Framebuffer) {
	framebuf := vk.Framebuffer {};
	image_view := image_view

	framebuffer_create_info := vk.FramebufferCreateInfo{
		sType = .FRAMEBUFFER_CREATE_INFO,
		pNext = nil,
		renderPass = render_pass,
		attachmentCount = 1,
		pAttachments = &image_view,
		width = shadow_image_width,
		height = shadow_image_height,
		layers = 1,
	}

	vk_assert(vk.CreateFramebuffer(device, &framebuffer_create_info, nil, &framebuf))

	return framebuf
}