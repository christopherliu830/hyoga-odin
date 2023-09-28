package graphics

import "core:fmt"
import "core:runtime"

import bt "pkgs:obacktracing"
import vk "vendor:vulkan"

vk_assert :: proc(result: vk.Result) {
    fmt.assertf(result == .SUCCESS, "assertion failed with code %v", result)
}

debug_messenger_callback :: proc "system" (
    messageSeverity: vk.DebugUtilsMessageSeverityFlagsEXT,
    messageTypes: vk.DebugUtilsMessageTypeFlagsEXT,
    pCallbackData: ^vk.DebugUtilsMessengerCallbackDataEXT,
    pUserData: rawptr,
) -> b32 {
    context = runtime.default_context()

    fmt.printf("%v: %v:\n", messageSeverity, messageTypes)
    fmt.printf("\tmessageIDName   = <%v>\n", pCallbackData.pMessageIdName)
    fmt.printf("\tmessageIDNumber = <%v>\n", pCallbackData.messageIdNumber)
    fmt.printf("\tmessage         = <%v>\n", pCallbackData.pMessage)

    if 0 < pCallbackData.queueLabelCount {
        fmt.printf("\tQueue Labels: \n")
        for i in 0 ..< pCallbackData.queueLabelCount {
            fmt.printf("\t\tlabelName = <%v>\n", pCallbackData.pQueueLabels[i].pLabelName)
        }
    }
    if 0 < pCallbackData.cmdBufLabelCount {
        fmt.printf("\tCommandBuffer Labels: \n")
        for i in 0 ..< pCallbackData.cmdBufLabelCount {
            fmt.printf("\t\tlabelName = <%v>\n", pCallbackData.pCmdBufLabels[i].pLabelName)
        }
    }
    if 0 < pCallbackData.objectCount {
        fmt.printf("Objects:\n")
        for i in 0 ..< pCallbackData.objectCount {
            fmt.printf("\t\tObject %d\n", pCallbackData.pObjects[i].objectType)
            fmt.printf("\t\t\tobjectType   = %s\n", pCallbackData.pObjects[i].objectType)
            fmt.printf("\t\t\tobjectHandle = %d\n", pCallbackData.pObjects[i].objectHandle)
            if pCallbackData.pObjects[i].pObjectName != nil {
                fmt.printf("\t\t\tobjectName   = <%v>\n", pCallbackData.pObjects[i].pObjectName)
            }
        }
    }
    backtrace()
    return true
}

glfw_error_callback :: proc "c" (code: i32, desc: cstring) {
    context = runtime.default_context()
    fmt.println(desc, code)
}

backtrace :: proc() {
    trace := bt.backtrace_get(16)
    defer bt.backtrace_delete(trace)

    messages, err := bt.backtrace_messages(trace)
    fmt.assertf(err == nil, "err: %v", err)
    defer bt.messages_delete(messages)

    fmt.println("[back trace]")
    // Skip obacktracing messages
    for i in 3..<len(messages) do fmt.printf("\t%s - %s\n", messages[i].symbol, messages[i].location)
}
