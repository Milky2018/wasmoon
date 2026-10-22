///|
fn array_access_context() -> @wasm_milkir.WasmValidationContext {
  @wasm_milkir.WasmValidationContext::new({
    function_contract: fn(_) { None },
    defined_type_contract: fn(_) {
      Some(Array({ storage: Value(I64), mutable_: true, defaultable: true, }))
    },
    table_contract: fn(_) { None },
    tag_contract: fn(_) { None },
    memory_exists: fn(_) { false },
    data_segment_exists: fn(_) { false },
    element_segment_type: fn(_) { None },
  })
}

///|
test "physical array regions reject forged uses across safepoints and CFG joins" {
  for
    barrier in [
      "none", "alias", "call", "allocation", "raw_write", "chain", "join",
    ] {
    let b = @milkir.FunctionBuilder::FunctionBuilder("array_view_\{barrier}")
    let a = b.add_param(Ref)
    let address = b.add_param(Ptr)
    let i = b.add_param(I32)
    let first = @wasm_milkir.array_get(b, 0, a, i, I64)
    @wasm_milkir.array_get(b, 0, a, i, I64) |> ignore
    if barrier == "call" {
      let symbol = b
        .get_function()
        .declare_external_symbol("collect_reenter_or_poll")
      b.call_symbol(symbol, None, []) |> ignore
    } else if barrier == "allocation" {
      @wasm_milkir.array_new_default(b, 0, i) |> ignore
    } else if barrier == "raw_write" {
      b.store_ptr(I64, address, b.iconst_i64(0L), b.iconst_i64(0L))
    } else if barrier == "join" {
      let left = b.create_block()
      let right = b.create_block()
      let merge = b.create_block()
      b.branch(i, left, [], right, [])
      b.switch_to_block(left)
      b.jump(merge, [])
      b.switch_to_block(right)
      b.jump(merge, [])
      b.switch_to_block(merge)
    } else if barrier == "chain" {
      let next = b.create_block()
      b.jump(next, [])
      b.switch_to_block(next)
    } else if barrier == "alias" {
      @wasm_milkir.array_set(b, 0, a, i, first)
    }
    @wasm_milkir.array_get(b, 0, a, i, I64) |> ignore
    @wasm_milkir.array_get(b, 0, a, i, I64) |> ignore
    b.return_([])
    let function = b.get_function()
    let context = array_access_context()
    let plan = plan_array_accesses(function, context)
    assert_true(verify_array_accesses(function, context, plan))
    let ids = plan.keys().to_array()
    ids.sort()
    let first_id = ids[0]
    let last = ids[ids.length() - 1]
    let safe = barrier == "none" || barrier == "alias" || barrier == "chain"
    assert_eq(plan[last].first == first_id, safe)
    // The checker must detect a plan that illegally carries a physical
    // pointer across a call/allocation, or from a different source block.
    plan[last] = {
      first: first_id,
      width: 8,
      opcode: ArrayGet(0),
      loop_header: None,
    }
    assert_eq(verify_array_accesses(function, context, plan), safe)
    plan[last] = {
      first: first_id,
      width: 4,
      opcode: ArrayGet(0),
      loop_header: None,
    }
    assert_false(verify_array_accesses(function, context, plan))
  }
}

