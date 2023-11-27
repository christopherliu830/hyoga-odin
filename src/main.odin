package main

import "core:log"

import "vendor:glfw"
import bt "pkgs:obacktracing"

import "graphics"

import la "core:math/linalg"

Transform :: struct {
    pos: la.Vector3f32,
    rot: la.Quaternionf32,
    sca: la.Vector3f32,
}

Object :: struct {
    transform: Transform,
    graphics: graphics.THandle(graphics.Renderable)
}

transform_to_mat4 :: proc(t: Transform) -> la.Matrix4f32 {
    return la.matrix4_translate(t.pos) * la.matrix4_from_quaternion(t.rot) * la.matrix4_scale(t.sca) 
}

main :: proc () {
    context.logger = log.create_console_logger();
    context.assertion_failure_proc = bt.assertion_failure_proc

    graphics.init()
    ctx := graphics.get_context()
    scene := &graphics.get_context().scene

    diffuse_mat := graphics.mats_get_mat(&ctx.mat_cache, "default_diffuse")
    // graphics.create_material({ name = "stone", diffuse_path = "assets/textures/stone.png" })

    cube := Object {
        transform = {
            pos = { 0, -0.5, 0 },
            rot = la.QUATERNIONF32_IDENTITY,
            sca = { 1, 1, 1 },
        },
    }

    tetra := Object {
        transform = {
            pos = { 0, 1, 0 },
            rot = la.QUATERNIONF32_IDENTITY,
            sca = { .2, .2, .2 },
        },
    }

    // MESHES
    c := graphics.cube()
    t := graphics.tetrahedron()

    cube_mesh := graphics.create_mesh(scene, c.vertices[:], c.indices[:])
    tetra_mesh := graphics.create_mesh(scene, t.vertices[:], t.indices[:])

    cube.graphics = graphics.add_object(scene, cube_mesh, diffuse_mat)
    tetra.graphics = graphics.add_object(scene, tetra_mesh, diffuse_mat)

    time: f32 = 0
    for v in t.vertices do log.debug(v)
    for i in t.indices do log.debug(i)

    for !glfw.WindowShouldClose(ctx.window) {
        time += 0.001

        glfw.PollEvents()

        cube.transform.rot = la.quaternion_angle_axis_f32(time, { 1, 2, 3 })
        tetra.transform.rot = la.quaternion_angle_axis_f32(time, { -3, 0, -1.5 })

        graphics.begin()

        graphics.update_object(scene, cube.graphics, transform_to_mat4(cube.transform))
        graphics.update_object(scene, tetra.graphics, transform_to_mat4(tetra.transform))

        graphics.end()
    }

    graphics.cleanup(ctx)

    log.info("Exit")
}
