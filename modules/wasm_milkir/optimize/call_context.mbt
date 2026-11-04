///|
/// Bind immutable, validated direct-body effects once before compiling callers.
/// Unknown, recursive, imported or effectful targets keep conservative calls.
pub fn with_read_only_calls(
  context : @wasm_milkir.WasmValidationContext,
  callees : Map[Int32, @milkir.Function],
) -> @wasm_milkir.WasmValidationContext {
  context.with_read_only_call_contracts(
    @effects.read_only_call_contracts(callees, context),
  )
}
