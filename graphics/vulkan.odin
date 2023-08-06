package graphics

import "core:fmt"
import "core:runtime"
import "core:strings"
import sa "core:container/small_array"

import "vendor:glfw"
import vk "vendor:vulkan"

init :: proc(ctx: ^Context) {
        create_window(ctx)

        // Vulkan does not come loaded into Odin by default, 
        // so we need to begin by loading Vulkan's functions at runtime.
        // This can be achieved using glfw's GetInstanceProcAddress function.
        // the non-overloaded function is used to leverage auto_cast and avoid
        // funky rawptr type stuff.
        vk.load_proc_addresses_global(auto_cast glfw.GetInstanceProcAddress);

        result: vk.Result
        ctx.instance, result = init_vulkan_instance()

}

init_vulkan_instance :: proc() -> (instance: vk.Instance, result: vk.Result) {

        application_info: vk.ApplicationInfo
        application_info.pApplicationName = "Untitled"
        application_info.pEngineName = "Odinpi"
        application_info.apiVersion = vk.API_VERSION_1_3

        instance_create_info: vk.InstanceCreateInfo 
        instance_create_info.flags = nil
        instance_create_info.pApplicationInfo = &application_info

	count: u32
	vk.EnumerateInstanceExtensionProperties(nil, &count, nil) or_return
	extensions := make([]vk.ExtensionProperties, count)
        defer delete(extensions)
	vk.EnumerateInstanceExtensionProperties(nil, &count, raw_data(extensions)) or_return

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
                                fmt.println("found extension", extension_name)
                                found = true
                                break
                        }
                }
                fmt.assertf(found, "%s not found", required_extension)
        }

        vk.CreateInstance(&instance_create_info, nil, &instance) or_return

        return instance, result
}