///|
fn test_environment() -> Environment {
  let runtime_symbols = @wasm_milkir.RuntimeSymbols::with_runtime_prefix(
    "wasm.runtime",
  )
  Environment::new(
    fn(index) { @machv.CodeSymbol::new("wasm.function.\{index}") },
    fn(index) {
      @machv.EnvironmentField::new("wasm.memory.\{index}.base", Ptr64)
    },
    @machv.EnvironmentField::new("wasm.function_table", Ptr64),
    fn(index) {
      @machv.EnvironmentField::new("wasm.table.\{index}.base", Ptr64)
    },
    fn(index) { index + 100 },
    fn(helper) {
      @machv.ExternalSymbol::new(runtime_symbols.symbol_name(helper))
    },
  )
}

///|
fn test_field(
  storage : @wasm_milkir.WasmStorageContract,
  mutable_? : Bool = true,
) -> @wasm_milkir.WasmFieldContract {
  { storage, mutable_, defaultable: true }
}

///|
fn test_validation_context(name : String) -> @wasm_milkir.WasmValidationContext {
  @wasm_milkir.WasmValidationContext::new({
    function_contract: fn(index) {
      match (name, index) {
        ("caller", 7) => Some({ params: [I32], results: [I64] })
        ("tail_caller", 4) => Some({ params: [Ref], results: [I64] })
        ("function_reference", 5) => Some({ params: [], results: [] })
        _ => None
      }
    },
    defined_type_contract: fn(index) {
      match (name, index) {
        ("reference_caller", 2) =>
          Some(Function({ params: [I32], results: [I32] }))
        ("gc_reference_queries", 7) => Some(Array(test_field(Value(Ref))))
        ("gc_aggregate_access", 2) =>
          Some(
            Struct([
              test_field(Value(I32)),
              test_field(Value(I32)),
              test_field(Value(I32)),
              test_field(Value(F64)),
              test_field(Value(Ref)),
              test_field(Packed8),
              test_field(Packed16),
            ]),
          )
        ("gc_aggregate_access", 9) => Some(Array(test_field(Value(F32))))
        ("gc_aggregate_access", 10) => Some(Array(test_field(Value(I32))))
        ("gc_v128_field", 2) =>
          Some(
            Struct([
              test_field(Value(I32)),
              test_field(Value(I32)),
              test_field(Value(I32)),
              test_field(Value(V128)),
            ]),
          )
        ("gc_array_bulk", 3) | ("gc_array_bulk", 4) =>
          Some(Array(test_field(Value(F32))))
        ("gc_allocations", 4) => Some(Array(test_field(Value(Ref))))
        ("gc_allocations", 5) => Some(Array(test_field(Value(I32))))
        ("gc_allocations", 8) => Some(Struct([]))
        ("gc_segments", 2) => Some(Array(test_field(Value(I32))))
        ("gc_segments", 4) => Some(Array(test_field(Value(Ref))))
        ("gc_fixed_allocations", 6) =>
          Some(
            Struct([
              test_field(Value(I32)),
              test_field(Value(F64)),
              test_field(Value(Ref)),
            ]),
          )
        ("gc_fixed_allocations", 7) => Some(Array(test_field(Value(Ref))))
        ("gc_v128_allocation", 1) => Some(Struct([test_field(Value(V128))]))
        ("indirect_table64", 3) =>
          Some(Function({ params: [I32], results: [I64] }))
        ("indirect_tail", 1) =>
          Some(Function({ params: [Ref], results: [I64] }))
        _ => None
      }
    },
    table_contract: fn(index) {
      match (name, index) {
        ("indirect_table64", 2) =>
          Some({ index_type: I64, element_type: CallableRef })
        ("indirect_tail", 0) =>
          Some({ index_type: I32, element_type: CallableRef })
        _ => None
      }
    },
    tag_contract: fn(index) {
      if name == "exception_throw" && index == 9 {
        Some({ params: [I64, Ref], results: [] })
      } else {
        None
      }
    },
    memory_exists: fn(index) { name == "memory_base" && index == 3 },
    data_segment_exists: fn(index) { name == "gc_segments" && index == 3 },
    element_segment_type: fn(index) {
      if name == "gc_segments" && index == 5 {
        Some(Ref)
      } else {
        None
      }
    },
  })
}

///|
fn lower_test_function(
  function : @milkir.Function,
) -> @machv.Function raise @milkir_machv.SemanticLowerError {
  lower_function(
    function,
    test_validation_context(function.name),
    test_environment(),
  )
}

///|
test "direct Wasm calls carry the explicit execution environment" {
  let builder = @milkir.FunctionBuilder::FunctionBuilder("caller")
  builder.add_param(I64) |> ignore
  let argument = builder.add_param(I32)
  builder.add_result(I64)
  let results = builder.emit_multi_ext_inst(
    [I64],
    @wasm_milkir.encode(WasmCall(7)),
    [argument],
  )
  builder.return_(results)
  inspect(
    lower_test_function(builder.finalize()),
    content=(
      #|machv caller [internal](v0:ptr64, v1:i32) -> (i64) {
      #|block0:
      #|  v2:i64 = call internal @wasm.function.7 (ptr64, i32) -> (i64) [internal] v0, v1 [memory=read-write, trap, unwind, gc-safepoint, cancel-safepoint]
      #|  return v2
      #|}
    ),
  )
}

