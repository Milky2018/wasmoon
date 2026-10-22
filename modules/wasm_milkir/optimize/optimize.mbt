///|
/// Validate Wasm contracts before eliminating any extension, then optimize.
/// At O2/O3, promote private integer fields and forward checked GC reads.
/// Optional scalar callees must be bodies from this exact module, keyed by
/// linked function index, with the frontend's hidden environment parameter.
/// Only short integer bodies without calls, polls or memory effects inline.
/// GC read forwarding never crosses loop headers, merges or unknown effects.
pub fn optimize_with_level(
  function : @milkir.Function,
  context : @wasm_milkir.WasmValidationContext,
  level : @generic.OptLevel,
  scalar_callees~ : Map[Int32, @milkir.Function] = Map([]),
) -> Bool raise @milkir.VerifyError {
  @wasm_milkir.verify_function_with_context(function, context)
  let inline_changed = if level is (O2 | O3) {
    inline_scalar_calls(function, scalar_callees)
  } else {
    false
  }
  let gc_changed = if level is (O2 | O3) {
    forward_gc_reads(function) > 0
  } else {
    false
  }
  let generic_result = @generic.optimize_with_level(function, level)
  let local_changed = if level is (O2 | O3) {
    promote_local_structs(function)
  } else {
    false
  }
  if local_changed {
    // Private writes used to invalidate potentially aliasing field facts.
    // Once those writes become SSA, revisit the surviving real heap reads.
    forward_gc_reads(function) |> ignore
    @wasm_milkir.verify_function_with_context(function, context)
    @generic.optimize_with_level(function, level) |> ignore
  }
  inline_changed || gc_changed || generic_result.changed || local_changed
}
