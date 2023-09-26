package common

import "core:fmt"

import vk "vendor:vulkan"
import bt "pkgs:obacktracing"

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