///|
test "contextual Wasm errors stop lowering before instruction selection" {
  let builder = @milkir.FunctionBuilder::FunctionBuilder("caller")
  builder.add_param(I64) |> ignore
  let argument = builder.add_param(I32)
  builder.add_result(F64)
  let results = builder.emit_multi_ext_inst(
    [F64],
    @wasm_milkir.encode(WasmCall(7)),
    [argument],
  )
  builder.return_(results)
  try
    lower_function(
      builder.finalize(),
      test_validation_context("caller"),
      test_environment(),
    )
    |> ignore
  catch {
    error =>
      debug_inspect(
        error,
        content=(
          #|InvalidMilkIR(message="UnverifiableInstruction(message=\"malformed contextual Wasm MilkIR extension 'call': expected call results [i64], got [f64]\")")
        ),
      )
  } noraise {
    _ => fail("expected contextual validation to stop Wasm lowering")
  }
}

///|
test "direct Wasm tail calls replace the source placeholder terminator" {
  let builder = @milkir.FunctionBuilder::FunctionBuilder("tail_caller")
  builder.add_param(I64) |> ignore
  let argument = builder.add_param(Ref)
  builder.add_result(I64)
  builder.emit_void_ext_inst(@wasm_milkir.encode(ReturnCall(4)), [argument])
  builder.trap("unreachable after return_call")
  inspect(
    lower_test_function(builder.finalize()),
    content=(
      #|machv tail_caller [internal](v0:ptr64, v1:gcref64) -> (i64) {
      #|block0:
      #|  tail_call internal @wasm.function.4 (ptr64, gcref64) -> (i64) [internal] (v0, v1) [memory=read-write, trap, unwind, gc-safepoint, cancel-safepoint] roots=[v1]
      #|}
    ),
  )
}

///|
test "call_ref exposes tagged-reference removal before an indirect call" {
  let builder = @milkir.FunctionBuilder::FunctionBuilder("reference_caller")
  builder.add_param(I64) |> ignore
  let callee = builder.add_param(CallableRef)
  let argument = builder.add_param(I32)
  builder.add_result(I32)
  let results = builder.emit_multi_ext_inst(
    [I32],
    @wasm_milkir.encode(CallRef(2)),
    [callee, argument],
  )
  builder.return_(results)
  inspect(
    lower_test_function(builder.finalize()),
    content=(
      #|machv reference_caller [internal](v0:ptr64, v1:gcref64, v2:i32) -> (i32) {
      #|block0:
      #|  v3:ptr64 = gcref.address v1
      #|  v4:i64 = convert.Bitcast(Ptr64, I64) v3
      #|  v5:i64 = i64.const 16140901064495857663
      #|  v6:i64 = int.binary.And v4, v5
      #|  v7:ptr64 = convert.Bitcast(I64, Ptr64) v6
      #|  v8:i32 = call indirect (ptr64, i32) -> (i32) [internal] v7, v0, v2 [memory=read-write, trap, unwind, gc-safepoint, cancel-safepoint] roots=[v1]
      #|  return v8
      #|}
    ),
  )
}

///|
test "reference primitives preserve explicit target-neutral representation" {
  let builder = @milkir.FunctionBuilder::FunctionBuilder("reference_primitives")
  builder.add_param(I64) |> ignore
  let integer = builder.add_param(I32)
  let left = builder.add_param(Ref)
  let right = builder.add_param(Ref)
  builder.add_result(Ref)
  builder.add_result(I32)
  let i31 = builder.emit_ext_inst(Ref, @wasm_milkir.encode(I31New), [integer])
  let equal = builder.emit_ext_inst(I32, @wasm_milkir.encode(RefEq), [
    left, right,
  ])
  builder.return_([i31, equal])
  inspect(
    lower_test_function(builder.finalize()),
    content=(
      #|machv reference_primitives [internal](v0:ptr64, v1:i32, v2:gcref64, v3:gcref64) -> (gcref64, i32) {
      #|block0:
      #|  v4:i64 = convert.I64ExtendI32(Unsigned) v1
      #|  v5:i64 = i64.const 1
      #|  v6:i64 = int.binary.ShiftLeft v4, v5
      #|  v7:i64 = int.binary.Or v6, v5
      #|  v8:gcref64 = gcref.from_bits v7
      #|  v9:i32 = reference.compare.Equal v2, v3
      #|  return v8, v9
      #|}
    ),
  )
}

