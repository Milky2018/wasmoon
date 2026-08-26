///|
fn contextual_test_context() -> WasmValidationContext {
  WasmValidationContext::new({
    function_contract: fn(index) {
      if index == 7 {
        Some({ params: [I32], results: [I64], })
      } else {
        None
      }
    },
    defined_type_contract: fn(index) {
      match index {
        2 => Some(Function({ params: [I64], results: [F32], }))
        3 =>
          Some(
            Struct([
              { storage: Value(I64), mutable_: true, defaultable: true, },
              { storage: Packed8, mutable_: false, defaultable: true, },
            ]),
          )
        4 =>
          Some(
            Array({ storage: Value(F64), mutable_: true, defaultable: true, }),
          )
        5 =>
          Some(
            Array({ storage: Packed16, mutable_: false, defaultable: true, }),
          )
        6 =>
          Some(
            Array({ storage: Value(Ref), mutable_: true, defaultable: true, }),
          )
        _ => None
      }
    },
    table_contract: fn(index) {
      if index == 1 {
        Some({ index_type: I64, element_type: CallableRef, })
      } else {
        None
      }
    },
    tag_contract: fn(index) {
      if index == 0 {
        Some({ params: [I32, F64], results: [], })
      } else {
        None
      }
    },
    memory_exists: fn(index) { index == 0 },
    data_segment_exists: fn(index) { index == 0 },
    element_segment_type: fn(index) {
      if index == 0 {
        Some(Ref)
      } else {
        None
      }
    },
  })
}

///|
fn contextual_error_for(
  builder : @milkir.FunctionBuilder,
) -> @milkir.VerifyError {
  try
    verify_function_with_context(
      builder.get_function(),
      contextual_test_context(),
    )
  catch {
    error => error
  } noraise {
    _ => abort("expected contextual Wasm validation to fail")
  }
}

///|
test "contextual Wasm validation rejects forged call contracts" {
  let direct = @milkir.FunctionBuilder::FunctionBuilder("bad_direct_call")
  let direct_arg = direct.add_param(I32)
  call_multi(direct, 7, [F64], [direct_arg]) |> ignore
  direct.return_([])

  let indirect = @milkir.FunctionBuilder::FunctionBuilder("bad_indirect_call")
  let table_index = indirect.add_param(I32)
  let indirect_arg = indirect.add_param(I64)
  call_indirect_multi(indirect, 2, 1, [F32], table_index, [indirect_arg])
  |> ignore
  indirect.return_([])

  let reference = @milkir.FunctionBuilder::FunctionBuilder("bad_call_ref")
  let function_reference = reference.add_param(CallableRef)
  let reference_arg = reference.add_param(I32)
  call_ref_multi(reference, 2, [F32], function_reference, [reference_arg])
  |> ignore
  reference.return_([])

  let tail = @milkir.FunctionBuilder::FunctionBuilder("bad_tail_call")
  tail.add_result(F32)
  let tail_arg = tail.add_param(I32)
  let fallback_result = tail.add_param(F32)
  return_call_multi(tail, 7, [tail_arg])
  tail.return_([fallback_result])

  debug_inspect(
    [
      contextual_error_for(direct),
      contextual_error_for(indirect),
      contextual_error_for(reference),
      contextual_error_for(tail),
    ],
    content=(
      #|[
      #|  UnverifiableInstruction(message="malformed contextual Wasm MilkIR extension 'call': expected call results [i64], got [f64]"),
      #|  UnverifiableInstruction(message="malformed contextual Wasm MilkIR extension 'call_indirect': table index 1 expects element index i64, got i32"),
      #|  UnverifiableInstruction(message="malformed contextual Wasm MilkIR extension 'call_ref': expected call parameters [i64], got [i32]"),
      #|  UnverifiableInstruction(message="malformed contextual Wasm MilkIR extension 'return_call': target results [i64] do not match enclosing function results [f32]"),
      #|]
    ),
  )
}

