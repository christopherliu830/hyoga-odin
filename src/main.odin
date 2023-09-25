package main

import "core:log"

import "vendor:glfw"
import bt "pkgs:obacktracing"

import "graphics"

main :: proc () {
    context.logger = log.create_console_logger();
    context.assertion_failure_proc = bt.assertion_failure_proc

    ctx: graphics.RenderContext
    graphics.init(&ctx)
    
    defer graphics.cleanup(&ctx)

    for !glfw.WindowShouldClose(ctx.window) {
        glfw.PollEvents()
        graphics.update(&ctx)
    }
}
