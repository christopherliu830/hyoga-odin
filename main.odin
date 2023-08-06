package main

import "core:fmt"
import "graphics"
import "vendor:glfw"

main :: proc () {
        using ctx : graphics.Context;

        graphics.init(&ctx)

        for !graphics.window_should_close(&ctx) {
                glfw.PollEvents()
        }

        glfw.DestroyWindow(window)
        glfw.Terminate()

        fmt.println("Done")
}