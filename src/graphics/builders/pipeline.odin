package builders

import "core:log"

import vk "vendor:vulkan"

create_pipeline :: proc(device:           vk.Device,
                        layout:           vk.PipelineLayout,
                        stages:           []vk.PipelineShaderStageCreateInfo = nil,
                        vertex_input:     ^vk.PipelineVertexInputStateCreateInfo = nil,
                        input_assembly:   ^vk.PipelineInputAssemblyStateCreateInfo = nil,
                        viewport:         ^vk.PipelineViewportStateCreateInfo = nil,
                        rasterization:    ^vk.PipelineRasterizationStateCreateInfo = nil,
                        multisampling:    ^vk.PipelineMultisampleStateCreateInfo = nil,
                        depth_stencil:    ^vk.PipelineDepthStencilStateCreateInfo = nil,
                        color_blend:      ^vk.PipelineColorBlendStateCreateInfo = nil,
                        dynamic_state:    ^vk.PipelineDynamicStateCreateInfo = nil,
                        render_pass:      vk.RenderPass,
                        old:              vk.Pipeline = 0) ->
(pipeline: vk.Pipeline) {

    vertex_input := vertex_input
    bindings := []vk.VertexInputBindingDescription {}
    attributes := []vk.VertexInputAttributeDescription {}
    vertex_input_default: vk.PipelineVertexInputStateCreateInfo 
    if vertex_input == nil {
        vertex_input_default = get_vertex_input(bindings, attributes)
        vertex_input = &vertex_input_default
    }
    

    input_assembly := input_assembly
    input_assembly_default: vk.PipelineInputAssemblyStateCreateInfo
    if input_assembly == nil {
        input_assembly_default = get_input_assembly()
        input_assembly = &input_assembly_default
    }

    viewport := viewport
    viewport_default: vk.PipelineViewportStateCreateInfo
    if viewport == nil {
        viewport_default = get_viewport_state({}, {})
        viewport = &viewport_default
    }

    rasterization := rasterization
    rasterization_default: vk.PipelineRasterizationStateCreateInfo 
    if rasterization == nil {
        rasterization_default = get_rasterization()
        rasterization = &rasterization_default
    }

    multisampling := multisampling
    multisampling_default: vk.PipelineMultisampleStateCreateInfo 
    if multisampling == nil {
        multisampling_default = get_multisampling()
        multisampling = &multisampling_default
    }

    depth_stencil := depth_stencil
    depth_stencil_default: vk.PipelineDepthStencilStateCreateInfo
    if depth_stencil == nil {
        depth_stencil_default := get_depth_stencil(true, true, .LESS_OR_EQUAL)
        depth_stencil = &depth_stencil_default
    }

    color_blend := color_blend 
    color_attachment: [1]vk.PipelineColorBlendAttachmentState
    color_blend_default: vk.PipelineColorBlendStateCreateInfo
    if color_blend == nil {
        color_attachment = { get_color_blending_attachment() }
        color_blend_default = get_color_blend(color_attachment[:])
        color_blend = &color_blend_default
    }

    dynamic_state := dynamic_state
    dynamic_states := []vk.DynamicState {
        .VIEWPORT_WITH_COUNT,
        .SCISSOR_WITH_COUNT,
    }

    dynamic_state_default: vk.PipelineDynamicStateCreateInfo
    if dynamic_state == nil {
        dynamic_state_default = get_dynamic_states(dynamic_states)
        dynamic_state = &dynamic_state_default
    }

    info := vk.GraphicsPipelineCreateInfo {
            sType               = .GRAPHICS_PIPELINE_CREATE_INFO,
            stageCount          = u32(len(stages)),
            pStages             = raw_data(stages),
            pVertexInputState   = vertex_input,
            pInputAssemblyState = input_assembly,
            pTessellationState  = nil,
            pViewportState      = viewport,
            pRasterizationState = rasterization,
            pMultisampleState   = multisampling,
            pDepthStencilState  = depth_stencil,
            pColorBlendState    = color_blend,
            pDynamicState       = dynamic_state,
            layout              = layout,
            renderPass          = render_pass,
            subpass             = 0,
            basePipelineHandle  = 0,
            basePipelineIndex   = -1,
    }

    result := vk.CreateGraphicsPipelines(device, 0, 1, &info, nil, &pipeline)
    assert(result == .SUCCESS)

    return pipeline
}

