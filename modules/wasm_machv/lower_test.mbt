///|
fn test_environment() -> Environment {
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
    fn(name) { @machv.ExternalSymbol::new("wasm.runtime.\{name}") },
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
    lower_function(builder.finalize(), test_environment()),
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
test "direct Wasm tail calls replace the source placeholder terminator" {
  let builder = @milkir.FunctionBuilder::FunctionBuilder("tail_caller")
  builder.add_param(I64) |> ignore
  let argument = builder.add_param(Ref)
  builder.add_result(I64)
  builder.emit_void_ext_inst(@wasm_milkir.encode(ReturnCall(4)), [argument])
  builder.trap("unreachable after return_call")
  inspect(
    lower_function(builder.finalize(), test_environment()),
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
    lower_function(builder.finalize(), test_environment()),
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
    lower_function(builder.finalize(), test_environment()),
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
    lower_function(builder.finalize(), test_environment()),
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
  @wasm_milkir.array_set(builder, 9, reference, index, integer_value)
  builder.return_([
    float_field, reference_field, signed_field, unsigned_field, float_element,
  ])
  inspect(
    lower_function(builder.finalize(), test_environment()),
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
      #|  v32:i32 = i32.const 9
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
  try lower_function(builder.finalize(), test_environment()) |> ignore catch {
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
    lower_function(builder.finalize(), test_environment()),
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
test "memory base access uses an opaque semantic environment field" {
  let builder = @milkir.FunctionBuilder::FunctionBuilder("memory_base")
  let vmctx = builder.add_param(I64)
  builder.add_result(I64)
  let base = builder.emit_ext_inst(I64, @wasm_milkir.encode(LoadMemBase(3)), [
    vmctx,
  ])
  builder.return_([base])
  inspect(
    lower_function(builder.finalize(), test_environment()),
    content=(
      #|machv memory_base [internal](v0:ptr64) -> (i64) {
      #|block0:
      #|  v1:ptr64 = environment.field @wasm.memory.3.base v0 [memory=read]
      #|  v2:i64 = convert.Bitcast(Ptr64, I64) v1
      #|  return v2
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
    lower_function(builder.finalize(), test_environment()),
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
    lower_function(builder.finalize(), test_environment()),
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
    lower_function(builder.finalize(), test_environment()),
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
    lower_function(builder.finalize(), test_environment()),
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
