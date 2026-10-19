///|
pub using @callable {type NativeCallableRegistry}

///|
pub using @jit_ffi {type NativeAllocationError}

///|
pub fn supported() -> Bool {
  @execution.supported()
}
