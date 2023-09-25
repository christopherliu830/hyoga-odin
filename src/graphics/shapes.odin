package graphics

import "core:math"
import la "core:math/linalg"

import vk "vendor:vulkan"

import "common"

ShapeType :: enum {
    CUBE,
    TETRAHEDRON,
}

Cube :: struct {
    vertices:  [24]common.Vertex,
    indices:   [36]u16,
}

Tetrahedron :: struct {
    vertices:  [12]common.Vertex,
    indices:   [12]u16,
}

create_tetrahedron :: proc() -> Tetrahedron {
	v := [?]la.Vector3f32 {
		{ 1,  1,  1},
		{ 1, -1, -1},
		{-1,  1, -1},
		{-1, -1,  1},
	};

    normals := [?]la.Vector3f32 {
        la.vector_normalize(la.cross(v[1] - v[0], v[2] - v[0])),
        la.vector_normalize(la.cross(v[1] - v[3], v[0] - v[3])),
        la.vector_normalize(la.cross(v[3] - v[1], v[2] - v[1])),
        la.vector_normalize(la.cross(v[3] - v[0], v[2] - v[0])),
    }

    color := la.Vector4f32 { 1, 1, 1, 1 }

	// normals_map[n] returns the indices of the three different normals
    // in the array above that are associated with the vertex at N.
    normals_map := [4][3]int {
		{0, 1, 3}, // i.e. vertex 0 will be triplicated with normals[0], normals[1], normals[3]
		{0, 1, 2},
		{0, 2, 3},
		{1, 2, 3},
    }

    tetra: Tetrahedron

    for vertex_num in 0..<4 {
        i := vertex_num *3

		tetra.vertices[i+0].position = v[vertex_num]
		tetra.vertices[i+0].normal = normals[normals_map[vertex_num][0]]
		tetra.vertices[i+0].color = color

		tetra.vertices[i+1].position = v[vertex_num]
		tetra.vertices[i+1].normal = normals[normals_map[vertex_num][1]]
		tetra.vertices[i+1].color = color

		tetra.vertices[i+2].position = v[vertex_num]
		tetra.vertices[i+2].normal = normals[normals_map[vertex_num][2]]
		tetra.vertices[i+2].color = color
    }

    tetra.indices = [12]u16 {
		6, 3, 0,
		11, 8, 2,
		9, 1, 4,
		10, 5, 8,
    }

    for _, i in tetra.vertices do tetra.vertices[i].position /= 2

    return tetra
}

create_cube :: proc() -> Cube {

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

    for _, i in cube.vertices do cube.vertices[i].position /= 2 

    return cube
}
