// Independent straight-line evaluator for migration regressions. It evaluates
// both the original and optimized DFG, including modular-width edge inputs.

///|
fn migration_eval(
  func : @milkir.Function,
  inputs : Array[Int64],
) -> Int64 raise {
  let values = Array::make(func.next_value_id, 0L)
  for i, entry in func.params {
    values[entry.0.id] = inputs[i]
  }
  for block in func.blocks {
    for id in block.instruction_ids() {
      let inst = func.instruction_by_id(id).unwrap()
      let args = inst.operands.map(v => values[v.id])
      let result = inst.first_result().unwrap()
      let bits = if result.ty == I32 { 32 } else { 64 }
      let value = match (inst.opcode, args) {
        (Scalar(IntConst(c)), []) => c
        (Scalar(Copy), [a]) => a
        (Scalar(IntUnary(Not)), [a]) => -1L ^ a
        (Scalar(IntBinary(op)), [a, b]) => {
          let shift = b.to_int() & (bits - 1)
          let unsigned = if bits == 32 {
            a.reinterpret_as_uint64() & 0xFFFFFFFFUL
          } else {
            a.reinterpret_as_uint64()
          }
          match op {
            Add => a + b
            Sub => a - b
            Mul => a * b
            And => a & b
            Or => a | b
            Xor => a ^ b
            ShiftLeft => a << shift
            SignedShiftRight => a >> shift
            UnsignedShiftRight => (unsigned >> shift).reinterpret_as_int64()
            RotateLeft =>
              if shift == 0 {
                a
              } else {
                ((unsigned << shift) | (unsigned >> (bits - shift))).reinterpret_as_int64()
              }
            RotateRight =>
              if shift == 0 {
                a
              } else {
                ((unsigned >> shift) | (unsigned << (bits - shift))).reinterpret_as_int64()
              }
            _ => fail("unsupported migration binary")
          }
        }
        (Scalar(IntCompare(cc)), [a, b]) => {
          let yes = if inst.operands[0].ty == I32 {
            eval_icmp_i32(cc, a.to_int(), b.to_int())
          } else {
            eval_icmp_i64(cc, a, b)
          }
          if yes {
            1L
          } else {
            0L
          }
        }
        (Scalar(Convert(UnsignedExtend)), [a]) => a & 0xFFFFFFFFL
        (Scalar(Convert(SignedExtend)), [a]) => a.to_int().to_int64()
        (Scalar(Convert(IntReduce)), [a]) => a.to_int().to_int64()
        (Scalar(Select), [c, a, b]) => if c == 0L { b } else { a }
        _ => fail("unsupported migration instruction: \{inst.opcode}")
      }
      values[result.id] = if bits == 32 {
        value.to_int().to_int64()
      } else {
        value
      }
    }
    if block.terminator is Some(Return([value])) {
      return values[value.id]
    }
  }
  fail("missing migration return")
}

///|
fn migration_equivalence(
  build : (@milkir.FunctionBuilder, @milkir.Value, @milkir.Value) -> @milkir.Value,
) -> Unit raise {
  for ty in ([I32, I64] : Array[@milkir.Type]) {
    let builder = @milkir.FunctionBuilder::FunctionBuilder("migration")
    let a = builder.add_param(ty)
    let b = builder.add_param(ty)
    let result = build(builder, a, b)
    builder.add_result(result.ty)
    builder.return_([result])
    let func = builder.get_function()
    let edges = if ty == I32 {
      [-2147483648L, -2147483647L, -1L, 0L, 1L, 31L, 2147483647L]
    } else {
      [
        -9223372036854775808L, -9223372036854775807L, -1L, 0L, 1L, 63L, 9223372036854775807L,
      ]
    }
    let before : Array[Int64] = []
    for a in edges {
      for b in edges {
        before.push(migration_eval(func, [a, b]))
      }
    }
    optimize_with_level(func, O2) |> ignore
    func.verify()
    let after : Array[Int64] = []
    for a in edges {
      for b in edges {
        after.push(migration_eval(func, [a, b]))
      }
    }
    inspect(before == after, content="true")
  }
}

