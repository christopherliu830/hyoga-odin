package main

import "core:log"

import "vendor:glfw"
import bt "pkgs:obacktracing"

import "graphics"

main :: proc () {
    context.logger = log.create_console_logger();
    context.assertion_failure_proc = bt.assertion_failure_proc

    graphics.init()
    ctx := graphics.get_context()

    graphics.create_material({ name = "stone", diffuse_path = "assets/textures/stone.png" })

    for !glfw.WindowShouldClose(ctx.window) {
        glfw.PollEvents()
        graphics.update(ctx)
    }

    graphics.cleanup(ctx)

    log.info("Exit")
}
