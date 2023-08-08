package graphics

import "core:os"
import "core:fmt"
import vk "vendor:vulkan"

/**
* The pipeline configures the stages of the graphics pipeline, e.g. vertex shader,
* tessellation, geometry shader, rasterization, fragment shader, color blending,
* depth and stencil test.
*/
Pipeline :: struct
{
	handle: vk.Pipeline,
	render_pass: vk.RenderPass,
	layout: vk.PipelineLayout,
}

create_pipeline :: proc(using ctx: ^Context) -> vk.Result {

        pipeline_layout: vk.PipelineLayout

        layout_info: vk.PipelineLayoutCreateInfo = {
                sType = .PIPELINE_LAYOUT_CREATE_INFO,
        }

        vk.CreatePipelineLayout(device, &layout_info, nil, &pipeline_layout)

        fragment_module := load_shader_module(ctx, "./frag.spv")
        defer vk.DestroyShaderModule(device, fragment_module, nil)
        vertex_module := load_shader_module(ctx, "./vert.spv")
        defer vk.DestroyShaderModule(device, vertex_module, nil)

        shader_stages : []vk.PipelineShaderStageCreateInfo = {
        {
                sType = .PIPELINE_SHADER_STAGE_CREATE_INFO,
                pName = "main",
                stage = { .VERTEX },
                module = vertex_module,
        }, 
        {
                sType = .PIPELINE_SHADER_STAGE_CREATE_INFO,
                pName = "main",
                stage = { .FRAGMENT },
                module = fragment_module,
        },
        }

        // VERTEX INPUT
        // describes the format of the vertex data that will be passed
        // to the vertex shader. 
        vertex_input: vk.PipelineVertexInputStateCreateInfo = {
                sType = .PIPELINE_VERTEX_INPUT_STATE_CREATE_INFO,
                vertexBindingDescriptionCount = 0,
                pVertexBindingDescriptions = nil,
                vertexAttributeDescriptionCount = 0,
                pVertexAttributeDescriptions = nil,

        }

        // INPUT ASSEMBLY
        // describes two things: what kind of geometry will be drawn from
        // the vertices and if primitive restart should be enabled.
        input_assembly: vk.PipelineInputAssemblyStateCreateInfo = {
                sType = .PIPELINE_INPUT_ASSEMBLY_STATE_CREATE_INFO,
                topology = .TRIANGLE_LIST,
                primitiveRestartEnable = false,
        }


        // VIEWPORTS AND SCISSORS
        // Note - since dynamic state is enabled, this is ignored.
        viewport: vk.Viewport = {
                x = 0, y = 0,
                width = f32(swapchain.extent.width),
                height = f32(swapchain.extent.height),
                minDepth = 0,
                maxDepth = 1,
        }

        scissor: vk.Rect2D = { offset = {0, 0}, extent = swapchain.extent }

        viewport_state: vk.PipelineViewportStateCreateInfo = {
                sType = .PIPELINE_VIEWPORT_STATE_CREATE_INFO,
                viewportCount = 1,
                pViewports = &viewport,
                scissorCount = 1,
                pScissors = &scissor,
        }

        // RASTERIZER
        rasterization: vk.PipelineRasterizationStateCreateInfo = {
                sType = .PIPELINE_RASTERIZATION_STATE_CREATE_INFO,
                depthClampEnable = false,
                cullMode = {},
                frontFace = .CLOCKWISE,
                depthBiasEnable = false,
                depthBiasConstantFactor = 0,
                depthBiasClamp = 0,
                depthBiasSlopeFactor = 0,
                lineWidth = 1,
        }

        // MULTISAMPLING - Antialiasing
        // It works by combining the fragment shader results of
        // multiple polygons that rasterize to the same pixel. This mainly
        // occurs along edges, which is also where the most noticeable
        // aliasing artifacts occur. 
        multisampling: vk.PipelineMultisampleStateCreateInfo = {
                sType = .PIPELINE_MULTISAMPLE_STATE_CREATE_INFO,
                sampleShadingEnable = false,
                rasterizationSamples = { ._1 },
                minSampleShading = 1,
                pSampleMask = nil,
                alphaToCoverageEnable = false,
                alphaToOneEnable = false,
        }


        // COLOR BLENDING
        color_blending_attachment: vk.PipelineColorBlendAttachmentState = {
                colorWriteMask = { .R, .G, .B, .A },
                blendEnable = false,
                srcColorBlendFactor = .SRC_ALPHA,
                dstColorBlendFactor = .ONE_MINUS_SRC_ALPHA,
                colorBlendOp = .ADD,
                srcAlphaBlendFactor = .ONE,
                dstAlphaBlendFactor =  .ZERO,
                alphaBlendOp = .ADD,
        }

        color_blending: vk.PipelineColorBlendStateCreateInfo = {
                sType = .PIPELINE_COLOR_BLEND_STATE_CREATE_INFO,
                logicOpEnable = false,
                logicOp = .COPY,
                attachmentCount = 1,
                pAttachments = &color_blending_attachment,
        }

        // depth_stencil: vk.PipelineDepthStencilStateCreateInfo = {
        //         depthTestEnable = true,
        //         depthWriteEnable = true,
        //         depthCompareOp = .LESS_OR_EQUAL,
        //         minDepthBounds = 0,
        //         maxDepthBounds = 1,
        //         stencilTestEnable = false,
        // }

        dynamic_states := []vk.DynamicState { .VIEWPORT, .SCISSOR }
        dynamic_state: vk.PipelineDynamicStateCreateInfo = {
                sType = .PIPELINE_DYNAMIC_STATE_CREATE_INFO,
                dynamicStateCount = 2,
                pDynamicStates = raw_data(dynamic_states),
        }

        pipeline_create_info: vk.GraphicsPipelineCreateInfo = {
                sType = .GRAPHICS_PIPELINE_CREATE_INFO,
                stageCount = 2, 
                pStages = raw_data(shader_stages),
                pVertexInputState = &vertex_input,
                pInputAssemblyState = &input_assembly,
                pViewportState = &viewport_state,
                pRasterizationState = &rasterization,
                pMultisampleState = &multisampling,
                pDepthStencilState = nil, // TO BE ADDED LATER
                pColorBlendState = &color_blending,
                pDynamicState = &dynamic_state,
                layout = pipeline_layout,
                renderPass = pipeline.render_pass,
                subpass = 0,
                basePipelineHandle = 0,
                basePipelineIndex = -1,
        }

        vk.CreateGraphicsPipelines(
                device, 0,
                1, &pipeline_create_info,
                nil,
                &pipeline.handle) or_return

        return .SUCCESS
}

