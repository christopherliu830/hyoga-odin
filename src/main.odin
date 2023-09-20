package main

import "core:log"
import "vendor:glfw"

import "graphics"

main :: proc () {
    context.logger = log.create_console_logger();

    using ctx := graphics.init()
    defer graphics.cleanup(&ctx)

    for !glfw.WindowShouldClose(ctx.window) {
        glfw.PollEvents()
        graphics.update(&ctx)
    }
}
