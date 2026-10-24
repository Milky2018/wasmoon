///|
fn digit_memory_context() -> @wasm_milkir.WasmValidationContext {
  @wasm_milkir.WasmValidationContext::new({
    function_contract: fn(_) { None },
    defined_type_contract: fn(index) {
      if index == 0 {
        Some(Array({ storage: Packed8, mutable_: true, defaultable: true, }))
      } else {
        Some(
          Struct([
            { storage: Value(Ref), mutable_: false, defaultable: true, },
            { storage: Value(I32), mutable_: true, defaultable: true, },
            { storage: Value(I32), mutable_: true, defaultable: true, },
          ]),
        )
      }
    },
    table_contract: fn(_) { None },
    tag_contract: fn(_) { None },
    memory_exists: fn(_) { false },
    data_segment_exists: fn(_) { false },
    element_segment_type: fn(_) { None },
  })
}

///|
test "digit-loop memory SSA hoists physical queries without a GC-specific loop recognizer" {
  let builder = @milkir.FunctionBuilder("digit_memory")
  builder.add_param(I64) |> ignore
  let holder = builder.add_param(Ref)
  let array = @wasm_milkir.struct_get(builder, 1, 0, holder, Ref)
  let count = @wasm_milkir.struct_get(builder, 1, 1, holder, I32)
  let header = builder.create_block()
  let index = builder.add_block_param(header, I32)
  let body = builder.create_block()
  let exit = builder.create_block()
  builder.jump(header, [builder.iconst_i32(0)])
  builder.switch_to_block(header)
  builder.branch(builder.icmp_ult(index, count), body, [], exit, [])
  builder.switch_to_block(body)
  let value = @wasm_milkir.array_get_u(builder, 0, array, index, 1)
  @wasm_milkir.array_set(builder, 0, array, index, value)
  @wasm_milkir.struct_set(builder, 1, 2, holder, value)
  // A different field/array store cannot invalidate this field's value.
  let unchanged = @wasm_milkir.struct_get(builder, 1, 1, holder, I32)
  builder.jump(header, [builder.iadd(index, unchanged)])
  builder.switch_to_block(exit)
  builder.return_([])
  let function = builder.finalize()
  prepare_gc_memory(function, digit_memory_context())
  let cfg = @milkir.CFG::build(function)
  let loops = cfg.find_loops()
  assert_false(loops.is_empty())
  for loop_ in loops {
    for block in function.blocks {
      if loop_.contains(block.id) {
        for id in function.block_instruction_ids(block) {
          let inst = function.instruction_by_id(id).unwrap()
          if inst.opcode is Ext(extension, _) {
            assert_true(decode_projection(extension) is None)
          }
        }
      }
    }
  }
  assert_true(verify_gc_borrows(function))
}

///|
test "large initializer retains checked accesses without physical CFG expansion" {
  let builder = @milkir.FunctionBuilder("large_initializer")
  builder.add_param(I64) |> ignore
  let array = builder.add_param(Ref)
  let value = builder.add_param(I32)
  for index in 0..<700 {
    @wasm_milkir.array_set(builder, 0, array, builder.iconst_i32(index), value)
  }
  builder.return_([])
  let function = builder.finalize()
  let blocks = function.blocks.length()
  prepare_gc_memory(function, digit_memory_context())
  assert_eq(function.blocks.length(), blocks)
  let mut stores = 0
  for block in function.blocks {
    for id in function.block_instruction_ids(block) {
      if function.instruction_by_id(id).unwrap().opcode is Ext(extension, _) {
        assert_true(decode_projection(extension) is None)
        stores += 1
      }
    }
  }
  assert_eq(stores, 700)
}

