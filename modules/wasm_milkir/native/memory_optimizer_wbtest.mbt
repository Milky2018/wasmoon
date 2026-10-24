///|
fn optimize_memory_test(
  function : @milkir.Function,
  context : @wasm_milkir.WasmValidationContext,
  level : @generic.OptLevel,
) -> Bool raise @milkir.VerifyError {
  let changed = @wasm_opt.optimize_with_level(function, context, level)
  if level is (O2 | O3) {
    prepare_gc_memory(function, context)
  }
  changed
}