///|
test "migration modular arithmetic and bitwise relations preserve boundaries" {
  let rules : Array[
    (@milkir.FunctionBuilder, @milkir.Value, @milkir.Value) -> @milkir.Value,
  ] = [
    (f, a, b) => f.iadd(a, f.isub(f.iconst(a.ty, 0L), b)),
    (f, a, b) => f.isub(a, f.isub(f.iconst(a.ty, 0L), b)),
    (f, a, b) => f.isub(f.isub(a, b), a),
    (f, a, b) => f.isub(a, f.isub(a, b)),
    (f, a, b) => {
      f.imul(f.isub(f.iconst(a.ty, 0L), a), f.isub(f.iconst(a.ty, 0L), b))
    },
    (f, a, _) => f.imul(a, f.iconst(a.ty, -1L)),
    (f, a, b) => f.imul(a, f.ishl(f.iconst(a.ty, 1L), b)),
    (f, a, b) => f.iadd(f.band(a, b), f.bxor(a, b)),
    (f, a, b) => f.iadd(f.bor(a, b), f.band(a, b)),
    (f, a, b) => f.isub(f.iadd(a, b), f.bor(a, b)),
    (f, a, _) => f.iadd(f.bnot(a), f.iconst(a.ty, 1L)),
    (f, a, _) => f.iadd(f.bor(a, f.iconst(a.ty, 13L)), f.iconst(a.ty, -13L)),
    (f, a, b) => f.bxor(f.band(a, b), f.bxor(a, b)),
    (f, a, b) => f.bxor(f.bor(a, b), f.band(a, b)),
    (f, a, b) => f.bor(f.band(a, b), f.bnot(b)),
    (f, a, b) => f.band(f.bxor(a, f.bnot(b)), a),
    (f, a, b) => f.bxor(f.band(a, b), f.band(a, f.iconst(a.ty, 17L))),
    (f, a, _) => f.imul(f.imul(a, f.iconst(a.ty, 3L)), f.iconst(a.ty, 7L)),
    (f, a, _) => f.imul(f.ishl(a, f.iconst(a.ty, 5L)), f.iconst(a.ty, 3L)),
    (f, a, b) => f.icmp_ugt(f.isub(a, b), a),
    (f, a, b) => f.icmp_slt(f.bnot(a), f.bnot(b)),
    (f, a, b) => f.icmp_eq(f.bxor(a, b), a),
    (f, a, _) => f.icmp_eq(f.iadd(a, f.iconst(a.ty, 19L)), f.iconst(a.ty, -1L)),
    (f, a, b) => f.bxor(f.icmp_slt(a, b), f.icmp_sgt(a, b)),
    (f, a, b) => f.band(f.icmp_slt(a, b), f.icmp_sgt(a, b)),
    (f, a, b) => f.bor(f.icmp_sle(a, b), f.icmp_sgt(a, b)),
    (f, a, b) => f.select(f.icmp_eq(a, b), a, b),
    (f, a, b) => f.select(f.icmp_slt(a, b), f.iconst_i32(0), f.iconst_i32(1)),
    (f, a, b) => f.icmp_sgt(f.select(f.icmp_slt(a, b), a, b), a),
    (f, a, b) => {
      f.iadd(
        f.select(f.icmp_slt(a, b), f.iconst(a.ty, -1L), f.iconst(a.ty, 7L)),
        f.iconst(a.ty, 1L),
      )
    },
    (f, a, b) => {
      f.iadd(f.iadd(a, f.iconst(a.ty, 3L)), f.iadd(b, f.iconst(a.ty, 5L)))
    },
    (f, a, b) => {
      f.imul(f.imul(a, f.iconst(a.ty, 3L)), f.imul(b, f.iconst(a.ty, 5L)))
    },
    (f, a, b) => {
      f.band(f.band(a, f.iconst(a.ty, 3L)), f.band(b, f.iconst(a.ty, 5L)))
    },
    (f, a, b) => {
      f.bor(f.bor(a, f.iconst(a.ty, 3L)), f.bor(b, f.iconst(a.ty, 5L)))
    },
    (f, a, b) => {
      f.bxor(f.bxor(a, f.iconst(a.ty, 3L)), f.bxor(b, f.iconst(a.ty, 5L)))
    },
    (f, a, b) => {
      f.icmp_eq(f.iadd(a, f.iconst(a.ty, 3L)), f.iadd(b, f.iconst(a.ty, 5L)))
    },
    (f, a, _) => f.isub(f.isub(f.iconst(a.ty, 3L), a), f.iconst(a.ty, 5L)),
    (f, a, _) => f.iadd(f.isub(f.iconst(a.ty, 3L), a), f.iconst(a.ty, 5L)),
    (f, a, b) => f.ushr(f.band(f.ishl(a, b), f.iconst(a.ty, -17L)), b),
  ]
  for rule in rules {
    migration_equivalence(rule)
  }
}