///|
test "a loop view requires an executed preheader check and a complete cycle proof" {
  for mode in ["checked", "unchecked", "call", "allocation", "raw_write"] {
    let b = @milkir.FunctionBuilder::FunctionBuilder("loop_array_view_\{mode}")
    let a = b.add_param(Ref)
    let address = b.add_param(Ptr)
    let n = b.add_param(I32)
    if mode != "unchecked" {
      @wasm_milkir.array_len(b, a) |> ignore
    }
    let header = b.create_block()
    let i = b.add_block_param(header, I32)
    let body = b.create_block()
    let exit = b.create_block()
    b.jump(header, [b.iconst_i32(0)])
    b.switch_to_block(header)
    b.branch(b.icmp_ult(i, n), body, [], exit, [])
    b.switch_to_block(body)
    let old = @wasm_milkir.array_get(b, 0, a, i, I64)
    if mode == "call" {
      let symbol = b.get_function().declare_external_symbol("reenter_or_poll")
      b.call_symbol(symbol, None, []) |> ignore
    } else if mode == "allocation" {
      @wasm_milkir.array_new_default(b, 0, n) |> ignore
    }
    if mode == "raw_write" {
      b.store_ptr(I64, address, b.iconst_i64(0L), b.iconst_i64(0L))
    }
    @wasm_milkir.array_set(b, 0, a, i, b.iadd(old, b.iconst_i64(1L)))
    b.jump(header, [b.iadd(i, b.iconst_i32(1))])
    b.switch_to_block(exit)
    b.return_([])
    let function = b.get_function()
    let context = array_access_context()
    let plan = plan_array_accesses(function, context)
    assert_true(verify_array_accesses(function, context, plan))
    assert_eq(
      plan.values().any(a => a.loop_header is Some(_)),
      mode == "checked",
    )
    // Even a forged loop annotation cannot hide a safepoint or speculate
    // preparation before a nullable array's first executed check.
    let accesses : Array[@milkir.Inst] = []
    for block in function.blocks {
      for id in function.block_instruction_ids(block) {
        let inst = function.instruction_by_id(id).unwrap()
        if scalar_array_access(inst, context) is Some(_) {
          accesses.push(inst)
        }
      }
    }
    let first = if mode == "unchecked" {
      accesses[0].id
    } else {
      function
      .block_instruction_ids(function.blocks[0])
      .to_owned()
      .iter()
      .find_first(id => {
        @wasm_milkir.decode_opcode(
          function.instruction_by_id(id).unwrap().opcode,
        )
        is Some(ArrayLen)
      })
      .unwrap()
    }
    for inst in accesses {
      let (width, opcode) = scalar_array_access(inst, context).unwrap()
      plan[inst.id] = { first, width, opcode, loop_header: Some(header.id), }
    }
    assert_eq(verify_array_accesses(function, context, plan), mode == "checked")
  }
}

///|
test "loop array views may be prepared from a produced nullable reference" {
  for mode in ["none", "call", "allocation", "raw_write"] {
    let barrier = mode != "none"
    let b = @milkir.FunctionBuilder::FunctionBuilder("produced_array_view")
    let holder = b.add_param(Ref)
    let address = b.add_param(Ptr)
    let n = b.add_param(I32)
    let a = @wasm_milkir.struct_get(b, 1, 0, holder, Ref)
    let origin = b.get_function().defining_inst(a).unwrap().id
    if mode == "call" {
      let symbol = b.get_function().declare_external_symbol("reenter")
      b.call_symbol(symbol, None, []) |> ignore
    } else if mode == "allocation" {
      @wasm_milkir.array_new_default(b, 0, n) |> ignore
    } else if mode == "raw_write" {
      b.store_ptr(I64, address, b.iconst_i64(0L), b.iconst_i64(0L))
    }
    let header = b.create_block()
    let i = b.add_block_param(header, I32)
    let body = b.create_block()
    let exit = b.create_block()
    b.jump(header, [b.iconst_i32(0)])
    b.switch_to_block(header)
    b.branch(b.icmp_ult(i, n), body, [], exit, [])
    b.switch_to_block(body)
    let value = @wasm_milkir.array_get(b, 0, a, i, I64)
    @wasm_milkir.array_set(b, 0, a, i, b.iadd(value, b.iconst_i64(1L)))
    b.jump(header, [b.iadd(i, b.iconst_i32(1))])
    b.switch_to_block(exit)
    b.return_([])
    let function = b.get_function()
    let context = array_access_context()
    let plan = plan_array_accesses(function, context)
    assert_true(verify_array_accesses(function, context, plan))
    assert_eq(plan.values().any(a => a.first == origin), !barrier)
    for id in plan.keys().to_array() {
      let access = plan[id]
      plan[id] = { ..access, first: origin, loop_header: Some(header.id), }
    }
    assert_eq(verify_array_accesses(function, context, plan), !barrier)
  }
}
