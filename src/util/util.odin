package util

import "core:hash"
import "core:bytes"

hash :: proc($type: typeid/u32, anything: $T) -> u32 {
    anything := anything
    data := transmute([]byte)(&anything)
    data := data[:size_of(anything)]
    return type(hash.fnv32a(data))
} 