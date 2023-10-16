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

CameraData :: struct {
    data:   Camera,
    buffer: Buffer
}

Light :: struct { 
    direction:  vec4,
    color:      vec4,
}

LightData :: struct {
    data: []Light,
    buffer: Buffer,
}

Scene :: struct {
    time:            f32,
    device:          vk.Device,
    object_ubos:     Buffer,
    shadow_context:  ShadowContext,

    // Camera and lights are duplicated for each frame in flight.
    // Both frames are set as dynamic offsets within the buffer.
    cam_data:        CameraData,
    light_data:      LightData,
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
        switch i % 4 {
            case 0: 
                scene.materials[i] = mats_get_mat(mat_cache, "default_diffuse")
            case 1: 
                scene.materials[i] = mats_get_mat(mat_cache, "dd_red")
            case 2: 
                scene.materials[i] = mats_get_mat(mat_cache, "dd_blue")
            case 3: 
                scene.materials[i] = mats_get_mat(mat_cache, "dd_green")
        }

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
        // return m
    }

}

scene_init :: proc(scene:  ^Scene,
                   ctx:    ^RenderContext) {

    // WRITE BUFFERS
    num_frames := int(ctx.swapchain.image_count)
    scene.device = ctx.device

    scene.cam_data = scene_setup_cameras(num_frames, ctx.swapchain.extent)
    scene.light_data = scene_setup_lights(num_frames)

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

    unlit_effect := mats_create_shader_effect(&ctx.mat_cache,
                                              "unlit_effect",
                                              ctx.device,
                                              ctx.render_pass,
                                              .DEFAULT,
                                              { BINDINGS, ATTRIBUTES },
                                              "assets/shaders/shader.vert.spv",
                                              "assets/shaders/shader.frag.spv")

    unlit_mat := mats_create(&ctx.mat_cache, "unlit_mat", ctx.device, ctx.descriptor_pool, unlit_effect)

    scene_bind_descriptors(scene, unlit_mat)

    diffuse_effect := mats_create_shader_effect(&ctx.mat_cache,
                                                "default_diffuse_effect",
                                                ctx.device,
                                                ctx.render_pass,
                                                .DIFFUSE,
                                                { BINDINGS, ATTRIBUTES },
                                                "assets/shaders/diffuse.vert.spv",
                                                "assets/shaders/diffuse.frag.spv")

    diffuse := mats_create(&ctx.mat_cache, "default_diffuse", ctx.device, ctx.descriptor_pool, diffuse_effect)
    scene_bind_descriptors(&ctx.scene, diffuse)
    data := vec4 { 1, 1, 1, 1 }
    buffers_write(diffuse.uniforms, &data)

    dd_red := mats_clone(&ctx.mat_cache, ctx.device, ctx.descriptor_pool, "default_diffuse", "dd_red");
    data = vec4 { 1, 0, 0, 1 }
    buffers_write(dd_red.uniforms, &data)

    dd_blue := mats_clone(&ctx.mat_cache, ctx.device, ctx.descriptor_pool, "default_diffuse", "dd_blue");
    data = vec4 { 0, 1, 0, 1 }
    buffers_write(dd_blue.uniforms, &data)

    dd_green := mats_clone(&ctx.mat_cache, ctx.device, ctx.descriptor_pool, "default_diffuse", "dd_green");
    data = vec4 { 0, 0, 1, 1 }
    buffers_write(dd_green.uniforms, &data)


    create_test_scene(scene, &ctx.mat_cache)

    // Shadow effect
    scene.shadow_context = shadow_init(ctx.device, scene, &ctx.mat_cache, 
                                       &scene.light_data, ctx.descriptor_pool, num_frames, 
                                       ctx.swapchain.extent)

}

scene_shutdown :: proc(scene: ^Scene) {
    buffers_destroy(scene.light_data.buffer)
    buffers_destroy(scene.cam_data.buffer)
    buffers_destroy(scene.object_ubos)
    buffers_destroy(scene.cube_vertex)
    buffers_destroy(scene.cube_index)
    shadow_destroy(scene.device, &scene.shadow_context)
}

