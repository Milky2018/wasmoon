///|
test "public scalar builders compose integer and floating operations" {
  let builder = @milkir.FunctionBuilder::FunctionBuilder("scalar_operations")
  let integer = builder.add_param(I32)
  let float = builder.add_param(F32)
  builder.add_result(I32)
  builder.add_result(F64)
  let one = builder.iconst_i32(1)
  let incremented = builder.iadd(integer, one)
  let positive = builder.icmp_sgt(incremented, integer)
  let absolute = builder.fabs(float)
  let widened = builder.fpromote(absolute)
  builder.return_([positive, widened])
  let func = builder.finalize()
  inspect(
    func.print(),
    content=(
      #|function scalar_operations(v0:i32, v1:f32) -> i32, f64 {
      #|block0:
      #|    v2:i32 = iconst 1
      #|    v3:i32 = iadd v0, v2
      #|    v4:i32 = icmp.sgt v3, v0
      #|    v5:f32 = fabs v1
      #|    v6:f64 = fpromote v5
      #|    return v4, v6
      #|}
      #|
    ),
  )
}

///|
test "public call builders support direct and pointer multi-value calls" {
  let builder = @milkir.FunctionBuilder::FunctionBuilder("calls")
  let argument = builder.add_param(I32)
  let function_pointer = builder.add_param(I64)
  builder.add_result(I32)
  builder.add_result(I64)
  let symbol = builder.get_function().declare_external_symbol("host_pair")
  let direct = builder.call_symbol_multi(symbol, [I32, I64], [argument])
  let indirect = builder.call_pointer(function_pointer, [argument], [I32, I64])
  builder.return_([direct[0], indirect[1]])
  let func = builder.finalize()
  inspect(
    func.print(),
    content=(
      #|function calls(v0:i32, v1:i64) -> i32, i64 {
      #|block0:
      #|    (v2:i32, v3:i64) = call host_pair(v0)
      #|    (v4:i32, v5:i64) = call_ptr(1) -> 2 (v1, v0)
      #|    return v2, v5
      #|}
      #|
    ),
  )
}

///|
test "public memory builders cover full-width and narrow accesses" {
  let builder = @milkir.FunctionBuilder::FunctionBuilder("memory")
  let address = builder.add_param(Ptr)
  let value = builder.add_param(I32)
  let offset = builder.add_param(I64)
  builder.add_result(I32)
  builder.add_result(I32)
  let loaded = builder.load_ptr(I32, address, offset)
  let narrow = builder.load_ptr_narrow(I32, 8, true, address, offset)
  builder.store_ptr(I32, address, value, offset)
  builder.store_ptr_narrow(16, address, value, offset)
  builder.return_([loaded, narrow])
  let func = builder.finalize()
  inspect(
    func.print(),
    content=(
      #|function memory(v0:ptr, v1:i32, v2:i64) -> i32, i32 {
      #|block0:
      #|    v3:i32 = load.i32 v0, v2
      #|    v4:i32 = load8_s.i32 v0, v2
      #|    store.i32 v0, v1, v2
      #|    store16 v0, v1, v2
      #|    return v3, v4
      #|}
      #|
    ),
  )
}

///|
test "public vector builders cover lanes, bitwise ops, and memory" {
  let builder = @milkir.FunctionBuilder::FunctionBuilder("vectors")
  let scalar = builder.add_param(I32)
  let address = builder.add_param(Ptr)
  builder.add_result(I32)
  builder.add_result(V128)
  let constant = builder.v128_const(
    b"\x00\x01\x02\x03\x04\x05\x06\x07\x08\x09\x0a\x0b\x0c\x0d\x0e\x0f",
  )
  let splat = builder.v128_splat32(scalar)
  let combined = builder.v128_xor(constant, splat)
  let replaced = builder.v128_replace32(combined, scalar, 2)
  let extracted = builder.v128_extract32(replaced, 2)
  let loaded = builder.v128_load_with_addr(LoadSplat(I32), address)
  builder.v128_store_lane_with_addr(StoreLane(I32, 1), address, loaded)
  builder.return_([extracted, loaded])
  let func = builder.finalize()
  debug_inspect(
    func.print(),
    content=(
      #|"function vectors(v0:i32, v1:ptr) -> i32, v128 {\nblock0:\n    v2:v128 = v128.const \n    v3:v128 = i32x4.splat v0\n    v4:v128 = v128.xor v2, v3\n    v5:v128 = i32x4.replace_lane 2 v4, v0\n    v6:i32 = i32x4.extract_lane 2 v5\n    v7:v128 = v128.load32_splat v1\n    v128.store32_lane lane=1 v1, v7\n    return v6, v7\n}\n"
    ),
  )
}

///|
test "public extension builders preserve typed multi-value contracts" {
  let builder = @milkir.FunctionBuilder::FunctionBuilder("extension")
  let input = builder.add_param(I32)
  builder.add_result(I32)
  builder.add_result(I64)
  let opcode = @milkir.ExtOp::ExtOp("demo", "split", [7])
  let results = builder.emit_multi_ext_inst([I32, I64], opcode, [input])
  builder.return_(results)
  let func = builder.finalize()
  debug_inspect(
    results,
    content=(
      #|[{ id: 1, ty: I32 }, { id: 2, ty: I64 }]
    ),
  )
  inspect(
    func.print(),
    content=(
      #|function extension(v0:i32) -> i32, i64 {
      #|block0:
      #|    (v1:i32, v2:i64) = ext.demo.split [7] v0
      #|    return v1, v2
      #|}
      #|
    ),
  )
}

///|
test "public extension descriptors support bounded immediate counts" {
  let descriptor = @milkir.ExtOpDescriptor::with_immediate_range(
    "demo", "range", 1, 3,
  )
  debug_inspect(
    descriptor,
    content=(
      #|{
      #|  dialect: "demo",
      #|  opcode: "range",
      #|  min_immediates: 1,
      #|  max_immediates: 3,
      #|}
    ),
  )
  let accepted_counts : Array[Int] = []
  for count in 0..<=4 {
    if descriptor.accepts_immediate_count(count) {
      accepted_counts.push(count)
    }
  }
  debug_inspect(
    accepted_counts,
    content=(
      #|[1, 2, 3]
    ),
  )
  let candidates = [
    @milkir.ExtOp::ExtOp("demo", "range", []),
    ExtOp("demo", "range", [1]),
    ExtOp("demo", "range", [1, 2]),
    ExtOp("demo", "range", [1, 2, 3]),
    ExtOp("demo", "range", [1, 2, 3, 4]),
    ExtOp("other", "range", [1, 2]),
    ExtOp("demo", "other", [1, 2]),
  ]
  let matches : Array[@milkir.ExtOp] = []
  for candidate in candidates {
    if candidate.matches_descriptor(descriptor) {
      matches.push(candidate)
    }
  }
  debug_inspect(
    matches,
    content=(
      #|[
      #|  { dialect: "demo", opcode: "range", immediates: <FixedArray: [1]> },
      #|  { dialect: "demo", opcode: "range", immediates: <FixedArray: [1, 2]> },
      #|  {
      #|    dialect: "demo",
      #|    opcode: "range",
      #|    immediates: <FixedArray: [1, 2, 3]>,
      #|  },
      #|]
    ),
  )
}
