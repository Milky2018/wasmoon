///|
test "checked reference loop versions preserve first allocation and opaque backedges" {
  for (reentry, alias_write) in [(false, false), (true, false), (false, true)] {
    let callee = @milkir.FunctionBuilder("increment")
    callee.add_param(I64) |> ignore
    let input = callee.add_param(I32)
    callee.add_result(I32)
    callee.return_([callee.iadd(input, callee.iconst_i32(1))])
    let b = @milkir.FunctionBuilder("reference_loop")
    b.add_param(I64) |> ignore
    let closure = b.add_param(Ref)
    let other = b.add_param(Ref)
    let count = b.add_param(I32)
    b.add_result(I32)
    let header = b.create_block()
    let i = b.add_block_param(header, I32)
    let body = b.create_block()
    let exit = b.create_block()
    let result = b.add_block_param(exit, I32)
    b.jump(header, [b.iconst_i32(0)])
    b.switch_to_block(header)
    b.branch(b.icmp_slt(i, count), body, [], exit, [i])
    b.switch_to_block(body)
    @wasm_milkir.struct_new_default(b, 8) |> ignore
    let reference = @wasm_milkir.struct_get(b, 9, 0, closure, CallableRef)
    if alias_write {
      @wasm_milkir.struct_set(b, 9, 0, other, reference)
    }
    let next = b.emit_inst(
      I32,
      Ext(@wasm_milkir.encode(CallRef(7)), Signature([CallableRef, I32], [I32])),
      [reference, i],
    )
    if reentry {
      let symbol = b.get_function().declare_external_symbol("reenter")
      b.call_symbol(symbol, None, []) |> ignore
    }
    b.jump(header, [next])
    b.switch_to_block(exit)
    b.return_([result])
    let context = @wasm_milkir.WasmValidationContext::new(
      {
        function_contract: fn(index) {
          if index == 0 {
            Some({ params: [I32], results: [I32], })
          } else {
            None
          }
        },
        defined_type_contract: fn(index) {
          match index {
            7 => Some(Function({ params: [I32], results: [I32], }))
            8 => Some(Struct([]))
            9 =>
              Some(
                Struct([
                  {
                    storage: Value(CallableRef),
                    mutable_: true,
                    defaultable: true,
                  },
                ]),
              )
            _ => None
          }
        },
        table_contract: fn(_) { None },
        tag_contract: fn(_) { None },
        memory_exists: fn(_) { false },
        data_segment_exists: fn(_) { false },
        element_segment_type: fn(_) { None },
      },
      function_types=Map([(0, 7)]),
    )
    let function = b.get_function()
    optimize_with_level(
      function,
      context,
      O2,
      scalar_callees=Map([(0, callee.get_function())]),
    )
    |> ignore
    @wasm_milkir.verify_function_with_context(function, context)
    let mut pure_loops = 0
    for loop_ in @milkir.CFG::build(function).find_loops() {
      let mut unknown = false
      for block in function.blocks {
        if !loop_.contains(block.id) {
          continue
        }
        for id in function.block_instruction_ids(block) {
          let opcode = function.instruction_by_id(id).unwrap().opcode
          if @wasm_milkir.decode_opcode(opcode) is Some(ExecutableFuncRefEq) ||
            !@effects.analyze(opcode).preserves_checked_references() {
            unknown = true
          }
        }
      }
      if !unknown {
        pure_loops += 1
      }
    }
    assert_eq(pure_loops, if reentry || alias_write { 0 } else { 1 })
    let mut allocations = 0
    for block in function.blocks {
      for id in function.block_instruction_ids(block) {
        if @wasm_milkir.decode_opcode(
            function.instruction_by_id(id).unwrap().opcode,
          )
          is Some(StructNewDefault(8)) {
          allocations += 1
        }
      }
    }
    assert_eq(allocations, if reentry || alias_write { 1 } else { 2 })
  }
}