///|
test "migration comparison bounds preserve both integer widths" {
  for
    cc in (
      [Eq, Ne, Slt, Sle, Sgt, Sge, Ult, Ule, Ugt, Uge] : Array[@milkir.IntCC]) {
    for
      bound in [
        0L, 1L, -1L, 2147483647L, -2147483648L, 9223372036854775807L, -9223372036854775808L,
      ] {
      migration_equivalence((f, a, _) => f.icmp(cc, a, f.iconst(a.ty, bound)))
    }
  }
}

///|
test "migration rotations and factored shifts preserve masked amounts" {
  for amount in [0L, 1L, 8L, 31L, 32L, 63L, 64L, -1L] {
    migration_equivalence((f, a, b) => {
      f.iadd(
        f.ishl(a, f.iconst(a.ty, amount)),
        f.ishl(b, f.iconst(a.ty, amount)),
      )
    })
    migration_equivalence((f, a, _) => {
      f.bor(
        f.ishl(a, f.iconst(a.ty, amount)),
        f.ushr(a, f.iconst(a.ty, -amount)),
      )
    })
    migration_equivalence((f, a, _) => {
      f.rotl(f.rotr(a, f.iconst(a.ty, amount)), f.iconst(a.ty, 7L))
    })
    migration_equivalence((f, a, _) => {
      f.ishl(f.ishl(f.iconst(a.ty, -17L), a), f.iconst(a.ty, amount))
    })
    migration_equivalence((f, a, _) => {
      f.ushr(f.ushr(f.iconst(a.ty, -17L), a), f.iconst(a.ty, amount))
    })
    migration_equivalence((f, a, _) => {
      f.sshr(f.sshr(f.iconst(a.ty, -17L), a), f.iconst(a.ty, amount))
    })
  }
}

///|
test "migration narrowing preserves discarded high bits" {
  let rules : Array[
    (@milkir.FunctionBuilder, @milkir.Value, @milkir.Value) -> @milkir.Value,
  ] = [
    (f, a, b) => f.iadd(f.uextend(I64, a), f.uextend(I64, b)),
    (f, a, b) => f.isub(f.uextend(I64, a), f.uextend(I64, b)),
    (f, a, b) => f.ireduce(I32, f.iadd(f.uextend(I64, a), f.uextend(I64, b))),
    (f, a, b) => f.ireduce(I32, f.imul(f.sextend(I64, a), f.sextend(I64, b))),
    (f, a, _) => f.ireduce(I32, f.bnot(f.uextend(I64, a))),
    (f, a, b) => f.band(f.uextend(I64, a), f.uextend(I64, b)),
    (f, a, b) => f.bor(f.uextend(I64, a), f.uextend(I64, b)),
    (f, a, b) => f.bxor(f.uextend(I64, a), f.uextend(I64, b)),
    (f, a, _) => f.band(f.sextend(I64, a), f.iconst_i64(0xFFFFFFFFL)),
  ]
  for rule in rules {
    // Both outer signatures remain supported; use an explicit reduction to
    // make the inner extension input i32 in the i64 test variant.
    migration_equivalence((f, a, b) => {
      rule(
        f,
        if a.ty == I32 {
          a
        } else {
          f.ireduce(I32, a)
        },
        if b.ty == I32 {
          b
        } else {
          f.ireduce(I32, b)
        },
      )
    })
  }
  for amount in [0L, 1L, 31L, 32L, 63L, 64L, -1L] {
    migration_equivalence((f, a, _) => {
      let a = if a.ty == I32 { a } else { f.ireduce(I32, a) }
      f.ireduce(I32, f.ishl(f.uextend(I64, a), f.iconst_i64(amount)))
    })
  }
}

