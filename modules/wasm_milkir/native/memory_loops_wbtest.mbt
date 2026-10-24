///|
fn loop_read_context() -> @wasm_milkir.WasmValidationContext {
  @wasm_milkir.WasmValidationContext::new({
    function_contract: fn(_) { None },
    defined_type_contract: fn(_) {
      Some(
        Struct([
          { storage: Value(I32), mutable_: true, defaultable: true, },
          { storage: Value(I32), mutable_: true, defaultable: true, },
        ]),
      )
    },
    table_contract: fn(_) { None },
    tag_contract: fn(_) { None },
    memory_exists: fn(_) { false },
    data_segment_exists: fn(_) { false },
    element_segment_type: fn(_) { None },
  })
}

///|
test "a checked object read leaves the loop without speculating its null check" {
  let b = @milkir.FunctionBuilder::FunctionBuilder("checked_loop_read")
  let object = b.add_param(Ref)
  let count = b.add_param(I32)
  b.add_result(I32)
  let checked = @wasm_milkir.struct_get(b, 0, 1, object, I32)
  let loop_ = b.create_block()
  let i = b.add_block_param(loop_, I32)
  let sum = b.add_block_param(loop_, I32)
  let body = b.create_block()
  let exit = b.create_block()
  let result = b.add_block_param(exit, I32)
  b.jump(loop_, [b.iconst_i32(0), checked])
  b.switch_to_block(loop_)
  b.branch(b.icmp_slt(i, count), body, [], exit, [sum])
  b.switch_to_block(body)
  let value = @wasm_milkir.struct_get(b, 0, 0, object, I32)
  b.jump(loop_, [b.iadd(i, b.iconst_i32(1)), b.iadd(sum, value)])
  b.switch_to_block(exit)
  b.return_([result])
  let function = b.get_function()
  optimize_memory_test(function, loop_read_context(), O2) |> ignore
  prepare_gc_memory(function, loop_read_context())
  let cfg = @milkir.CFG::build(function)
  let mut reads = 0
  for loop_ in cfg.find_loops() {
    for block in function.blocks {
      if loop_.contains(block.id) {
        for id in function.block_instruction_ids(block) {
          if function.instruction_by_id(id).unwrap().opcode is Ext(extension, _) &&
            decode_projection(extension) is Some(_) {
            reads += 1
          }
        }
      }
    }
  }
  assert_eq(reads, 0)
}

///|
test "loop read motion respects barriers and guards an initially unchecked read" {
  for mode in ["alias", "call", "allocate", "unchecked", "intervening_call"] {
    let b = @milkir.FunctionBuilder::FunctionBuilder("loop_barrier_\{mode}")
    let object = b.add_param(Ref)
    let other = b.add_param(Ref)
    let condition = b.add_param(I32)
    if mode != "unchecked" {
      @wasm_milkir.struct_get(b, 0, 1, object, I32) |> ignore
    }
    if mode == "intervening_call" {
      let symbol = b.get_function().declare_external_symbol("may_reenter")
      b.call_symbol(symbol, None, []) |> ignore
    }
    let header = b.create_block()
    let body = b.create_block()
    let exit = b.create_block()
    b.jump(header, [])
    b.switch_to_block(header)
    b.branch(condition, body, [], exit, [])
    b.switch_to_block(body)
    if mode == "alias" {
      @wasm_milkir.struct_set(b, 1, 0, other, b.iconst_i32(42))
    } else if mode == "call" {
      let symbol = b.get_function().declare_external_symbol("mutate_field")
      b.call_symbol(symbol, None, [object]) |> ignore
    } else if mode == "allocate" {
      @wasm_milkir.struct_new_default(b, 0) |> ignore
    }
    @wasm_milkir.struct_get(b, 0, 0, object, I32) |> ignore
    b.jump(header, [])
    b.switch_to_block(exit)
    b.return_([])
    let function = b.get_function()
    optimize_memory_test(function, loop_read_context(), O2) |> ignore
    let cfg = @milkir.CFG::build(function)
    let mut reads = 0
    for loop_ in cfg.find_loops() {
      for block in function.blocks {
        if loop_.contains(block.id) {
          for id in function.block_instruction_ids(block) {
            if function.instruction_by_id(id).unwrap().opcode is Memory(Load(_)) {
              reads += 1
            }
          }
        }
      }
    }
    assert_eq(
      reads,
      if mode == "unchecked" || mode == "intervening_call" {
        0
      } else {
        1
      },
      msg=mode,
    )
  }
}