///|
test "constructor fields never cross an opaque backedge even with a checked prefix" {
  let context = @wasm_milkir.WasmValidationContext::new({
    function_contract: fn(_) { None },
    defined_type_contract: fn(_) {
      Some(
        Struct([
          { storage: Value(I32), mutable_: false, defaultable: true, },
          { storage: Value(I32), mutable_: false, defaultable: true, },
        ]),
      )
    },
    table_contract: fn(_) { None },
    tag_contract: fn(_) { None },
    memory_exists: fn(_) { false },
    data_segment_exists: fn(_) { false },
    element_segment_type: fn(_) { None },
  })
  for reentry in [false, true] {
    let b = @milkir.FunctionBuilder("constructor_backedge")
    let initial = b.add_param(Ref)
    b.add_result(Ref)
    let header = b.create_block()
    let object = b.add_block_param(header, Ref)
    let body = b.create_block()
    let exit = b.create_block()
    let returned = b.add_block_param(exit, Ref)
    b.jump(header, [initial])
    b.switch_to_block(header)
    let bound = @wasm_milkir.struct_get(b, 0, 1, object, I32)
    let index = @wasm_milkir.struct_get(b, 0, 0, object, I32)
    b.branch(b.icmp_slt(index, bound), body, [], exit, [object])
    b.switch_to_block(body)
    let next = @wasm_milkir.struct_new(b, 0, [
      b.iadd(index, b.iconst_i32(1)),
      bound,
    ])
    if reentry {
      let symbol = b.get_function().declare_external_symbol("replace_heap")
      b.call_symbol(symbol, None, []) |> ignore
    }
    b.jump(header, [next])
    b.switch_to_block(exit)
    b.return_([returned])
    let function = b.get_function()
    let before = function.print()
    assert_eq(forward_constructor_fields(function, context), !reentry)
    @wasm_milkir.verify_function_with_context(function, context)
    if reentry {
      assert_eq(function.print(), before)
    }
  }
}

///|
test "checked header prefix admits conditional immutable reference fields" {
  for mutable_ in [false, true] {
    let context = @wasm_milkir.WasmValidationContext::new({
      function_contract: fn(_) { None },
      defined_type_contract: fn(_) {
        Some(
          Struct([
            { storage: Value(Ref), mutable_, defaultable: true, },
            { storage: Value(I32), mutable_: false, defaultable: true, },
          ]),
        )
      },
      table_contract: fn(_) { None },
      tag_contract: fn(_) { None },
      memory_exists: fn(_) { false },
      data_segment_exists: fn(_) { false },
      element_segment_type: fn(_) { None },
    })
    let b = @milkir.FunctionBuilder("constructor_reference_prefix")
    let initial = b.add_param(Ref)
    let replacement = b.add_param(Ref)
    b.add_result(Ref)
    let header = b.create_block()
    let object = b.add_block_param(header, Ref)
    let body = b.create_block()
    let exit = b.create_block()
    let returned = b.add_block_param(exit, Ref)
    b.jump(header, [initial])
    b.switch_to_block(header)
    let count = @wasm_milkir.struct_get(b, 0, 1, object, I32)
    b.branch(count, body, [], exit, [object])
    b.switch_to_block(body)
    @wasm_milkir.struct_get(b, 0, 0, object, Ref) |> ignore
    let next = @wasm_milkir.struct_new(b, 0, [
      replacement,
      b.isub(count, b.iconst_i32(1)),
    ])
    b.jump(header, [next])
    b.switch_to_block(exit)
    b.return_([returned])
    let function = b.finalize()
    assert_true(forward_constructor_fields(function, context))
    @wasm_milkir.verify_function_with_context(function, context)
    let loops = @milkir.CFG::build(function).find_loops()
    let mut remaining = 0
    for loop_ in loops {
      for block in function.blocks {
        if !loop_.contains(block.id) {
          continue
        }
        for id in function.block_instruction_ids(block) {
          if @wasm_milkir.decode_opcode(
              function.instruction_by_id(id).unwrap().opcode,
            )
            is Some(StructGet(0, 0)) {
            remaining += 1
          }
        }
      }
    }
    assert_eq(remaining, if mutable_ { 1 } else { 0 })
  }
}
