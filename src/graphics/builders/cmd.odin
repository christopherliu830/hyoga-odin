package builders

import vk "vendor:vulkan"

cmd_bind_descriptor_set :: proc (cmd: vk.CommandBuffer,
                                 layout: vk.PipelineLayout, 
                                 set_num: int,
                                 sets: []vk.DescriptorSet,
                                 offsets: []u32) {

    vk.CmdBindDescriptorSets(cmd, .GRAPHICS, layout, u32(set_num),
                             u32(len(sets)), raw_data(sets), u32(len(offsets)), raw_data(offsets))
}

cmd_pipeline_barrier :: proc(cmd:                    vk.CommandBuffer,
                             src:                    vk.PipelineStageFlags,
                             dst:                    vk.PipelineStageFlags,
                             dependency_flags:       vk.DependencyFlags = {},
                             memory_barriers:        []vk.MemoryBarrier = {},
                             buffer_memory_barriers: []vk.BufferMemoryBarrier = {},
                             image_memory_barriers:  []vk.ImageMemoryBarrier = {}) {
    vk.CmdPipelineBarrier(cmd, src, dst,
                          dependency_flags,
                          u32(len(memory_barriers)),
                          raw_data(memory_barriers),
                          u32(len(buffer_memory_barriers)),
                          raw_data(buffer_memory_barriers),
                          u32(len(image_memory_barriers)),
                          raw_data(image_memory_barriers))

}