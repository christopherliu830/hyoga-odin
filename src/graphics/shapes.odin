package graphics

import "core:math"
import la "core:math/linalg"

import vk "vendor:vulkan"

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
		cube.vertices[i].position     = vertices[i];
		cube.vertices[i].normal       = vertices[i];
		cube.vertices[i].color        = color;
    }

	cube.indices = {
		// TOP
		3, 6, 2,
		6, 3, 7,

		// BOTTOM
		0, 1, 4,
		4, 1, 5,

		// LEFT
		0, 1, 2,
		3, 2, 1,

		// RIGHT
		6, 5, 4,
		5, 6, 7,

		// FRONT
		0, 2, 4,
		4, 2, 6,

		// BACK
		5, 3, 1,
		3, 5, 7,
	};

    for _, i in cube.vertices do cube.vertices[i].position /= 2 

    return cube
}
