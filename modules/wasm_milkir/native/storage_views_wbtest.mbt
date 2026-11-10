///|
fn storage_view_context(
  fields : Array[@wasm_milkir.WasmFieldContract],
  array~ : Bool = false,
) -> @wasm_milkir.WasmValidationContext {
  @wasm_milkir.WasmValidationContext::new({
    function_contract: fn(_) { None },
    defined_type_contract: fn(_) {
      Some(if array { Array(fields[0]) } else { Struct(fields) })
    },
    table_contract: fn(_) { None },
    tag_contract: fn(_) { None },
    memory_exists: fn(_) { false },
    data_segment_exists: fn(_) { false },
    element_segment_type: fn(_) { None },
  })
}

///|
test "all reference carriers share physical reads but retain typed SSA and write barriers" {
  let carriers : Array[@milkir.Type] = [Ref, CallableRef, OpaqueRef]
  for carrier in carriers {
    let fields : Array[@wasm_milkir.WasmFieldContract] = [
      { storage: Value(carrier), mutable_: true, defaultable: true, },
      { storage: Value(I64), mutable_: true, defaultable: true, },
    ]
    let context = storage_view_context(fields)
    assert_eq(struct_view_shape(context, 0), Some((76UL, 2)))
    for field in [0, 1] {
      let b = @milkir.FunctionBuilder("reference_carrier_read")
      let object = b.add_param(Ref)
      let result_type = if field == 0 { carrier } else { I64 }
      b.add_result(result_type)
      b.return_([@wasm_milkir.struct_get(b, 0, field, object, result_type)])
      let function = b.finalize()
      prepare_gc_memory(function, context)
      assert_true(function.print().contains("native_struct_data"))
      assert_true(
        function.blocks.any(block => {
          function
          .block_instruction_ids(block)
          .any(id => {
            function.instruction_by_id(id).unwrap().opcode ==
            Memory(Load(result_type))
          })
        }),
      )
    }
    let b = @milkir.FunctionBuilder("reference_carrier_write")
    let object = b.add_param(Ref)
    let value = b.add_param(carrier)
    b.add_result(I64)
    @wasm_milkir.struct_set(b, 0, 0, object, value)
    b.return_([@wasm_milkir.struct_get(b, 0, 1, object, I64)])
    let function = b.finalize()
    prepare_gc_memory(function, context)
    assert_true(function.print().contains("struct_set"))
    let array = @milkir.FunctionBuilder("reference_array_read")
    let object = array.add_param(Ref)
    let index = array.add_param(I32)
    array.add_result(carrier)
    array.return_([@wasm_milkir.array_get(array, 0, object, index, carrier)])
    let function = array.finalize()
    let before = function.print()
    prepare_gc_memory(function, storage_view_context([fields[0]], array=true))
    assert_eq(function.print(), before)
  }
}

///|
test "large structs admit only a completely checked physical prefix" {
  let fields : Array[@wasm_milkir.WasmFieldContract] = Array::makei(27, _ => {
    storage: Value(I64),
    mutable_: true,
    defaultable: true,
  })
  let context = storage_view_context(fields)
  assert_eq(struct_view_shape(context, 0), Some((0x4444444444444444UL, 16)))
  let b = @milkir.FunctionBuilder("large_struct_prefix")
  let object = b.add_param(Ref)
  b.add_result(I64)
  let first = @wasm_milkir.struct_get(b, 0, 8, object, I64)
  let last = @wasm_milkir.struct_get(b, 0, 26, object, I64)
  b.return_([b.iadd(first, last)])
  let function = b.finalize()
  prepare_gc_memory(function, context)
  assert_true(function.print().contains("native_struct_data"))
  let remaining : Array[Int32] = []
  for block in function.blocks {
    for id in function.block_instruction_ids(block) {
      if @wasm_milkir.decode_opcode(
          function.instruction_by_id(id).unwrap().opcode,
        )
        is Some(StructGet(_, field)) {
        remaining.push(field)
      }
    }
  }
  assert_eq(remaining, [26])
  let forged = @milkir.FunctionBuilder("out_of_prefix_field")
  let object = forged.add_param(Ref)
  let view = forged.emit_ext_inst(Ptr, projection_opcode(StructData(0)), [
    object,
  ])
  let field = forged.emit_ext_inst(
    Ptr,
    projection_opcode(FieldData(0, 26, 8, 0, true)),
    [view],
  )
  forged.add_result(I64)
  forged.return_([forged.load_ptr(I64, field, forged.iconst_i64(0L))])
  let rejected = try {
    prepare_gc_memory(forged.finalize(), context)
    false
  } catch {
    _ => true
  }
  assert_true(rejected)
}

