package builders

import "core:log"

import vk "vendor:vulkan"

import "../common"

create_pipeline :: proc(device:           vk.Device,
                        layout:           vk.PipelineLayout,
                        render_pass:      vk.RenderPass,
                        shader_stages:    []vk.PipelineShaderStageCreateInfo,
                        old:              vk.Pipeline = 0) ->
(pipeline: vk.Pipeline) {

    bindings := common.BINDINGS
    attributes := common.ATTRIBUTES
    vert     := get_vertex_input(bindings[:], attributes[:])

    input    := get_input_assembly()

    view     := get_dummy_viewport_state()

    raster   := get_rasterization()

    multi    := get_multisampling()

    depth    := get_depth_stencil(true, true, .LESS_OR_EQUAL)

    color_attachment := []vk.PipelineColorBlendAttachmentState { get_color_blending_attachment() }
    color := get_color_blend(color_attachment)

    dynamic_states := []vk.DynamicState { .VIEWPORT, .SCISSOR }
    dyna := get_dynamic_states(dynamic_states)

    info := vk.GraphicsPipelineCreateInfo {
            sType               = .GRAPHICS_PIPELINE_CREATE_INFO,
            stageCount          = u32(len(shader_stages)),
            pStages             = raw_data(shader_stages),
            pVertexInputState   = &vert,
            pInputAssemblyState = &input,
            pViewportState      = &view,
            pRasterizationState = &raster,
            pMultisampleState   = &multi,
            pDepthStencilState  = &depth,
            pColorBlendState    = &color,
            pDynamicState       = &dyna,
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

    count := u32(len(layouts))
    ls : [4]vk.DescriptorSetLayout
    for i in 0..<count {
        ls[i] = layouts[i]
    }

    info: vk.PipelineLayoutCreateInfo = {
        sType          = .PIPELINE_LAYOUT_CREATE_INFO,
        setLayoutCount = count,
        pSetLayouts    = raw_data(ls[:]),
    }

    result := vk.CreatePipelineLayout(device, &info, nil, &layout)
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

    render_pass_create_info: vk.RenderPassCreateInfo = {
        sType           = .RENDER_PASS_CREATE_INFO,
        attachmentCount = u32(len(attachments)),
        pAttachments    = raw_data(attachments),
        subpassCount    = 1,
        pSubpasses      = &subpass,
        dependencyCount = u32(len(dependencies)),
        pDependencies   = raw_data(dependencies),
    }

    result := vk.CreateRenderPass(device, &render_pass_create_info, nil, &render_pass)
    assert(result == .SUCCESS)

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

get_dummy_viewport_state :: proc() -> vk.PipelineViewportStateCreateInfo {
    viewport := vk.Viewport {
        x        = 0,
        y        = 0,
        width    = 1,
        height   = 1,
        minDepth = 0,
        maxDepth = 1,
    }

    scissor := vk.Rect2D { offset = {0, 0}, extent = { 1, 1 } }

    viewport_state := vk.PipelineViewportStateCreateInfo {
        sType         = .PIPELINE_VIEWPORT_STATE_CREATE_INFO,
        viewportCount = 1,
        pViewports    = &viewport,
        scissorCount  = 1,
        pScissors     = &scissor,
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
        srcAlphaBlendFactor = .ONE,
        dstAlphaBlendFactor = .ZERO,
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