create_pipeline_layout :: proc(device: vk.Device, layouts: []vk.DescriptorSetLayout) ->
(layout: vk.PipelineLayout) {
    info := vk.PipelineLayoutCreateInfo {
        sType          = .PIPELINE_LAYOUT_CREATE_INFO,
        setLayoutCount = u32(len(layouts)),
        pSetLayouts    = raw_data(layouts),
    }

    vk_assert(vk.CreatePipelineLayout(device, &info, nil, &layout))
    return layout
}

create_render_pass :: proc(device: vk.Device, format: vk.Format) ->
(render_pass: vk.RenderPass) {
    color_attachment := vk.AttachmentDescription {
        format         = format,
        samples        = { ._1 },
        loadOp         = .CLEAR,
        storeOp        = .STORE,
        stencilLoadOp  = .DONT_CARE,
        stencilStoreOp = .DONT_CARE,
        initialLayout  = .UNDEFINED,
        finalLayout    = .PRESENT_SRC_KHR,
    }

    color_attachment_ref := vk.AttachmentReference {
        attachment = 0,
        layout     = .COLOR_ATTACHMENT_OPTIMAL,
    }
    
    depth_attachment := vk.AttachmentDescription {
        flags          = {},
        format         = .D32_SFLOAT,
        samples        = { ._1 },
        loadOp         = .CLEAR,
        storeOp        = .STORE,
        stencilLoadOp  = .CLEAR,
        stencilStoreOp = .DONT_CARE,
        initialLayout  = .UNDEFINED,
        finalLayout    = .DEPTH_STENCIL_ATTACHMENT_OPTIMAL,
    }
    
    depth_attachment_ref := vk.AttachmentReference  {
        attachment = 1,
        layout = .DEPTH_STENCIL_ATTACHMENT_OPTIMAL,
    }

    subpass := vk.SubpassDescription {
        pipelineBindPoint       = .GRAPHICS,
        colorAttachmentCount    = 1,
        pColorAttachments       = &color_attachment_ref,
        pDepthStencilAttachment = &depth_attachment_ref,
    }

    dependency := vk.SubpassDependency {
        srcSubpass    = vk.SUBPASS_EXTERNAL,
        dstSubpass    = .0,
        srcStageMask  = { .COLOR_ATTACHMENT_OUTPUT },
        srcAccessMask = { },
        dstStageMask  = { .COLOR_ATTACHMENT_OUTPUT },
        dstAccessMask = { .COLOR_ATTACHMENT_READ, .COLOR_ATTACHMENT_WRITE },
    }
    
    depth_dependency := vk.SubpassDependency {
        srcSubpass    = vk.SUBPASS_EXTERNAL,
        dstSubpass    = .0,
        srcStageMask  = { .EARLY_FRAGMENT_TESTS, .LATE_FRAGMENT_TESTS },
        srcAccessMask = {},
        dstStageMask  = { .EARLY_FRAGMENT_TESTS, .LATE_FRAGMENT_TESTS },
        dstAccessMask = { .DEPTH_STENCIL_ATTACHMENT_WRITE },
    }

    attachments := []vk.AttachmentDescription { color_attachment, depth_attachment }
    dependencies := []vk.SubpassDependency { dependency, depth_dependency }

    render_pass_create_info := vk.RenderPassCreateInfo {
        sType           = .RENDER_PASS_CREATE_INFO,
        attachmentCount = u32(len(attachments)),
        pAttachments    = raw_data(attachments),
        subpassCount    = 1,
        pSubpasses      = &subpass,
        dependencyCount = u32(len(dependencies)),
        pDependencies   = raw_data(dependencies),
    }

    vk_assert(vk.CreateRenderPass(device, &render_pass_create_info, nil, &render_pass))

    return render_pass
}


get_vertex_input :: proc(bindings:   []vk.VertexInputBindingDescription,
                         attributes: []vk.VertexInputAttributeDescription) ->
