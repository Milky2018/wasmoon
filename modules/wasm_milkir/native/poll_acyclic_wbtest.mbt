///|
fn acyclic_poll_fixture(
  reentry~ : Bool = false,
) -> @milkir.Function raise @milkir.VerifyError {
  let b = @milkir.FunctionBuilder("acyclic_poll_reads")
  b.add_param(I64) |> ignore
  let object = b.add_param(Ref)
  let selected = b.add_param(I32)
  b.add_result(I64)
  b.emit_void_ext_inst(@wasm_milkir.encode(SafepointPoll(-224, 64, 0, 16)), [])
  let before = @wasm_milkir.struct_get(b, 0, 0, object, I64)
  if reentry {
    let symbol = b
      .get_function()
      .declare_external_symbol("unknown_control_mutation")
    b.call_symbol(symbol, None, []) |> ignore
  }
  let yes = b.create_block()
  let no = b.create_block()
  b.branch(selected, yes, [], no, [])
  b.switch_to_block(yes)
  b.emit_void_ext_inst(@wasm_milkir.encode(SafepointPoll(-224, 64, 0, 16)), [])
  let after = @wasm_milkir.struct_get(b, 0, 1, object, I64)
  b.return_([b.iadd(before, after)])
  b.switch_to_block(no)
  b.emit_void_ext_inst(@wasm_milkir.encode(SafepointPoll(-224, 64, 0, 16)), [])
  b.return_([@wasm_milkir.struct_get(b, 0, 0, object, I64)])
  b.finalize()
}

///|
test "acyclic poll regions preserve every source charge and complete fallback" {
  let function = acyclic_poll_fixture()
  assert_true(version_poll_acyclic(function))
  assert_eq(poll_region_error(function), None)
  let mut guards = 0
  let mut charges = 0
  let mut polls = 0
  for block in function.blocks {
    for id in function.block_instruction_ids(block) {
      let inst = function.instruction_by_id(id).unwrap()
      if inst.opcode is Ext(op, _) &&
        decode_poll_region(op) is Some((region, guard_)) {
        assert_eq(region.limit, 3)
        if guard_ {
          guards += 1
        } else {
          charges += 1
        }
      }
      if @wasm_milkir.decode_opcode(inst.opcode)
        is Some(SafepointPoll(_, _, _, _)) {
        polls += 1
      }
    }
  }
  assert_eq((guards, charges, polls), (1, 3, 3))
  let context = allocation_contract_context()
  function.verify_with_dialect_validator(
    @wasm_milkir.WASM_DIALECT,
    fn(view) { validate_memory_extension(view, context, function.results) },
    fn(value) { context.validate_global_value(value) },
  )
  let guard_block = function.blocks[0]
  let id = function.block_instruction_ids(guard_block)[0]
  let inst = function.instruction_by_id(id).unwrap()
  guard inst.opcode is Ext(op, signature) else { abort("missing poll guard") }
  let (region, _) = decode_poll_region(op).unwrap()
  inst.set_opcode(
    Ext(poll_region_opcode({ ..region, limit: 1, }, true), signature),
  )
  assert_true(poll_region_error(function) is Some(_))
}

///|
test "acyclic poll regions reject intervening reentry and cyclic control flow" {
  for function in [acyclic_poll_fixture(reentry=true), polled_digit_fixture()] {
    let before = function.print()
    assert_false(version_poll_acyclic(function))
    assert_eq(function.print(), before)
  }
}

///|
test "acyclic poll regions retain independent borrow and credit verification after expansion" {
  let function = acyclic_poll_fixture()
  prepare_gc_memory(
    function,
    allocation_contract_context(),
    exclusive_poll_controls=true,
  )
  assert_eq(poll_region_error(function), None)
  assert_eq(gc_borrow_error(function), None)
}

///|
test "inline object views stay inside successful guarded regions" {
  let function = acyclic_poll_fixture()
  prepare_gc_memory(
    function,
    allocation_contract_context(),
    exclusive_poll_controls=true,
  )
  let sites = inline_projection_sites(function)
  assert_true(sites.length() > 0)
  guard function.blocks[0].terminator is Some(Branch(_, fast, _, slow, _)) else {
    fail("missing guarded entry")
  }
  let cfg = @milkir.CFG::build(function)
  let dominance = cfg.compute_dominance()
  let mut slow_views = 0
  for block in function.blocks {
    for id in function.block_instruction_ids(block) {
      if sites.contains(id) {
        assert_true(dominance.dominates(fast, block.id))
      }
      if function.instruction_by_id(id).unwrap().opcode is Ext(op, _) &&
        decode_projection(op) is Some(StructData(_)) &&
        dominance.dominates(slow, block.id) {
        slow_views += 1
        assert_false(sites.contains(id))
      }
    }
  }
  assert_true(slow_views > 0)
  assert_eq(gc_borrow_error(function), None)
}

///|
test "acyclic array reads share the exact poll-budget proof" {
  let b = @milkir.FunctionBuilder("acyclic_array_reads")
  b.add_param(I64) |> ignore
  let array = b.add_param(Ref)
  let index = b.add_param(I32)
  b.add_result(I64)
  b.emit_void_ext_inst(@wasm_milkir.encode(SafepointPoll(-224, 64, 0, 16)), [])
  let before = @wasm_milkir.array_get(b, 0, array, index, I64)
  b.emit_void_ext_inst(@wasm_milkir.encode(SafepointPoll(-224, 64, 0, 16)), [])
  let after = @wasm_milkir.array_get(b, 0, array, index, I64)
  b.return_([b.iadd(before, after)])
  let function = b.finalize()
  assert_true(version_poll_acyclic(function))
  assert_eq(poll_region_error(function), None)
  let mut charges = 0
  let mut fallback_polls = 0
  for block in function.blocks {
    for id in function.block_instruction_ids(block) {
      let inst = function.instruction_by_id(id).unwrap()
      if inst.opcode is Ext(op, _) &&
        decode_poll_region(op) is Some((region, false)) {
        assert_eq(region.limit, 2)
        charges += 1
      }
      if @wasm_milkir.decode_opcode(inst.opcode)
        is Some(SafepointPoll(_, _, _, _)) {
        fallback_polls += 1
      }
    }
  }
  assert_eq((charges, fallback_polls), (2, 2))
}
