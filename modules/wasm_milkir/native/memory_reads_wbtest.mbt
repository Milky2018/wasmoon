///|
fn test_context() -> @wasm_milkir.WasmValidationContext {
  @wasm_milkir.WasmValidationContext::new({
    function_contract: fn(_) { None },
    defined_type_contract: fn(index) {
      match index {
        0 =>
          Some(
            Struct([
              { storage: Value(I32), mutable_: true, defaultable: true, },
              { storage: Value(I32), mutable_: true, defaultable: true, },
              { storage: Packed8, mutable_: true, defaultable: true, },
              { storage: Value(Ref), mutable_: true, defaultable: true, },
            ]),
          )
        1 =>
          Some(
            Array({ storage: Value(I32), mutable_: true, defaultable: true, }),
          )
        _ => None
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
fn gc_read_count(
  function : @milkir.Function,
  include_lengths~ : Bool = false,
) -> Int32 {
  let mut count = 0
  for block in function.blocks {
    for id in function.block_instruction_ids(block) {
      let opcode = function.instruction_by_id(id).unwrap().opcode
      if opcode is Memory(Load(_) | LoadNarrow(_, _, _)) {
        count += 1
        continue
      }
      if include_lengths &&
        opcode is Ext(extension, _) &&
        extension.opcode == "native_array_length" {
        count += 1
        continue
      }
      match @wasm_milkir.decode_opcode(opcode) {
        Some(StructGet(_, _) | StructGetS(_, _, _) | StructGetU(_, _, _)) =>
          count += 1
        _ => ()
      }
    }
  }
  count
}

///|
test "GC reads forward through distinct field writes and array mutation" {
  let b = @milkir.FunctionBuilder::FunctionBuilder("gc_reads")
  let object = b.add_param(Ref)
  let array = b.add_param(Ref)
  let value = b.add_param(I32)
  let first = @wasm_milkir.struct_get(b, 0, 0, object, I32)
  @wasm_milkir.struct_set(b, 0, 1, object, value)
  @wasm_milkir.array_set(b, 1, array, b.iconst_i32(0), value)
  let second = @wasm_milkir.struct_get(b, 0, 0, object, I32)
  b.add_result(I32)
  b.return_([b.iadd(first, second)])
  let function = b.get_function()
  optimize_memory_test(function, test_context(), O2) |> ignore
  inspect(gc_read_count(function), content="1")
}

///|
test "GC writes invalidate aliases while preserving each checked read" {
  let b = @milkir.FunctionBuilder::FunctionBuilder("aliases")
  let left = b.add_param(Ref)
  let right = b.add_param(Ref)
  let value = b.add_param(I32)
  @wasm_milkir.struct_get(b, 0, 0, left, I32) |> ignore
  @wasm_milkir.struct_set(b, 0, 0, right, value)
  @wasm_milkir.struct_get(b, 0, 0, right, I32) |> ignore
  @wasm_milkir.struct_get(b, 0, 0, left, I32) |> ignore
  b.return_([])
  let function = b.get_function()
  optimize_memory_test(function, test_context(), O2) |> ignore
  inspect(gc_read_count(function), content="3")
}

///|
test "packed reads keep signedness and truncate intervening writes" {
  let b = @milkir.FunctionBuilder::FunctionBuilder("packed")
  let object = b.add_param(Ref)
  let value = b.add_param(I32)
  @wasm_milkir.struct_get_s(b, 0, 2, object, 1) |> ignore
  @wasm_milkir.struct_get_s(b, 0, 2, object, 1) |> ignore
  @wasm_milkir.struct_get_u(b, 0, 2, object, 1) |> ignore
  @wasm_milkir.struct_get_u(b, 0, 2, object, 1) |> ignore
  @wasm_milkir.struct_set(b, 0, 2, object, value)
  @wasm_milkir.struct_get_s(b, 0, 2, object, 1) |> ignore
  b.return_([])
  let function = b.get_function()
  optimize_memory_test(function, test_context(), O2) |> ignore
  inspect(gc_read_count(function), content="3")
}

///|
test "array length forwarding survives element writes" {
  let b = @milkir.FunctionBuilder::FunctionBuilder("array_length")
  let array = b.add_param(Ref)
  @wasm_milkir.array_len(b, array) |> ignore
  @wasm_milkir.array_set(b, 1, array, b.iconst_i32(0), b.iconst_i32(42))
  @wasm_milkir.array_len(b, array) |> ignore
  b.return_([])
  let function = b.get_function()
  optimize_memory_test(function, test_context(), O2) |> ignore
  inspect(gc_read_count(function, include_lengths=true), content="1")
}

///|
test "allocation preserves logical GC reads without retaining physical views" {
  let b = @milkir.FunctionBuilder::FunctionBuilder("allocation_barrier")
  let object = b.add_param(Ref)
  @wasm_milkir.struct_get(b, 0, 0, object, I32) |> ignore
  @wasm_milkir.struct_new_default(b, 0) |> ignore
  @wasm_milkir.struct_get(b, 0, 0, object, I32) |> ignore
  b.return_([])
  let function = b.get_function()
  optimize_memory_test(function, test_context(), O2) |> ignore
  inspect(gc_read_count(function), content="1")
}

///|
test "dominating reads survive unmodified control flow merges" {
  let b = @milkir.FunctionBuilder::FunctionBuilder("merge")
  let object = b.add_param(Ref)
  let condition = b.add_param(I32)
  let left = b.create_block()
  let right = b.create_block()
  let join = b.create_block()
  @wasm_milkir.struct_get(b, 0, 0, object, I32) |> ignore
  b.branch(condition, left, [], right, [])
  b.switch_to_block(left)
  @wasm_milkir.struct_get(b, 0, 0, object, I32) |> ignore
  b.jump(join, [])
  b.switch_to_block(right)
  @wasm_milkir.struct_get(b, 0, 0, object, I32) |> ignore
  b.jump(join, [])
  b.switch_to_block(join)
  @wasm_milkir.struct_get(b, 0, 0, object, I32) |> ignore
  b.return_([])
  let function = b.get_function()
  optimize_memory_test(function, test_context(), O2) |> ignore
  inspect(gc_read_count(function), content="1")
}

///|
test "GC forwarding leaves O0 and O1 reads unchanged" {
  for level in [@generic.OptLevel::O0, O1] {
    let b = @milkir.FunctionBuilder::FunctionBuilder("unoptimized")
    let object = b.add_param(Ref)
    @wasm_milkir.struct_get(b, 0, 0, object, I32) |> ignore
    @wasm_milkir.struct_get(b, 0, 0, object, I32) |> ignore
    b.return_([])
    let function = b.get_function()
    optimize_memory_test(function, test_context(), level) |> ignore
    inspect(gc_read_count(function), content="2")
  }
}

///|
test "context validation precedes removal of redundant malformed reads" {
  let b = @milkir.FunctionBuilder::FunctionBuilder("forged_read")
  let object = b.add_param(Ref)
  @wasm_milkir.struct_set(b, 0, 2, object, b.iconst_i32(511))
  // A plain get of a packed field is invalid. Forwarding the stored I32
  // before validation would erase the only malformed extension entirely.
  @wasm_milkir.struct_get(b, 0, 2, object, I32) |> ignore
  b.return_([])
  let function = b.get_function()
  let before = function.print()
  let rejected = try {
    optimize_memory_test(function, test_context(), O2) |> ignore
    false
  } catch {
    _ => true
  }
  assert_true(rejected)
  assert_eq(function.print(), before)
}

///|
test "unknown calls invalidate GC read facts" {
  let b = @milkir.FunctionBuilder::FunctionBuilder("call_barrier")
  let object = b.add_param(Ref)
  @wasm_milkir.struct_get(b, 0, 0, object, I32) |> ignore
  let symbol = b.get_function().declare_external_symbol("mutate_gc_object")
  b.call_symbol(symbol, None, [object]) |> ignore
  @wasm_milkir.struct_get(b, 0, 0, object, I32) |> ignore
  b.return_([])
  let function = b.get_function()
  optimize_memory_test(function, test_context(), O2) |> ignore
  inspect(gc_read_count(function), content="2")
}

///|
test "prechecked stable loop reads reuse the preheader value" {
  let b = @milkir.FunctionBuilder::FunctionBuilder("loop")
  let object = b.add_param(Ref)
  let condition = b.add_param(I32)
  let header = b.create_block()
  let exit = b.create_block()
  @wasm_milkir.struct_get(b, 0, 0, object, I32) |> ignore
  b.jump(header, [])
  b.switch_to_block(header)
  @wasm_milkir.struct_get(b, 0, 0, object, I32) |> ignore
  @wasm_milkir.struct_get(b, 0, 0, object, I32) |> ignore
  b.branch(condition, header, [], exit, [])
  b.switch_to_block(exit)
  b.return_([])
  let function = b.get_function()
  optimize_memory_test(function, test_context(), O2) |> ignore
  inspect(gc_read_count(function), content="1")
}

///|
test "forwarded references preserve their GC carrier" {
  let b = @milkir.FunctionBuilder::FunctionBuilder("reference")
  let object = b.add_param(Ref)
  let first = @wasm_milkir.struct_get(b, 0, 3, object, Ref)
  let second = @wasm_milkir.struct_get(b, 0, 3, object, Ref)
  b.add_result(Ref)
  b.add_result(Ref)
  b.return_([first, second])
  let function = b.get_function()
  optimize_memory_test(function, test_context(), O2) |> ignore
  prepare_gc_memory(function, test_context())
  inspect(gc_read_count(function), content="1")
  assert_eq(function.results, [Ref, Ref])
}

///|
test "large extended regions and long copy chains remain well formed" {
  let b = @milkir.FunctionBuilder::FunctionBuilder("large_region")
  let objects = Array::makei(192, _ => b.add_param(Ref))
  let mut sum = b.iconst_i32(0)
  for index, object in objects {
    let next = b.create_block()
    b.jump(next, [])
    b.switch_to_block(next)
    let mut copied = object
    if index == 0 {
      for _ in 0..<192 {
        copied = b.copy(copied)
      }
    }
    let value = @wasm_milkir.struct_get(b, 0, 0, copied, I32)
    sum = b.iadd(sum, value)
  }
  b.add_result(I32)
  b.return_([sum])
  let function = b.get_function()
  optimize_memory_test(function, test_context(), O2) |> ignore
  prepare_gc_memory(function, test_context())
  // Forgetting available reads must not discard any of these distinct reads.
  inspect(gc_read_count(function), content="192")
}
