///|
#cfg(platform="windows")
pub fn is_windows() -> Bool {
  true
}

///|
#cfg(not(platform="windows"))
pub fn is_windows() -> Bool {
  false
}

///|
/// Host architecture tag used by native JIT artifacts.
pub extern "c" fn target_arch() -> Int32 = "wasmoon_jit_host_target_arch"

///|
pub extern "c" fn operating_system_abi_tag() -> Int32 = "wasmoon_jit_host_operating_system_abi"

///|
pub extern "c" fn has_aarch64_lse() -> Bool = "wasmoon_jit_host_has_aarch64_lse"