///|
test "GC reference queries use typed non-safepoint runtime calls" {
  let builder = @milkir.FunctionBuilder::FunctionBuilder("gc_reference_queries")
  builder.add_param(I64) |> ignore
  let reference = builder.add_param(Ref)
  builder.add_result(I32)
  builder.add_result(Ref)
  builder.add_result(I32)
  let matches = @wasm_milkir.ref_test(builder, 7, true, reference)
  let cast = @wasm_milkir.ref_cast(builder, 7, false, reference, Ref)
  let length = @wasm_milkir.array_len(builder, reference)
  builder.return_([matches, cast, length])
  inspect(
    lower_test_function(builder.finalize()),
    content=(
      #|machv gc_reference_queries [internal](v0:ptr64, v1:gcref64) -> (i32, gcref64, i32) {
      #|block0:
      #|  v2:i32 = i32.const 7
      #|  v3:i32 = i32.const 1
      #|  v4:i32 = call external @wasm.runtime.gc.ref_test (gcref64, i32, i32) -> (i32) [platform] v1, v2, v3 [memory=read]
      #|  v5:i32 = i32.const 7
      #|  v6:i32 = i32.const 0
      #|  v7:gcref64 = call external @wasm.runtime.gc.ref_cast (gcref64, i32, i32) -> (gcref64) [platform] v1, v5, v6 [memory=read, trap]
      #|  v8:i32 = call external @wasm.runtime.gc.array_len (gcref64) -> (i32) [platform] v1 [memory=read, trap]
      #|  return v4, v7, v8
      #|}
    ),
  )
}

///|
test "GC aggregate access converts the explicit runtime word ABI" {
  let builder = @milkir.FunctionBuilder::FunctionBuilder("gc_aggregate_access")
  builder.add_param(I64) |> ignore
  let reference = builder.add_param(Ref)
  let index = builder.add_param(I32)
  let float_value = builder.add_param(F64)
  let integer_value = builder.add_param(I32)
  builder.add_result(F64)
  builder.add_result(Ref)
  builder.add_result(I32)
  builder.add_result(I32)
  builder.add_result(F32)
  let float_field = @wasm_milkir.struct_get(builder, 2, 3, reference, F64)
  let reference_field = @wasm_milkir.struct_get(builder, 2, 4, reference, Ref)
  let signed_field = @wasm_milkir.struct_get_s(builder, 2, 5, reference, 1)
  let unsigned_field = @wasm_milkir.struct_get_u(builder, 2, 6, reference, 2)
  @wasm_milkir.struct_set(builder, 2, 3, reference, float_value)
  let float_element = @wasm_milkir.array_get(builder, 9, reference, index, F32)
  @wasm_milkir.array_set(builder, 10, reference, index, integer_value)
  builder.return_([
    float_field, reference_field, signed_field, unsigned_field, float_element,
  ])
  inspect(
    lower_test_function(builder.finalize()),
    content=(
      #|machv gc_aggregate_access [internal](v0:ptr64, v1:gcref64, v2:i32, v3:f64, v4:i32) -> (f64, gcref64, i32, i32, f32) {
      #|block0:
      #|  v5:i32 = i32.const 2
      #|  v6:i32 = i32.const 3
      #|  v7:i64 = call external @wasm.runtime.gc.struct_get (gcref64, i32, i32) -> (i64) [platform] v1, v5, v6 [memory=read, trap]
      #|  v8:f64 = convert.Bitcast(I64, F64) v7
      #|  v9:i32 = i32.const 2
      #|  v10:i32 = i32.const 4
      #|  v11:i64 = call external @wasm.runtime.gc.struct_get (gcref64, i32, i32) -> (i64) [platform] v1, v9, v10 [memory=read, trap]
      #|  v12:gcref64 = gcref.from_bits v11
      #|  v13:i32 = i32.const 2
      #|  v14:i32 = i32.const 5
      #|  v15:i64 = call external @wasm.runtime.gc.struct_get (gcref64, i32, i32) -> (i64) [platform] v1, v13, v14 [memory=read, trap]
      #|  v16:i32 = convert.I32WrapI64 v15
      #|  v17:i32 = convert.SignExtend(I32, W8) v16
      #|  v18:i32 = i32.const 2
      #|  v19:i32 = i32.const 6
      #|  v20:i64 = call external @wasm.runtime.gc.struct_get (gcref64, i32, i32) -> (i64) [platform] v1, v18, v19 [memory=read, trap]
      #|  v21:i32 = convert.I32WrapI64 v20
      #|  v22:i32 = i32.const 65535
      #|  v23:i32 = int.binary.And v21, v22
      #|  v24:i64 = convert.Bitcast(F64, I64) v3
      #|  v25:i32 = i32.const 2
      #|  v26:i32 = i32.const 3
      #|  call external @wasm.runtime.gc.struct_set (gcref64, i32, i32, i64) -> () [platform] v1, v25, v26, v24 [memory=read-write, trap]
      #|  v27:i32 = i32.const 9
      #|  v28:i64 = call external @wasm.runtime.gc.array_get (gcref64, i32, i32) -> (i64) [platform] v1, v27, v2 [memory=read, trap]
      #|  v29:i32 = convert.I32WrapI64 v28
      #|  v30:f32 = convert.Bitcast(I32, F32) v29
      #|  v31:i64 = convert.I64ExtendI32(Unsigned) v4
      #|  v32:i32 = i32.const 10
      #|  call external @wasm.runtime.gc.array_set (gcref64, i32, i32, i64) -> () [platform] v1, v32, v2, v31 [memory=read-write, trap]
      #|  return v8, v12, v17, v23, v30
      #|}
    ),
  )
}