///|
test "migration comparison combinations preserve signed and unsigned domains" {
  let conditions : Array[@milkir.IntCC] = [
    Eq,
    Ne,
    Slt,
    Sle,
    Sgt,
    Sge,
    Ult,
    Ule,
    Ugt,
    Uge,
  ]
  for left_cc in conditions {
    for right_cc in conditions {
      for op in ([And, Or, Xor] : Array[@milkir.IntBinaryOp]) {
        migration_equivalence((f, a, b) => {
          f.emit_inst(I32, Scalar(IntBinary(op)), [
            f.icmp(left_cc, a, b),
            f.icmp(right_cc, b, a),
          ])
        })
      }
    }
  }
}

///|
fn migration_return_opcode(func : @milkir.Function) -> @milkir.Opcode {
  for block in func.blocks {
    if block.terminator is Some(Return([value])) {
      return func.defining_inst(value).unwrap().opcode
    }
  }
  abort("missing return")
}

///|
test "migration select and min bound eliminate operations exactly" {
  let f = @milkir.FunctionBuilder::FunctionBuilder("select_bound")
  let a = f.add_param(I32)
  let b = f.add_param(I32)
  let min = f.select(f.icmp_slt(a, b), a, b)
  let result = f.icmp_sgt(min, a)
  f.add_result(I32)
  f.return_([result])
  let func = f.get_function()
  optimize_with_level(func, O2) |> ignore
  inspect(
    func.print(),
    content=(
      #|function select_bound(v0:i32, v1:i32) -> i32 {
      #|block0:
      #|    v4:i32 = iconst 0
      #|    return v4
      #|}
      #|
    ),
  )
}

///|
test "migration vector constant splats retain all six lane widths" {
  let lanes : Array[@milkir.VectorLane] = [I8, I16, I32, I64, F32, F64]
  let expected : Array[Bytes] = [
    [
      0x88, 0x88, 0x88, 0x88, 0x88, 0x88, 0x88, 0x88, 0x88, 0x88, 0x88, 0x88, 0x88,
      0x88, 0x88, 0x88,
    ],
    [
      0x88, 0x77, 0x88, 0x77, 0x88, 0x77, 0x88, 0x77, 0x88, 0x77, 0x88, 0x77, 0x88,
      0x77, 0x88, 0x77,
    ],
    [
      0x88, 0x77, 0x66, 0x55, 0x88, 0x77, 0x66, 0x55, 0x88, 0x77, 0x66, 0x55, 0x88,
      0x77, 0x66, 0x55,
    ],
    [
      0x88, 0x77, 0x66, 0x55, 0x44, 0x33, 0x22, 0x11, 0x88, 0x77, 0x66, 0x55, 0x44,
      0x33, 0x22, 0x11,
    ],
    [
      0x88, 0x77, 0x66, 0x55, 0x88, 0x77, 0x66, 0x55, 0x88, 0x77, 0x66, 0x55, 0x88,
      0x77, 0x66, 0x55,
    ],
    [
      0x88, 0x77, 0x66, 0x55, 0x44, 0x33, 0x22, 0x11, 0x88, 0x77, 0x66, 0x55, 0x44,
      0x33, 0x22, 0x11,
    ],
  ]
  for i, lane in lanes {
    let f = @milkir.FunctionBuilder::FunctionBuilder("splat")
    let value = match lane {
      I8 | I16 | I32 => f.iconst_i32(0x55667788)
      I64 => f.iconst_i64(0x1122334455667788L)
      F32 => f.emit_inst(F32, Scalar(FloatConst32(0x55667788U)), [])
      F64 => f.emit_inst(F64, Scalar(FloatConst64(0x1122334455667788UL)), [])
    }
    let result = f.emit_inst(V128, Vector(Splat(lane)), [value])
    f.add_result(V128)
    f.return_([result])
    let func = f.get_function()
    optimize_with_level(func, O2) |> ignore
    func.verify()
    assert_eq(migration_return_opcode(func), Vector(Const(expected[i])))
  }
}

