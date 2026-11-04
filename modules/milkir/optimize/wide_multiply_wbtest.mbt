///|
fn limb_multiply_function(
  mask~ : Int64 = 0xFFFFFFFFL,
  shift~ : Int64 = 32L,
  signed~ : Bool = false,
  cross~ : Bool = false,
) -> @milkir.Function {
  let b = @milkir.FunctionBuilder::FunctionBuilder("limb_multiply")
  let a = b.add_param(I64)
  let c = b.add_param(I64)
  let extra = if cross { Some(b.add_param(I64)) } else { None }
  b.add_result(I64)
  b.add_result(I64)
  let mask = b.iconst_i64(mask)
  let shift = b.iconst_i64(shift)
  let al = b.band(a, mask)
  let cl = b.band(c, mask)
  let ah = if signed { b.sshr(a, shift) } else { b.ushr(a, shift) }
  let ch = if signed { b.sshr(c, shift) } else { b.ushr(c, shift) }
  let low = b.imul(al, cl)
  let carry = b.iadd(b.imul(cl, ah), b.ushr(low, shift))
  let middle = b.iadd(b.imul(ch, al), b.band(carry, mask))
  let upper = b.imul(ch, ah)
  let upper = if extra is Some(extra) {
    b.iadd(b.imul(extra, c), upper)
  } else {
    upper
  }
  let high = b.iadd(b.iadd(upper, b.ushr(carry, shift)), b.ushr(middle, shift))
  let low = b.bor(b.band(low, mask), b.ishl(middle, shift))
  b.return_([low, high])
  b.get_function()
}

///|
test "wide product recognition rejects changed masks shifts and signed limbs" {
  for
    function in [
      limb_multiply_function(mask=0xFFFFFFFEL),
      limb_multiply_function(shift=31L),
      limb_multiply_function(signed=true),
    ] {
    optimize_with_level(function, O2) |> ignore
    function.verify()
    for block in function.blocks {
      for id in function.block_instruction_ids(block) {
        assert_false(
          function.instruction_by_id(id).unwrap().opcode
          is Scalar(IntBinary(UnsignedMulHigh)),
        )
      }
    }
  }
}

///|
test "unsigned 64-bit limb product becomes low and high multiply primitives" {
  for cross in [false, true] {
    let function = limb_multiply_function(cross~)
    optimize_with_level(function, O2) |> ignore
    function.verify()
    let mut products = 0
    let mut high = 0
    for block in function.blocks {
      for id in function.block_instruction_ids(block) {
        match function.instruction_by_id(id).unwrap().opcode {
          Scalar(IntBinary(Mul)) => products += 1
          Scalar(IntBinary(UnsignedMulHigh)) => high += 1
          _ => ()
        }
      }
    }
    assert_eq((products, high), (if cross { 2 } else { 1 }, 1))
  }
}
