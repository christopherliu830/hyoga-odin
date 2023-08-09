package main

import "core:fmt"
import "graphics"
import "vendor:glfw"

main :: proc () {
        using ctx := graphics.init()
        defer graphics.cleanup(&ctx)

        for !graphics.window_should_close(ctx.window) {
                glfw.PollEvents()
                graphics.update(&ctx)
        }
}