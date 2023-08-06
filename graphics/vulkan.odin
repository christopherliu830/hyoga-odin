package graphics

import "core:fmt"
import "core:runtime"
import "core:strings"
import sa "core:container/small_array"

import "vendor:glfw"
import vk "vendor:vulkan"

debug_messenger_callback :: proc "system" (
        messageSeverity: vk.DebugUtilsMessageSeverityFlagsEXT,
        messageTypes: vk.DebugUtilsMessageTypeFlagsEXT,
        pCallbackData: ^vk.DebugUtilsMessengerCallbackDataEXT,
        pUserData: rawptr \
) -> b32 {
        context = runtime.default_context()

        fmt.printf("%s: %s:\n", messageSeverity, messageTypes)
        return true
}

init :: proc() -> (ctx: Context) {
        using ctx;
        create_window(&ctx)


        // Vulkan does not come loaded into Odin by default, 
        // so we need to begin by loading Vulkan's functions at runtime.
        // This can be achieved using glfw's GetInstanceProcAddress function.
        // the non-overloaded function is used to leverage auto_cast and avoid
        // funky rawptr type stuff.
        vk.load_proc_addresses_global(auto_cast glfw.GetInstanceProcAddress);

        // In order to get debug information while creating the 
        // Vulkan instance, the DebugCreateInfo is passed as part of the
        // InstanceCreateInfo.
        debug_utils_info := debug_utils_messenger_create_info()

        // Create Instance
        result: vk.Result
        instance, result = init_vulkan_instance(&debug_utils_info)
        if (result != vk.Result.SUCCESS) {
                fmt.panicf("VULKAN: %s\n", result)
        }

        // Load the rest of Vulkan's functions.
        vk.load_proc_addresses(instance)

        init_debug_utils_messenger(&ctx, &debug_utils_info)

        init_physical_device_and_surface(&ctx)

        return ctx
}

cleanup :: proc(using ctx: ^Context) {
        vk.DestroyDebugUtilsMessengerEXT(instance, debug_messenger, nil)
        vk.DestroyInstance(nil, nil)
        cleanup_window(ctx)
}

init_vulkan_instance :: proc(debug_create_info: ^vk.DebugUtilsMessengerCreateInfoEXT) ->
(instance: vk.Instance, result: vk.Result) {
        application_info: vk.ApplicationInfo
        application_info.sType = vk.StructureType.APPLICATION_INFO
        application_info.pApplicationName = "Untitled"
        application_info.pEngineName = "Odinpi"
        application_info.apiVersion = vk.API_VERSION_1_3

        // Available Extensions
	count: u32
	vk.EnumerateInstanceExtensionProperties(nil, &count, nil) or_return
	extensions := make([]vk.ExtensionProperties, count)
        defer delete(extensions)
	vk.EnumerateInstanceExtensionProperties(nil, &count, raw_data(extensions)) or_return

        // Required Extensions
        required_extensions: [dynamic]cstring
        defer delete(required_extensions)
        glfw_required_extensions := glfw.GetRequiredInstanceExtensions()
        append(&required_extensions, ..glfw_required_extensions)
        append(&required_extensions, vk.EXT_DEBUG_UTILS_EXTENSION_NAME)

        for required_extension in required_extensions {
                found := false
                for extension in extensions {
                        e := extension
                        extension_name := cstring(raw_data(&e.extensionName))
                        if required_extension == extension_name {
                                found = true
                                break
                        }
                }
                fmt.assertf(found, "%s not found", required_extension)
        }

        // Enabled Layers
        layers := []cstring { "VK_LAYER_KHRONOS_validation" }

        fmt.print("Enabled Extensions: ")
        for extension in required_extensions do fmt.printf("%s ", extension); fmt.println()

        fmt.print("Enabled Layers: ")
        for layer in layers do fmt.printf("%s ", layer); fmt.println()

        instance_create_info: vk.InstanceCreateInfo 
        instance_create_info.sType = vk.StructureType.INSTANCE_CREATE_INFO
        instance_create_info.flags = nil
        instance_create_info.enabledExtensionCount = u32(len(required_extensions))
        instance_create_info.ppEnabledExtensionNames = raw_data(required_extensions)
        instance_create_info.enabledLayerCount = u32(len(layers))
        instance_create_info.ppEnabledLayerNames = raw_data(layers)
        instance_create_info.pApplicationInfo = &application_info
        instance_create_info.pNext = debug_create_info

        vk.CreateInstance(&instance_create_info, nil, &instance) or_return

        return instance, result
}

debug_utils_messenger_create_info :: proc() -> (debug_utils: vk.DebugUtilsMessengerCreateInfoEXT) {
        debug_utils.sType = vk.StructureType.DEBUG_UTILS_MESSENGER_CREATE_INFO_EXT
        debug_utils.messageSeverity = vk.DebugUtilsMessageSeverityFlagsEXT { .WARNING, .ERROR }
        debug_utils.messageType = vk.DebugUtilsMessageTypeFlagsEXT { .GENERAL, .PERFORMANCE, .VALIDATION }
        debug_utils.pfnUserCallback = debug_messenger_callback
        return debug_utils
}

init_debug_utils_messenger :: proc(using ctx: ^Context, debug_utils: ^vk.DebugUtilsMessengerCreateInfoEXT) {
        result := vk.CreateDebugUtilsMessengerEXT(instance, debug_utils, nil, &debug_messenger)
}

init_physical_device_and_surface :: proc(using ctx: ^Context) -> vk.Result {
        count: u32
        vk.EnumeratePhysicalDevices(instance, &count, nil) or_return
        devices := make([]vk.PhysicalDevice, count)
        vk.EnumeratePhysicalDevices(instance, &count, raw_data(devices)) or_return

        return vk.Result.SUCCESS
}