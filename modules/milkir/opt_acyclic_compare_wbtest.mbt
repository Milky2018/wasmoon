///|
test "acyclic rewrite complements a comparison tested against zero" {
  let builder = FunctionBuilder::FunctionBuilder("compare_boolean_zero")
  let left = builder.add_param(I32)
  let right = builder.add_param(I32)
  builder.add_result(I32)
  let predicate = builder.icmp_ugt(left, right)
  let zero = builder.iconst_i32(0)
  let result = builder.icmp_eq(predicate, zero)
  builder.return_([result])
  let func = builder.get_function()
  optimize_with_level(func, O2) |> ignore
  inspect(
    func.print(),
    content=(
      #|function compare_boolean_zero(v0:i32, v1:i32) -> i32 {
      #|block0:
      #|    v4:i32 = icmp.ule v0, v1
      #|    return v4
      #|}
      #|
    ),
  )
  inspect(func.verify(), content="()")
}

///|
test "acyclic rewrite removes a one-bit mask from a comparison" {
  let builder = FunctionBuilder::FunctionBuilder("mask_boolean")
  let left = builder.add_param(I32)
  let right = builder.add_param(I32)
  builder.add_result(I32)
  let predicate = builder.icmp_slt(left, right)
  let one = builder.iconst_i32(1)
  let result = builder.band(predicate, one)
  builder.return_([result])
  let func = builder.get_function()
  optimize_with_level(func, O2) |> ignore
  inspect(
    func.print(),
    content=(
      #|function mask_boolean(v0:i32, v1:i32) -> i32 {
      #|block0:
      #|    v2:i32 = icmp.slt v0, v1
      #|    return v2
      #|}
      #|
    ),
  )
  inspect(func.verify(), content="()")
}

///|
test "acyclic rewrite narrows a signed comparison through sign extension" {
  let builder = FunctionBuilder::FunctionBuilder("compare_sign_extend_zero")
  let value = builder.add_param(I32)
  builder.add_result(I32)
  let extended = builder.sextend(I64, value)
  let zero = builder.iconst_i64(0L)
  let result = builder.icmp_slt(extended, zero)
  builder.return_([result])
  let func = builder.get_function()
  optimize_with_level(func, O2) |> ignore
  inspect(
    func.print(),
    content=(
      #|function compare_sign_extend_zero(v0:i32) -> i32 {
      #|block0:
      #|    v4:i32 = iconst 0
      #|    v5:i32 = icmp.slt v0, v4
      #|    return v5
      #|}
      #|
    ),
  )
  inspect(func.verify(), content="()")
}

///|
test "acyclic rewrite proves the sign of a zero-extended value" {
  let builder = FunctionBuilder::FunctionBuilder("compare_zero_extend_sign")
  let value = builder.add_param(I32)
  builder.add_result(I32)
  let extended = builder.uextend(I64, value)
  let zero = builder.iconst_i64(0L)
  let result = builder.icmp_slt(extended, zero)
  builder.return_([result])
  let func = builder.get_function()
  optimize_with_level(func, O2) |> ignore
  inspect(
    func.print(),
    content=(
      #|function compare_zero_extend_sign(v0:i32) -> i32 {
      #|block0:
      #|    v3:i32 = iconst 0
      #|    return v3
      #|}
      #|
    ),
  )
  inspect(func.verify(), content="()")
}

///|
test "acyclic rewrite looks through an extended boolean comparison" {
  let builder = FunctionBuilder::FunctionBuilder("compare_extended_boolean")
  let left = builder.add_param(I32)
  let right = builder.add_param(I32)
  builder.add_result(I32)
  let predicate = builder.icmp_sge(left, right)
  let extended = builder.uextend(I64, predicate)
  let zero = builder.iconst_i64(0L)
  let result = builder.icmp_ne(extended, zero)
  builder.return_([result])
  let func = builder.get_function()
  optimize_with_level(func, O2) |> ignore
  inspect(
    func.print(),
    content=(
      #|function compare_extended_boolean(v0:i32, v1:i32) -> i32 {
      #|block0:
      #|    v2:i32 = icmp.sge v0, v1
      #|    return v2
      #|}
      #|
    ),
  )
  inspect(func.verify(), content="()")
}

///|
test "acyclic rewrite cancels a common modular addend for equality" {
  let builder = FunctionBuilder::FunctionBuilder("compare_common_addend")
  let left = builder.add_param(I32)
  let right = builder.add_param(I32)
  let common = builder.add_param(I32)
  builder.add_result(I32)
  let adjusted_left = builder.iadd(left, common)
  let adjusted_right = builder.iadd(common, right)
  let result = builder.icmp_ne(adjusted_left, adjusted_right)
  builder.return_([result])
  let func = builder.get_function()
  optimize_with_level(func, O2) |> ignore
  inspect(
    func.print(),
    content=(
      #|function compare_common_addend(v0:i32, v1:i32, v2:i32) -> i32 {
      #|block0:
      #|    v5:i32 = icmp.ne v0, v1
      #|    return v5
      #|}
      #|
    ),
  )
  inspect(func.verify(), content="()")
}

///|
test "acyclic rewrite keeps a shared extension instead of duplicating work" {
  let builder = FunctionBuilder::FunctionBuilder("shared_sign_extension")
  let value = builder.add_param(I32)
  builder.add_result(I64)
  builder.add_result(I32)
  let extended = builder.sextend(I64, value)
  let zero = builder.iconst_i64(0L)
  let sign = builder.icmp_slt(extended, zero)
  builder.return_([extended, sign])
  let func = builder.get_function()
  optimize_with_level(func, O2) |> ignore
  inspect(
    func.print(),
    content=(
      #|function shared_sign_extension(v0:i32) -> i64, i32 {
      #|block0:
      #|    v1:i64 = sextend v0
      #|    v2:i64 = iconst 0
      #|    v3:i32 = icmp.slt v1, v2
      #|    return v1, v3
      #|}
      #|
    ),
  )
  inspect(func.verify(), content="()")
}

///|
test "acyclic rewrite canonicalizes a left constant before narrowing" {
  let builder = FunctionBuilder::FunctionBuilder("compare_left_zero")
  let value = builder.add_param(I32)
  builder.add_result(I32)
  let zero = builder.iconst_i64(0L)
  let extended = builder.sextend(I64, value)
  let result = builder.icmp_sgt(zero, extended)
  builder.return_([result])
  let func = builder.get_function()
  optimize_with_level(func, O2) |> ignore
  inspect(
    func.print(),
    content=(
      #|function compare_left_zero(v0:i32) -> i32 {
      #|block0:
      #|    v4:i32 = iconst 0
      #|    v5:i32 = icmp.slt v0, v4
      #|    return v5
      #|}
      #|
    ),
  )
  inspect(func.verify(), content="()")
}

///|
test "acyclic rewrite canonicalizes unsigned comparison with zero" {
  let builder = FunctionBuilder::FunctionBuilder("compare_unsigned_zero")
  let value = builder.add_param(I32)
  builder.add_result(I32)
  let zero = builder.iconst_i32(0)
  let result = builder.icmp_ugt(value, zero)
  builder.return_([result])
  let func = builder.get_function()
  optimize_with_level(func, O2) |> ignore
  inspect(
    func.print(),
    content=(
      #|function compare_unsigned_zero(v0:i32) -> i32 {
      #|block0:
      #|    v1:i32 = iconst 0
      #|    v2:i32 = icmp.ne v0, v1
      #|    return v2
      #|}
      #|
    ),
  )
  inspect(func.verify(), content="()")
}
