///|
/// platform predicate for native host adapters.
extern "c" fn c_is_windows() -> Int = "wasmoon_host_is_windows"

///|
pub fn is_windows() -> Bool {
  c_is_windows() != 0
}
