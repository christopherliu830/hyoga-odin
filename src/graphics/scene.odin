package graphics

import "core:log"
import "core:math"
import "core:fmt"
import la "core:math/linalg"
import "core:math/rand"
import "core:mem"
import vk "vendor:vulkan"

import "builders"

Camera :: struct {
    view: mat4,
    proj: mat4,
}

Light :: struct { 
    direction:  vec4,
    color:      vec4,
}

Scene :: struct {
    time:            f32,
    device:          vk.Device,
    object_ubos:     TBuffer(mat4),

    // Camera and lights are duplicated for each frame in flight.
    // Both frames are set as dynamic offsets within the buffer.
    camera_buffer:   TBuffer(Camera),
    lights_buffer:   TBuffer(Light),

    cube_vertex:     Buffer,
    cube_index:      Buffer,

    // Each element is a handle, not a completely separete buffer.
    model:           [OBJECT_COUNT]mat4,
    vertex_buffers:  [OBJECT_COUNT]Buffer,
    index_buffers:   [OBJECT_COUNT]Buffer,
    materials:       [OBJECT_COUNT]^Material,

    // Animation func for cubes.
    offsets:         proc(i: int, t: f32, m: mat4) -> mat4
}


ObjectType :: enum {
    CUBE,
    TETRA
}

create_test_scene :: proc(scene: ^Scene, mat_cache: ^MaterialCache) {
    for i in 0..<OBJECT_COUNT {
        scene.vertex_buffers[i] = scene.cube_vertex
        scene.index_buffers[i] = scene.cube_index
        if i % 2 == 0 do scene.materials[i] = mats_get_mat(mat_cache, "default_diffuse")
        else do scene.materials[i] = mats_get_mat(mat_cache, "diffuse_red")

        scene.model[i] = la.MATRIX4F32_IDENTITY *
            la.matrix4_translate_f32(vec3 { math.sin(f32(i)/OBJECT_COUNT*math.TAU), 0, math.cos(f32(i)/OBJECT_COUNT*math.TAU) }) *
            la.matrix4_scale(vec3 {0.2, 0.2, 0.2})
    }

    scene.offsets = proc(i: int, t: f32, m: mat4) -> mat4 {
        r := rand.create(u64(i))
        s := rand.float32(&r) * 5
        x := rand.float32(&r) - 0.5 * s
        y := rand.float32(&r) - 0.5 * s
        z := rand.float32(&r) - 0.5 * s
        return m * la.matrix4_rotate(t * 1, vec3 { x, y, z }) 
    }

}

scene_init :: proc(scene:  ^Scene,
                   ctx:    ^RenderContext) {

    // WRITE BUFFERS
    num_frames := int(ctx.swapchain.image_count)
    scene.device = ctx.device

    scene.camera_buffer = scene_setup_cameras(num_frames, ctx.swapchain.extent)
    scene.lights_buffer = scene_setup_lights(num_frames)

    scene.object_ubos = buffers_create_dubo(mat4, OBJECT_COUNT * num_frames)

    cube := create_cube()
    scene.cube_vertex = buffers_create(size_of(cube.vertices), .VERTEX)
    scene.cube_index = buffers_create(size_of(cube.indices), .INDEX)

    up_ctx := buffers_stage(&ctx.stage, &cube.vertices, size_of(cube.vertices))
    buffers_copy(up_ctx, size_of(cube.vertices), scene.cube_vertex)

    up_ctx = buffers_stage(&ctx.stage, &cube.indices, size_of(cube.indices))
    buffers_copy(up_ctx, size_of(cube.indices), scene.cube_index)

    buffers_flush_stage(&ctx.stage)

    // CREATE MATERIALS

    unlit_effect := mats_create_shader_effect(ctx,
                                              ctx.render_pass,
                                              "unlit_effect",
                                              .DEFAULT,
                                              {{ "assets/shaders/shader.vert.spv", .VERTEX },
                                              { "assets/shaders/shader.frag.spv", .FRAGMENT }})

    unlit_mat := mats_create(ctx, "unlit_mat", {{ .FORWARD, unlit_effect }})

    scene_bind_descriptors(scene, unlit_mat)

    diffuse_effect := mats_create_shader_effect(ctx,
                                                ctx.render_pass,
                                                "default_diffuse_effect",
                                                .DIFFUSE,
                                                {{ "assets/shaders/diffuse.vert.spv", .VERTEX },
                                                { "assets/shaders/diffuse.frag.spv", .FRAGMENT }})

    diffuse := mats_create(ctx, "default_diffuse", {{ .FORWARD, diffuse_effect }})
    scene_bind_descriptors(&ctx.scene, diffuse)
    data := vec4 { 1, 1, 1, 1 }
    buffers_write(diffuse.uniforms, &data)

    diffuse_red := mats_create(ctx, "diffuse_red", {{ .FORWARD, diffuse_effect }})
    scene_bind_descriptors(&ctx.scene, diffuse_red)
    data = vec4 { 0.6, 0.2, 0.2, 1 }
    buffers_write(diffuse_red.uniforms, &data)

    //TODO: Shadow Pass

    create_test_scene(scene, &ctx.mat_cache)

    //TODO: Shadow Effect
    //scene.shadow_context = shadow_init(ctx.device, ctx, num_frames, ctx.swapchain.extent)

}

