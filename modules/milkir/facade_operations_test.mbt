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
  let printed = func.print()
  inspect(printed.contains("iadd"), content="true")
  inspect(printed.contains("icmp.sgt"), content="true")
  inspect(printed.contains("fabs"), content="true")
  inspect(printed.contains("fpromote"), content="true")
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
  let printed = func.print()
  inspect(printed.contains("call host_pair(v0)"), content="true")
  inspect(printed.contains("call_ptr(1) -> 2"), content="true")
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
  let printed = func.print()
  inspect(printed.contains("load.i32"), content="true")
  inspect(printed.contains("load8_s.i32"), content="true")
  inspect(printed.contains("store.i32"), content="true")
  inspect(printed.contains("store16"), content="true")
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
  let printed = func.print()
  inspect(printed.contains("v128.const"), content="true")
  inspect(printed.contains("i32x4.splat"), content="true")
  inspect(printed.contains("v128.xor"), content="true")
  inspect(printed.contains("i32x4.replace_lane 2"), content="true")
  inspect(printed.contains("i32x4.extract_lane 2"), content="true")
  inspect(printed.contains("v128.load32_splat"), content="true")
  inspect(printed.contains("v128.store32_lane lane=1"), content="true")
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
  inspect(results.length(), content="2")
  inspect(func.print().contains("ext.demo.split [7] v0"), content="true")
}

///|
test "public extension descriptors support bounded immediate counts" {
  let descriptor = @milkir.ExtOpDescriptor::with_immediate_range(
    "demo", "range", 1, 3,
  )
  inspect(descriptor.accepts_immediate_count(0), content="false")
  inspect(descriptor.accepts_immediate_count(1), content="true")
  inspect(descriptor.accepts_immediate_count(3), content="true")
  inspect(descriptor.accepts_immediate_count(4), content="false")
  inspect(descriptor.expected_immediate_count(), content="1..3")
  inspect(
    @milkir.ExtOp::ExtOp("demo", "range", [1, 2]).matches_descriptor(descriptor),
    content="true",
  )
}