///|
test "GC aggregate access rejects values wider than the runtime ABI" {
  let builder = @milkir.FunctionBuilder::FunctionBuilder("gc_v128_field")
  builder.add_param(I64) |> ignore
  let reference = builder.add_param(Ref)
  builder.add_result(V128)
  let result = @wasm_milkir.struct_get(builder, 2, 3, reference, V128)
  builder.return_([result])
  try lower_test_function(builder.finalize()) |> ignore catch {
    error =>
      inspect(
        error,
        content=(
          #|UnsupportedOperation(
          #|  block_id=0,
          #|  instruction_id=0,
          #|  message="the current Wasm GC runtime ABI cannot return a v128 aggregate value",
          #|)
        ),
      )
  }
}

///|
test "GC array bulk mutation preserves value encoding and effects" {
  let builder = @milkir.FunctionBuilder::FunctionBuilder("gc_array_bulk")
  builder.add_param(I64) |> ignore
  let destination = builder.add_param(Ref)
  let source = builder.add_param(Ref)
  let destination_offset = builder.add_param(I32)
  let source_offset = builder.add_param(I32)
  let count = builder.add_param(I32)
  let fill_value = builder.add_param(F32)
  @wasm_milkir.array_fill(
    builder, 3, destination, destination_offset, fill_value, count,
  )
  @wasm_milkir.array_copy(
    builder, 3, 4, destination, destination_offset, source, source_offset, count,
  )
  builder.return_([])
  inspect(
    lower_test_function(builder.finalize()),
    content=(
      #|machv gc_array_bulk [internal](v0:ptr64, v1:gcref64, v2:gcref64, v3:i32, v4:i32, v5:i32, v6:f32) -> () {
      #|block0:
      #|  v7:i32 = convert.Bitcast(F32, I32) v6
      #|  v8:i64 = convert.I64ExtendI32(Unsigned) v7
      #|  call external @wasm.runtime.gc.array_fill (gcref64, i32, i64, i32) -> () [platform] v1, v3, v8, v5 [memory=read-write, trap]
      #|  call external @wasm.runtime.gc.array_copy (gcref64, i32, gcref64, i32, i32) -> () [platform] v1, v3, v2, v4, v5 [memory=read-write, trap]
      #|  return
      #|}
    ),
  )
}

///|
test "GC allocation calls expose precise roots without a source-level safepoint id" {
  let builder = @milkir.FunctionBuilder::FunctionBuilder("gc_allocations")
  builder.add_param(I64) |> ignore
  let initial = builder.add_param(Ref)
  let length = builder.add_param(I32)
  builder.add_result(Ref)
  builder.add_result(Ref)
  builder.add_result(Ref)
  let array = @wasm_milkir.array_new(builder, 4, initial, length)
  let default_array = @wasm_milkir.array_new_default(builder, 5, length)
  let structure = @wasm_milkir.struct_new_default(builder, 8)
  builder.return_([array, default_array, structure])
  inspect(
    lower_test_function(builder.finalize()),
    content=(
      #|machv gc_allocations [internal](v0:ptr64, v1:gcref64, v2:i32) -> (gcref64, gcref64, gcref64) {
      #|block0:
      #|  v3:ptr64 = gcref.address v1
      #|  v4:i64 = convert.Bitcast(Ptr64, I64) v3
      #|  v5:i32 = i32.const 4
      #|  v6:i64 = call external @wasm.runtime.gc.alloc_array_slow (ptr64, i32, i32, i64) -> (i64) [platform] v0, v5, v2, v4 [memory=read-write, trap, gc-safepoint] roots=[v1]
      #|  v7:gcref64 = gcref.from_bits v6
      #|  v8:i64 = i64.const 0
      #|  v9:i32 = i32.const 5
      #|  v10:i64 = call external @wasm.runtime.gc.alloc_array_slow (ptr64, i32, i32, i64) -> (i64) [platform] v0, v9, v2, v8 [memory=read-write, trap, gc-safepoint] roots=[v7]
      #|  v11:gcref64 = gcref.from_bits v10
      #|  v12:i32 = i32.const 8
      #|  v13:ptr64 = ptr.null
      #|  v14:i32 = i32.const 0
      #|  v15:i64 = call external @wasm.runtime.gc.alloc_struct_slow (ptr64, i32, ptr64, i32) -> (i64) [platform] v0, v12, v13, v14 [memory=read-write, trap, gc-safepoint] roots=[v7, v11]
      #|  v16:gcref64 = gcref.from_bits v15
      #|  return v7, v11, v16
      #|}
    ),
  )
}

