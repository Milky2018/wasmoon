///|
fn build_constant_expression(
  name : String,
) -> @milkir.Function raise @milkir.VerifyError {
  let builder = @milkir.FunctionBuilder::FunctionBuilder(name)
  builder.add_result(I32)
  let left = builder.iconst_i32(20)
  let right = builder.iconst_i32(22)
  let answer = builder.iadd(left, right)
  builder.return_([answer])
  builder.finalize()
}

///|
test "public default optimizer folds a constant expression" {
  let func = build_constant_expression("default_optimize")
  @milkir.optimize(func) |> ignore
  inspect(
    func.print(),
    content=(
      #|function default_optimize() -> i32 {
      #|block0:
      #|    v2:i32 = iconst 42
      #|    return v2
      #|}
      #|
    ),
  )
  func.verify()
}

///|
test "public integer optimization levels select complete pipelines" {
  let outputs : Array[String] = []
  for level in [0, 1, 2, 3, 99] {
    let func = build_constant_expression("level_\{level}")
    @milkir.optimize_with_level(func, @milkir.OptLevel::from_int(level))
    |> ignore
    outputs.push(func.print())
  }
  debug_inspect(
    outputs,
    content=(
      #|[
      #|  "function level_0() -> i32 {\nblock0:\n    v0:i32 = iconst 20\n    v1:i32 = iconst 22\n    v2:i32 = iadd v0, v1\n    return v2\n}\n",
      #|  "function level_1() -> i32 {\nblock0:\n    v2:i32 = iconst 42\n    return v2\n}\n",
      #|  "function level_2() -> i32 {\nblock0:\n    v2:i32 = iconst 42\n    return v2\n}\n",
      #|  "function level_3() -> i32 {\nblock0:\n    v2:i32 = iconst 42\n    return v2\n}\n",
      #|  "function level_99() -> i32 {\nblock0:\n    v2:i32 = iconst 42\n    return v2\n}\n",
      #|]
    ),
  )
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
  @milkir.optimize_with_level(func, O0) |> ignore
  inspect(@milkir.instruction_count(func), content="0")
  inspect(
    func.print(),
    content=(
      #|function large_dead_function() {
      #|block0:
      #|    return
      #|}
      #|
    ),
  )
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
  @milkir.optimize_with_level(func, O1) |> ignore
  inspect(
    func.print(),
    content=(
      #|function fold() -> i32 {
      #|block0:
      #|    v2:i32 = iconst 42
      #|    return v2
      #|}
      #|
    ),
  )
  func.verify()
}

///|
fn build_repeated_expression(
  name : String,
) -> @milkir.Function raise @milkir.VerifyError {
  let builder = @milkir.FunctionBuilder::FunctionBuilder(name)
  let left = builder.add_param(I32)
  let right = builder.add_param(I32)
  builder.add_result(I32)
  let first = builder.iadd(left, right)
  let second = builder.iadd(left, right)
  let product = builder.imul(first, second)
  builder.return_([product])
  builder.finalize()
}

///|
test "public O1 and O2 select distinct optimization pipelines" {
  let o1 = build_repeated_expression("repeated_o1")
  let o2 = build_repeated_expression("repeated_o2")
  @milkir.optimize_with_level(o1, O1) |> ignore
  @milkir.optimize_with_level(o2, O2) |> ignore
  inspect(
    o1.print(),
    content=(
      #|function repeated_o1(v0:i32, v1:i32) -> i32 {
      #|block0:
      #|    v2:i32 = iadd v0, v1
      #|    v3:i32 = iadd v0, v1
      #|    v4:i32 = imul v2, v3
      #|    return v4
      #|}
      #|
    ),
  )
  inspect(
    o2.print(),
    content=(
      #|function repeated_o2(v0:i32, v1:i32) -> i32 {
      #|block0:
      #|    v2:i32 = iadd v0, v1
      #|    v4:i32 = imul v2, v2
      #|    return v4
      #|}
      #|
    ),
  )
  o1.verify()
  o2.verify()
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
  @milkir.optimize_with_level(func, O2) |> ignore
  inspect(@milkir.instruction_count(func), content="1")
  inspect(
    func.print(),
    content=(
      #|function common_subexpression(v0:i32, v1:i32) -> i32 {
      #|block0:
      #|    v3:i32 = iadd v0, v1
      #|    return v3
      #|}
      #|
    ),
  )
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
  inspect(
    func.print(),
    content=(
      #|function strength_reduce(v0:i32) -> i32, i32, i32 {
      #|block0:
      #|    v5:i32 = iconst 3
      #|    v2:i32 = ishl v0, v5
      #|    v3:i32 = ushr v0, v5
      #|    v7:i32 = iconst 7
      #|    v4:i32 = band v0, v7
      #|    return v2, v3, v4
      #|}
      #|
    ),
  )
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
  debug_inspect(
    func.print(),
    content=(
      #|"function effects(v0:ptr, v1:i32, v2:i64) {\nblock0:\n    v3:i32 = load.i32 v0, v2\n    store.i32 v0, v1, v2\n    call effect()\n    ext.demo.effect \n    return\n}\n"
    ),
  )
  func.verify()
}
