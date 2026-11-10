/// WASI state and symbol access for managed native JIT contexts.

///|
fn take_wasi_exit_code(context : JITContext) -> Int32 {
  let raw_code = c_jit_get_wasi_exit_code_managed(context)
  c_jit_clear_wasi_exit_managed(context)
  // Exit codes are unsigned P1 bits transported in Int; negative values are
  // valid payloads and must not be mistaken for a missing exit status.
  raw_code
}

///|
pub fn NativeJITContext::take_wasi_exit_code(self : NativeJITContext) -> Int32 {
  take_wasi_exit_code(self.handle)
}
