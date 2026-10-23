///|
fn wasm(operation : @wasm_milkir.WasmOpcode) -> @milkir.Opcode {
  Ext(@wasm_milkir.encode(operation), Signature([], []))
}

///|
test "collection preserves checked identity but ends borrowed addresses" {
  let allocation = @effects.analyze(wasm(StructNew(0)))
  inspect(allocation.allocation, content="true")
  inspect(allocation.preserves_checked_references(), content="true")
  inspect(allocation.preserves_struct_values(), content="false")
  inspect(allocation.preserves_physical_addresses(), content="false")
  let write = @effects.analyze(wasm(StructSet(0, 2)))
  debug_inspect(write.write, content="Some(StructField(0, 2))")
  inspect(write.preserves_physical_addresses(), content="true")
}

///|
test "bulk element writes and unknown writes have distinct alias contracts" {
  let fill = @effects.analyze(wasm(ArrayFill(0)))
  debug_inspect(fill.write, content="Some(ArrayElements)")
  inspect(fill.preserves_struct_values(), content="true")
  inspect(fill.preserves_physical_addresses(), content="false")
  let foreign = @effects.analyze(
    Ext(ExtOp("foreign", "read", []), Signature([], [])),
  )
  debug_inspect(foreign.write, content="Some(Unknown)")
  inspect(foreign.preserves_struct_values(), content="false")
  inspect(foreign.preserves_checked_references(), content="false")
  inspect(foreign.preserves_physical_addresses(), content="false")
}

///|
test "read purity never erases a nullable or arithmetic trap" {
  let query = @effects.analyze(wasm(StructGet(0, 1)))
  inspect(query.may_trap, content="true")
  debug_inspect(query.checked_reference, content="Some(0)")
  debug_inspect(query.write, content="None")
  inspect(query.preserves_physical_addresses(), content="true")
  inspect(
    @effects.analyze(Scalar(IntBinary(SignedDiv))).may_trap,
    content="true",
  )
  inspect(
    @effects.analyze(Scalar(Convert(FloatToSignedInt))).may_trap,
    content="true",
  )
}

///|
test "calls and suspension end every borrowed lifetime" {
  let operations : Array[@wasm_milkir.WasmOpcode] = [
    WasmCall(0),
    ReturnCallRef(0),
    ContSuspend(0),
  ]
  for operation in operations {
    let effects = @effects.analyze(wasm(operation))
    inspect(effects.may_reenter, content="true")
    inspect(effects.preserves_checked_references(), content="false")
    inspect(effects.preserves_physical_addresses(), content="false")
  }
}

///|
test "retained-metadata ref tests preserve physical epochs and cast traps" {
  for
    operation in [@wasm_milkir.WasmOpcode::RefTest(0, false), RefCast(0, false)] {
    let effects = @effects.analyze(wasm(operation))
    assert_true(effects.preserves_physical_addresses())
    assert_true(effects.preserves_checked_references())
    assert_eq(effects.may_trap, operation is RefCast(_, _))
    debug_inspect(effects.write, content="None")
  }
}
