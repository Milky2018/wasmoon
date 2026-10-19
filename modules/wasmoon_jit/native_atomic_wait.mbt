///|
pub using @runtime_bridge {type NativeAtomicWait, atomic_wait_begin}

///|
extern "c" fn c_jit_get_atomic_wait32_ptr() -> Int64 = "wasmoon_jit_get_atomic_wait32_ptr"

///|
extern "c" fn c_jit_get_atomic_wait64_ptr() -> Int64 = "wasmoon_jit_get_atomic_wait64_ptr"

///|
extern "c" fn c_jit_get_atomic_notify_ptr() -> Int64 = "wasmoon_jit_get_atomic_notify_ptr"

///|
pub using @runtime_bridge {atomic_notify, cooperative_idle}
