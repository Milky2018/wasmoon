///|
test "emitter rejects invalid MachV before layout and encoding" {
  let func = @machv.Function::Function("invalid_emit_input")
  func.new_block() |> ignore
  try @machv_emit.emit_function(func) catch {
    err => inspect(err, content="MissingTerminator(block_id=0)")
  } noraise {
    _ => fail("expected emitter input verification to fail")
  }
}
