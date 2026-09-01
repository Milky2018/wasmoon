///|
/// Whether to run internal compiler verifiers during JIT compilation.
///
/// Wasm validation remains unconditional. This gate covers redundant checks of
/// compiler-owned MilkIR, selected VCode, and the allocator's completed plan.
/// Wasmtime likewise disables Cranelift's internal verifier in its production
/// compiler builder while retaining it for development configurations. CI sets
/// this flag so every internally trusted boundary remains checked there.
///
/// The existing `VCODE_REGALLOC_VALIDATION` name is retained for compatibility
/// with CI and local compiler-validation runs.
let compiler_validation_enabled : Ref[Bool?] = { val: None, }

///|
fn compiler_validation() -> Bool {
  match compiler_validation_enabled.val {
    Some(value) => value
    None => {
      let value = match @env.get_env_var("VCODE_REGALLOC_VALIDATION") {
        Some("1") | Some("true") | Some("TRUE") | Some("yes") | Some("on") =>
          true
        _ => false
      }
      compiler_validation_enabled.val = Some(value)
      value
    }
  }
}
