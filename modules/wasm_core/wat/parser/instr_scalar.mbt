// Dispatch by instruction family keeps generated C functions within native compiler limits.

///|
fn Parser::parse_i32_instruction(
  self : Parser,
  kw : String,
) -> @types.Instruction raise WatError {
  match kw {

    // Memory
    "i32.load" => parse_mem_arg(self, fn(m, a, o) { I32Load(m, a, o) })
    "i32.load8_s" => parse_mem_arg(self, fn(m, a, o) { I32Load8S(m, a, o) })
    "i32.load8_u" => parse_mem_arg(self, fn(m, a, o) { I32Load8U(m, a, o) })
    "i32.load16_s" => parse_mem_arg(self, fn(m, a, o) { I32Load16S(m, a, o) })
    "i32.load16_u" => parse_mem_arg(self, fn(m, a, o) { I32Load16U(m, a, o) })
    "i32.store" => parse_mem_arg(self, fn(m, a, o) { I32Store(m, a, o) })
    "i32.store8" => parse_mem_arg(self, fn(m, a, o) { I32Store8(m, a, o) })
    "i32.store16" => parse_mem_arg(self, fn(m, a, o) { I32Store16(m, a, o) })

    // Constants
    "i32.const" => I32Const(self.parse_i32())

    // i32 operations
    "i32.eqz" => I32Eqz
    "i32.eq" => I32Eq
    "i32.ne" => I32Ne
    "i32.lt_s" => I32LtS
    "i32.lt_u" => I32LtU
    "i32.gt_s" => I32GtS
    "i32.gt_u" => I32GtU
    "i32.le_s" => I32LeS
    "i32.le_u" => I32LeU
    "i32.ge_s" => I32GeS
    "i32.ge_u" => I32GeU
    "i32.clz" => I32Clz
    "i32.ctz" => I32Ctz
    "i32.popcnt" => I32Popcnt
    "i32.add" => I32Add
    "i32.sub" => I32Sub
    "i32.mul" => I32Mul
    "i32.div_s" => I32DivS
    "i32.div_u" => I32DivU
    "i32.rem_s" => I32RemS
    "i32.rem_u" => I32RemU
    "i32.and" => I32And
    "i32.or" => I32Or
    "i32.xor" => I32Xor
    "i32.shl" => I32Shl
    "i32.shr_s" => I32ShrS
    "i32.shr_u" => I32ShrU
    "i32.rotl" => I32Rotl
    "i32.rotr" => I32Rotr
    // Sign-extension operators
    "i32.extend8_s" => I32Extend8S
    "i32.extend16_s" => I32Extend16S

    // Conversions
    "i32.wrap_i64" => I32WrapI64
    "i32.trunc_f32_s" => I32TruncF32S
    "i32.trunc_f32_u" => I32TruncF32U
    "i32.trunc_f64_s" => I32TruncF64S
    "i32.trunc_f64_u" => I32TruncF64U
    "i32.reinterpret_f32" => I32ReinterpretF32

    // Saturating truncation instructions (nontrapping float-to-int)
    "i32.trunc_sat_f32_s" => I32TruncSatF32S
    "i32.trunc_sat_f32_u" => I32TruncSatF32U
    "i32.trunc_sat_f64_s" => I32TruncSatF64S
    "i32.trunc_sat_f64_u" => I32TruncSatF64U
    _ => self.parse_atomic_instruction(kw)
  }
}

