///|
/// Whether to run the register allocator's own plan verifier during JIT
/// compilation.
///
/// The verifier is a debugging gate, not a correctness requirement of the
/// emitted code: it re-checks the allocator's plan against the function it
/// allocated. Measured on `examples/algorithms`, it is 15 to 20 percent of
/// register allocation, which is itself about 90 percent of module compile
/// time (ISS-371) — so it is off unless asked for.
///
/// `docs/optimization-vs-cranelift.md` records this gate as
/// `VCODE_REGALLOC_VALIDATION` (entry `wasmoon-il8.10`). The gate was lost
/// when the allocator moved into `modules/`, leaving the verifier
/// unconditional and the variable dead; this restores it. CI's `moon test`
/// step sets the variable, so the test matrix keeps full verification.
let regalloc_validation_enabled : Ref[Bool?] = { val: None, }

///|
fn regalloc_validation() -> Bool {
  match regalloc_validation_enabled.val {
    Some(value) => value
    None => {
      let value = match @env.get_env_var("VCODE_REGALLOC_VALIDATION") {
        Some("1") | Some("true") | Some("TRUE") | Some("yes") | Some("on") =>
          true
        _ => false
      }
      regalloc_validation_enabled.val = Some(value)
      value
    }
  }
}