///|
test "checked physical projections retain the original trap source location" {
  let builder = @milkir.FunctionBuilder("located_field")
  builder.add_param(I64) |> ignore
  let object = builder.add_param(Ref)
  builder.add_result(I32)
  let value = @wasm_milkir.struct_get(builder, 1, 1, object, I32)
  let function = builder.get_function()
  for id in function.block_instruction_ids(function.blocks[0]) {
    function
    .instruction_by_id(id)
    .unwrap()
    .add_metadata(SourceLoc("field.wasm:19"))
  }
  builder.return_([value])
  prepare_gc_memory(builder.finalize(), digit_memory_context())
  let mut checks = 0
  for block in function.blocks {
    for id in function.block_instruction_ids(block) {
      let inst = function.instruction_by_id(id).unwrap()
      if inst.opcode is Ext(extension, _) &&
        decode_projection(extension) is Some(StructData(_)) {
        assert_true(inst.metadata.contains(SourceLoc("field.wasm:19")))
        checks += 1
      }
    }
  }
  assert_eq(checks, 1)
}

///|
test "GC loop placement does not oscillate with single-use rematerialization" {
  let builder = @milkir.FunctionBuilder("bounded_loop_placement")
  builder.add_param(I64) |> ignore
  let array = builder.add_param(Ref)
  let count = builder.add_param(I32)
  let header = builder.create_block()
  let index = builder.add_block_param(header, I32)
  let body = builder.create_block()
  let exit = builder.create_block()
  builder.jump(header, [builder.iconst_i32(0)])
  builder.switch_to_block(header)
  builder.branch(builder.icmp_ult(index, count), body, [], exit, [])
  builder.switch_to_block(body)
  let byte = @wasm_milkir.array_get_u(builder, 0, array, index, 1)
  @wasm_milkir.array_set(builder, 0, array, index, byte)
  builder.jump(header, [builder.iadd(index, builder.iconst_i32(1))])
  builder.switch_to_block(exit)
  builder.return_([])
  let runs = Ref(0)
  @generic.install_optimization_metrics_sink(
    @generic.OptimizationMetricsSink::new(fn() { 0L }, fn(metric) {
      if metric.name == "acyclic_optimize" {
        runs.val += 1
      }
    }),
  )
  defer @generic.clear_optimization_metrics_sink()
  let function = builder.finalize()
  prepare_gc_memory(function, digit_memory_context())
  assert_true(verify_gc_borrows(function))
  assert_true(
    runs.val <= 4,
    msg="redundant whole-function rewrite runs: \{runs.val}",
  )
}

///|
test "checked loop views merge distinct external entries before guarded placement" {
  let builder = @milkir.FunctionBuilder("multiple_loop_entries")
  builder.add_param(I64) |> ignore
  let holder = builder.add_param(Ref)
  let choose = builder.add_param(I32)
  let count = builder.add_param(I32)
  let left = builder.create_block()
  let right = builder.create_block()
  let header = builder.create_block()
  let remaining = builder.add_block_param(header, I32)
  let body = builder.create_block()
  let exit = builder.create_block()
  builder.branch(choose, left, [], right, [])
  builder.switch_to_block(left)
  builder.jump(header, [count])
  builder.switch_to_block(right)
  builder.jump(header, [builder.iadd(count, builder.iconst_i32(1))])
  builder.switch_to_block(header)
  builder.branch(
    builder.icmp_sgt(remaining, builder.iconst_i32(0)),
    body,
    [],
    exit,
    [],
  )
  builder.switch_to_block(body)
  let value = @wasm_milkir.struct_get(builder, 1, 1, holder, I32)
  @wasm_milkir.struct_set(builder, 1, 2, holder, value)
  builder.jump(header, [builder.isub(remaining, builder.iconst_i32(1))])
  builder.switch_to_block(exit)
  builder.return_([])
  let function = builder.finalize()
  prepare_gc_memory(function, digit_memory_context())
  for loop_ in @milkir.CFG::build(function).find_loops() {
    for block in function.blocks {
      if loop_.contains(block.id) {
        for id in function.block_instruction_ids(block) {
          let inst = function.instruction_by_id(id).unwrap()
          if inst.opcode is Ext(extension, _) {
            assert_true(decode_projection(extension) is None)
          }
        }
      }
    }
  }
  assert_true(verify_gc_borrows(function))
}
