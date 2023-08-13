package main

import "graphics"
import "vendor:glfw"

DEBUG :: true

main :: proc () {
        using ctx := graphics.init()
        defer graphics.cleanup(&ctx)

        for !glfw.WindowShouldClose(ctx.window) {
                glfw.PollEvents()
                graphics.update(&ctx)
        }
}