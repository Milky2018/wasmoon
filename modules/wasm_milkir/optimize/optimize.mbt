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
    let guarded_changed = inline_guarded_reference_calls(
      function, scalar_callees, context,
    )
    let scalar_changed = inline_leaf_calls(function, scalar_callees, context)
    let checked_changed = inline_checked_leaf_calls(
      function, scalar_callees, context,
    )
    if checked_changed || guarded_changed {
      @wasm_milkir.verify_function_with_context(function, context)
    }
    guarded_changed || scalar_changed || checked_changed
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
    // Resolve the new field SSA before recognizing constructor-carried loops.
    @generic.optimize_with_level(function, O1) |> ignore
  }
  let reference_changed = if level is (O2 | O3) {
    specialize_reference_loops(function, context)
  } else {
    false
  }
  let constructor_changed = if level is (O2 | O3) {
    forward_constructor_fields(function, context)
  } else {
    false
  }
  let exposed_local_changed = if reference_changed || constructor_changed {
    promote_local_structs(function)
  } else {
    false
  }
  let loop_changed = if level is (O2 | O3) {
    forward_loop_fields(function)
  } else {
    false
  }
  if reference_changed ||
    constructor_changed ||
    local_changed ||
    exposed_local_changed ||
    loop_changed {
    @wasm_milkir.verify_function_with_context(function, context)
    @generic.optimize_with_level(function, level) |> ignore
  }
  inline_changed ||
  generic_result.changed ||
  reference_changed ||
  constructor_changed ||
  local_changed ||
  exposed_local_changed ||
  loop_changed
}
