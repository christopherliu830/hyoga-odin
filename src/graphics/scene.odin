package graphics

import la "core:math/linalg"
import "core:math"
import vk "vendor:vulkan"

import "materials"

Camera :: struct {
    view: mat4,
    proj: mat4,
}

CameraData :: struct {
    data: []Camera,
    buffer: Buffer
}

Scene :: struct {
    time:       f32,
    camera_ubo:      Buffer,
    object_ubo:      Buffer,
    cam_data:        CameraData,
    light_position:  vec3,

    // Per-frame resources
    model:           [OBJECT_COUNT]mat4,
    camera:          CameraData,

    vertex_buffers:  [OBJECT_COUNT]Buffer,
    index_buffers:   [OBJECT_COUNT]Buffer,
    materials:       [OBJECT_COUNT]^materials.Material,
}

ObjectType :: enum {
    CUBE,
    TETRA
}

scene_init :: proc(scene: ^Scene, camera: CameraData) {
    scene.cam_data = camera
}

scene_create_camera :: proc(swapchain: Swapchain) ->
(cam_data: CameraData) {
    cam_data.buffer = buffers_create(size_of(Camera) * int(swapchain.image_count),
                                     buffers_default_flags(.UNIFORM_DYNAMIC))

    cam_data.data = buffers_to_mtptr(cam_data.buffer, Camera)

    for i in 0..<swapchain.image_count {
        c := &cam_data.data[i]
        c.view = la.matrix4_look_at(
            vec3 { 5, 5, 5 },
            vec3 { 0, 0, 0 },
            vec3 { 0, 0, 1 },
        )

        c.proj = la.matrix4_perspective_f32(
            45,
            f32(swapchain.extent.width) / f32(swapchain.extent.height),
            0.1,
            100,
        )
        c.proj[1][1] *= -1
    }

    return cam_data
}

scene_render :: proc(scene: ^Scene, cmd: vk.CommandBuffer, frame_num: int) {
    scene.time+= 0.001

    cam_buffer := buffers_to_mtptr(scene.cam_data.buffer, Camera)
    camera := &cam_buffer[frame_num]
    camera.view = la.matrix4_look_at(
        vec3 { math.sin(scene.time) * 5, 5, math.cos(scene.time) * 5 },
        vec3 { 0, 0, 0 },
        vec3 { 0, 1, 0 },
    )

    last_material: ^materials.Material = nil
    for i in 0..<OBJECT_COUNT {
        scene_render_object(scene, cmd, frame_num, i, &last_material)
    }
}

scene_render_object :: proc(scene: ^Scene,
                            cmd: vk.CommandBuffer,
                            frame_num: int,
                            object_num: int,
                            last_material: ^^materials.Material) {

    material := scene.materials[object_num]
    vertex_buffer := scene.vertex_buffers[object_num]
    index_buffer := scene.index_buffers[object_num]

    object_transform := buffers_to_mtptr(scene.object_ubo, mat4)
    object_transform[object_num] = la.matrix4_translate(vec3 { 0, math.sin(scene.time * 3), 0 })

    // BIND GLOBAL DATA
    if last_material^ == nil {
        offset := size_of(Camera) * u32(frame_num)
        vk.CmdBindDescriptorSets(cmd, .GRAPHICS,
                                 material.pass.effect.pipeline_layout, 0,
                                 1, &material.descriptors[0],
                                 1, &offset)
    }

    // BIND PER MATERIAL DATA
    if material != last_material^ {
        vk.CmdBindPipeline(cmd, .GRAPHICS, material.pass.pipeline)

        vk.CmdBindDescriptorSets(cmd, .GRAPHICS,
                           material.pass.effect.pipeline_layout, 2,
                           1, &material.descriptors[2],
                           0, nil)
    }

    last_material^ = material

    // BIND PER OBJECT DATA
    dynamic_offset := u32(size_of(mat4) * object_num)
    vk.CmdBindDescriptorSets(cmd, .GRAPHICS,
                             material.pass.effect.pipeline_layout, 3,
                             1, &material.descriptors[3],
                             1, &dynamic_offset)

    offset : vk.DeviceSize = 0
    vk.CmdBindVertexBuffers(cmd, 0, 1, &vertex_buffer.handle, &offset)
    vk.CmdBindIndexBuffer(cmd, index_buffer.handle, 0, .UINT16)
    vk.CmdDrawIndexed(cmd, u32(index_buffer.size / size_of(u16)), 1, 0, 0, 0)
}


