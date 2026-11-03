///|
priv struct GuardedCall {
  region : PollRegion
  target : Int32
  polls : Int32
}

///|
fn guarded_call_opcode(call : GuardedCall) -> @milkir.ExtOp {
  let r = call.region
  ExtOp(
    @wasm_milkir.WASM_DIALECT,
    "native_guarded_read_only_call",
    [
      r.execution,
      r.controls,
      r.callback,
      r.budget,
      r.limit,
      r.key,
      call.target,
      call.polls,
    ],
    effects=Some({
      read: Some(Other),
      write: Some(Control),
      may_trap: true,
      observable: true,
      invalidates_addresses: false,
      pointer_region: None,
      pointer_bytes: 0,
    }),
  )
}

///|
fn decode_guarded_call(op : @milkir.ExtOp) -> GuardedCall? {
  guard op.dialect == @wasm_milkir.WASM_DIALECT &&
    op.opcode == "native_guarded_read_only_call" &&
    op.immediates
    is [execution, controls, callback, budget, limit, key, target, polls] &&
    limit > 0 &&
    limit <= 256 &&
    key >= 0 &&
    target >= 0 &&
    polls >= 0 &&
    polls <= limit else {
    return None
  }
  let call = {
    region: { execution, controls, callback, budget, limit, key, },
    target,
    polls,
  }
  if op == guarded_call_opcode(call) {
    Some(call)
  } else {
    None
  }
}

///|
fn validate_guarded_call(
  view : @milkir.ExtensionInstView,
  call : GuardedCall,
  context : @wasm_milkir.WasmValidationContext,
) -> String? {
  guard context.read_only_call_contract(call.target) is Some(contract) &&
    contract.polls == call.polls else {
    return Some("guarded call lacks its validated direct-body contract")
  }
  let r = call.region
  if contract.layout is Some(layout) &&
    layout != (r.execution, r.controls, r.callback, r.budget) {
    return Some("guarded call uses a different poll control layout")
  }
  context.validate_guarded_call_signature(view, call.target)
}