///|
test "contextual Wasm validation rejects forged aggregate contracts" {
  let get = @milkir.FunctionBuilder::FunctionBuilder("bad_struct_get")
  let struct_reference = get.add_param(Ref)
  struct_get(get, 3, 0, struct_reference, F64) |> ignore
  get.return_([])

  let packed = @milkir.FunctionBuilder::FunctionBuilder("bad_struct_packed_get")
  let packed_reference = packed.add_param(Ref)
  struct_get_s(packed, 3, 1, packed_reference, 2) |> ignore
  packed.return_([])

  let set = @milkir.FunctionBuilder::FunctionBuilder("bad_array_set")
  let array_reference = set.add_param(Ref)
  let array_index = set.add_param(I32)
  let array_value = set.add_param(I32)
  array_set(set, 4, array_reference, array_index, array_value)
  set.return_([])

  let copy = @milkir.FunctionBuilder::FunctionBuilder("bad_array_copy")
  let destination = copy.add_param(Ref)
  let destination_offset = copy.add_param(I32)
  let source = copy.add_param(Ref)
  let source_offset = copy.add_param(I32)
  let count = copy.add_param(I32)
  array_copy(
    copy, 4, 5, destination, destination_offset, source, source_offset, count,
  )
  copy.return_([])

  debug_inspect(
    [
      contextual_error_for(get),
      contextual_error_for(packed),
      contextual_error_for(set),
      contextual_error_for(copy),
    ],
    content=(
      #|[
      #|  UnverifiableInstruction(message="malformed contextual Wasm MilkIR extension 'struct_get': field 0 of struct type 3 has carrier i64, got f64"),
      #|  UnverifiableInstruction(message="malformed contextual Wasm MilkIR extension 'struct_get_s': field 1 of struct type 3 has packed width Some(1), got Some(2)"),
      #|  UnverifiableInstruction(message="malformed contextual Wasm MilkIR extension 'array_set': array type 4 has element carrier f64, got i32"),
      #|  UnverifiableInstruction(message="malformed contextual Wasm MilkIR extension 'array_copy': array element storage mismatch between destination type 4 and source type 5"),
      #|]
    ),
  )
}

///|
test "contextual Wasm validation rejects invalid indices and exception payloads" {
  let memory = @milkir.FunctionBuilder::FunctionBuilder("bad_memory")
  let vmctx = memory.add_param(I64)
  load_mem_base(memory, vmctx, 4, Mutable) |> ignore
  memory.return_([])

  let function_reference = @milkir.FunctionBuilder::FunctionBuilder(
    "bad_function_reference",
  )
  get_func_ref(function_reference, 99) |> ignore
  function_reference.return_([])

  let segment = @milkir.FunctionBuilder::FunctionBuilder("bad_segment")
  let offset = segment.add_param(I32)
  let length = segment.add_param(I32)
  array_new_data(segment, 4, 8, offset, length) |> ignore
  segment.return_([])

  let element = @milkir.FunctionBuilder::FunctionBuilder("bad_element_segment")
  let element_offset = element.add_param(I32)
  let element_length = element.add_param(I32)
  array_new_elem(element, 4, 0, element_offset, element_length) |> ignore
  element.return_([])

  let thrown = @milkir.FunctionBuilder::FunctionBuilder("bad_throw")
  let payload = thrown.add_param(I64)
  emit_throw(thrown, 0, [payload])
  thrown.return_([])

  let reference_type = @milkir.FunctionBuilder::FunctionBuilder(
    "bad_reference_type",
  )
  let reference_value = reference_type.add_param(Ref)
  ref_cast(reference_type, 99, false, reference_value, Ref) |> ignore
  reference_type.return_([])

  debug_inspect(
    [
      contextual_error_for(memory),
      contextual_error_for(function_reference),
      contextual_error_for(segment),
      contextual_error_for(element),
      contextual_error_for(thrown),
      contextual_error_for(reference_type),
    ],
    content=(
      #|[
      #|  UnverifiableInstruction(message="malformed contextual Wasm MilkIR extension 'memory_base': unknown memory index 4"),
      #|  UnverifiableInstruction(message="malformed contextual Wasm MilkIR extension 'get_func_ref': unknown linked function index 99"),
      #|  UnverifiableInstruction(message="malformed contextual Wasm MilkIR extension 'array_new_data': unknown data segment index 8"),
      #|  UnverifiableInstruction(message="malformed contextual Wasm MilkIR extension 'array_new_elem': element segment 0 has carrier ref, expected f64"),
      #|  UnverifiableInstruction(message="malformed contextual Wasm MilkIR extension 'throw': tag index 0 expects values [i32, f64], got [i64]"),
      #|  UnverifiableInstruction(message="malformed contextual Wasm MilkIR extension 'ref_cast': unknown type index 99"),
      #|]
    ),
  )
}

///|
test "contextual Wasm validation accepts built-in abstract heap types" {
  let builder = @milkir.FunctionBuilder::FunctionBuilder("abstract_ref_cast")
  let reference = builder.add_param(Ref)
  builder.add_result(Ref)
  let cast = ref_cast(builder, -1, true, reference, Ref)
  builder.return_([cast])
  verify_function_with_context(
    builder.get_function(),
    WasmValidationContext::empty(),
  )
}