///|
test "reference storage reads retain exact width and forbid raw reference stores" {
  let carriers : Array[@milkir.Type] = [Ref, CallableRef, OpaqueRef]
  for carrier in carriers {
    let b = @milkir.FunctionBuilder("reference_storage_permissions")
    let pointer = b.add_param(Ptr)
    let value = b.add_param(carrier)
    let load = b.load_ptr(carrier, pointer, b.iconst_i64(0L))
    b.store_ptr(carrier, pointer, value, b.iconst_i64(0L))
    b.return_([load])
    b.add_result(carrier)
    let function = b.finalize()
    for block in function.blocks {
      for id in function.block_instruction_ids(block) {
        let inst = function.instruction_by_id(id).unwrap()
        match inst.opcode {
          Memory(Load(_)) => {
            assert_true(valid_borrow_access(inst, FieldData(0, 0, 8, 1, true)))
            assert_false(valid_borrow_access(inst, FieldData(0, 0, 4, 1, true)))
            assert_false(valid_borrow_access(inst, FieldData(0, 0, 8, 0, true)))
          }
          Memory(Store(_)) =>
            assert_false(
              valid_borrow_access(inst, FieldData(0, 0, 8, 1, false)),
            )
          _ => ()
        }
      }
    }
  }
}

///|
test "loop reference projection gets a reserved struct expansion slot" {
  let b = @milkir.FunctionBuilder("loop_projection_priority")
  let object = b.add_param(Ref)
  let again = b.add_param(I32)
  let wider = b.create_block()
  let body = b.create_block()
  let latch = b.create_block()
  let tight = b.create_block()
  let exit = b.create_block()
  fn read_reference_field() -> @milkir.Value {
    let view = b.emit_ext_inst(Ptr, projection_opcode(StructData(0)), [object])
    let field = b.emit_ext_inst(
      Ptr,
      projection_opcode(FieldData(0, 0, 8, 1, true)),
      [view],
    )
    b.load_ptr(Ref, field, b.iconst_i64(0L)) |> ignore
    view
  }
  b.jump(wider, [])
  b.switch_to_block(wider)
  b.branch(again, body, [], tight, [])
  b.switch_to_block(body)
  let wide_view = read_reference_field()
  b.jump(latch, [])
  b.switch_to_block(latch)
  b.jump(wider, [])
  b.switch_to_block(tight)
  let tight_view = read_reference_field()
  b.branch(again, tight, [], exit, [])
  b.switch_to_block(exit)
  b.return_([])
  let function = b.finalize()
  let wide_id = function.defining_inst(wide_view).unwrap().id
  let tight_id = function.defining_inst(tight_view).unwrap().id
  let sites = inline_projection_sites(function, reserve_struct=true)
  inspect(sites.eligible.contains(wide_id), content="true")
  inspect(sites.eligible.contains(tight_id), content="true")
  inspect(sites.reserved_struct == Some(tight_id), content="true")
  inspect(
    inline_projection_sites(function).reserved_struct is None,
    content="true",
  )
}

///|
test "offset projections only cache fixed context loads in read-only loops" {
  for writes in [false, true] {
    let b = @milkir.FunctionBuilder("offset_context_load")
    let context = b.add_param(I64)
    let replacement = b.add_param(Ref)
    let again = b.add_param(I32)
    let header = b.create_block()
    let exit = b.create_block()
    b.jump(header, [])
    b.switch_to_block(header)
    let table = b.load_ptr(I64, context, b.iconst_i64(8L))
    let slot = b.load_ptr(I64, table, b.iconst_i64(16L))
    let zero = b.iconst_i64(0L)
    if writes {
      b.store_ptr(Ref, slot, replacement, zero)
    }
    let reference = b.load_ptr(Ref, slot, zero)
    let view = b.emit_ext_inst(Ptr, projection_opcode(StructData(0)), [
      reference,
    ])
    b.branch(again, header, [], exit, [])
    b.switch_to_block(exit)
    b.return_([])
    let function = b.finalize()
    let projection = function.defining_inst(view).unwrap().id
    let sites = inline_projection_sites(function, reuse_only=true)
    assert_eq(sites.eligible.contains(projection), !writes)
  }
}
