package graphics

/**
* Code for managing GLFW windows.
*/

WINDOW_HEIGHT :: 1280
WINDOW_WIDTH :: 720
WINDOW_TITLE :: "Odinpi"

import "core:fmt"
import "core:runtime"
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

window_should_close :: proc(using ctx: ^Context) -> bool {
        return bool(glfw.WindowShouldClose(window))
}

cleanup_window :: proc(using ctx: ^Context) {
        glfw.DestroyWindow(window)
        glfw.Terminate()
}