///|
test "GC segment array operations keep segment identities and allocation roots" {
  let builder = @milkir.FunctionBuilder::FunctionBuilder("gc_segments")
  builder.add_param(I64) |> ignore
  let offset = builder.add_param(I32)
  let length = builder.add_param(I32)
  builder.add_result(Ref)
  builder.add_result(Ref)
  let data_array = @wasm_milkir.array_new_data(builder, 2, 3, offset, length)
  let elem_array = @wasm_milkir.array_new_elem(builder, 4, 5, offset, length)
  @wasm_milkir.array_init_data(
    builder, 2, 3, data_array, offset, offset, length,
  )
  @wasm_milkir.array_init_elem(
    builder, 4, 5, elem_array, offset, offset, length,
  )
  builder.return_([data_array, elem_array])
  inspect(
    lower_test_function(builder.finalize()),
    content=(
      #|machv gc_segments [internal](v0:ptr64, v1:i32, v2:i32) -> (gcref64, gcref64) {
      #|block0:
      #|  v3:i32 = i32.const 2
      #|  v4:i32 = i32.const 3
      #|  v5:i64 = call external @wasm.runtime.gc.array_new_data (ptr64, i32, i32, i32, i32) -> (i64) [platform] v0, v3, v4, v1, v2 [memory=read-write, trap, gc-safepoint]
      #|  v6:gcref64 = gcref.from_bits v5
      #|  v7:i32 = i32.const 4
      #|  v8:i32 = i32.const 5
      #|  v9:i64 = call external @wasm.runtime.gc.array_new_elem (ptr64, i32, i32, i32, i32) -> (i64) [platform] v0, v7, v8, v1, v2 [memory=read-write, trap, gc-safepoint] roots=[v6]
      #|  v10:gcref64 = gcref.from_bits v9
      #|  v11:i32 = i32.const 2
      #|  v12:i32 = i32.const 3
      #|  call external @wasm.runtime.gc.array_init_data (ptr64, i32, i32, gcref64, i32, i32, i32) -> () [platform] v0, v11, v12, v6, v1, v1, v2 [memory=read-write, trap]
      #|  v13:i32 = i32.const 4
      #|  v14:i32 = i32.const 5
      #|  call external @wasm.runtime.gc.array_init_elem (ptr64, i32, i32, gcref64, i32, i32, i32) -> () [platform] v0, v13, v14, v10, v1, v1, v2 [memory=read-write, trap]
      #|  return v6, v10
      #|}
    ),
  )
}

///|
test "GC fixed allocations use typed address-visible value buffers" {
  let builder = @milkir.FunctionBuilder::FunctionBuilder("gc_fixed_allocations")
  builder.add_param(I64) |> ignore
  let integer = builder.add_param(I32)
  let float = builder.add_param(F64)
  let reference = builder.add_param(Ref)
  builder.add_result(Ref)
  builder.add_result(Ref)
  let structure = @wasm_milkir.struct_new(builder, 6, [
    integer, float, reference,
  ])
  let array = @wasm_milkir.array_new_fixed(builder, 7, 2, [reference, reference])
  builder.return_([structure, array])
  inspect(
    lower_test_function(builder.finalize()),
    content=(
      #|machv gc_fixed_allocations [internal](v0:ptr64, v1:i32, v2:f64, v3:gcref64) -> (gcref64, gcref64) {
      #|stack0: size=24, alignment=16
      #|stack1: size=16, alignment=16
      #|block0:
      #|  v4:ptr64 = stack.address stack0
      #|  v5:i64 = convert.I64ExtendI32(Unsigned) v1
      #|  store {
      #|  width: W64,
      #|  value_type: I64,
      #|  offset: 0,
      #|  endianness: Little,
      #|  trap: None,
      #|} v4, v5 [memory=write]
      #|  v6:i64 = convert.Bitcast(F64, I64) v2
      #|  store {
      #|  width: W64,
      #|  value_type: I64,
      #|  offset: 8,
      #|  endianness: Little,
      #|  trap: None,
      #|} v4, v6 [memory=write]
      #|  v7:ptr64 = gcref.address v3
      #|  v8:i64 = convert.Bitcast(Ptr64, I64) v7
      #|  store {
      #|  width: W64,
      #|  value_type: I64,
      #|  offset: 16,
      #|  endianness: Little,
      #|  trap: None,
      #|} v4, v8 [memory=write]
      #|  v9:i32 = i32.const 6
      #|  v10:i32 = i32.const 3
      #|  v11:i64 = call external @wasm.runtime.gc.alloc_struct_slow (ptr64, i32, ptr64, i32) -> (i64) [platform] v0, v9, v4, v10 [memory=read-write, trap, gc-safepoint] roots=[v3]
      #|  v12:gcref64 = gcref.from_bits v11
      #|  v13:ptr64 = stack.address stack1
      #|  v14:ptr64 = gcref.address v3
      #|  v15:i64 = convert.Bitcast(Ptr64, I64) v14
      #|  store {
      #|  width: W64,
      #|  value_type: I64,
      #|  offset: 0,
      #|  endianness: Little,
      #|  trap: None,
      #|} v13, v15 [memory=write]
      #|  v16:ptr64 = gcref.address v3
      #|  v17:i64 = convert.Bitcast(Ptr64, I64) v16
      #|  store {
      #|  width: W64,
      #|  value_type: I64,
      #|  offset: 8,
      #|  endianness: Little,
      #|  trap: None,
      #|} v13, v17 [memory=write]
      #|  v18:i32 = i32.const 7
      #|  v19:i32 = i32.const 2
      #|  v20:i64 = call external @wasm.runtime.gc.alloc_array_from_values_slow (ptr64, i32, ptr64, i32) -> (i64) [platform] v0, v18, v13, v19 [memory=read-write, trap, gc-safepoint] roots=[v3, v12]
      #|  v21:gcref64 = gcref.from_bits v20
      #|  return v12, v21
      #|}
    ),
  )
}

