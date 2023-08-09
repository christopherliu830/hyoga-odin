package graphics

/**
* Code for managing GLFW windows.
*/

WINDOW_HEIGHT :: 1280
WINDOW_WIDTH :: 720
WINDOW_TITLE :: "Odinpi"

import "core:fmt"
import "core:runtime"
import vk "vendor:vulkan"
import "vendor:glfw"

error_callback :: proc "c" (code: i32, desc: cstring) {
	context = runtime.default_context()
	fmt.println(desc, code)
}

key_callback :: proc "c" (window: glfw.WindowHandle, key, scancode, action, mods: i32) {
	if key == glfw.KEY_ESCAPE && action == glfw.PRESS {
		glfw.SetWindowShouldClose(window, glfw.TRUE)
	}
}

create_window :: proc(using ctx: ^Context) {
        glfw.SetErrorCallback(error_callback)
        glfw.Init()

        glfw.WindowHint(glfw.CLIENT_API, glfw.NO_API);

        window = glfw.CreateWindow(WINDOW_HEIGHT, WINDOW_WIDTH, WINDOW_TITLE, nil, nil);
        
        if (!glfw.VulkanSupported()) {
                panic("Vulkan not supported!")
        }
}

create_surface :: proc(instance: vk.Instance, window: glfw.WindowHandle) ->
(surface: vk.SurfaceKHR) {
        glfw.CreateWindowSurface(instance, window, nil, &surface)
        return surface
}

window_should_close :: proc(window: glfw.WindowHandle) -> bool {
        return bool(glfw.WindowShouldClose(window))
}

cleanup_window :: proc(window: glfw.WindowHandle) {
        glfw.DestroyWindow(window)
        glfw.Terminate()
}

get_frame_buffer_size :: proc(window: glfw.WindowHandle) -> (w, h: u32) {
        x, y := glfw.GetFramebufferSize(window)
        w = cast(u32)x
        h = cast(u32)y
        return w, h
}