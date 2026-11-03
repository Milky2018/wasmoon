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
test "unchanged GC-free preparation validates each call contract once" {
  let lookups = Ref(0)
  let context = @wasm_milkir.WasmValidationContext::new({
    function_contract: fn(_) {
      lookups.val += 1
      Some({ params: [I32], results: [I32], })
    },
    defined_type_contract: fn(_) { None },
    table_contract: fn(_) { None },
    tag_contract: fn(_) { None },
    memory_exists: fn(_) { false },
    data_segment_exists: fn(_) { false },
    element_segment_type: fn(_) { None },
  })
  let b = @milkir.FunctionBuilder::FunctionBuilder("ordinary_call")
  b.add_param(Ptr) |> ignore
  let argument = b.add_param(I32)
  b.add_result(I32)
  b.return_([@wasm_milkir.call_multi(b, 0, [I32], [argument])[0]])
  let function = b.get_function()
  let before = function.print()
  prepare_gc_memory(function, context)
  assert_eq(lookups.val, 1)
  assert_eq(function.print(), before)
}

///|
test "removed instructions do not disable checked memory lowering" {
  let b = @milkir.FunctionBuilder("sparse_checked_array")
  let array = b.add_param(Ref)
  let index = b.add_param(I32)
  b.add_result(I64)
  for value in 0..<1300 {
    b.iconst_i32(value) |> ignore
  }
  b.return_([@wasm_milkir.array_get(b, 0, array, index, I64)])
  let function = b.get_function()
  let context = array_access_context()
  @wasm_opt.optimize_with_level(function, context, O2) |> ignore
  assert_true(function.next_inst_id > 1200)
  assert_true(
    function.blocks.fold(init=0, fn(total, block) {
      total + block.instruction_count()
    }) <
    10,
  )
  prepare_gc_memory(function, context)
  assert_true(function.print().contains("native_array_data"))
}

///|
fn allocation_contract_context() -> @wasm_milkir.WasmValidationContext {
  @wasm_milkir.WasmValidationContext::new({
    function_contract: fn(_) { Some({ params: [], results: [], }) },
    defined_type_contract: fn(index) {
      if index == 0 {
        Some(
          Struct([
            { storage: Value(I64), mutable_: true, defaultable: true, },
            { storage: Value(I64), mutable_: true, defaultable: true, },
          ]),
        )
      } else {
        None
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
test "generated initialization bounds allocation code growth without removing allocations" {
  let b = @milkir.FunctionBuilder("many_allocations")
  let n = b.add_param(I64)
  for _ in 0..<12 {
    @wasm_milkir.struct_new(b, 0, [n, n]) |> ignore
  }
  b.return_([])
  let function = b.get_function()
  let before = function.print()
  let (structs, _, shared) = allocation_expansion_limits(
    function,
    allocation_contract_context(),
  )
  assert_false(structs)
  assert_true(shared)
  assert_eq(function.print(), before)
}

///|
test "shared reservation work is bounded independently without mutating input" {
  for count in [30, 31] {
    let b = @milkir.FunctionBuilder("shared_work_bound")
    let n = b.add_param(I64)
    for _ in 0..<count {
      @wasm_milkir.struct_new(b, 0, [n, n]) |> ignore
    }
    b.return_([])
    let function = b.get_function()
    let before = function.print()
    let (_, arrays, shared) = allocation_expansion_limits(
      function,
      allocation_contract_context(),
    )
    assert_eq(shared, count == 30)
    assert_true(arrays)
    assert_eq(function.print(), before)
  }
}

///|
test "broader access views do not consume unrelated allocation expansion budgets" {
  let context = @wasm_milkir.WasmValidationContext::new({
    function_contract: fn(_) { None },
    defined_type_contract: fn(index) {
      let scalar : @wasm_milkir.WasmFieldContract = {
        storage: Value(I64),
        mutable_: true,
        defaultable: true,
      }
      match index {
        0 => Some(Struct([scalar, scalar]))
        1 =>
          Some(
            Struct([
              {
                storage: Value(CallableRef),
                mutable_: true,
                defaultable: true,
              },
              scalar,
            ]),
          )
        2 =>
          Some(
            Struct([
              { storage: Value(OpaqueRef), mutable_: true, defaultable: true, },
              scalar,
            ]),
          )
        3 => Some(Struct(Array::make(17, scalar)))
        _ => None
      }
    },
    table_contract: fn(_) { None },
    tag_contract: fn(_) { None },
    memory_exists: fn(_) { false },
    data_segment_exists: fn(_) { false },
    element_segment_type: fn(_) { None },
  })
  let b = @milkir.FunctionBuilder("independent_access_and_allocation")
  let callback = b.add_param(CallableRef)
  let opaque_value = b.add_param(OpaqueRef)
  let number = b.add_param(I64)
  for _ in 0..<12 {
    @wasm_milkir.struct_new(b, 1, [callback, number]) |> ignore
    @wasm_milkir.struct_new(b, 2, [opaque_value, number]) |> ignore
    @wasm_milkir.struct_new(b, 3, Array::make(17, number)) |> ignore
  }
  @wasm_milkir.struct_new(b, 0, [number, number]) |> ignore
  b.return_([])
  let function = b.get_function()
  let before = function.print()
  assert_true(struct_view_shape(context, 1) is Some(_))
  assert_true(struct_view_shape(context, 2) is Some(_))
  assert_true(struct_view_shape(context, 3) is Some(_))
  assert_eq(allocation_expansion_limits(function, context), (true, true, true))
  assert_eq(function.print(), before)
}
