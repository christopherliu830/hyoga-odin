package graphics

import "core:image/png"
import "core:log"
import "core:bytes"
import "core:mem"

import vk "vendor:vulkan"

MaterialIn :: struct {
    name: string,
    diffuse_path: string,
    normal_path: string,
}

create_material :: proc (mat_in: MaterialIn) -> (mat: MyMaterial) {

    ctx := get_context()
    stage := ctx.stage

    image, error := png.load(mat_in.diffuse_path)
    defer png.destroy(image)
    assert(error == nil)

    data := bytes.buffer_to_bytes(&image.pixels)

    extent := vk.Extent3D { width = u32(image.width), height = u32(image.height), depth = 1 }
    mat.diffuse = buffers_create_image(.R8G8B8A8_SRGB, extent, { .SAMPLED, .TRANSFER_DST })

    up_ctx := buffers_stage(&stage, raw_data(data), len(data))
    buffers_copy_image(up_ctx, extent, mat.diffuse)

    return mat
}

MyMaterial :: struct {
    color: vec4,
    diffuse: Image
}
