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