///|
test "GC fixed allocation rejects values wider than one runtime word" {
  let builder = @milkir.FunctionBuilder::FunctionBuilder("gc_v128_allocation")
  builder.add_param(I64) |> ignore
  let vector = builder.add_param(V128)
  builder.add_result(Ref)
  let result = @wasm_milkir.struct_new(builder, 1, [vector])
  builder.return_([result])
  try lower_test_function(builder.finalize()) |> ignore catch {
    error =>
      inspect(
        error,
        content=(
          #|UnsupportedOperation(
          #|  block_id=0,
          #|  instruction_id=0,
          #|  message="the current Wasm GC runtime ABI cannot allocate v128 aggregate values",
          #|)
        ),
      )
  }
}

///|
test "i31 get uses explicit null-trap control flow" {
  let builder = @milkir.FunctionBuilder::FunctionBuilder("i31_get")
  builder.add_param(I64) |> ignore
  let reference = builder.add_param(Ref)
  builder.add_result(I32)
  let result = builder.emit_ext_inst(I32, @wasm_milkir.encode(I31GetS), [
    reference,
  ])
  builder.return_([result])
  inspect(
    lower_test_function(builder.finalize()),
    content=(
      #|machv i31_get [internal](v0:ptr64, v1:gcref64) -> (i32) {
      #|block0:
      #|  v2:gcref64 = gcref.null
      #|  v3:i32 = reference.compare.Equal v1, v2
      #|  branch v3, block1, block2
      #|block1:
      #|  trap NullReference
      #|block2:
      #|  v4:ptr64 = gcref.address v1
      #|  v5:i64 = convert.Bitcast(Ptr64, I64) v4
      #|  v6:i64 = i64.const 1
      #|  v7:i64 = int.binary.UnsignedShiftRight v5, v6
      #|  v8:i32 = convert.I32WrapI64 v7
      #|  v9:i32 = i32.const 1
      #|  v10:i32 = int.binary.ShiftLeft v8, v9
      #|  v11:i32 = int.binary.SignedShiftRight v10, v9
      #|  return v11
      #|}
    ),
  )
}

///|
test "memory base access preserves stable field identity in semantic MachV" {
  let builder = @milkir.FunctionBuilder::FunctionBuilder("memory_base")
  let vmctx = builder.add_param(I64)
  builder.add_result(I64)
  builder.add_result(I64)
  let first = @wasm_milkir.load_mem_base(builder, vmctx, 3, Stable)
  let second = @wasm_milkir.load_mem_base(builder, vmctx, 3, Stable)
  builder.return_([first, second])
  inspect(
    lower_test_function(builder.finalize()),
    content=(
      #|machv memory_base [internal](v0:ptr64) -> (i64, i64) {
      #|block0:
      #|  v1:ptr64 = environment.field.stable @wasm.memory.3.base v0 [memory=read]
      #|  v2:i64 = convert.Bitcast(Ptr64, I64) v1
      #|  v3:ptr64 = environment.field.stable @wasm.memory.3.base v0 [memory=read]
      #|  v4:i64 = convert.Bitcast(Ptr64, I64) v3
      #|  return v2, v4
      #|}
    ),
  )
}

///|
test "function references use explicit table access and tagging" {
  let builder = @milkir.FunctionBuilder::FunctionBuilder("function_reference")
  builder.add_param(I64) |> ignore
  builder.add_result(CallableRef)
  let reference = builder.emit_ext_inst(
    CallableRef,
    @wasm_milkir.encode(GetFuncRef(5)),
    [],
  )
  builder.return_([reference])
  inspect(
    lower_test_function(builder.finalize()),
    content=(
      #|machv function_reference [internal](v0:ptr64) -> (gcref64) {
      #|block0:
      #|  v1:ptr64 = environment.field @wasm.function_table v0 [memory=read]
      #|  v2:i64 = i64.const 40
      #|  v3:ptr64 = pointer.offset v1, v2
      #|  v4:ptr64 = load {
      #|  width: W64,
      #|  extension: None,
      #|  result_type: Ptr64,
      #|  offset: 0,
      #|  endianness: Little,
      #|  trap: None,
      #|} v3 [memory=read]
      #|  v5:i64 = convert.Bitcast(Ptr64, I64) v4
      #|  v6:i64 = i64.const 2305843009213693952
      #|  v7:i64 = int.binary.Or v5, v6
      #|  v8:gcref64 = gcref.from_bits v7
      #|  return v8
      #|}
    ),
  )
}

