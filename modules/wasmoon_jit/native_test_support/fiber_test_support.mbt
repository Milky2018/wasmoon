///|
extern "c" fn c_hostcall_probe_trampoline() -> Int64 = "wasmoon_test_hostcall_probe_trampoline"

///|
extern "c" fn c_fiber_stack_hostcall_probe_trampoline() -> Int64 = "wasmoon_test_fiber_stack_hostcall_probe_trampoline"

///|
extern "c" fn c_nested_hostcall_tls_probe_trampoline() -> Int64 = "wasmoon_test_nested_hostcall_tls_probe_trampoline"

///|
extern "c" fn c_nested_trap_probe() -> Int64 = "wasmoon_test_nested_trap_probe"

///|
extern "c" fn c_parked_gc_root_probe() -> Int64 = "wasmoon_test_parked_gc_root_probe"

///|
extern "c" fn c_fiber_guard_rejects_access() -> Int = "wasmoon_test_fiber_guard_rejects_access"

///|
extern "c" fn c_fiber_preserves_registers() -> Int = "wasmoon_test_fiber_preserves_registers"

///|
pub fn hostcall_probe_trampoline() -> Int64 {
  c_hostcall_probe_trampoline()
}

///|
pub fn fiber_stack_hostcall_probe_trampoline() -> Int64 {
  c_fiber_stack_hostcall_probe_trampoline()
}

///|
pub fn nested_hostcall_tls_probe_trampoline() -> Int64 {
  c_nested_hostcall_tls_probe_trampoline()
}

///|
pub fn nested_trap_probe() -> Int64 {
  c_nested_trap_probe()
}

///|
pub fn parked_gc_root_probe() -> Int64 {
  c_parked_gc_root_probe()
}

///|
pub fn fiber_guard_rejects_access() -> Bool {
  c_fiber_guard_rejects_access() == 1
}

///|
pub fn fiber_preserves_registers() -> Bool {
  c_fiber_preserves_registers() == 1
}