cleanup_pipeline :: proc(using ctx: ^Context) {
        using pipeline
        vk.DestroyPipelineLayout(device, layout, nil)
        vk.DestroyRenderPass(device, render_pass, nil)
}

create_render_pass :: proc(using ctx: ^Context) -> vk.Result {
        color_attachment: vk.AttachmentDescription = {
                format = swapchain.format.format,
                samples = { ._1 },
                loadOp = .CLEAR,
                storeOp = .STORE,
                stencilLoadOp = .DONT_CARE,
                stencilStoreOp = .DONT_CARE,
                initialLayout = .UNDEFINED,
                finalLayout = .PRESENT_SRC_KHR, 
        }

        color_attachment_ref: vk.AttachmentReference = {
                attachment = 0,
                layout = .COLOR_ATTACHMENT_OPTIMAL,
        }

        subpass: vk.SubpassDescription = {
                pipelineBindPoint = .GRAPHICS,
                colorAttachmentCount = 1,
                pColorAttachments = &color_attachment_ref,
        }

        dependency: vk.SubpassDependency = {
                srcSubpass = vk.SUBPASS_EXTERNAL,
                dstSubpass = .0,
                srcStageMask = { .COLOR_ATTACHMENT_OUTPUT },
                srcAccessMask = { },
                dstStageMask = { .COLOR_ATTACHMENT_OUTPUT },
                dstAccessMask = { .COLOR_ATTACHMENT_READ, .COLOR_ATTACHMENT_WRITE },
        }

        render_pass_create_info: vk.RenderPassCreateInfo = {
                sType = .RENDER_PASS_CREATE_INFO,
                attachmentCount = 1,
                pAttachments = &color_attachment,
                subpassCount = 1,
                pSubpasses = &subpass,
                dependencyCount = 1,
                pDependencies = &dependency,
        }

        vk.CreateRenderPass(device, &render_pass_create_info, nil, &pipeline.render_pass) or_return

        return .SUCCESS
}

load_shader_module :: proc(using ctx: ^Context, name: string) -> (shader_module: vk.ShaderModule) {
        data, ok := os.read_entire_file(name)
        if (!ok) {
                // Could not read file
                fmt.panicf("Could not read file\nPath: %v/%v",
                        os.get_current_directory(),
                        name)
        }
        defer delete(data)

        shader_module_create_info: vk.ShaderModuleCreateInfo = {
                sType = .SHADER_MODULE_CREATE_INFO,
                codeSize = len(data),
                pCode = cast(^u32)raw_data(data),
        }

        result := vk.CreateShaderModule(device, &shader_module_create_info, nil, &shader_module)
        if (result != .SUCCESS) {
                fmt.panicf("Shader creation failed with error %v", result)
        }

        return shader_module
}
