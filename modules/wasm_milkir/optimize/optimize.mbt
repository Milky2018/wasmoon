///|
/// Verify semantic Wasm before inlining and private-field promotion. Native
/// checked memory lowering and its general GVN/LICM run at the native seam;
/// there are no independent GC read/loop caches here.
pub fn optimize_with_level(
  function : @milkir.Function,
  context : @wasm_milkir.WasmValidationContext,
  level : @generic.OptLevel,
  scalar_callees~ : Map[Int32, @milkir.Function] = Map([]),
) -> Bool raise @milkir.VerifyError {
  @wasm_milkir.verify_function_with_context(function, context)
  let inline_changed = if level is (O2 | O3) {
    inline_leaf_calls(function, scalar_callees, context)
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
    @wasm_milkir.verify_function_with_context(function, context)
    @generic.optimize_with_level(function, level) |> ignore
  }
  inline_changed || generic_result.changed || local_changed
}
