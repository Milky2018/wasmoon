///|
fn guarded_call_test_context() -> @wasm_milkir.WasmValidationContext {
  let context = @wasm_milkir.WasmValidationContext::new({
    function_contract: fn(_) { Some({ params: [Ref], results: [I64], }) },
    defined_type_contract: fn(_) {
      Some(
        Struct([
          { storage: Value(I64), mutable_: true, defaultable: true, },
          { storage: Value(I64), mutable_: true, defaultable: true, },
        ]),
      )
    },
    table_contract: fn(_) { None },
    tag_contract: fn(_) { None },
    memory_exists: fn(_) { false },
    data_segment_exists: fn(_) { false },
    element_segment_type: fn(_) { None },
  })
  context.with_read_only_call_contracts(
    Map([(0, { polls: 2, layout: Some((-224, 64, 0, 16)), })]),
  )
}

///|
fn guarded_call_fixture() -> @milkir.Function raise @milkir.VerifyError {
  let b = @milkir.FunctionBuilder("cross_call_reads")
  b.add_param(I64) |> ignore
  let object = b.add_param(Ref)
  b.add_result(I64)
  b.emit_void_ext_inst(@wasm_milkir.encode(SafepointPoll(-224, 64, 0, 16)), [])
  let before = @wasm_milkir.struct_get(b, 0, 0, object, I64)
  let middle = @wasm_milkir.call_multi(b, 0, [I64], [object])[0]
  let after = @wasm_milkir.struct_get(b, 0, 1, object, I64)
  b.return_([b.iadd(b.iadd(before, middle), after)])
  b.finalize()
}

///|
test "guarded direct calls preserve fallback and validate cross-call address lifetime" {
  let context = guarded_call_test_context()
  let function = guarded_call_fixture()
  prepare_gc_memory(function, context, exclusive_poll_controls=true)
  assert_eq(poll_region_error(function), None)
  assert_eq(gc_borrow_error(function), None)
  let mut direct = 0
  let mut guarded = 0
  for block in function.blocks {
    for id in function.block_instruction_ids(block) {
      let inst = function.instruction_by_id(id).unwrap()
      if @wasm_milkir.decode_opcode(inst.opcode) is Some(WasmCall(_)) {
        direct += 1
      }
      if inst.opcode is Ext(op, _) && decode_guarded_call(op) is Some(call) {
        assert_eq((call.region.limit, call.polls), (3, 2))
        guarded += 1
      }
    }
  }
  assert_eq((direct, guarded), (1, 1))
}

///|
test "guarded direct calls reject forged contracts tokens credit and stale addresses" {
  for mode in ["cost", "target", "layout", "token", "credit"] {
    let function = guarded_call_fixture()
    let context = guarded_call_test_context()
    assert_true(version_poll_acyclic(function, context~))
    for block in function.blocks {
      for id in function.block_instruction_ids(block) {
        let inst = function.instruction_by_id(id).unwrap()
        if inst.opcode is Ext(op, signature) &&
          decode_guarded_call(op) is Some(call) {
          match mode {
            "cost" =>
              inst.set_opcode(
                Ext(guarded_call_opcode({ ..call, polls: 1, }), signature),
              )
            "target" =>
              inst.set_opcode(
                Ext(guarded_call_opcode({ ..call, target: 1, }), signature),
              )
            "layout" =>
              inst.set_opcode(
                Ext(
                  guarded_call_opcode({
                    ..call,
                    region: { ..call.region, budget: 20, },
                  }),
                  signature,
                ),
              )
            "token" => inst.args[0] = inst.args[1]
            "credit" => {
              let duplicate = function.new_inst(
                inst.opcode,
                inst.args.copy(),
                inst.results.map(v => function.new_value(v.ty)),
              )
              block.append_inst(duplicate)
            }
            _ => ()
          }
        }
      }
    }
    let rejected = try {
      prepare_gc_memory(function, context, exclusive_poll_controls=true)
      false
    } catch {
      _ => true
    }
    assert_true(rejected, msg=mode)
  }
}

///|
test "replacing a proven direct call revokes cross-call physical borrows" {
  let function = guarded_call_fixture()
  prepare_gc_memory(
    function,
    guarded_call_test_context(),
    exclusive_poll_controls=true,
  )
  for block in function.blocks {
    for id in function.block_instruction_ids(block) {
      let inst = function.instruction_by_id(id).unwrap()
      if inst.opcode is Ext(op, _) && decode_guarded_call(op) is Some(call) {
        let args = inst.args.copy()
        inst.args.clear()
        for i in 1..<args.length() {
          inst.args.push(args[i])
        }
        inst.set_opcode(
          Ext(
            @wasm_milkir.encode(WasmCall(call.target)),
            Signature(inst.args.map(v => v.ty), inst.results.map(v => v.ty)),
          ),
        )
      }
    }
  }
  assert_true(gc_borrow_error(function) is Some(_))
}

///|
test "loop direct-call credit is refreshed at each backedge" {
  let b = @milkir.FunctionBuilder("loop_cross_call_reads")
  b.add_param(I64) |> ignore
  let object = b.add_param(Ref)
  let count = b.add_param(I32)
  let header = b.create_block()
  let index = b.add_block_param(header, I32)
  let body = b.create_block()
  let exit = b.create_block()
  b.jump(header, [b.iconst_i32(0)])
  b.switch_to_block(header)
  b.emit_void_ext_inst(@wasm_milkir.encode(SafepointPoll(-224, 64, 0, 16)), [])
  b.branch(b.icmp_ult(index, count), body, [], exit, [])
  b.switch_to_block(body)
  @wasm_milkir.struct_get(b, 0, 0, object, I64) |> ignore
  @wasm_milkir.call_multi(b, 0, [I64], [object]) |> ignore
  @wasm_milkir.struct_get(b, 0, 1, object, I64) |> ignore
  b.jump(header, [b.iadd(index, b.iconst_i32(1))])
  b.switch_to_block(exit)
  b.return_([])
  let function = b.finalize()
  prepare_gc_memory(
    function,
    guarded_call_test_context(),
    exclusive_poll_controls=true,
  )
  assert_true(function.print().contains("native_guarded_read_only_call"))
  assert_eq(poll_region_error(function), None)
  assert_eq(gc_borrow_error(function), None)
}
