///|
test "cached native polls cross a scalar latch and restore the source CFG" {
  let b = @milkir.FunctionBuilder("cached_native_poll")
  b.add_param(I64) |> ignore
  let input = b.add_param(I32)
  let header = b.create_block()
  let body = b.create_block()
  let latch = b.create_block()
  let exit = b.create_block()
  b.jump(header, [])
  let poll = @wasm_milkir.encode(SafepointPoll(-224, 64, 0, 16))
  b.switch_to_block(header)
  b.emit_void_ext_inst(poll, [])
  b.branch(input, body, [], exit, [])
  b.switch_to_block(body)
  b.emit_void_ext_inst(@wasm_milkir.encode(WasmCall(1)), [])
  b.emit_void_ext_inst(poll, [])
  b.jump(latch, [])
  b.switch_to_block(latch)
  b.jump(header, [])
  b.switch_to_block(exit)
  b.return_([])
  let function = b.finalize()
  let original = function.print()
  for _ in 0..<2 {
    guard prepare_poll_cache(function) is Some(edit) else {
      fail("the two polls are separated only by a scalar latch")
    }
    assert_true(edit.operations.values().any(op => op is Step(_, true)))
    assert_true(edit.operations.values().any(op => op is Step(_, false)))
    function.verify()
    (edit.restore)()
    function.verify()
    assert_eq(function.print(), original)
  }
}
