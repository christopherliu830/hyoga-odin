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

    object_ubos:     TBuffer(ObjectUBO),
    obj_descriptor:  vk.DescriptorSet,

    mat_buffers:     TBuffer(MaterialUBO),
    mat_descriptor:  vk.DescriptorSet,

    // Camera and lights are duplicated for each frame in flight.
    // Both frames are set as dynamic offsets within the buffer.
    camera_buffer:   TBuffer(Camera),
    lights_buffer:   TBuffer(Light),

	shadows_sampler: vk.Sampler,
    shadows_buffer:  TBuffer(Camera),
    shadow_images:    []Image,

    meshes:          [MAX_MESHES]Mesh,
    n_meshes:        int, 

    // Animation func for cubes.
    offsets:         proc(i: int, t: f32, m: mat4) -> mat4
}

ObjectType :: enum {
    CUBE,
    TETRA
}

MAX_MESHES :: 4

scene_init :: proc(scene:  ^Scene) {
    ctx := get_context()

    // WRITE BUFFERS
    num_frames := int(ctx.swapchain.image_count)
    scene.device = ctx.device

    scene.camera_buffer = scene_setup_cameras(num_frames, ctx.swapchain.extent)
    scene.lights_buffer = scene_setup_lights(num_frames)

    scene.shadows_buffer = scene_setup_shadows(num_frames)
	scene.shadows_sampler = builders.create_sampler(scene.device, 1.0)
    scene.shadow_images = ctx.passes[.SHADOW].images

    // CREATE MATERIALS

    shadow_info := ShaderEffectIn {
        name = "shadow_pass",
        pass_type = .SHADOW,
        paths = {
            { "assets/shaders/shadow-pass.vert.spv", .VERTEX },
        },
    }
    shadow_effect := mats_create_shader_effect(shadow_info)

    forward_info := ShaderEffectIn {
        name = "forward_pass",
        pass_type = .FORWARD,
        paths = {
            { "assets/shaders/diffuse_shadows.vert.spv", .VERTEX },
            { "assets/shaders/diffuse_shadows.frag.spv", .FRAGMENT },
        },
    }
    diffuse_effect := mats_create_shader_effect(forward_info)

    diffuse := mats_create("default_diffuse", { shadow_effect, diffuse_effect })
    diffuse_red := mats_create("diffuse_red", { shadow_effect, diffuse_effect })

    buffers_flush_stage(&ctx.stage)
}

scene_shutdown :: proc(scene: ^Scene) {
    //TODO: shadow_destroy(scene.device, &scene.shadow_context)

    for i in 0..<scene.n_meshes {
        buffers_destroy(scene.meshes[i].vertices)
        buffers_destroy(scene.meshes[i].indices)
    }

    buffers_destroy(scene.lights_buffer)
    buffers_destroy(scene.camera_buffer)
    buffers_destroy(scene.object_ubos)
}

scene_setup_cameras :: proc(frame_count: int, extent: vk.Extent2D) ->
(buffer: TBuffer(Camera)) {
    buffer = buffers_create_dubo(Camera, frame_count)

    camera: Camera

    camera.view = la.matrix4_look_at(
        vec3 { 0, 2, -2 },
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
        direction = vec4 { 1, -4, 0, 1 },
        color = vec4 { 1, 1, 1, 1 },
    }

    for i in 0..<frame_count do buffers_write_tbuffer(lights, &light, i)

    return lights
}

scene_setup_shadows :: proc(frame_count: int) ->
(shadows: TBuffer(Camera)) {
    shadows = buffers_create_dubo(Camera, frame_count)

    shadow := Camera {
        view = la.matrix4_look_at(
            vec3{  -1, 4, 0 },
            vec3{  0, 0,  0 },
            vec3{  0, 1,  0 },
        ),
        proj = la.matrix_ortho3d_f32(-1, 1, -1, 1, 0, 8),
    }

    for i in 0..<frame_count { 
		buffers_write_tbuffer(shadows, &shadow, i) 
	}

    return shadows 
}

scene_prepare :: proc(scene: ^Scene, pass: ^PassInfo) {
    ctx := get_context()
    frame_num := g_frame_index

    rd := DEFAULT_RESOURCES[.FORWARD]

    pass.global_descriptor = descriptors_get(pass.in_layouts.descriptors[GLOBAL_SET])
    gd := pass.global_descriptor
    descriptors_bind(gd, "_camera", rd, scene.camera_buffer)
    descriptors_bind(gd, "_lights", rd, scene.lights_buffer)
    descriptors_bind(gd, "_image_sampler", rd, scene.shadows_sampler, scene.shadow_images[frame_num].view)
    descriptors_bind(gd, "_shadow_cam", rd, scene.shadows_buffer)

    pass.mat_descriptor = descriptors_get(pass.in_layouts.descriptors[MATERIAL_SET])
    md := pass.mat_descriptor
    descriptors_bind(md, "_material", rd, pass.mat_buffer)

    pass.object_descriptor = descriptors_get(pass.in_layouts.descriptors[OBJECT_SET])
    od := pass.object_descriptor
    descriptors_bind(od, "_object", rd, pass.object_buffers[g_frame_index])
}

scene_do_forward_pass :: proc(scene: ^Scene, pass: ^PassInfo) {

    begin_render_pass(pass)

    scene.time += 0.001

    cmd := get_frame().command_buffer
    frame_num := get_frame().index

    // Bind Global Descriptor Set
    descriptor := pass.global_descriptor
    cam_offset := u32(size_of(Camera) * frame_num)
    builders.cmd_bind_descriptor_set(cmd, pass.in_layouts.pipeline, 0, { descriptor }, { cam_offset, cam_offset } )

    last_material: ^ShaderEffect = nil
    for i in 0..<pass.n_renderables do scene_render_object(scene, pass, i, &last_material)

    end_render_pass()
}

scene_render_object :: proc(scene: ^Scene,
                            pass: ^PassInfo,
                            object_num: int,
                            last_material: ^^ShaderEffect) {
    frame_num := get_frame().index
    cmd := get_frame().command_buffer
    device := get_context().device

    object := &pass.renderables[object_num]

    // BIND PER MATERIAL DATA
    if object.prog != last_material^ {
        vk.CmdBindPipeline(cmd, .GRAPHICS, object.prog.pipeline)

        offset := u32(object.material_offset)
        builders.cmd_bind_descriptor_set(cmd, pass.in_layouts.pipeline, MATERIAL_SET, { pass.mat_descriptor }, { offset })
    }

    last_material^ = object.prog

    // BIND PER OBJECT DATA
    dynamic_offset := u32(object.object_offset)
    builders.cmd_bind_descriptor_set(cmd, pass.in_layouts.pipeline, OBJECT_SET, { pass.object_descriptor }, { dynamic_offset })

    offset : vk.DeviceSize = 0
    vk.CmdBindVertexBuffers(cmd, 0, 1, &object.vertex_buffer.handle, &offset)
    vk.CmdBindIndexBuffer(cmd, object.index_buffer.handle, 0, .UINT16)
    vk.CmdDrawIndexed(cmd, u32(object.index_buffer.size / size_of(u16)), 1, 0, 0, 0)
}

scene_find_resource :: proc(this: ^Scene, pass: ^PassInfo, name: string) -> rawptr {
    switch(name) {
        case "_camera": 
            return &this.camera_buffer
        case "_lights":
            return &this.lights_buffer
        case "_image_sampler":
            return &this.shadows_sampler
        case "_shadow_cam":
            return &this.shadows_buffer
        case "_object":
            return &pass.object_buffers[g_frame_index]
        case:
            return nil
    }
}