///|
test "table64 indirect calls preserve index width and subtype checks" {
  let builder = @milkir.FunctionBuilder::FunctionBuilder("indirect_table64")
  builder.add_param(I64) |> ignore
  let index = builder.add_param(I64)
  let argument = builder.add_param(I32)
  builder.add_result(I64)
  let results = builder.emit_multi_ext_inst(
    [I64],
    @wasm_milkir.encode(WasmCallIndirect(3, 2)),
    [index, argument],
  )
  builder.return_(results)
  inspect(
    lower_test_function(builder.finalize()),
    content=(
      #|machv indirect_table64 [internal](v0:ptr64, v1:i64, v2:i32) -> (i64) {
      #|block0:
      #|  v3:i64 = i64.const 4
      #|  v4:i64 = int.binary.ShiftLeft v1, v3
      #|  v5:ptr64 = environment.field @wasm.table.2.base v0 [memory=read]
      #|  v6:ptr64 = pointer.offset v5, v4
      #|  v7:ptr64 = load {
      #|  width: W64,
      #|  extension: None,
      #|  result_type: Ptr64,
      #|  offset: 0,
      #|  endianness: Little,
      #|  trap: None,
      #|} v6 [memory=read]
      #|  v8:i32 = load {
      #|  width: W32,
      #|  extension: None,
      #|  result_type: I32,
      #|  offset: 8,
      #|  endianness: Little,
      #|  trap: None,
      #|} v6 [memory=read]
      #|  v9:i32 = i32.const 103
      #|  v10:i32 = int.compare.Equal v8, v9
      #|  branch v10, block2, block1
      #|block1:
      #|  call external @wasm.runtime.gc.type_check_subtype (i32, i32) -> () [platform] v8, v9 [memory=read, trap]
      #|  jump block2
      #|block2:
      #|  v11:i64 = convert.Bitcast(Ptr64, I64) v7
      #|  v12:i64 = i64.const 16140901064495857663
      #|  v13:i64 = int.binary.And v11, v12
      #|  v14:ptr64 = convert.Bitcast(I64, Ptr64) v13
      #|  v15:i64 = call indirect (ptr64, i32) -> (i64) [internal] v14, v0, v2 [memory=read-write, trap, unwind, gc-safepoint, cancel-safepoint]
      #|  return v15
      #|}
    ),
  )
}

///|
test "indirect tail calls preserve roots and replace placeholder traps" {
  let builder = @milkir.FunctionBuilder::FunctionBuilder("indirect_tail")
  builder.add_param(I64) |> ignore
  let index = builder.add_param(I32)
  let argument = builder.add_param(Ref)
  builder.add_result(I64)
  builder.emit_void_ext_inst(@wasm_milkir.encode(ReturnCallIndirect(1, 0)), [
    index, argument,
  ])
  builder.trap("unreachable after return_call_indirect")
  inspect(
    lower_test_function(builder.finalize()),
    content=(
      #|machv indirect_tail [internal](v0:ptr64, v1:i32, v2:gcref64) -> (i64) {
      #|block0:
      #|  v3:i64 = convert.I64ExtendI32(Unsigned) v1
      #|  v4:i64 = i64.const 4
      #|  v5:i64 = int.binary.ShiftLeft v3, v4
      #|  v6:ptr64 = environment.field @wasm.table.0.base v0 [memory=read]
      #|  v7:ptr64 = pointer.offset v6, v5
      #|  v8:ptr64 = load {
      #|  width: W64,
      #|  extension: None,
      #|  result_type: Ptr64,
      #|  offset: 0,
      #|  endianness: Little,
      #|  trap: None,
      #|} v7 [memory=read]
      #|  v9:i32 = load {
      #|  width: W32,
      #|  extension: None,
      #|  result_type: I32,
      #|  offset: 8,
      #|  endianness: Little,
      #|  trap: None,
      #|} v7 [memory=read]
      #|  v10:i32 = i32.const 101
      #|  v11:i32 = int.compare.Equal v9, v10
      #|  branch v11, block2, block1
      #|block1:
      #|  call external @wasm.runtime.gc.type_check_subtype (i32, i32) -> () [platform] v9, v10 [memory=read, trap]
      #|  jump block2
      #|block2:
      #|  v12:i64 = convert.Bitcast(Ptr64, I64) v8
      #|  v13:i64 = i64.const 16140901064495857663
      #|  v14:i64 = int.binary.And v12, v13
      #|  v15:ptr64 = convert.Bitcast(I64, Ptr64) v14
      #|  tail_call indirect (ptr64, gcref64) -> (i64) [internal] (v15, v0, v2) [memory=read-write, trap, unwind, gc-safepoint, cancel-safepoint] roots=[v2]
      #|}
    ),
  )
}

///|
test "exception queries use typed runtime capabilities" {
  let builder = @milkir.FunctionBuilder::FunctionBuilder("exception_queries")
  builder.add_param(I64) |> ignore
  builder.add_result(I32)
  builder.add_result(I64)
  builder.add_result(I32)
  let tag = builder.emit_ext_inst(I32, @wasm_milkir.encode(GetExceptionTag), [])
  let value = builder.emit_ext_inst(
    I64,
    @wasm_milkir.encode(GetExceptionValue(2)),
    [],
  )
  let count = builder.emit_ext_inst(
    I32,
    @wasm_milkir.encode(GetExceptionValueCount),
    [],
  )
  builder.return_([tag, value, count])
  inspect(
    lower_test_function(builder.finalize()),
    content=(
      #|machv exception_queries [internal](v0:ptr64) -> (i32, i64, i32) {
      #|block0:
      #|  v1:i32 = call external @wasm.runtime.exception.get_tag (ptr64) -> (i32) [platform] v0 [memory=read]
      #|  v2:i32 = i32.const 2
      #|  v3:i64 = call external @wasm.runtime.exception.get_value (ptr64, i32) -> (i64) [platform] v0, v2 [memory=read]
      #|  v4:i32 = call external @wasm.runtime.exception.get_value_count (ptr64) -> (i32) [platform] v0 [memory=read]
      #|  return v1, v3, v4
      #|}
    ),
  )
}