vk.PipelineVertexInputStateCreateInfo {
    return {
        sType                           = .PIPELINE_VERTEX_INPUT_STATE_CREATE_INFO,
        vertexBindingDescriptionCount   = u32(len(bindings)),
        pVertexBindingDescriptions      = raw_data(bindings),
        vertexAttributeDescriptionCount = u32(len(attributes)),
        pVertexAttributeDescriptions    = raw_data(attributes),
    }
}

get_input_assembly :: proc() -> vk.PipelineInputAssemblyStateCreateInfo {
    return {
        sType                  = .PIPELINE_INPUT_ASSEMBLY_STATE_CREATE_INFO,
        topology               = .TRIANGLE_LIST,
        primitiveRestartEnable = false,
    }
}

get_viewport_state :: proc(viewports: []vk.Viewport, scissors: []vk.Rect2D) ->
vk.PipelineViewportStateCreateInfo {
    viewport_state := vk.PipelineViewportStateCreateInfo {
        sType         = .PIPELINE_VIEWPORT_STATE_CREATE_INFO,
        viewportCount = u32(len(viewports)),
        pViewports    = raw_data(viewports),
        scissorCount  = u32(len(scissors)),
        pScissors     = raw_data(scissors),
    }

    return viewport_state
}

get_rasterization :: proc() -> vk.PipelineRasterizationStateCreateInfo {
    return {
        sType                   = .PIPELINE_RASTERIZATION_STATE_CREATE_INFO,
        depthClampEnable        = false,
        cullMode                = {},
        frontFace               = .CLOCKWISE,
        depthBiasEnable         = false,
        depthBiasConstantFactor = 0,
        depthBiasClamp          = 0,
        depthBiasSlopeFactor    = 0,
        lineWidth               = 1,
    }
}

get_multisampling :: proc() -> vk.PipelineMultisampleStateCreateInfo {
    return {
        sType                 = .PIPELINE_MULTISAMPLE_STATE_CREATE_INFO,
        sampleShadingEnable   = false,
        rasterizationSamples  = { ._1 },
        minSampleShading      = 1,
        pSampleMask           = nil,
        alphaToCoverageEnable = false,
        alphaToOneEnable      = false,
    }
}

get_depth_stencil :: proc(test, write: bool, op: vk.CompareOp) -> vk.PipelineDepthStencilStateCreateInfo {
    return vk.PipelineDepthStencilStateCreateInfo {
        sType                 = .PIPELINE_DEPTH_STENCIL_STATE_CREATE_INFO,
        depthTestEnable       = b32(test),
        depthWriteEnable      = b32(write),
        depthCompareOp        = test ? op : .ALWAYS,
        depthBoundsTestEnable = b32(false),
        minDepthBounds        = 0,
        maxDepthBounds        = 1,
        stencilTestEnable     = b32(false),
    }
}

get_color_blending_attachment :: proc() -> vk.PipelineColorBlendAttachmentState {
    return {
        colorWriteMask      = { .R, .G, .B, .A },
        blendEnable         = false,
        srcColorBlendFactor = .SRC_ALPHA,
        dstColorBlendFactor = .ONE_MINUS_SRC_ALPHA,
        colorBlendOp        = .ADD,
        srcAlphaBlendFactor = .SRC_ALPHA,
        dstAlphaBlendFactor = .ONE_MINUS_SRC_ALPHA,
        alphaBlendOp        = .ADD,
    }
}

get_color_blend :: proc(blends: []vk.PipelineColorBlendAttachmentState) ->
vk.PipelineColorBlendStateCreateInfo {
    return {
        sType           = .PIPELINE_COLOR_BLEND_STATE_CREATE_INFO,
        logicOpEnable   = false,
        logicOp         = .COPY,
        attachmentCount = u32(len(blends)),
        pAttachments    = raw_data(blends),
    }
}

get_dynamic_states :: proc(states: []vk.DynamicState) -> vk.PipelineDynamicStateCreateInfo {
    return {
        sType             = .PIPELINE_DYNAMIC_STATE_CREATE_INFO,
        dynamicStateCount = u32(len(states)),
        pDynamicStates    = raw_data(states),
    }
}
