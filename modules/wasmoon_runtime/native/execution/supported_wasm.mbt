///|
pub fn supported() -> Bool {
  false
}

///|
// Imports also serve the target-selected native state implementation.
let _native_state_imports : Unit = {
  ignore(@jit_ffi.NativeAllocationError::to_string)
  ignore(@types.ONE_MIB_BYTES)
}
