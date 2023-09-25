package builders 

import "core:fmt"

import vk "vendor:vulkan"

vk_assert :: proc(result: vk.Result) {
    fmt.assertf(result == .SUCCESS, "assertion failed with code %v", result)
}
