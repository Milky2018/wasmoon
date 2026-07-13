///|
test "public optimization levels have stable integer defaults" {
  inspect(@milkir.OptLevel::from_int(0) is O0, content="true")
  inspect(@milkir.OptLevel::from_int(1) is O1, content="true")
  inspect(@milkir.OptLevel::from_int(2) is O2, content="true")
  inspect(@milkir.OptLevel::from_int(3) is O3, content="true")
  inspect(@milkir.OptLevel::from_int(99) is O2, content="true")
}

///|
test "public O0 cleanup is mandatory for large functions" {
  let builder = @milkir.FunctionBuilder::FunctionBuilder("large_dead_function")
  for i in 0..<300 {
    builder.iconst_i32(i) |> ignore
  }
  builder.return_([])
  let func = builder.finalize()
  inspect(@milkir.instruction_count(func), content="300")
  let result = @milkir.optimize_with_level(func, O0)
  inspect(result.changed, content="true")
  inspect(@milkir.instruction_count(func), content="0")
  func.verify()
}

///|
test "public O1 folds a constant expression" {
  let builder = @milkir.FunctionBuilder::FunctionBuilder("fold")
  builder.add_result(I32)
  let left = builder.iconst_i32(20)
  let right = builder.iconst_i32(22)
  let answer = builder.iadd(left, right)
  builder.return_([answer])
  let func = builder.finalize()
  inspect(@milkir.optimize_with_level(func, O1).changed, content="true")
  inspect(@milkir.instruction_count(func), content="1")
  inspect(func.print().contains("iconst 42"), content="true")
  func.verify()
}

///|
test "public O2 eliminates a duplicate expression" {
  let builder = @milkir.FunctionBuilder::FunctionBuilder("common_subexpression")
  let left = builder.add_param(I32)
  let right = builder.add_param(I32)
  builder.add_result(I32)
  builder.iadd(left, right) |> ignore
  let result = builder.iadd(left, right)
  builder.return_([result])
  let func = builder.finalize()
  inspect(@milkir.instruction_count(func), content="2")
  inspect(@milkir.optimize_with_level(func, O2).changed, content="true")
  inspect(@milkir.instruction_count(func), content="1")
  func.verify()
}

///|
test "public O3 derives power-of-two strength-reduction constants" {
  let builder = @milkir.FunctionBuilder::FunctionBuilder("strength_reduce")
  let value = builder.add_param(I32)
  builder.add_result(I32)
  builder.add_result(I32)
  builder.add_result(I32)
  let eight = builder.iconst_i32(8)
  let product = builder.imul(value, eight)
  let quotient = builder.udiv(value, eight)
  let remainder = builder.urem(value, eight)
  builder.return_([product, quotient, remainder])
  let func = builder.finalize()
  @milkir.optimize_with_level(func, O3) |> ignore
  let printed = func.print()
  inspect(printed.contains("iconst 3"), content="true")
  inspect(printed.contains("ishl"), content="true")
  inspect(printed.contains("ushr"), content="true")
  inspect(printed.contains("iconst 7"), content="true")
  inspect(printed.contains("band"), content="true")
  func.verify()
}

///|
test "public optimizer preserves observable and trapping operations" {
  let builder = @milkir.FunctionBuilder::FunctionBuilder("effects")
  let address = builder.add_param(Ptr)
  let value = builder.add_param(I32)
  let offset = builder.add_param(I64)
  builder.load_ptr(I32, address, offset) |> ignore
  builder.store_ptr(I32, address, value, offset)
  let symbol = builder.get_function().declare_external_symbol("effect")
  builder.call_symbol(symbol, None, []) |> ignore
  builder.emit_void_ext_inst(ExtOp("demo", "effect", []), [])
  builder.return_([])
  let func = builder.finalize()
  @milkir.optimize_with_level(func, O3) |> ignore
  let printed = func.print()
  inspect(printed.contains("load.i32"), content="true")
  inspect(printed.contains("store.i32"), content="true")
  inspect(printed.contains("call effect()"), content="true")
  inspect(printed.contains("ext.demo.effect"), content="true")
  func.verify()
}
