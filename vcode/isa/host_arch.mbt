///|
/// Host architecture detection for the ISA layer.
///
/// MoonBit currently lacks stable conditional compilation for native targets.
/// We therefore delegate host-arch detection to a tiny C helper compiled as a
/// native stub, so x86_64 CI can select the correct JIT backend.

///|
pub extern "c" fn c_host_arch() -> Int = "wasmoon_host_arch"
