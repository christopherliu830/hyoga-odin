package main

import "core:fmt"
import "graphics"
import "vendor:glfw"

main :: proc () {
        using ctx := graphics.init()
        defer graphics.cleanup(&ctx)

        for !glfw.WindowShouldClose(ctx.window) {
                glfw.PollEvents()
                graphics.update(&ctx)
        }
}