scene_setup_cameras :: proc(frame_count: int, extent: vk.Extent2D) ->
(cam_data: CameraData) {
    cam_data.buffer = buffers_create_dubo(Camera, frame_count)

    c : Camera

    c.view = la.matrix4_look_at(
        vec3 { 0, 0, 0 },
        vec3 { 0, 0, 0 },
        vec3 { 0, 1, 0 },
    )

    c.proj = la.matrix4_perspective_f32(
        45,
        f32(extent.width) / f32(extent.height),
        0.1,
        100,
    )
    c.proj[1][1] *= -1

    cam_data.data = c

    for i in 0..<frame_count {
        buffers_write(cam_data.buffer, &c, Camera, i)
    }

    return cam_data
}

scene_setup_lights :: proc(frame_count: int) -> (lights: LightData) {
    lights.buffer = buffers_create_dubo(Light, frame_count)
    light := Light {
        direction = vec4 { 0, -1, 0, 1 },
        color = vec4 { 1, 1, 1, 1 },
    }
    lights.data = make([]Light, 1)
    lights.data[0] = light
    for i in 0..<frame_count { buffers_write(lights.buffer, &light, Light, i) }

    return lights
}

scene_render :: proc(scene: ^Scene,
                     perframe: ^Perframe) {
    scene.time += 0.001
    frame_num := int(perframe.index)
    cmd := perframe.command_buffer

    view := la.matrix4_look_at(
        vec3 { 0, 1, -2 },
        vec3 { 0, 0, 0 },
        vec3 { 0, 1, 0 },
    )

    buffers_write(scene.cam_data.buffer,
                  &view,
                  Camera,
                  frame_num,
                  size_of(mat4),
                  offset_of(Camera, view))

    last_material: ^Material = nil
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

    model := scene.offsets(object_num, scene.time, scene.model[object_num])
    buffers_write(scene.object_ubos,
                  &model,
                  mat4,
                  frame_num * OBJECT_COUNT + object_num)

    // BIND GLOBAL DATA
    if last_material^ == nil {
        offset := size_of(Camera) * u32(frame_num)
        vk.CmdBindDescriptorSets(cmd, .GRAPHICS,
                                 material.effect.pipeline_layout, 0,
                                 1, &material.descriptors[0],
                                 1, &offset)
    }

    // BIND PER MATERIAL DATA
    if material != last_material^ {
        vk.CmdBindPipeline(cmd, .GRAPHICS, material.effect.pipeline)

        vk.CmdBindDescriptorSets(cmd, .GRAPHICS,
                           material.effect.pipeline_layout, 2,
                           1, &material.descriptors[2],
                           0, nil)
    }

    last_material^ = material

    // BIND PER OBJECT DATA
    dynamic_offset := u32(size_of(mat4) * object_num)
    vk.CmdBindDescriptorSets(cmd, .GRAPHICS,
                             material.effect.pipeline_layout, 3,
                             1, &material.descriptors[3],
                             1, &dynamic_offset)

    offset : vk.DeviceSize = 0
    vk.CmdBindVertexBuffers(cmd, 0, 1, &vertex_buffer.handle, &offset)
    vk.CmdBindIndexBuffer(cmd, index_buffer.handle, 0, .UINT16)
    vk.CmdDrawIndexed(cmd, u32(index_buffer.size / size_of(u16)), 1, 0, 0, 0)
}

scene_bind_descriptors :: proc(this: ^Scene, material: ^Material) {
    builders.bind_descriptor_set(this.device,
                                 { this.cam_data.buffer.handle, 0, size_of(Camera) },
                                 .UNIFORM_BUFFER_DYNAMIC, 
                                 material.descriptors[0], 0)

    builders.bind_descriptor_set(this.device,
                                 { this.light_data.buffer.handle, 0, size_of(Light) },
                                 .UNIFORM_BUFFER, 
                                 material.descriptors[0], 1)

    builders.bind_descriptor_set(this.device,
                                 { this.object_ubos.handle, 0, size_of(mat4) },
                                 .UNIFORM_BUFFER_DYNAMIC, 
                                 material.descriptors[3], 0)
}

