///|
/// A bounded direct body can read guest state and trap. Polls retain their
/// original positions; this summary alone never makes a call noncollecting.
#derive(Eq, Debug)
pub(all) struct WasmReadOnlyCallContract {
  polls : Int32
  layout : (Int32, Int32, Int32, Int32)?
}

///|
pub extend WasmReadOnlyCallContract with Eq::{equal, not_equal}

///|
pub extend WasmReadOnlyCallContract with Debug::{to_repr}

///|
/// Attach summaries derived from validated immutable direct bodies. Like the
/// function/type resolvers, these are trusted producer metadata at the adapter
/// seam. Snapshot the map so later producer mutations cannot change a proof.
pub fn WasmValidationContext::with_read_only_call_contracts(
  self : WasmValidationContext,
  contracts : Map[Int32, WasmReadOnlyCallContract],
) -> WasmValidationContext {
  { ..self, read_only_calls: contracts.copy(), }
}

///|
pub fn WasmValidationContext::read_only_call_contract(
  self : WasmValidationContext,
  index : Int32,
) -> WasmReadOnlyCallContract? {
  guard self.read_only_calls.get(index) is Some(contract) &&
    contract.polls >= 0 &&
    contract.polls <= 256 &&
    (contract.polls == 0 || contract.layout is Some(_)) else {
    return None
  }
  Some(contract)
}

///|
/// Check the template's own carrier signature, not just calls inside its body.
pub fn WasmValidationContext::admits_function_body(
  self : WasmValidationContext,
  index : Int32,
  function : @milkir.Function,
) -> Bool {
  guard (self.function_contract)(index) is Some(contract) &&
    function.params.length() == contract.params.length() + 1 &&
    function.params[0].1 == I64 &&
    function.results == contract.results else {
    return false
  }
  for i, type_ in contract.params {
    if function.params[i + 1].1 != type_ {
      return false
    }
  }
  true
}

///|
/// The leading pointer is an independently verified budget proof token, not
/// a guest argument. Validate every remaining carrier against the direct target.
pub fn WasmValidationContext::validate_guarded_call_signature(
  self : WasmValidationContext,
  view : @milkir.ExtensionInstView,
  index : Int32,
) -> String? {
  guard (self.function_contract)(index) is Some(contract) &&
    view.operand_types.length() == contract.params.length() + 1 &&
    view.operand_types[0] == Ptr &&
    view.result_types.length() == contract.results.length() else {
    return Some("invalid guarded direct call signature")
  }
  for i, type_ in contract.params {
    if view.operand_types[i + 1] != type_ {
      return Some("invalid guarded direct call argument")
    }
  }
  for i, type_ in contract.results {
    if view.result_types[i] != type_ {
      return Some("invalid guarded direct call result")
    }
  }
  None
}