scene_shutdown :: proc(scene: ^Scene) {
    //TODO: shadow_destroy(scene.device, &scene.shadow_context)

    buffers_destroy(scene.lights_buffer)
    buffers_destroy(scene.camera_buffer)
    buffers_destroy(scene.object_ubos)
    buffers_destroy(scene.cube_vertex)
    buffers_destroy(scene.cube_index)
}

scene_setup_cameras :: proc(frame_count: int, extent: vk.Extent2D) ->
(buffer: TBuffer(Camera)) {
    buffer = buffers_create_dubo(Camera, frame_count)

    camera: Camera

    camera.view = la.matrix4_look_at(
        vec3 { 0, 1, -2 },
        vec3 { 0, 0, 0 },
        vec3 { 0, 1, 0 },
    )

    camera.proj = la.matrix4_perspective_f32(
        45,
        f32(extent.width) / f32(extent.height),
        0.1,
        100,
    )

    camera.proj[1][1] *= -1

    for i in 0..<frame_count do buffers_write_tbuffer(buffer, &camera, i)

    return buffer
}

scene_setup_lights :: proc(frame_count: int) -> (lights: TBuffer(Light)) {
    lights = buffers_create_dubo(Light, frame_count)

    light := Light {
        direction = vec4 { 0, -1, 0, 1 },
        color = vec4 { 1, 1, 1, 1 },
    }

    for i in 0..<frame_count do buffers_write_tbuffer(lights, &light, i)

    return lights
}

scene_render :: proc(scene: ^Scene,
                     perframe: ^Perframe) {

    scene.time += 0.001

    frame_num := int(perframe.index)
    cmd := perframe.command_buffer

    last_material: ^Material = nil

    object_data : [OBJECT_COUNT]mat4
    for i in 0..<OBJECT_COUNT do object_data[i] = scene.offsets(i, scene.time, scene.model[i])
    buffers_write(scene.object_ubos,
                            &object_data,
                            size_of(object_data),
                            uintptr(frame_num * OBJECT_COUNT * size_of(mat4)))

    for i in 0..<OBJECT_COUNT {
        scene_render_object(scene, cmd, int(frame_num), i, &last_material)
    }
}

scene_render_object :: proc(scene: ^Scene,
                            cmd: vk.CommandBuffer,
                            frame_num: int,
                            object_num: int,
                            last_material: ^^Material) {

    material := scene.materials[object_num]
    vertex_buffer := scene.vertex_buffers[object_num]
    index_buffer := scene.index_buffers[object_num]

    // BIND GLOBAL DATA
    if last_material^ == nil {
        offset := size_of(Camera) * u32(frame_num)
        mats_bind_descriptor(cmd, material, .FORWARD, 0, { u32(size_of(Camera) * frame_num) })
    }

    // BIND PER MATERIAL DATA
    if material != last_material^ {
        vk.CmdBindPipeline(cmd, .GRAPHICS, material.passes[.FORWARD].pipeline)
        mats_bind_descriptor(cmd, material, .FORWARD, 2, { 0 })
    }

    last_material^ = material

    // BIND PER OBJECT DATA
    dynamic_offset := u32((frame_num * OBJECT_COUNT + object_num) * size_of(mat4))
    mats_bind_descriptor(cmd, material, .FORWARD, 3, { dynamic_offset })

    offset : vk.DeviceSize = 0

    vk.CmdBindVertexBuffers(cmd, 0, 1, &vertex_buffer.handle, &offset)
    vk.CmdBindIndexBuffer(cmd, index_buffer.handle, 0, .UINT16)
    vk.CmdDrawIndexed(cmd, u32(index_buffer.size / size_of(u16)), 1, 0, 0, 0)
}

scene_bind_descriptors :: proc(this: ^Scene, material: ^Material) {
    builders.bind_descriptor_set(this.device,
                                 { this.camera_buffer.handle, 0, size_of(Camera) },
                                 .UNIFORM_BUFFER_DYNAMIC, 
                                 material.descriptors[.FORWARD][0], 0)

    builders.bind_descriptor_set(this.device,
                                 { this.lights_buffer.handle, 0, size_of(Light) },
                                 .UNIFORM_BUFFER, 
                                 material.descriptors[.FORWARD][0], 1)

    builders.bind_descriptor_set(this.device,
                                 { material.uniforms.handle, 0, MATERIAL_UNIFORM_BUFFER_SIZE },
                                 .UNIFORM_BUFFER_DYNAMIC, 
                                 material.descriptors[.FORWARD][2], 0)

    builders.bind_descriptor_set(this.device,
                                 { this.object_ubos.handle, 0, size_of(mat4) },
                                 .UNIFORM_BUFFER_DYNAMIC, 
                                 material.descriptors[.FORWARD][3], 0)
}

