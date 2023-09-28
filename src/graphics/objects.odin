package graphics

import la "core:math/linalg"
import "materials"

RenderData :: struct {
    cube:            Cube,
    tetra:           Tetrahedron,
    camera_ubo:      Buffer,
    object_ubo:      Buffer,
    model:           [OBJECT_COUNT]la.Matrix4f32,
    vertex_buffers:  [OBJECT_COUNT]Buffer,
    index_buffers:   [OBJECT_COUNT]Buffer,
    materials:       [OBJECT_COUNT]^materials.Material,
}

ObjectType :: enum {
    CUBE,
    TETRA
}

objects_create :: proc() {
}

