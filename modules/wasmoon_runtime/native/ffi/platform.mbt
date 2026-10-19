///|
/// Query the native host platform for descriptor adapters.
extern "c" fn c_is_windows() -> Int32 = "wasmoon_host_is_windows"

///|
pub fn is_windows() -> Bool {
  c_is_windows() != 0
}