///|
test "try-table setup preserves the returns-twice setjmp contract" {
  let builder = @milkir.FunctionBuilder::FunctionBuilder("exception_try")
  builder.add_param(I64) |> ignore
  builder.add_result(I32)
  let result = @wasm_milkir.try_table_begin(builder, 4)
  builder.return_([result])
  inspect(
    lower_test_function(builder.finalize()),
    content=(
      #|machv exception_try [internal](v0:ptr64) -> (i32) {
      #|block0:
      #|  v1:i32 = i32.const 4
      #|  v2:ptr64 = call external @wasm.runtime.exception.try_begin (ptr64, i32) -> (ptr64) [platform] v0, v1 [memory=read-write, trap]
      #|  v3:i32 = i32.const 0
      #|  v4:i32 = call external @wasm.runtime.exception.sigsetjmp (ptr64, i32) -> (i32) [platform] v2, v3 [memory=read-write, returns-twice]
      #|  return v4
      #|}
    ),
  )
}

///|
test "exception local snapshots use address-visible runtime-word buffers" {
  let builder = @milkir.FunctionBuilder::FunctionBuilder("exception_spill")
  builder.add_param(I64) |> ignore
  let integer = builder.add_param(I64)
  let reference = builder.add_param(Ref)
  @wasm_milkir.spill_locals_for_throw(builder, [integer, reference])
  builder.return_([])
  inspect(
    lower_test_function(builder.finalize()),
    content=(
      #|machv exception_spill [internal](v0:ptr64, v1:i64, v2:gcref64) -> () {
      #|stack0: size=16, alignment=16
      #|block0:
      #|  v3:ptr64 = stack.address stack0
      #|  store {
      #|  width: W64,
      #|  value_type: I64,
      #|  offset: 0,
      #|  endianness: Little,
      #|  trap: None,
      #|} v3, v1 [memory=write]
      #|  v4:ptr64 = gcref.address v2
      #|  v5:i64 = convert.Bitcast(Ptr64, I64) v4
      #|  store {
      #|  width: W64,
      #|  value_type: I64,
      #|  offset: 8,
      #|  endianness: Little,
      #|  trap: None,
      #|} v3, v5 [memory=write]
      #|  v6:i32 = i32.const 2
      #|  call external @wasm.runtime.exception.spill_locals (ptr64, ptr64, i32) -> () [platform] v0, v3, v6 [memory=read-write]
      #|  return
      #|}
    ),
  )
}

///|
test "exception throws terminate control flow with typed value buffers" {
  let builder = @milkir.FunctionBuilder::FunctionBuilder("exception_throw")
  builder.add_param(I64) |> ignore
  let integer = builder.add_param(I64)
  let reference = builder.add_param(Ref)
  @wasm_milkir.emit_throw(builder, 9, [integer, reference])
  builder.trap("unreachable after throw")
  inspect(
    lower_test_function(builder.finalize()),
    content=(
      #|machv exception_throw [internal](v0:ptr64, v1:i64, v2:gcref64) -> () {
      #|stack0: size=16, alignment=16
      #|block0:
      #|  v3:i32 = i32.const 9
      #|  v4:ptr64 = stack.address stack0
      #|  store {
      #|  width: W64,
      #|  value_type: I64,
      #|  offset: 0,
      #|  endianness: Little,
      #|  trap: None,
      #|} v4, v1 [memory=write]
      #|  v5:ptr64 = gcref.address v2
      #|  v6:i64 = convert.Bitcast(Ptr64, I64) v5
      #|  store {
      #|  width: W64,
      #|  value_type: I64,
      #|  offset: 8,
      #|  endianness: Little,
      #|  trap: None,
      #|} v4, v6 [memory=write]
      #|  v7:i32 = i32.const 2
      #|  noreturn_call external @wasm.runtime.exception.throw (ptr64, i32, ptr64, i32) -> () [platform] (v0, v3, v4, v7) [memory=read-write, trap]
      #|}
    ),
  )
}

///|
test "exception reference throws replace placeholder traps" {
  let builder = @milkir.FunctionBuilder::FunctionBuilder("exception_throw_ref")
  builder.add_param(I64) |> ignore
  let reference = builder.add_param(Ref)
  @wasm_milkir.emit_throw_ref(builder, reference)
  builder.trap("unreachable after throw_ref")
  inspect(
    lower_test_function(builder.finalize()),
    content=(
      #|machv exception_throw_ref [internal](v0:ptr64, v1:gcref64) -> () {
      #|block0:
      #|  noreturn_call external @wasm.runtime.exception.throw_ref (ptr64, gcref64) -> () [platform] (v0, v1) [memory=read-write, trap]
      #|}
    ),
  )
}

///|
test "exception delegation is an explicit noreturn runtime transfer" {
  let builder = @milkir.FunctionBuilder::FunctionBuilder("exception_delegate")
  builder.add_param(I64) |> ignore
  @wasm_milkir.delegate(builder, 3)
  builder.trap("unreachable after delegate")
  inspect(
    lower_test_function(builder.finalize()),
    content=(
      #|machv exception_delegate [internal](v0:ptr64) -> () {
      #|block0:
      #|  v1:i32 = i32.const 3
      #|  noreturn_call external @wasm.runtime.exception.delegate (ptr64, i32) -> () [platform] (v0, v1) [memory=read-write, trap]
      #|}
    ),
  )
}
