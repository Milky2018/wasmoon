///|
fn loop_materialization_fixture(
  call_in_loop~ : Bool = false,
) -> (
  @milkir.Function,
  @milkir.Block,
  @milkir.Block,
  @milkir.Value,
  @milkir.Value,
) raise {
  let b = @milkir.FunctionBuilder("loop_materializations")
  let pointer = b.add_param(Ptr)
  let count = b.add_param(I32)
  b.add_result(I32)
  let preheader = b.create_block()
  let header = b.create_block()
  let index = b.add_block_param(header, I32)
  let body = b.create_block()
  let exit = b.create_block()
  let answer = b.add_block_param(exit, I32)
  let constant = b.iconst_i64(7378697629483820647L)
  let extended = b.emit_inst(I64, Scalar(Convert(SignedExtend)), [count])
  let callee = b.get_function().declare_external_symbol("opaque_boundary")
  b.call_symbol(callee, None, []) |> ignore
  b.jump(preheader, [])
  b.switch_to_block(preheader)
  b.jump(header, [b.iconst_i32(0)])
  b.switch_to_block(header)
  b.branch(b.icmp_slt(index, count), body, [], exit, [index])
  b.switch_to_block(body)
  if call_in_loop {
    b.call_symbol(callee, None, []) |> ignore
  }
  let offset = b.iconst_i64(0L)
  let loaded = b.load_ptr(I64, pointer, offset)
  let added = b.emit_inst(I64, Scalar(IntBinary(Add)), [loaded, constant])
  let shifted = b.emit_inst(I64, Scalar(IntBinary(UnsignedShiftRight)), [
    added, extended,
  ])
  b.store_ptr(I64, pointer, shifted, offset)
  b.jump(header, [b.iadd(index, b.iconst_i32(1))])
  b.switch_to_block(exit)
  b.return_([answer])
  (b.finalize(), preheader, body, constant, extended)
}

///|
test "loop materializations have fresh definitions after the call boundary" {
  let (function, preheader, body, constant, extended) = loop_materialization_fixture()
  let sources = [constant, extended]
  assert_true(localize_loop_materializations(function).changed)
  function.verify()
  for source in sources {
    let definition = function.defining_inst(source).unwrap()
    let fresh = function
      .block_instruction_ids(preheader)
      .filter(id => {
        function.instruction_by_id(id).unwrap().opcode == definition.opcode
      })
    assert_eq(fresh.length(), 1)
    let replacement = function.instruction_by_id(fresh[0]).unwrap().results[0]
    assert_true(replacement != source)
    assert_false(
      function
      .block_instruction_ids(body)
      .any(id => function.instruction_by_id(id).unwrap().args.contains(source)),
    )
  }
  assert_false(localize_loop_materializations(function).changed)
}

///|
test "loop materializations leave call-containing loops unchanged" {
  let (function, _, _, _, _) = loop_materialization_fixture(call_in_loop=true)
  let before = function.print()
  assert_false(localize_loop_materializations(function).changed)
  assert_eq(function.print(), before)
}
