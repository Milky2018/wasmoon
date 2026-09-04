///|
test "acyclic rewrite recognizes a value and its complement" {
  let builder = @milkir.FunctionBuilder::FunctionBuilder("xor_complement")
  let value = builder.add_param(I32)
  builder.add_result(I32)
  let complement = builder.bnot(value)
  let result = builder.bxor(value, complement)
  builder.return_([result])
  let func = builder.get_function()
  optimize_with_level(func, O2) |> ignore
  inspect(
    func.print(),
    content=(
      #|function xor_complement(v0:i32) -> i32 {
      #|block0:
      #|    v2:i32 = iconst -1
      #|    return v2
      #|}
      #|
    ),
  )
  inspect(func.verify(), content="()")
}

///|
test "acyclic rewrite applies bitwise absorption" {
  let builder = @milkir.FunctionBuilder::FunctionBuilder("bitwise_absorption")
  let left = builder.add_param(I64)
  let right = builder.add_param(I64)
  builder.add_result(I64)
  let intersection = builder.band(left, right)
  let result = builder.bor(intersection, left)
  builder.return_([result])
  let func = builder.get_function()
  optimize_with_level(func, O2) |> ignore
  inspect(
    func.print(),
    content=(
      #|function bitwise_absorption(v0:i64, v1:i64) -> i64 {
      #|block0:
      #|    return v0
      #|}
      #|
    ),
  )
  inspect(func.verify(), content="()")
}

///|
test "acyclic rewrite cancels a nested xor operand" {
  let builder = @milkir.FunctionBuilder::FunctionBuilder("xor_cancel")
  let left = builder.add_param(I32)
  let right = builder.add_param(I32)
  builder.add_result(I32)
  let inner = builder.bxor(left, right)
  let result = builder.bxor(inner, right)
  builder.return_([result])
  let func = builder.get_function()
  optimize_with_level(func, O2) |> ignore
  inspect(
    func.print(),
    content=(
      #|function xor_cancel(v0:i32, v1:i32) -> i32 {
      #|block0:
      #|    return v0
      #|}
      #|
    ),
  )
  inspect(func.verify(), content="()")
}

///|
test "acyclic rewrite cancels opposite rotations" {
  let builder = @milkir.FunctionBuilder::FunctionBuilder("rotate_cancel")
  let value = builder.add_param(I64)
  let amount = builder.add_param(I64)
  builder.add_result(I64)
  let inner = builder.rotr(value, amount)
  let result = builder.rotl(inner, amount)
  builder.return_([result])
  let func = builder.get_function()
  optimize_with_level(func, O2) |> ignore
  inspect(
    func.print(),
    content=(
      #|function rotate_cancel(v0:i64, v1:i64) -> i64 {
      #|block0:
      #|    return v0
      #|}
      #|
    ),
  )
  inspect(func.verify(), content="()")
}

///|
test "acyclic rewrite combines constant rotations" {
  let builder = @milkir.FunctionBuilder::FunctionBuilder("rotate_combine")
  let value = builder.add_param(I32)
  builder.add_result(I32)
  let five = builder.iconst_i32(5)
  let inner = builder.rotl(value, five)
  let seven = builder.iconst_i32(7)
  let result = builder.rotl(inner, seven)
  builder.return_([result])
  let func = builder.get_function()
  optimize_with_level(func, O2) |> ignore
  inspect(
    func.print(),
    content=(
      #|function rotate_combine(v0:i32) -> i32 {
      #|block0:
      #|    v5:i32 = iconst 12
      #|    v6:i32 = rotl v0, v5
      #|    return v6
      #|}
      #|
    ),
  )
  inspect(func.verify(), content="()")
}

///|
test "acyclic rewrite folds overflowing constant shifts" {
  let builder = @milkir.FunctionBuilder::FunctionBuilder("shift_overflow")
  let value = builder.add_param(I32)
  builder.add_result(I32)
  let twenty = builder.iconst_i32(20)
  let inner = builder.ishl(value, twenty)
  let result = builder.ishl(inner, twenty)
  builder.return_([result])
  let func = builder.get_function()
  optimize_with_level(func, O2) |> ignore
  inspect(
    func.print(),
    content=(
      #|function shift_overflow(v0:i32) -> i32 {
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
test "acyclic rewrite replaces a shift round trip with a mask" {
  let builder = @milkir.FunctionBuilder::FunctionBuilder("shift_mask")
  let value = builder.add_param(I32)
  builder.add_result(I32)
  let eight = builder.iconst_i32(8)
  let inner = builder.ushr(value, eight)
  let result = builder.ishl(inner, eight)
  builder.return_([result])
  let func = builder.get_function()
  optimize_with_level(func, O2) |> ignore
  inspect(
    func.print(),
    content=(
      #|function shift_mask(v0:i32) -> i32 {
      #|block0:
      #|    v4:i32 = iconst -256
      #|    v5:i32 = band v0, v4
      #|    return v5
      #|}
      #|
    ),
  )
  inspect(func.verify(), content="()")
}

///|
test "acyclic rewrite masks high bits after a left-shift round trip" {
  let builder = @milkir.FunctionBuilder::FunctionBuilder("shift_low_mask")
  let value = builder.add_param(I32)
  builder.add_result(I32)
  let eight = builder.iconst_i32(8)
  let inner = builder.ishl(value, eight)
  let result = builder.ushr(inner, eight)
  builder.return_([result])
  let func = builder.get_function()
  optimize_with_level(func, O2) |> ignore
  inspect(
    func.print(),
    content=(
      #|function shift_low_mask(v0:i32) -> i32 {
      #|block0:
      #|    v4:i32 = iconst 16777215
      #|    v5:i32 = band v0, v4
      #|    return v5
      #|}
      #|
    ),
  )
  inspect(func.verify(), content="()")
}

///|
test "acyclic rewrite saturates combined signed shifts at the sign bit" {
  let builder = @milkir.FunctionBuilder::FunctionBuilder("signed_shift_combine")
  let value = builder.add_param(I32)
  builder.add_result(I32)
  let twenty = builder.iconst_i32(20)
  let inner = builder.sshr(value, twenty)
  let result = builder.sshr(inner, twenty)
  builder.return_([result])
  let func = builder.get_function()
  optimize_with_level(func, O2) |> ignore
  inspect(
    func.print(),
    content=(
      #|function signed_shift_combine(v0:i32) -> i32 {
      #|block0:
      #|    v4:i32 = iconst 31
      #|    v5:i32 = sshr v0, v4
      #|    return v5
      #|}
      #|
    ),
  )
  inspect(func.verify(), content="()")
}
