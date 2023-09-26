package builders

import "core:log"

import vk "vendor:vulkan"

create_debug_utils_messenger :: proc(instance: vk.Instance, callback: vk.ProcDebugUtilsMessengerCallbackEXT) ->
(messenger: vk.DebugUtilsMessengerEXT) {
    info: vk.DebugUtilsMessengerCreateInfoEXT = {
        sType = vk.StructureType.DEBUG_UTILS_MESSENGER_CREATE_INFO_EXT,
        messageSeverity = vk.DebugUtilsMessageSeverityFlagsEXT{.WARNING, .ERROR},
        messageType = vk.DebugUtilsMessageTypeFlagsEXT{.GENERAL, .PERFORMANCE, .VALIDATION},
        pfnUserCallback = callback,
    }

    vk_assert(vk.CreateDebugUtilsMessengerEXT(instance, &info, nil, &messenger))
    return messenger
}