///|
fn Parser::parse_i64_instruction(
  self : Parser,
  kw : String,
) -> @types.Instruction raise WatError {
  match kw {
    "i64.load" => parse_mem_arg(self, fn(m, a, o) { I64Load(m, a, o) })
    "i64.load8_s" => parse_mem_arg(self, fn(m, a, o) { I64Load8S(m, a, o) })
    "i64.load8_u" => parse_mem_arg(self, fn(m, a, o) { I64Load8U(m, a, o) })
    "i64.load16_s" => parse_mem_arg(self, fn(m, a, o) { I64Load16S(m, a, o) })
    "i64.load16_u" => parse_mem_arg(self, fn(m, a, o) { I64Load16U(m, a, o) })
    "i64.load32_s" => parse_mem_arg(self, fn(m, a, o) { I64Load32S(m, a, o) })
    "i64.load32_u" => parse_mem_arg(self, fn(m, a, o) { I64Load32U(m, a, o) })
    "i64.store" => parse_mem_arg(self, fn(m, a, o) { I64Store(m, a, o) })
    "i64.store8" => parse_mem_arg(self, fn(m, a, o) { I64Store8(m, a, o) })
    "i64.store16" => parse_mem_arg(self, fn(m, a, o) { I64Store16(m, a, o) })
    "i64.store32" => parse_mem_arg(self, fn(m, a, o) { I64Store32(m, a, o) })
    "i64.const" => I64Const(self.parse_i64())

    // i64 operations
    "i64.eqz" => I64Eqz
    "i64.eq" => I64Eq
    "i64.ne" => I64Ne
    "i64.lt_s" => I64LtS
    "i64.lt_u" => I64LtU
    "i64.gt_s" => I64GtS
    "i64.gt_u" => I64GtU
    "i64.le_s" => I64LeS
    "i64.le_u" => I64LeU
    "i64.ge_s" => I64GeS
    "i64.ge_u" => I64GeU
    "i64.clz" => I64Clz
    "i64.ctz" => I64Ctz
    "i64.popcnt" => I64Popcnt
    "i64.add128" => I64Add128
    "i64.sub128" => I64Sub128
    "i64.add" => I64Add
    "i64.sub" => I64Sub
    "i64.mul" => I64Mul
    "i64.mul_wide_s" => I64MulWideS
    "i64.mul_wide_u" => I64MulWideU
    "i64.div_s" => I64DivS
    "i64.div_u" => I64DivU
    "i64.rem_s" => I64RemS
    "i64.rem_u" => I64RemU
    "i64.and" => I64And
    "i64.or" => I64Or
    "i64.xor" => I64Xor
    "i64.shl" => I64Shl
    "i64.shr_s" => I64ShrS
    "i64.shr_u" => I64ShrU
    "i64.rotl" => I64Rotl
    "i64.rotr" => I64Rotr
    // Sign-extension operators
    "i64.extend8_s" => I64Extend8S
    "i64.extend16_s" => I64Extend16S
    "i64.extend32_s" => I64Extend32S
    "i64.extend_i32_s" => I64ExtendI32S
    "i64.extend_i32_u" => I64ExtendI32U
    "i64.trunc_f32_s" => I64TruncF32S
    "i64.trunc_f32_u" => I64TruncF32U
    "i64.trunc_f64_s" => I64TruncF64S
    "i64.trunc_f64_u" => I64TruncF64U
    "i64.reinterpret_f64" => I64ReinterpretF64
    "i64.trunc_sat_f32_s" => I64TruncSatF32S
    "i64.trunc_sat_f32_u" => I64TruncSatF32U
    "i64.trunc_sat_f64_s" => I64TruncSatF64S
    "i64.trunc_sat_f64_u" => I64TruncSatF64U
    _ => self.parse_atomic_instruction(kw)
  }
}

///|
fn Parser::parse_f32_instruction(
  self : Parser,
  kw : String,
) -> @types.Instruction raise WatError {
  match kw {
    "f32.load" => parse_mem_arg(self, fn(m, a, o) { F32Load(m, a, o) })
    "f32.store" => parse_mem_arg(self, fn(m, a, o) { F32Store(m, a, o) })
    "f32.const" => F32Const(self.parse_f32())

    // f32 operations
    "f32.abs" => F32Abs
    "f32.neg" => F32Neg
    "f32.ceil" => F32Ceil
    "f32.floor" => F32Floor
    "f32.trunc" => F32Trunc
    "f32.nearest" => F32Nearest
    "f32.sqrt" => F32Sqrt
    "f32.add" => F32Add
    "f32.sub" => F32Sub
    "f32.mul" => F32Mul
    "f32.div" => F32Div
    "f32.min" => F32Min
    "f32.max" => F32Max
    "f32.copysign" => F32Copysign
    "f32.eq" => F32Eq
    "f32.ne" => F32Ne
    "f32.lt" => F32Lt
    "f32.gt" => F32Gt
    "f32.le" => F32Le
    "f32.ge" => F32Ge
    "f32.convert_i32_s" => F32ConvertI32S
    "f32.convert_i32_u" => F32ConvertI32U
    "f32.convert_i64_s" => F32ConvertI64S
    "f32.convert_i64_u" => F32ConvertI64U
    "f32.demote_f64" => F32DemoteF64
    "f32.reinterpret_i32" => F32ReinterpretI32
    _ => self.parse_atomic_instruction(kw)
  }
}

///|
fn Parser::parse_f64_instruction(
  self : Parser,
  kw : String,
) -> @types.Instruction raise WatError {
  match kw {
    "f64.load" => parse_mem_arg(self, fn(m, a, o) { F64Load(m, a, o) })
    "f64.store" => parse_mem_arg(self, fn(m, a, o) { F64Store(m, a, o) })
    "f64.const" => F64Const(self.parse_f64())

    // f64 operations
    "f64.abs" => F64Abs
    "f64.neg" => F64Neg
    "f64.ceil" => F64Ceil
    "f64.floor" => F64Floor
    "f64.trunc" => F64Trunc
    "f64.nearest" => F64Nearest
    "f64.sqrt" => F64Sqrt
    "f64.add" => F64Add
    "f64.sub" => F64Sub
    "f64.mul" => F64Mul
    "f64.div" => F64Div
    "f64.min" => F64Min
    "f64.max" => F64Max
    "f64.copysign" => F64Copysign
    "f64.eq" => F64Eq
    "f64.ne" => F64Ne
    "f64.lt" => F64Lt
    "f64.gt" => F64Gt
    "f64.le" => F64Le
    "f64.ge" => F64Ge
    "f64.convert_i32_s" => F64ConvertI32S
    "f64.convert_i32_u" => F64ConvertI32U
    "f64.convert_i64_s" => F64ConvertI64S
    "f64.convert_i64_u" => F64ConvertI64U
    "f64.promote_f32" => F64PromoteF32
    "f64.reinterpret_i64" => F64ReinterpretI64
    _ => self.parse_atomic_instruction(kw)
  }
}
