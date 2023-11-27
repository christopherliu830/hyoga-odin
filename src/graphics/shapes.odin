package graphics

import "core:math"
import la "core:math/linalg"

import vk "vendor:vulkan"

tetrahedron :: proc() -> Tetrahedron {
    A := 1 / f32(la.SQRT_TWO)
    v := [?]la.Vector3f32 {
        {-1,  0, -A}, 
        {+1,  0, -A}, 
        { 0, -1, +A}, 
        { 0, +1, +A},
    };

    normals := [?]la.Vector3f32 {
        la.vector_normalize(la.cross(v[1] - v[2], v[3] - v[1])), // +X - +Z
        la.vector_normalize(la.cross(v[0] - v[3], v[2] - v[0])), // -X - +Z
        la.vector_normalize(la.cross(v[0] - v[1], v[3] - v[0])), // +Y - -Z
        la.vector_normalize(la.cross(v[0] - v[2], v[1] - v[0])), // -Y - -Z
    }


    color := la.Vector4f32 { 1, 1, 1, 1 }

    tetra: Tetrahedron

    faces := [?]int {
        1, 3, 2,
        0, 2, 3,
        0, 3, 1,
        0, 1, 2,
    }

    for vertex_num in 0..<4 {
        i := vertex_num * 3

        tetra.vertices[i+0].position = v[faces[i+0]]
        tetra.vertices[i+0].normal = normals[vertex_num]
        tetra.vertices[i+0].color = color

        tetra.vertices[i+1].position = v[faces[i+1]]
        tetra.vertices[i+1].normal = normals[vertex_num]
        tetra.vertices[i+1].color = color

        tetra.vertices[i+2].position = v[faces[i+2]]
        tetra.vertices[i+2].normal = normals[vertex_num]
        tetra.vertices[i+2].color = color
    }

    tetra.indices = [12]u16 {
        0, 1, 2,
        3, 4, 5,
        6, 7, 8,
        9, 10, 11,
    }
    
    for &vertex in tetra.vertices do vertex.position /= 2

    return tetra
}

cube :: proc() -> Cube {

    vertices := [8]la.Vector3f32 {
        {-1, -1, -1},
        {-1, -1,  1},
        {-1,  1, -1},
        {-1,  1,  1},
        { 1, -1, -1},
        { 1, -1,  1},
        { 1,  1, -1},
        { 1,  1,  1},
    };

    color := la.Vector4f32 { 1, 1, 1, 1 }

    cube: Cube

    for i in 0..<8 {
        index := i * 3;
        cube.vertices[index].position     = vertices[i];
        cube.vertices[index].normal       = la.Vector3f32{1, 0, 0} * vertices[i];
        cube.vertices[index].color        = color;

        cube.vertices[index + 1].position = vertices[i];
        cube.vertices[index + 1].normal   = la.Vector3f32{0, 1, 0} * vertices[i];
        cube.vertices[index + 1].color    = color;

        cube.vertices[index + 2].position = vertices[i];
        cube.vertices[index + 2].normal   = la.Vector3f32{0, 0, 1} * vertices[i];
        cube.vertices[index + 2].color    = color;
    }

    cube.indices = {
        // TOP
        7, 19, 10,
        10, 19, 22,

        // BOTTOM
        4, 16, 1,
        1, 16, 13,

        // LEFT
        3, 0, 9,
        9, 0, 6,

        // RIGHT
        12, 15, 18,
        18, 15, 21,

        // FRONT
        2, 14, 8,
        8, 14, 20,

        // BACK
        17, 5, 23,
        23, 5, 11,
    };

    for &vertex in cube.vertices do vertex.position /= 2 

    return cube
}

create_mesh :: proc(scene: ^Scene, vertices: []Vertex, indices: []u16) -> THandle(Mesh) {
    ctx := get_context()

    size_vertices := size_of(vertices[0]) * len(vertices)
    size_indices := size_of(indices[0]) * len(indices)

    mesh := Mesh {
        vertices = buffers_create(size_vertices, .VERTEX),
        indices = buffers_create(size_indices, .INDEX),
    }

    scene.meshes[scene.n_meshes] = mesh

    v := buffers_stage(&ctx.stage, raw_data(vertices), size_vertices)
    buffers_copy(v, size_vertices, mesh.vertices)

    i := buffers_stage(&ctx.stage, raw_data(indices), size_indices)
    buffers_copy(i, size_indices, mesh.indices)

    buffers_flush_stage(&ctx.stage)

    handle := scene.n_meshes

    scene.n_meshes += 1

    return THandle(Mesh) { handle }
}

add_object :: proc(scene: ^Scene, mesh_id: THandle(Mesh), material: ^Material) -> THandle(Renderable) {
    ctx := get_context()

    mesh := scene.meshes[mesh_id.id]
    r: Renderable
    r.vertex_buffer = mesh.vertices
    r.index_buffer = mesh.indices

    id := 0

    for effect in material.passes {
        if effect == nil do continue

        pass := &ctx.passes[effect.type]
        id = pass.n_renderables

        r.prog = effect
        r.object_offset = id

        pass.renderables[pass.n_renderables] = r

        pass.n_renderables += 1
    }

    return THandle(Renderable) { id } 
}

update_object :: proc(scene: ^Scene, handle: THandle(Renderable), transform: mat4) {
    ctx := get_context()

    transform := transform

    for &pass in ctx.passes {
        offset := buffers_write_tbuffer(pass.object_buffers[g_frame_index], &transform, handle.id)
        pass.renderables[handle.id].object_offset = offset
    }
}