///|
test "migration splat lifting respects lane agreement and sharing" {
  for shared in [false, true] {
    for matching in [false, true] {
      let f = @milkir.FunctionBuilder::FunctionBuilder("splat_lift")
      let a = f.add_param(I32)
      let b = f.add_param(I32)
      let av = f.v128_splat8(a)
      let bv = f.v128_splat8(b)
      let result = f.emit_inst(
        V128,
        Vector(IntBinary(Add, if matching { I8 } else { I16 })),
        [av, bv],
      )
      f.add_result(V128)
      if shared {
        f.add_result(V128)
        f.return_([result, av])
      } else {
        f.return_([result])
      }
      let func = f.get_function()
      optimize_with_level(func, O2) |> ignore
      func.verify()
      let ops = func.blocks[0]
        .instruction_ids()
        .map(id => func.instruction_by_id(id).unwrap().opcode)
      assert_eq(ops.contains(Scalar(IntBinary(Add))), matching && !shared)
    }
  }
}

///|
test "migration float folds preserve NaN payloads signed zero and ties to even" {
  let cases : Array[(@milkir.FloatUnaryOp, UInt64, UInt64)] = [
    (Neg, 0x7ff0000000000042UL, 0xfff0000000000042UL),
    (Abs, 0xfff0000000000042UL, 0x7ff0000000000042UL),
    (Nearest, 0x3fe0000000000000UL, 0UL),
    (Nearest, 0xbfe0000000000000UL, 0x8000000000000000UL),
    (Nearest, 0x3ff8000000000000UL, 0x4000000000000000UL),
    (Nearest, 0x4004000000000000UL, 0x4000000000000000UL),
  ]
  for item in cases {
    let (op, input, expected) = item
    let f = @milkir.FunctionBuilder::FunctionBuilder("float_fold")
    let a = f.emit_inst(F64, Scalar(FloatConst64(input)), [])
    let result = f.emit_inst(F64, Scalar(FloatUnary(op)), [a])
    f.add_result(F64)
    f.return_([result])
    let func = f.get_function()
    optimize_with_level(func, O2) |> ignore
    assert_eq(migration_return_opcode(func), Scalar(FloatConst64(expected)))
  }
  for op in ([Min, Max] : Array[@milkir.FloatBinaryOp]) {
    let f = @milkir.FunctionBuilder::FunctionBuilder("signed_zero")
    let a = f.emit_inst(F32, Scalar(FloatConst32(0x80000000U)), [])
    let b = f.emit_inst(F32, Scalar(FloatConst32(0U)), [])
    let result = f.emit_inst(F32, Scalar(FloatBinary(op)), [a, b])
    f.add_result(F32)
    f.return_([result])
    let func = f.get_function()
    optimize_with_level(func, O2) |> ignore
    assert_eq(
      migration_return_opcode(func),
      Scalar(FloatConst32(if op == Min { 0x80000000U } else { 0U })),
    )
  }
}
