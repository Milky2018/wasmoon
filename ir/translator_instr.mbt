// Instruction translation - the main dispatch for WASM instructions
// Split from translator.mbt for maintainability

///|
/// Translate a single instruction
fn Translator::translate_instruction(
  self : Translator,
  instr : @types.Instruction,
) -> Unit {
  // If we're in unreachable code, only process control flow instructions
  // that may create new reachable regions
  if self.is_unreachable {
    match instr {
      Block(block_type, body) => self.translate_block(block_type, body)
      Loop(block_type, body) => self.translate_loop(block_type, body)
      If(block_type, then_body, else_body) =>
        self.translate_if(block_type, then_body, else_body)
      // All other instructions are dead code, skip them
      _ => return
    }
    return
  }
  match instr {
    Atomic(subopcode, memidx, _, offset) =>
      self.translate_atomic(subopcode, memidx, offset)

    // Constants
    I32Const(n) => {
      let v = self.builder.iconst_i32(n)
      self.push(v)
    }
    I64Const(n) => {
      let v = self.builder.iconst_i64(n)
      self.push(v)
    }
    F32Const(n) => {
      let v = self.builder.fconst_f32(n)
      self.push(v)
    }
    F64Const(n) => {
      let v = self.builder.fconst_f64(n)
      self.push(v)
    }

    // Local variables
    LocalGet(idx) => {
      let v = self.locals[idx]
      self.push(v)
    }
    LocalSet(idx) => {
      let v = self.pop()
      self.locals[idx] = v
    }
    LocalTee(idx) => {
      let v = self.peek()
      self.locals[idx] = v
    }

    // Stack operations
    Drop => self.pop() |> ignore
    Select => {
      let c = self.pop() // condition
      let val2 = self.pop() // false value
      let val1 = self.pop() // true value
      let result = self.builder.select(c, val1, val2)
      self.push(result)
    }
    SelectTyped(_) => {
      // Same as Select - type annotation is for validation only
      let c = self.pop() // condition
      let val2 = self.pop() // false value
      let val1 = self.pop() // true value
      let result = self.builder.select(c, val1, val2)
      self.push(result)
    }

    // i32 arithmetic
    I32Add => self.translate_binary_i32(fn(b, a, v) { b.iadd(a, v) })
    I32Sub => self.translate_binary_i32(fn(b, a, v) { b.isub(a, v) })
    I32Mul => self.translate_binary_i32(fn(b, a, v) { b.imul(a, v) })
    I32DivS => self.translate_binary_i32(fn(b, a, v) { b.sdiv(a, v) })
    I32DivU => self.translate_binary_i32(fn(b, a, v) { b.udiv(a, v) })
    I32RemS => self.translate_binary_i32(fn(b, a, v) { b.srem(a, v) })
    I32RemU => self.translate_binary_i32(fn(b, a, v) { b.urem(a, v) })
    I32And => self.translate_binary_i32(fn(b, a, v) { b.band(a, v) })
    I32Or => self.translate_binary_i32(fn(b, a, v) { b.bor(a, v) })
    I32Xor => self.translate_binary_i32(fn(b, a, v) { b.bxor(a, v) })
    I32Shl => self.translate_binary_i32(fn(b, a, v) { b.ishl(a, v) })
    I32ShrS => self.translate_binary_i32(fn(b, a, v) { b.sshr(a, v) })
    I32ShrU => self.translate_binary_i32(fn(b, a, v) { b.ushr(a, v) })
    I32Rotl => self.translate_binary_i32(fn(b, a, v) { b.rotl(a, v) })
    I32Rotr => self.translate_binary_i32(fn(b, a, v) { b.rotr(a, v) })

    // i32 bit counting
    I32Clz => self.translate_unary_i32(fn(b, a) { b.clz(a) })
    I32Ctz => self.translate_unary_i32(fn(b, a) { b.ctz(a) })
    I32Popcnt => self.translate_unary_i32(fn(b, a) { b.popcnt(a) })

    // i32 comparisons
    I32Eqz => {
      let a = self.pop()
      let zero = self.builder.iconst_i32(0)
      let result = self.builder.icmp_eq(a, zero)
      self.push(result)
    }
    I32Eq => self.translate_icmp(IntCC::Eq)
    I32Ne => self.translate_icmp(IntCC::Ne)
    I32LtS => self.translate_icmp(IntCC::Slt)
    I32LtU => self.translate_icmp(IntCC::Ult)
    I32GtS => self.translate_icmp(IntCC::Sgt)
    I32GtU => self.translate_icmp(IntCC::Ugt)
    I32LeS => self.translate_icmp(IntCC::Sle)
    I32LeU => self.translate_icmp(IntCC::Ule)
    I32GeS => self.translate_icmp(IntCC::Sge)
    I32GeU => self.translate_icmp(IntCC::Uge)

    // i64 arithmetic
    I64Add => self.translate_binary_i64(fn(b, a, v) { b.iadd(a, v) })
    I64Sub => self.translate_binary_i64(fn(b, a, v) { b.isub(a, v) })
    I64Mul => self.translate_binary_i64(fn(b, a, v) { b.imul(a, v) })
    I64MulWideU => {
      let b = self.pop()
      let a = self.pop()
      let lo = self.builder.imul(a, b)
      let hi = self.builder.umulh(a, b)
      self.push(lo)
      self.push(hi)
    }
    I64MulWideS => {
      let b = self.pop()
      let a = self.pop()
      let lo = self.builder.imul(a, b)
      let hi = self.builder.smulh(a, b)
      self.push(lo)
      self.push(hi)
    }
    I64DivS => self.translate_binary_i64(fn(b, a, v) { b.sdiv(a, v) })
    I64DivU => self.translate_binary_i64(fn(b, a, v) { b.udiv(a, v) })
    I64RemS => self.translate_binary_i64(fn(b, a, v) { b.srem(a, v) })
    I64RemU => self.translate_binary_i64(fn(b, a, v) { b.urem(a, v) })
    I64And => self.translate_binary_i64(fn(b, a, v) { b.band(a, v) })
    I64Or => self.translate_binary_i64(fn(b, a, v) { b.bor(a, v) })
    I64Xor => self.translate_binary_i64(fn(b, a, v) { b.bxor(a, v) })
    I64Shl => self.translate_binary_i64(fn(b, a, v) { b.ishl(a, v) })
    I64ShrS => self.translate_binary_i64(fn(b, a, v) { b.sshr(a, v) })
    I64ShrU => self.translate_binary_i64(fn(b, a, v) { b.ushr(a, v) })
    I64Rotl => self.translate_binary_i64(fn(b, a, v) { b.rotl(a, v) })
    I64Rotr => self.translate_binary_i64(fn(b, a, v) { b.rotr(a, v) })

    // i64 bit counting
    I64Clz => self.translate_unary_i64(fn(b, a) { b.clz(a) })
    I64Ctz => self.translate_unary_i64(fn(b, a) { b.ctz(a) })
    I64Popcnt => self.translate_unary_i64(fn(b, a) { b.popcnt(a) })

    // i64 comparisons
    I64Eqz => {
      let a = self.pop()
      let zero = self.builder.iconst_i64(0L)
      let result = self.builder.icmp_eq(a, zero)
      self.push(result)
    }
    I64Eq => self.translate_icmp(IntCC::Eq)
    I64Ne => self.translate_icmp(IntCC::Ne)
    I64LtS => self.translate_icmp(IntCC::Slt)
    I64LtU => self.translate_icmp(IntCC::Ult)
    I64GtS => self.translate_icmp(IntCC::Sgt)
    I64GtU => self.translate_icmp(IntCC::Ugt)
    I64LeS => self.translate_icmp(IntCC::Sle)
    I64LeU => self.translate_icmp(IntCC::Ule)
    I64GeS => self.translate_icmp(IntCC::Sge)
    I64GeU => self.translate_icmp(IntCC::Uge)

    // f32 arithmetic
    F32Add => self.translate_binary_f32(fn(b, a, v) { b.fadd(a, v) })
    F32Sub => self.translate_binary_f32(fn(b, a, v) { b.fsub(a, v) })
    F32Mul => self.translate_binary_f32(fn(b, a, v) { b.fmul(a, v) })
    F32Div => self.translate_binary_f32(fn(b, a, v) { b.fdiv(a, v) })
    F32Min => self.translate_binary_f32(fn(b, a, v) { b.fmin(a, v) })
    F32Max => self.translate_binary_f32(fn(b, a, v) { b.fmax(a, v) })
    F32Copysign => {
      // copysign(x, y) = magnitude of x with sign of y
      let y = self.pop() // sign source
      let x = self.pop() // magnitude source
      // Use bitwise operations to implement copysign
      // result_bits = (x_bits & 0x7FFFFFFF) | (y_bits & 0x80000000)
      let x_bits = self.builder.bitcast(Type::I32, x)
      let y_bits = self.builder.bitcast(Type::I32, y)
      let magnitude = self.builder.band(
        x_bits,
        self.builder.iconst_i32(0x7FFFFFFF),
      )
      let sign = self.builder.band(
        y_bits,
        self.builder.iconst_i32(0x80000000U.reinterpret_as_int()),
      )
      let result_bits = self.builder.bor(magnitude, sign)
      let result = self.builder.bitcast(Type::F32, result_bits)
      self.push(result)
    }

    // f32 unary
    F32Neg => self.translate_unary_f32(fn(b, a) { b.fneg(a) })
    F32Abs => self.translate_unary_f32(fn(b, a) { b.fabs(a) })
    F32Sqrt => self.translate_unary_f32(fn(b, a) { b.fsqrt(a) })
    F32Ceil => self.translate_unary_f32(fn(b, a) { b.fceil(a) })
    F32Floor => self.translate_unary_f32(fn(b, a) { b.ffloor(a) })
    F32Trunc => self.translate_unary_f32(fn(b, a) { b.ftrunc(a) })
    F32Nearest => self.translate_unary_f32(fn(b, a) { b.fnearest(a) })

    // f32 comparisons
    F32Eq => self.translate_fcmp(FloatCC::Eq)
    F32Ne => self.translate_fcmp(FloatCC::Ne)
    F32Lt => self.translate_fcmp(FloatCC::Lt)
    F32Gt => self.translate_fcmp(FloatCC::Gt)
    F32Le => self.translate_fcmp(FloatCC::Le)
    F32Ge => self.translate_fcmp(FloatCC::Ge)

    // f64 arithmetic
    F64Add => self.translate_binary_f64(fn(b, a, v) { b.fadd(a, v) })
    F64Sub => self.translate_binary_f64(fn(b, a, v) { b.fsub(a, v) })
    F64Mul => self.translate_binary_f64(fn(b, a, v) { b.fmul(a, v) })
    F64Div => self.translate_binary_f64(fn(b, a, v) { b.fdiv(a, v) })
    F64Min => self.translate_binary_f64(fn(b, a, v) { b.fmin(a, v) })
    F64Max => self.translate_binary_f64(fn(b, a, v) { b.fmax(a, v) })
    F64Copysign => {
      // copysign(x, y) = magnitude of x with sign of y
      let y = self.pop() // sign source
      let x = self.pop() // magnitude source
      // Use bitwise operations to implement copysign
      // result_bits = (x_bits & 0x7FFFFFFFFFFFFFFF) | (y_bits & 0x8000000000000000)
      let x_bits = self.builder.bitcast(Type::I64, x)
      let y_bits = self.builder.bitcast(Type::I64, y)
      let magnitude = self.builder.band(
        x_bits,
        self.builder.iconst_i64(0x7FFFFFFFFFFFFFFFL),
      )
      let sign = self.builder.band(
        y_bits,
        self.builder.iconst_i64(0x8000000000000000UL.reinterpret_as_int64()),
      )
      let result_bits = self.builder.bor(magnitude, sign)
      let result = self.builder.bitcast(Type::F64, result_bits)
      self.push(result)
    }

    // f64 unary
    F64Neg => self.translate_unary_f64(fn(b, a) { b.fneg(a) })
    F64Abs => self.translate_unary_f64(fn(b, a) { b.fabs(a) })
    F64Sqrt => self.translate_unary_f64(fn(b, a) { b.fsqrt(a) })
    F64Ceil => self.translate_unary_f64(fn(b, a) { b.fceil(a) })
    F64Floor => self.translate_unary_f64(fn(b, a) { b.ffloor(a) })
    F64Trunc => self.translate_unary_f64(fn(b, a) { b.ftrunc(a) })
    F64Nearest => self.translate_unary_f64(fn(b, a) { b.fnearest(a) })

    // f64 comparisons
    F64Eq => self.translate_fcmp(FloatCC::Eq)
    F64Ne => self.translate_fcmp(FloatCC::Ne)
    F64Lt => self.translate_fcmp(FloatCC::Lt)
    F64Gt => self.translate_fcmp(FloatCC::Gt)
    F64Le => self.translate_fcmp(FloatCC::Le)
    F64Ge => self.translate_fcmp(FloatCC::Ge)

    // Conversions
    I32WrapI64 => {
      let a = self.pop()
      let result = self.builder.ireduce(Type::I32, a)
      self.push(result)
    }
    I64ExtendI32S => {
      let a = self.pop()
      let result = self.builder.sextend(Type::I64, a)
      self.push(result)
    }
    I64ExtendI32U => {
      let a = self.pop()
      let result = self.builder.uextend(Type::I64, a)
      self.push(result)
    }
    // In-place sign extension instructions 
    I32Extend8S => {
      let a = self.pop()
      let result = self.builder.sextend8(Type::I32, a)
      self.push(result)
    }
    I32Extend16S => {
      let a = self.pop()
      let result = self.builder.sextend16(Type::I32, a)
      self.push(result)
    }
    I64Extend8S => {
      let a = self.pop()
      let result = self.builder.sextend8(Type::I64, a)
      self.push(result)
    }
    I64Extend16S => {
      let a = self.pop()
      let result = self.builder.sextend16(Type::I64, a)
      self.push(result)
    }
    I64Extend32S => {
      let a = self.pop()
      let result = self.builder.sextend32(a)
      self.push(result)
    }
    F32DemoteF64 => {
      let a = self.pop()
      let result = self.builder.fdemote(a)
      self.push(result)
    }
    F64PromoteF32 => {
      let a = self.pop()
      let result = self.builder.fpromote(a)
      self.push(result)
    }
    I32TruncF32S | I32TruncF64S => {
      let a = self.pop()
      let result = self.builder.fcvt_to_sint(Type::I32, a)
      self.push(result)
    }
    I32TruncF32U | I32TruncF64U => {
      let a = self.pop()
      let result = self.builder.fcvt_to_uint(Type::I32, a)
      self.push(result)
    }
    I64TruncF32S | I64TruncF64S => {
      let a = self.pop()
      let result = self.builder.fcvt_to_sint(Type::I64, a)
      self.push(result)
    }
    I64TruncF32U | I64TruncF64U => {
      let a = self.pop()
      let result = self.builder.fcvt_to_uint(Type::I64, a)
      self.push(result)
    }
    F32ConvertI32S | F32ConvertI64S => {
      let a = self.pop()
      let result = self.builder.sint_to_fcvt(Type::F32, a)
      self.push(result)
    }
    F32ConvertI32U | F32ConvertI64U => {
      let a = self.pop()
      let result = self.builder.uint_to_fcvt(Type::F32, a)
      self.push(result)
    }
    F64ConvertI32S | F64ConvertI64S => {
      let a = self.pop()
      let result = self.builder.sint_to_fcvt(Type::F64, a)
      self.push(result)
    }
    F64ConvertI32U | F64ConvertI64U => {
      let a = self.pop()
      let result = self.builder.uint_to_fcvt(Type::F64, a)
      self.push(result)
    }
    // Saturating truncation operations
    I32TruncSatF32S | I32TruncSatF64S => {
      let a = self.pop()
      let result = self.builder.fcvt_to_sint_sat(Type::I32, a)
      self.push(result)
    }
    I32TruncSatF32U | I32TruncSatF64U => {
      let a = self.pop()
      let result = self.builder.fcvt_to_uint_sat(Type::I32, a)
      self.push(result)
    }
    I64TruncSatF32S | I64TruncSatF64S => {
      let a = self.pop()
      let result = self.builder.fcvt_to_sint_sat(Type::I64, a)
      self.push(result)
    }
    I64TruncSatF32U | I64TruncSatF64U => {
      let a = self.pop()
      let result = self.builder.fcvt_to_uint_sat(Type::I64, a)
      self.push(result)
    }
    I32ReinterpretF32
    | I64ReinterpretF64
    | F32ReinterpretI32
    | F64ReinterpretI64 => {
      let a = self.pop()
      let target_ty = match instr {
        I32ReinterpretF32 => Type::I32
        I64ReinterpretF64 => Type::I64
        F32ReinterpretI32 => Type::F32
        F64ReinterpretI64 => Type::F64
        _ => Type::I32
      }
      let result = self.builder.bitcast(target_ty, a)
      self.push(result)
    }

    // Memory operations (desugared via FuncEnvironment)
    // - memory 0 (memory32): relies on guard pages (no explicit bounds checks)
    // - others: use explicit bounds checks
    I32Load(memidx, _, offset) => {
      let addr = self.pop()
      let result = self.func_env.translate_memory_load(
        self.builder,
        self.vmctx,
        memidx,
        Type::I32,
        addr,
        offset,
      )
      self.push(result)
    }
    I64Load(memidx, _, offset) => {
      let addr = self.pop()
      let result = self.func_env.translate_memory_load(
        self.builder,
        self.vmctx,
        memidx,
        Type::I64,
        addr,
        offset,
      )
      self.push(result)
    }
    F32Load(memidx, _, offset) => {
      let addr = self.pop()
      let result = self.func_env.translate_memory_load(
        self.builder,
        self.vmctx,
        memidx,
        Type::F32,
        addr,
        offset,
      )
      self.push(result)
    }
    F64Load(memidx, _, offset) => {
      let addr = self.pop()
      let result = self.func_env.translate_memory_load(
        self.builder,
        self.vmctx,
        memidx,
        Type::F64,
        addr,
        offset,
      )
      self.push(result)
    }

    // Narrow load operations (desugared via FuncEnvironment)
    I32Load8S(memidx, _, offset) => {
      let addr = self.pop()
      let result = self.func_env.translate_memory_load_narrow(
        self.builder,
        self.vmctx,
        memidx,
        Type::I32,
        8,
        true,
        addr,
        offset,
      )
      self.push(result)
    }
    I32Load8U(memidx, _, offset) => {
      let addr = self.pop()
      let result = self.func_env.translate_memory_load_narrow(
        self.builder,
        self.vmctx,
        memidx,
        Type::I32,
        8,
        false,
        addr,
        offset,
      )
      self.push(result)
    }
    I32Load16S(memidx, _, offset) => {
      let addr = self.pop()
      let result = self.func_env.translate_memory_load_narrow(
        self.builder,
        self.vmctx,
        memidx,
        Type::I32,
        16,
        true,
        addr,
        offset,
      )
      self.push(result)
    }
    I32Load16U(memidx, _, offset) => {
      let addr = self.pop()
      let result = self.func_env.translate_memory_load_narrow(
        self.builder,
        self.vmctx,
        memidx,
        Type::I32,
        16,
        false,
        addr,
        offset,
      )
      self.push(result)
    }
    I64Load8S(memidx, _, offset) => {
      let addr = self.pop()
      let result = self.func_env.translate_memory_load_narrow(
        self.builder,
        self.vmctx,
        memidx,
        Type::I64,
        8,
        true,
        addr,
        offset,
      )
      self.push(result)
    }
    I64Load8U(memidx, _, offset) => {
      let addr = self.pop()
      let result = self.func_env.translate_memory_load_narrow(
        self.builder,
        self.vmctx,
        memidx,
        Type::I64,
        8,
        false,
        addr,
        offset,
      )
      self.push(result)
    }
    I64Load16S(memidx, _, offset) => {
      let addr = self.pop()
      let result = self.func_env.translate_memory_load_narrow(
        self.builder,
        self.vmctx,
        memidx,
        Type::I64,
        16,
        true,
        addr,
        offset,
      )
      self.push(result)
    }
    I64Load16U(memidx, _, offset) => {
      let addr = self.pop()
      let result = self.func_env.translate_memory_load_narrow(
        self.builder,
        self.vmctx,
        memidx,
        Type::I64,
        16,
        false,
        addr,
        offset,
      )
      self.push(result)
    }
    I64Load32S(memidx, _, offset) => {
      let addr = self.pop()
      let result = self.func_env.translate_memory_load_narrow(
        self.builder,
        self.vmctx,
        memidx,
        Type::I64,
        32,
        true,
        addr,
        offset,
      )
      self.push(result)
    }
    I64Load32U(memidx, _, offset) => {
      let addr = self.pop()
      let result = self.func_env.translate_memory_load_narrow(
        self.builder,
        self.vmctx,
        memidx,
        Type::I64,
        32,
        false,
        addr,
        offset,
      )
      self.push(result)
    }

    // Store operations (desugared via FuncEnvironment to StorePtr with explicit bounds check)
    I32Store(memidx, _, offset) => {
      let value = self.pop()
      let addr = self.pop()
      self.func_env.translate_memory_store(
        self.builder,
        self.vmctx,
        memidx,
        Type::I32,
        addr,
        value,
        offset,
      )
    }
    I64Store(memidx, _, offset) => {
      let value = self.pop()
      let addr = self.pop()
      self.func_env.translate_memory_store(
        self.builder,
        self.vmctx,
        memidx,
        Type::I64,
        addr,
        value,
        offset,
      )
    }
    F32Store(memidx, _, offset) => {
      let value = self.pop()
      let addr = self.pop()
      self.func_env.translate_memory_store(
        self.builder,
        self.vmctx,
        memidx,
        Type::F32,
        addr,
        value,
        offset,
      )
    }
    F64Store(memidx, _, offset) => {
      let value = self.pop()
      let addr = self.pop()
      self.func_env.translate_memory_store(
        self.builder,
        self.vmctx,
        memidx,
        Type::F64,
        addr,
        value,
        offset,
      )
    }

    // Narrow store operations (desugared via FuncEnvironment)
    I32Store8(memidx, _, offset) => {
      let value = self.pop()
      let addr = self.pop()
      self.func_env.translate_memory_store_narrow(
        self.builder,
        self.vmctx,
        memidx,
        8,
        addr,
        value,
        offset,
      )
    }
    I32Store16(memidx, _, offset) => {
      let value = self.pop()
      let addr = self.pop()
      self.func_env.translate_memory_store_narrow(
        self.builder,
        self.vmctx,
        memidx,
        16,
        addr,
        value,
        offset,
      )
    }
    I64Store8(memidx, _, offset) => {
      let value = self.pop()
      let addr = self.pop()
      self.func_env.translate_memory_store_narrow(
        self.builder,
        self.vmctx,
        memidx,
        8,
        addr,
        value,
        offset,
      )
    }
    I64Store16(memidx, _, offset) => {
      let value = self.pop()
      let addr = self.pop()
      self.func_env.translate_memory_store_narrow(
        self.builder,
        self.vmctx,
        memidx,
        16,
        addr,
        value,
        offset,
      )
    }
    I64Store32(memidx, _, offset) => {
      let value = self.pop()
      let addr = self.pop()
      self.func_env.translate_memory_store_narrow(
        self.builder,
        self.vmctx,
        memidx,
        32,
        addr,
        value,
        offset,
      )
    }

    // Control flow
    Unreachable => {
      self.builder.trap("unreachable")
      self.is_unreachable = true
    }
    Nop => () // No operation
    Return => {
      let results = self.builder.get_function().results
      let return_vals : Array[Value] = []
      for _ in 0..<results.length() {
        return_vals.push(self.pop())
      }
      return_vals.rev_in_place()
      self.builder.return_(return_vals)
      self.is_unreachable = true
    }
    Block(block_type, body) => self.translate_block(block_type, body)
    Loop(block_type, body) => self.translate_loop(block_type, body)
    If(block_type, then_body, else_body) =>
      self.translate_if(block_type, then_body, else_body)
    Br(depth) => self.translate_br(depth)
    BrIf(depth) => self.translate_br_if(depth)
    BrTable(labels, default_) => self.translate_br_table(labels, default_)
    BrOnNull(depth) => self.translate_br_on_null(depth)
    BrOnNonNull(depth) => self.translate_br_on_non_null(depth)

    // Function calls - spill locals before call when inside try_table
    // because the callee might throw and we need caller's locals at call point
    Call(func_idx) => {
      self.spill_locals_if_in_try()
      self.translate_call(func_idx)
    }
    CallIndirect(type_idx, table_idx) => {
      self.spill_locals_if_in_try()
      self.translate_call_indirect(type_idx, table_idx)
    }
    CallRef(type_idx) => {
      self.spill_locals_if_in_try()
      self.translate_call_ref(type_idx)
    }
    ReturnCall(func_idx) => {
      self.spill_locals_if_in_try()
      self.translate_return_call(func_idx)
    }
    ReturnCallIndirect(type_idx, table_idx) => {
      self.spill_locals_if_in_try()
      self.translate_return_call_indirect(type_idx, table_idx)
    }
    ReturnCallRef(type_idx) => {
      self.spill_locals_if_in_try()
      self.translate_return_call_ref(type_idx)
    }

    // Memory management (multi-memory support via memidx)
    // Note: These use IR opcodes instead of desugaring because they require
    // libcalls that are handled in the VCode emit phase
    MemoryGrow(memidx) => {
      let delta = self.pop()
      let is_mem64 = memidx < self.memory_is_64.length() &&
        self.memory_is_64[memidx]

      // Use the module/override maximum for memory 0.
      // For other memories, rely on the runtime descriptor's max.
      let max_pages = if memidx == 0 { self.memory_max } else { None }
      let result = match max_pages {
        Some(max) =>
          self.builder.memory_grow(
            memidx,
            delta,
            max_pages=max,
            is_memory64=is_mem64,
          )
        None => self.builder.memory_grow(memidx, delta, is_memory64=is_mem64)
      }
      self.push(result)
    }
    MemorySize(memidx) => {
      let is_mem64 = memidx < self.memory_is_64.length() &&
        self.memory_is_64[memidx]
      let result = self.builder.memory_size(memidx, is_memory64=is_mem64)
      self.push(result)
    }
    MemoryFill(memidx) => {
      let n = self.pop() // size
      let val = self.pop() // value (byte)
      let d = self.pop() // destination
      self.builder.memory_fill(memidx, d, val, n)
    }
    MemoryCopy(dst_memidx, src_memidx) => {
      let n = self.pop() // size
      let s = self.pop() // source
      let d = self.pop() // destination
      self.builder.memory_copy(dst_memidx, src_memidx, d, s, n)
    }
    MemoryInit(memidx, data_idx) => {
      let n = self.pop() // size
      let s = self.pop() // source offset in data segment
      let d = self.pop() // destination offset in memory
      self.builder.memory_init(memidx, data_idx, d, s, n)
    }
    DataDrop(data_idx) => self.builder.data_drop(data_idx)

    // Table bulk operations
    TableFill(table_idx) => {
      let n = self.pop() // size
      let val = self.pop() // value (ref)
      let d = self.pop() // destination
      self.builder.table_fill(table_idx, d, val, n)
    }
    TableCopy(dst_table_idx, src_table_idx) => {
      let n = self.pop() // size
      let s = self.pop() // source
      let d = self.pop() // destination
      self.builder.table_copy(dst_table_idx, src_table_idx, d, s, n)
    }
    TableInit(table_idx, elem_idx) => {
      let n = self.pop() // size
      let s = self.pop() // source offset in element segment
      let d = self.pop() // destination offset in table
      self.builder.table_init(table_idx, elem_idx, d, s, n)
    }
    ElemDrop(elem_idx) => self.builder.elem_drop(elem_idx)

    // Reference types
    RefNull(ref_type) => {
      // JIT/reference encoding uses 0 for null.
      let result_ty = Type::from_wasm(ref_type)
      let result = self.builder.iconst(result_ty, @types.NULL_REF)
      self.push(result)
    }
    RefIsNull => {
      let ref_val = self.pop()
      let null_sentinel = self.builder.iconst(ref_val.ty, @types.NULL_REF)
      let result = self.builder.icmp_eq(ref_val, null_sentinel)
      self.push(result)
    }
    RefFunc(func_idx) => {
      // Create a function reference - use GetFuncRef to get tagged function pointer
      // The pointer is tagged with FUNCREF_TAG (bit 61) for ref.test detection
      let result = self.builder.get_func_ref(func_idx)
      self.push(result)
    }
    RefAsNonNull => {
      // ref.as_non_null: convert nullable ref to non-null ref
      // Pop the reference, check if null, trap if so, otherwise push back
      let ref_val = self.pop()
      let null_sentinel = self.builder.iconst(ref_val.ty, @types.NULL_REF)
      let is_null = self.builder.icmp_eq(ref_val, null_sentinel)

      // Create trap block and continuation block
      let trap_block = self.builder.create_block()
      let continue_block = self.builder.create_block()

      // Branch: if is_null goto trap_block else continue_block
      self.builder.brnz(is_null, trap_block, continue_block)

      // Trap block: emit trap for null reference
      self.builder.switch_to_block(trap_block)
      self.builder.trap("null reference")

      // Continue block: push the non-null ref back on stack
      self.builder.switch_to_block(continue_block)
      self.push(ref_val)
    }
    RefEqInstr => {
      // ref.eq: compare two references for equality
      let ref2 = self.pop()
      let ref1 = self.pop()
      let result = self.builder.ref_eq(ref1, ref2)
      self.push(result)
    }
    TableGet(table_idx) => {
      // Desugar to load from vmctx.tables[table_idx][elem_idx]
      let elem_idx = self.pop()
      let is_table64 = table_idx < self.table_is_64.length() &&
        self.table_is_64[table_idx]
      let result = self.func_env.translate_table_get(
        self.builder,
        self.vmctx,
        table_idx,
        elem_idx,
        is_table64~,
      )
      self.push(result)
    }
    TableSet(table_idx) => {
      // Desugar to store to vmctx.tables[table_idx][elem_idx]
      let value = self.pop()
      let elem_idx = self.pop()
      let is_table64 = table_idx < self.table_is_64.length() &&
        self.table_is_64[table_idx]
      self.func_env.translate_table_set(
        self.builder,
        self.vmctx,
        table_idx,
        elem_idx,
        value,
        is_table64~,
      )
    }
    TableSize(table_idx) => {
      // Desugar to load from vmctx.table_sizes[table_idx]
      let is_table64 = table_idx < self.table_is_64.length() &&
        self.table_is_64[table_idx]
      let result = self.func_env.translate_table_size(
        self.builder,
        self.vmctx,
        table_idx,
        is_table64~,
      )
      self.push(result)
    }
    TableGrow(table_idx) => {
      // Note: Uses IR opcode instead of desugaring because it requires
      // a libcall that is handled in the VCode emit phase
      // Stack: [init_value, delta] -> [result]
      let delta = self.pop()
      let init_value = self.pop()
      let result = self.builder.table_grow(table_idx, delta, init_value)
      self.push(result)
    }
    GlobalGet(idx) => {
      // Desugar to load from vmctx.globals[idx]
      let result = self.func_env.translate_global_get(
        self.builder,
        self.vmctx,
        idx,
      )
      self.push(result)
    }
    GlobalSet(idx) => {
      // Desugar to store to vmctx.globals[idx]
      let value = self.pop()
      self.func_env.translate_global_set(self.builder, self.vmctx, idx, value)
    }

    // GC instructions - struct operations
    StructNew(type_idx) => {
      // Pop field values from stack (in reverse order)
      let field_count = self.get_struct_field_count(type_idx)
      let fields : Array[Value] = []
      for i = 0; i < field_count; i = i + 1 {
        fields.push(self.pop())
      }
      // Reverse to get correct order
      fields.rev_in_place()
      let result = self.builder.struct_new(type_idx, fields)
      self.push(result)
    }
    StructNewDefault(type_idx) => {
      let result = self.builder.struct_new_default(type_idx)
      self.push(result)
    }
    StructGet(type_idx, field_idx) => {
      let struct_ref = self.pop()
      let field_type = self.get_struct_field_ir_type(type_idx, field_idx)
      let result = self.builder.struct_get(
        type_idx, field_idx, struct_ref, field_type,
      )
      self.push(result)
    }
    StructGetS(type_idx, field_idx) => {
      let struct_ref = self.pop()
      let field_type = self.get_struct_field_ir_type(type_idx, field_idx)
      let byte_width = self.get_struct_field_byte_width(type_idx, field_idx)
      let result = self.builder.struct_get_s(
        type_idx, field_idx, struct_ref, field_type, byte_width,
      )
      self.push(result)
    }
    StructGetU(type_idx, field_idx) => {
      let struct_ref = self.pop()
      let field_type = self.get_struct_field_ir_type(type_idx, field_idx)
      let byte_width = self.get_struct_field_byte_width(type_idx, field_idx)
      let result = self.builder.struct_get_u(
        type_idx, field_idx, struct_ref, field_type, byte_width,
      )
      self.push(result)
    }
    StructSet(type_idx, field_idx) => {
      let value = self.pop()
      let struct_ref = self.pop()
      self.builder.struct_set(type_idx, field_idx, struct_ref, value)
    }

    // GC instructions - array operations
    ArrayNew(type_idx) => {
      // Stack: [init_value, length] -> [arrayref]
      let length = self.pop()
      let init_value = self.pop()
      let result = self.builder.array_new(type_idx, init_value, length)
      self.push(result)
    }
    ArrayNewDefault(type_idx) => {
      // Stack: [length] -> [arrayref]
      let length = self.pop()
      let result = self.builder.array_new_default(type_idx, length)
      self.push(result)
    }
    ArrayNewFixed(type_idx, count) => {
      // Pop count values from stack
      let elements : Array[Value] = []
      for i = 0; i < count; i = i + 1 {
        elements.push(self.pop())
      }
      // Reverse to get correct order
      elements.rev_in_place()
      let result = self.builder.array_new_fixed(type_idx, count, elements)
      self.push(result)
    }
    ArrayGet(type_idx) => {
      // Stack: [arrayref, index] -> [value]
      let index = self.pop()
      let array_ref = self.pop()
      let elem_type = self.get_array_element_ir_type(type_idx)
      let result = self.builder.array_get(type_idx, array_ref, index, elem_type)
      self.push(result)
    }
    ArrayGetS(type_idx) => {
      let index = self.pop()
      let array_ref = self.pop()
      let elem_type = self.get_array_element_ir_type(type_idx)
      let byte_width = self.get_array_element_byte_width(type_idx)
      let result = self.builder.array_get_s(
        type_idx, array_ref, index, elem_type, byte_width,
      )
      self.push(result)
    }
    ArrayGetU(type_idx) => {
      let index = self.pop()
      let array_ref = self.pop()
      let elem_type = self.get_array_element_ir_type(type_idx)
      let byte_width = self.get_array_element_byte_width(type_idx)
      let result = self.builder.array_get_u(
        type_idx, array_ref, index, elem_type, byte_width,
      )
      self.push(result)
    }
    ArraySet(type_idx) => {
      // Stack: [arrayref, index, value] -> []
      let value = self.pop()
      let index = self.pop()
      let array_ref = self.pop()
      self.builder.array_set(type_idx, array_ref, index, value)
    }
    ArrayLen => {
      let array_ref = self.pop()
      let result = self.builder.array_len(array_ref)
      self.push(result)
    }
    ArrayFill(type_idx) => {
      // Stack: [arrayref, offset, value, count] -> []
      let count = self.pop()
      let value = self.pop()
      let offset = self.pop()
      let array_ref = self.pop()
      self.builder.array_fill(type_idx, array_ref, offset, value, count)
    }
    ArrayCopy(dst_type_idx, src_type_idx) => {
      // Stack: [dst, dst_offset, src, src_offset, count] -> []
      let count = self.pop()
      let src_offset = self.pop()
      let src = self.pop()
      let dst_offset = self.pop()
      let dst = self.pop()
      self.builder.array_copy(
        dst_type_idx, src_type_idx, dst, dst_offset, src, src_offset, count,
      )
    }
    ArrayNewData(type_idx, data_idx) => {
      // Stack: [data_offset, length] -> [arrayref]
      let length = self.pop()
      let data_offset = self.pop()
      let result = self.builder.array_new_data(
        type_idx, data_idx, data_offset, length,
      )
      self.push(result)
    }
    ArrayNewElem(type_idx, elem_idx) => {
      // Stack: [elem_offset, length] -> [arrayref]
      let length = self.pop()
      let elem_offset = self.pop()
      let result = self.builder.array_new_elem(
        type_idx, elem_idx, elem_offset, length,
      )
      self.push(result)
    }
    ArrayInitData(type_idx, data_idx) => {
      // Stack: [arrayref, arr_offset, data_offset, length] -> []
      let length = self.pop()
      let data_offset = self.pop()
      let arr_offset = self.pop()
      let array_ref = self.pop()
      self.builder.array_init_data(
        type_idx, data_idx, array_ref, arr_offset, data_offset, length,
      )
    }
    ArrayInitElem(type_idx, elem_idx) => {
      // Stack: [arrayref, arr_offset, elem_offset, length] -> []
      let length = self.pop()
      let elem_offset = self.pop()
      let arr_offset = self.pop()
      let array_ref = self.pop()
      self.builder.array_init_elem(
        type_idx, elem_idx, array_ref, arr_offset, elem_offset, length,
      )
    }

    // GC instructions - i31 operations
    RefI31 => {
      let value = self.pop()
      let result = self.builder.i31_new(value)
      self.push(result)
    }
    I31GetS => {
      let i31_ref = self.pop()
      let result = self.builder.i31_get_s(i31_ref)
      self.push(result)
    }
    I31GetU => {
      let i31_ref = self.pop()
      let result = self.builder.i31_get_u(i31_ref)
      self.push(result)
    }

    // GC instructions - type conversions
    AnyConvertExtern => {
      let extern_ref = self.pop()
      let result = self.builder.any_convert_extern(extern_ref)
      self.push(result)
    }
    ExternConvertAny => {
      let any_ref = self.pop()
      let result = self.builder.extern_convert_any(any_ref)
      self.push(result)
    }

    // Type testing/casting - these are more complex, need runtime support
    RefTest(value_type) => {
      let ref_val = self.pop()
      let type_idx = self.extract_type_idx(value_type)
      let result = self.builder.ref_test(type_idx, false, ref_val)
      self.push(result)
    }
    RefTestNull(value_type) => {
      let ref_val = self.pop()
      let type_idx = self.extract_type_idx(value_type)
      let result = self.builder.ref_test(type_idx, true, ref_val)
      self.push(result)
    }
    RefCast(value_type) => {
      let ref_val = self.pop()
      let type_idx = self.extract_type_idx(value_type)
      let result = self.builder.ref_cast(type_idx, false, ref_val)
      self.push(result)
    }
    RefCastNull(value_type) => {
      let ref_val = self.pop()
      let type_idx = self.extract_type_idx(value_type)
      let result = self.builder.ref_cast(type_idx, true, ref_val)
      self.push(result)
    }
    BrOnCast(label_depth, _from_type, to_type) =>
      self.translate_br_on_cast(label_depth, to_type)
    BrOnCastFail(label_depth, _from_type, to_type) =>
      self.translate_br_on_cast_fail(label_depth, to_type)

    // Exception handling
    // Uses setjmp/longjmp pattern in the JIT runtime
    Throw(tag_idx) => {
      // Get the tag's parameter types to know how many values to pop
      let tag_types = self.get_tag_param_types(tag_idx)

      // Pop exception values from stack (in reverse order)
      let values : Array[Value] = Array::make(
        tag_types.length(),
        self.builder.iconst_i32(0),
      )
      for i = tag_types.length() - 1; i >= 0; i = i - 1 {
        values[i] = self.pop()
      }

      // Spill all locals before throw so catch handlers see throw-time values
      self.spill_locals_if_in_try()

      // Emit Throw IR opcode with the exception values
      self.builder.emit_throw(tag_idx, values)
      self.is_unreachable = true
    }
    ThrowRef => {
      // Pop exnref from stack
      let exnref = self.pop()
      // Spill all locals before throw so catch handlers see throw-time values
      self.spill_locals_if_in_try()
      // Emit ThrowRef IR opcode
      self.builder.emit_throw_ref(exnref)
      self.is_unreachable = true
    }
    TryTable(block_type, handlers, body) => {
      // Exception handling via setjmp/longjmp
      //
      // The TryTableBegin opcode returns:
      // - 0 on normal entry (first setjmp return)
      // - non-zero on exception catch (longjmp return with handler_id)
      //
      // Flow:
      // 1. Call TryTableBegin (setjmp)
      // 2. If result != 0, branch to catch_dispatch
      // 3. Otherwise, execute try body
      // 4. In catch_dispatch: match tag and branch to handler

      let handler_id = self.block_stack.length() // Use stack depth as unique ID

      // Create blocks for control flow
      let try_body_block = self.builder.create_block()
      let catch_dispatch = self.builder.create_block()
      let try_continuation = self.builder.create_block()

      // Emit TryTableBegin - sets up exception handler and calls setjmp
      let setjmp_result = self.builder.try_table_begin(handler_id)

      // Branch based on setjmp result: 0 = normal, non-zero = exception caught
      let zero = self.builder.iconst_i32(0)
      let is_exception = self.builder.icmp_ne(setjmp_result, zero)
      self.builder.brnz(is_exception, catch_dispatch, try_body_block)

      // Save local types before translating body for proper restoration in catch
      let local_types : Array[Type] = []
      for loc in self.locals {
        local_types.push(loc.ty)
      }
      let num_locals = local_types.length()

      // === Try body block ===
      self.builder.switch_to_block(try_body_block)

      // Increment try_table_depth so spill_locals_if_in_try knows to spill
      // Note: decrement happens AFTER all catch handlers are translated,
      // so catch handlers can still spill for outer try_tables
      self.try_table_depth = self.try_table_depth + 1

      // Translate the body using normal block translation
      self.translate_block(block_type, body)

      // Save post-body locals for the normal continuation path
      // (locals modified in try body should be visible after try_table)
      let post_body_locals = self.locals.copy()

      // Emit TryTableEnd - pops exception handler
      self.builder.try_table_end(handler_id)

      // Jump to continuation after try body
      if not(self.is_unreachable) &&
        self.builder.current_block() is Some(blk) &&
        blk.terminator is None {
        self.builder.jump(try_continuation, [])
      }

      // === Catch dispatch block ===
      self.builder.switch_to_block(catch_dispatch)

      // Load locals from spilled storage (saved before throw/call).
      // v128 locals are stored as two i64 words; other locals are one word.
      self.locals.clear()
      let mut spill_idx = 0
      for i in 0..<num_locals {
        match local_types[i] {
          V128 => {
            let lo = self.builder.get_spilled_local(spill_idx)
            let hi = self.builder.get_spilled_local(spill_idx + 1)
            spill_idx += 2
            self.locals.push(self.spill_words_to_v128(lo, hi))
          }
          ty => {
            let spilled_bits = self.builder.get_spilled_local(spill_idx)
            spill_idx += 1
            let restored_val = self.i64_bits_to_local(spilled_bits, ty)
            self.locals.push(restored_val)
          }
        }
      }

      // Get exception tag for matching
      let exn_tag = self.builder.get_exception_tag()

      // Process each handler
      // Note: handlers reference labels in the OUTER block stack, not inside try_table
      for handler in handlers {
        match handler {
          Catch(tag_idx, label_depth) => {
            // Check if exception tag matches this handler
            let handler_tag = self.builder.iconst_i32(tag_idx)
            let tag_matches = self.builder.icmp_eq(exn_tag, handler_tag)

            // Create block for next handler check
            let next_check = self.builder.create_block()

            // If matches, branch to handler; otherwise continue checking
            let handler_block = self.builder.create_block()
            self.builder.brnz(tag_matches, handler_block, next_check)

            // In handler block: pop handler and branch to label
            self.builder.switch_to_block(handler_block)
            self.emit_catch_branch(tag_idx, label_depth, handler_id)
            self.builder.switch_to_block(next_check)
          }
          CatchRef(tag_idx, label_depth) => {
            // Same as Catch but also pushes exnref
            let handler_tag = self.builder.iconst_i32(tag_idx)
            let tag_matches = self.builder.icmp_eq(exn_tag, handler_tag)
            let next_check = self.builder.create_block()
            let handler_block = self.builder.create_block()
            self.builder.brnz(tag_matches, handler_block, next_check)
            self.builder.switch_to_block(handler_block)
            self.emit_catch_ref_branch(tag_idx, label_depth, handler_id)
            self.builder.switch_to_block(next_check)
          }
          CatchAll(label_depth) => {
            // Catch any exception - no tag check needed
            self.emit_catch_all_branch(label_depth, handler_id)
            // No need to continue checking after catch_all
            break
          }
          CatchAllRef(label_depth) => {
            // Catch any exception with exnref
            self.emit_catch_all_ref_branch(label_depth, handler_id)
            break
          }
        }
      }

      // If no handler matched, rethrow (delegate to outer handler)
      // Use depth=1 to skip this handler and propagate to the next outer one
      // (depth=0 would cause infinite loop by re-entering this same handler)
      if self.builder.current_block() is Some(blk) && blk.terminator is None {
        self.builder.delegate(1) // Propagate to outer handler
      }

      // Decrement try_table_depth AFTER all catch handlers are translated
      // This ensures catch handlers can still spill for outer try_tables
      self.try_table_depth = self.try_table_depth - 1

      // === Continuation block ===
      self.builder.switch_to_block(try_continuation)

      // Restore post-body locals for the normal continuation path
      // This ensures locals modified in the try body are visible after try_table
      self.locals.clear()
      for loc in post_body_locals {
        self.locals.push(loc)
      }
      self.is_unreachable = false
    }
    // ============ SIMD Instructions ============

    // V128 constant
    V128Const(bytes) => {
      let v = self.builder.v128_const(bytes)
      self.push(v)
    }

    // Splat operations (scalar -> vector)
    I8x16Splat => {
      let val = self.pop()
      let result = self.builder.v128_splat8(val)
      self.push(result)
    }
    I16x8Splat => {
      let val = self.pop()
      let result = self.builder.v128_splat16(val)
      self.push(result)
    }
    I32x4Splat => {
      let val = self.pop()
      let result = self.builder.v128_splat32(val)
      self.push(result)
    }
    I64x2Splat => {
      let val = self.pop()
      let result = self.builder.v128_splat64(val)
      self.push(result)
    }
    F32x4Splat => {
      let val = self.pop()
      let result = self.builder.v128_splat_f32(val)
      self.push(result)
    }
    F64x2Splat => {
      let val = self.pop()
      let result = self.builder.v128_splat_f64(val)
      self.push(result)
    }

    // Extract lane operations (vector -> scalar)
    I8x16ExtractLaneS(lane) => {
      let vec = self.pop()
      let result = self.builder.v128_extract8s(vec, lane)
      self.push(result)
    }
    I8x16ExtractLaneU(lane) => {
      let vec = self.pop()
      let result = self.builder.v128_extract8u(vec, lane)
      self.push(result)
    }
    I16x8ExtractLaneS(lane) => {
      let vec = self.pop()
      let result = self.builder.v128_extract16s(vec, lane)
      self.push(result)
    }
    I16x8ExtractLaneU(lane) => {
      let vec = self.pop()
      let result = self.builder.v128_extract16u(vec, lane)
      self.push(result)
    }
    I32x4ExtractLane(lane) => {
      let vec = self.pop()
      let result = self.builder.v128_extract32(vec, lane)
      self.push(result)
    }
    I64x2ExtractLane(lane) => {
      let vec = self.pop()
      let result = self.builder.v128_extract64(vec, lane)
      self.push(result)
    }
    F32x4ExtractLane(lane) => {
      let vec = self.pop()
      let result = self.builder.v128_extract_f32(vec, lane)
      self.push(result)
    }
    F64x2ExtractLane(lane) => {
      let vec = self.pop()
      let result = self.builder.v128_extract_f64(vec, lane)
      self.push(result)
    }

    // Replace lane operations (vector, scalar -> vector)
    I8x16ReplaceLane(lane) => {
      let val = self.pop()
      let vec = self.pop()
      let result = self.builder.v128_replace8(vec, val, lane)
      self.push(result)
    }
    I16x8ReplaceLane(lane) => {
      let val = self.pop()
      let vec = self.pop()
      let result = self.builder.v128_replace16(vec, val, lane)
      self.push(result)
    }
    I32x4ReplaceLane(lane) => {
      let val = self.pop()
      let vec = self.pop()
      let result = self.builder.v128_replace32(vec, val, lane)
      self.push(result)
    }
    I64x2ReplaceLane(lane) => {
      let val = self.pop()
      let vec = self.pop()
      let result = self.builder.v128_replace64(vec, val, lane)
      self.push(result)
    }
    F32x4ReplaceLane(lane) => {
      let val = self.pop()
      let vec = self.pop()
      let result = self.builder.v128_replace_f32(vec, val, lane)
      self.push(result)
    }
    F64x2ReplaceLane(lane) => {
      let val = self.pop()
      let vec = self.pop()
      let result = self.builder.v128_replace_f64(vec, val, lane)
      self.push(result)
    }

    // Shuffle and swizzle
    I8x16Shuffle(lanes) => {
      let b = self.pop()
      let a = self.pop()
      let result = self.builder.v128_shuffle(a, b, lanes)
      self.push(result)
    }
    I8x16Swizzle => {
      let b = self.pop()
      let a = self.pop()
      let result = self.builder.v128_swizzle(a, b)
      self.push(result)
    }

    // Bitwise operations
    V128Not => {
      let a = self.pop()
      let result = self.builder.v128_not(a)
      self.push(result)
    }
    V128And => {
      let b = self.pop()
      let a = self.pop()
      let result = self.builder.v128_and(a, b)
      self.push(result)
    }
    V128AndNot => {
      let b = self.pop()
      let a = self.pop()
      let result = self.builder.v128_andnot(a, b)
      self.push(result)
    }
    V128Or => {
      let b = self.pop()
      let a = self.pop()
      let result = self.builder.v128_or(a, b)
      self.push(result)
    }
    V128Xor => {
      let b = self.pop()
      let a = self.pop()
      let result = self.builder.v128_xor(a, b)
      self.push(result)
    }
    V128Bitselect => {
      let c = self.pop() // mask
      let b = self.pop()
      let a = self.pop()
      let result = self.builder.v128_bitselect(a, b, c)
      self.push(result)
    }
    V128AnyTrue => {
      let a = self.pop()
      let result = self.builder.v128_anytrue(a)
      self.push(result)
    }

    // i8x16 operations
    I8x16Eq => self.translate_simd_binary(Opcode::V128Eq8)
    I8x16Ne => self.translate_simd_binary(Opcode::V128Ne8)
    I8x16LtS => self.translate_simd_binary(Opcode::V128Lt8S)
    I8x16LtU => self.translate_simd_binary(Opcode::V128Lt8U)
    I8x16GtS => self.translate_simd_binary(Opcode::V128Gt8S)
    I8x16GtU => self.translate_simd_binary(Opcode::V128Gt8U)
    I8x16LeS => self.translate_simd_binary(Opcode::V128Le8S)
    I8x16LeU => self.translate_simd_binary(Opcode::V128Le8U)
    I8x16GeS => self.translate_simd_binary(Opcode::V128Ge8S)
    I8x16GeU => self.translate_simd_binary(Opcode::V128Ge8U)
    I8x16Abs => self.translate_simd_unary(Opcode::V128Abs8)
    I8x16Neg => self.translate_simd_unary(Opcode::V128Neg8)
    I8x16Popcnt => self.translate_simd_unary(Opcode::V128Popcnt8)
    I8x16AllTrue => self.translate_simd_to_i32(Opcode::V128AllTrue8)
    I8x16Bitmask => self.translate_simd_to_i32(Opcode::V128Bitmask8)
    I8x16NarrowI16x8S => self.translate_simd_binary(Opcode::V128Narrow16to8S)
    I8x16NarrowI16x8U => self.translate_simd_binary(Opcode::V128Narrow16to8U)
    I8x16Shl => self.translate_simd_shift(Opcode::V128Shl8)
    I8x16ShrS => self.translate_simd_shift(Opcode::V128Shr8S)
    I8x16ShrU => self.translate_simd_shift(Opcode::V128Shr8U)
    I8x16Add => self.translate_simd_binary(Opcode::V128Add8)
    I8x16AddSatS => self.translate_simd_binary(Opcode::V128AddSat8S)
    I8x16AddSatU => self.translate_simd_binary(Opcode::V128AddSat8U)
    I8x16Sub => self.translate_simd_binary(Opcode::V128Sub8)
    I8x16SubSatS => self.translate_simd_binary(Opcode::V128SubSat8S)
    I8x16SubSatU => self.translate_simd_binary(Opcode::V128SubSat8U)
    I8x16MinS => self.translate_simd_binary(Opcode::V128Min8S)
    I8x16MinU => self.translate_simd_binary(Opcode::V128Min8U)
    I8x16MaxS => self.translate_simd_binary(Opcode::V128Max8S)
    I8x16MaxU => self.translate_simd_binary(Opcode::V128Max8U)
    I8x16AvgrU => self.translate_simd_binary(Opcode::V128Avgr8U)

    // i16x8 operations
    I16x8ExtAddPairwiseI8x16S =>
      self.translate_simd_unary(Opcode::V128ExtAddPairwise8to16S)
    I16x8ExtAddPairwiseI8x16U =>
      self.translate_simd_unary(Opcode::V128ExtAddPairwise8to16U)
    I16x8Eq => self.translate_simd_binary(Opcode::V128Eq16)
    I16x8Ne => self.translate_simd_binary(Opcode::V128Ne16)
    I16x8LtS => self.translate_simd_binary(Opcode::V128Lt16S)
    I16x8LtU => self.translate_simd_binary(Opcode::V128Lt16U)
    I16x8GtS => self.translate_simd_binary(Opcode::V128Gt16S)
    I16x8GtU => self.translate_simd_binary(Opcode::V128Gt16U)
    I16x8LeS => self.translate_simd_binary(Opcode::V128Le16S)
    I16x8LeU => self.translate_simd_binary(Opcode::V128Le16U)
    I16x8GeS => self.translate_simd_binary(Opcode::V128Ge16S)
    I16x8GeU => self.translate_simd_binary(Opcode::V128Ge16U)
    I16x8Abs => self.translate_simd_unary(Opcode::V128Abs16)
    I16x8Neg => self.translate_simd_unary(Opcode::V128Neg16)
    I16x8Q15MulrSatS => self.translate_simd_binary(Opcode::V128Q15MulrSat16S)
    I16x8AllTrue => self.translate_simd_to_i32(Opcode::V128AllTrue16)
    I16x8Bitmask => self.translate_simd_to_i32(Opcode::V128Bitmask16)
    I16x8NarrowI32x4S => self.translate_simd_binary(Opcode::V128Narrow32to16S)
    I16x8NarrowI32x4U => self.translate_simd_binary(Opcode::V128Narrow32to16U)
    I16x8ExtendLowI8x16S =>
      self.translate_simd_unary(Opcode::V128ExtendLow8to16S)
    I16x8ExtendHighI8x16S =>
      self.translate_simd_unary(Opcode::V128ExtendHigh8to16S)
    I16x8ExtendLowI8x16U =>
      self.translate_simd_unary(Opcode::V128ExtendLow8to16U)
    I16x8ExtendHighI8x16U =>
      self.translate_simd_unary(Opcode::V128ExtendHigh8to16U)
    I16x8Shl => self.translate_simd_shift(Opcode::V128Shl16)
    I16x8ShrS => self.translate_simd_shift(Opcode::V128Shr16S)
    I16x8ShrU => self.translate_simd_shift(Opcode::V128Shr16U)
    I16x8Add => self.translate_simd_binary(Opcode::V128Add16)
    I16x8AddSatS => self.translate_simd_binary(Opcode::V128AddSat16S)
    I16x8AddSatU => self.translate_simd_binary(Opcode::V128AddSat16U)
    I16x8Sub => self.translate_simd_binary(Opcode::V128Sub16)
    I16x8SubSatS => self.translate_simd_binary(Opcode::V128SubSat16S)
    I16x8SubSatU => self.translate_simd_binary(Opcode::V128SubSat16U)
    I16x8Mul => self.translate_simd_binary(Opcode::V128Mul16)
    I16x8MinS => self.translate_simd_binary(Opcode::V128Min16S)
    I16x8MinU => self.translate_simd_binary(Opcode::V128Min16U)
    I16x8MaxS => self.translate_simd_binary(Opcode::V128Max16S)
    I16x8MaxU => self.translate_simd_binary(Opcode::V128Max16U)
    I16x8AvgrU => self.translate_simd_binary(Opcode::V128Avgr16U)
    I16x8ExtMulLowI8x16S =>
      self.translate_simd_binary(Opcode::V128ExtMulLow8to16S)
    I16x8ExtMulHighI8x16S =>
      self.translate_simd_binary(Opcode::V128ExtMulHigh8to16S)
    I16x8ExtMulLowI8x16U =>
      self.translate_simd_binary(Opcode::V128ExtMulLow8to16U)
    I16x8ExtMulHighI8x16U =>
      self.translate_simd_binary(Opcode::V128ExtMulHigh8to16U)

    // i32x4 operations
    I32x4ExtAddPairwiseI16x8S =>
      self.translate_simd_unary(Opcode::V128ExtAddPairwise16to32S)
    I32x4ExtAddPairwiseI16x8U =>
      self.translate_simd_unary(Opcode::V128ExtAddPairwise16to32U)
    I32x4Eq => self.translate_simd_binary(Opcode::V128Eq32)
    I32x4Ne => self.translate_simd_binary(Opcode::V128Ne32)
    I32x4LtS => self.translate_simd_binary(Opcode::V128Lt32S)
    I32x4LtU => self.translate_simd_binary(Opcode::V128Lt32U)
    I32x4GtS => self.translate_simd_binary(Opcode::V128Gt32S)
    I32x4GtU => self.translate_simd_binary(Opcode::V128Gt32U)
    I32x4LeS => self.translate_simd_binary(Opcode::V128Le32S)
    I32x4LeU => self.translate_simd_binary(Opcode::V128Le32U)
    I32x4GeS => self.translate_simd_binary(Opcode::V128Ge32S)
    I32x4GeU => self.translate_simd_binary(Opcode::V128Ge32U)
    I32x4Abs => self.translate_simd_unary(Opcode::V128Abs32)
    I32x4Neg => self.translate_simd_unary(Opcode::V128Neg32)
    I32x4AllTrue => self.translate_simd_to_i32(Opcode::V128AllTrue32)
    I32x4Bitmask => self.translate_simd_to_i32(Opcode::V128Bitmask32)
    I32x4ExtendLowI16x8S =>
      self.translate_simd_unary(Opcode::V128ExtendLow16to32S)
    I32x4ExtendHighI16x8S =>
      self.translate_simd_unary(Opcode::V128ExtendHigh16to32S)
    I32x4ExtendLowI16x8U =>
      self.translate_simd_unary(Opcode::V128ExtendLow16to32U)
    I32x4ExtendHighI16x8U =>
      self.translate_simd_unary(Opcode::V128ExtendHigh16to32U)
    I32x4Shl => self.translate_simd_shift(Opcode::V128Shl32)
    I32x4ShrS => self.translate_simd_shift(Opcode::V128Shr32S)
    I32x4ShrU => self.translate_simd_shift(Opcode::V128Shr32U)
    I32x4Add => self.translate_simd_binary(Opcode::V128Add32)
    I32x4Sub => self.translate_simd_binary(Opcode::V128Sub32)
    I32x4Mul => self.translate_simd_binary(Opcode::V128Mul32)
    I32x4MinS => self.translate_simd_binary(Opcode::V128Min32S)
    I32x4MinU => self.translate_simd_binary(Opcode::V128Min32U)
    I32x4MaxS => self.translate_simd_binary(Opcode::V128Max32S)
    I32x4MaxU => self.translate_simd_binary(Opcode::V128Max32U)
    I32x4DotI16x8S => self.translate_simd_binary(Opcode::V128Dot16to32S)
    I32x4ExtMulLowI16x8S =>
      self.translate_simd_binary(Opcode::V128ExtMulLow16to32S)
    I32x4ExtMulHighI16x8S =>
      self.translate_simd_binary(Opcode::V128ExtMulHigh16to32S)
    I32x4ExtMulLowI16x8U =>
      self.translate_simd_binary(Opcode::V128ExtMulLow16to32U)
    I32x4ExtMulHighI16x8U =>
      self.translate_simd_binary(Opcode::V128ExtMulHigh16to32U)

    // i64x2 operations
    I64x2Eq => self.translate_simd_binary(Opcode::V128Eq64)
    I64x2Ne => self.translate_simd_binary(Opcode::V128Ne64)
    I64x2LtS => self.translate_simd_binary(Opcode::V128Lt64S)
    I64x2GtS => self.translate_simd_binary(Opcode::V128Gt64S)
    I64x2LeS => self.translate_simd_binary(Opcode::V128Le64S)
    I64x2GeS => self.translate_simd_binary(Opcode::V128Ge64S)
    I64x2Abs => self.translate_simd_unary(Opcode::V128Abs64)
    I64x2Neg => self.translate_simd_unary(Opcode::V128Neg64)
    I64x2AllTrue => self.translate_simd_to_i32(Opcode::V128AllTrue64)
    I64x2Bitmask => self.translate_simd_to_i32(Opcode::V128Bitmask64)
    I64x2ExtendLowI32x4S =>
      self.translate_simd_unary(Opcode::V128ExtendLow32to64S)
    I64x2ExtendHighI32x4S =>
      self.translate_simd_unary(Opcode::V128ExtendHigh32to64S)
    I64x2ExtendLowI32x4U =>
      self.translate_simd_unary(Opcode::V128ExtendLow32to64U)
    I64x2ExtendHighI32x4U =>
      self.translate_simd_unary(Opcode::V128ExtendHigh32to64U)
    I64x2Shl => self.translate_simd_shift(Opcode::V128Shl64)
    I64x2ShrS => self.translate_simd_shift(Opcode::V128Shr64S)
    I64x2ShrU => self.translate_simd_shift(Opcode::V128Shr64U)
    I64x2Add => self.translate_simd_binary(Opcode::V128Add64)
    I64x2Sub => self.translate_simd_binary(Opcode::V128Sub64)
    I64x2Mul => self.translate_simd_binary(Opcode::V128Mul64)
    I64x2ExtMulLowI32x4S =>
      self.translate_simd_binary(Opcode::V128ExtMulLow32to64S)
    I64x2ExtMulHighI32x4S =>
      self.translate_simd_binary(Opcode::V128ExtMulHigh32to64S)
    I64x2ExtMulLowI32x4U =>
      self.translate_simd_binary(Opcode::V128ExtMulLow32to64U)
    I64x2ExtMulHighI32x4U =>
      self.translate_simd_binary(Opcode::V128ExtMulHigh32to64U)

    // f32x4 operations
    F32x4Eq => self.translate_simd_binary(Opcode::V128EqF32)
    F32x4Ne => self.translate_simd_binary(Opcode::V128NeF32)
    F32x4Lt => self.translate_simd_binary(Opcode::V128LtF32)
    F32x4Gt => self.translate_simd_binary(Opcode::V128GtF32)
    F32x4Le => self.translate_simd_binary(Opcode::V128LeF32)
    F32x4Ge => self.translate_simd_binary(Opcode::V128GeF32)
    F32x4Ceil => self.translate_simd_unary(Opcode::V128CeilF32)
    F32x4Floor => self.translate_simd_unary(Opcode::V128FloorF32)
    F32x4Trunc => self.translate_simd_unary(Opcode::V128TruncF32)
    F32x4Nearest => self.translate_simd_unary(Opcode::V128NearestF32)
    F32x4Abs => self.translate_simd_unary(Opcode::V128AbsF32)
    F32x4Neg => self.translate_simd_unary(Opcode::V128NegF32)
    F32x4Sqrt => self.translate_simd_unary(Opcode::V128SqrtF32)
    F32x4Add => self.translate_simd_binary(Opcode::V128AddF32)
    F32x4Sub => self.translate_simd_binary(Opcode::V128SubF32)
    F32x4Mul => self.translate_simd_binary(Opcode::V128MulF32)
    F32x4Div => self.translate_simd_binary(Opcode::V128DivF32)
    F32x4Min => self.translate_simd_binary(Opcode::V128MinF32)
    F32x4Max => self.translate_simd_binary(Opcode::V128MaxF32)
    F32x4Pmin => self.translate_simd_binary(Opcode::V128PMinF32)
    F32x4Pmax => self.translate_simd_binary(Opcode::V128PMaxF32)

    // f64x2 operations
    F64x2Eq => self.translate_simd_binary(Opcode::V128EqF64)
    F64x2Ne => self.translate_simd_binary(Opcode::V128NeF64)
    F64x2Lt => self.translate_simd_binary(Opcode::V128LtF64)
    F64x2Gt => self.translate_simd_binary(Opcode::V128GtF64)
    F64x2Le => self.translate_simd_binary(Opcode::V128LeF64)
    F64x2Ge => self.translate_simd_binary(Opcode::V128GeF64)
    F64x2Ceil => self.translate_simd_unary(Opcode::V128CeilF64)
    F64x2Floor => self.translate_simd_unary(Opcode::V128FloorF64)
    F64x2Trunc => self.translate_simd_unary(Opcode::V128TruncF64)
    F64x2Nearest => self.translate_simd_unary(Opcode::V128NearestF64)
    F64x2Abs => self.translate_simd_unary(Opcode::V128AbsF64)
    F64x2Neg => self.translate_simd_unary(Opcode::V128NegF64)
    F64x2Sqrt => self.translate_simd_unary(Opcode::V128SqrtF64)
    F64x2Add => self.translate_simd_binary(Opcode::V128AddF64)
    F64x2Sub => self.translate_simd_binary(Opcode::V128SubF64)
    F64x2Mul => self.translate_simd_binary(Opcode::V128MulF64)
    F64x2Div => self.translate_simd_binary(Opcode::V128DivF64)
    F64x2Min => self.translate_simd_binary(Opcode::V128MinF64)
    F64x2Max => self.translate_simd_binary(Opcode::V128MaxF64)
    F64x2Pmin => self.translate_simd_binary(Opcode::V128PMinF64)
    F64x2Pmax => self.translate_simd_binary(Opcode::V128PMaxF64)

    // SIMD conversions
    I32x4TruncSatF32x4S =>
      self.translate_simd_unary(Opcode::V128TruncSatF32toI32S)
    I32x4TruncSatF32x4U =>
      self.translate_simd_unary(Opcode::V128TruncSatF32toI32U)
    F32x4ConvertI32x4S =>
      self.translate_simd_unary(Opcode::V128ConvertI32toF32S)
    F32x4ConvertI32x4U =>
      self.translate_simd_unary(Opcode::V128ConvertI32toF32U)
    I32x4TruncSatF64x2SZero =>
      self.translate_simd_unary(Opcode::V128TruncSatF64toI32SZero)
    I32x4TruncSatF64x2UZero =>
      self.translate_simd_unary(Opcode::V128TruncSatF64toI32UZero)
    F64x2ConvertLowI32x4S =>
      self.translate_simd_unary(Opcode::V128ConvertLowI32toF64S)
    F64x2ConvertLowI32x4U =>
      self.translate_simd_unary(Opcode::V128ConvertLowI32toF64U)
    F32x4DemoteF64x2Zero =>
      self.translate_simd_unary(Opcode::V128DemoteF64toF32Zero)
    F64x2PromoteLowF32x4 =>
      self.translate_simd_unary(Opcode::V128PromoteLowF32toF64)

    // V128 load/store operations
    V128Load(memidx, _, offset) => {
      let addr = self.pop()
      let result = self.func_env.translate_memory_load(
        self.builder,
        self.vmctx,
        memidx,
        Type::V128,
        addr,
        offset,
      )
      self.push(result)
    }
    V128Store(memidx, _, offset) => {
      let value = self.pop()
      let addr = self.pop()
      self.func_env.translate_memory_store(
        self.builder,
        self.vmctx,
        memidx,
        Type::V128,
        addr,
        value,
        offset,
      )
    }
    V128Load8x8S(memidx, _, offset) => {
      let addr = self.pop()
      let result = self.translate_simd_load(
        memidx,
        offset,
        addr,
        Opcode::V128Load8x8S(memidx, 0, offset),
      )
      self.push(result)
    }
    V128Load8x8U(memidx, _, offset) => {
      let addr = self.pop()
      let result = self.translate_simd_load(
        memidx,
        offset,
        addr,
        Opcode::V128Load8x8U(memidx, 0, offset),
      )
      self.push(result)
    }
    V128Load16x4S(memidx, _, offset) => {
      let addr = self.pop()
      let result = self.translate_simd_load(
        memidx,
        offset,
        addr,
        Opcode::V128Load16x4S(memidx, 0, offset),
      )
      self.push(result)
    }
    V128Load16x4U(memidx, _, offset) => {
      let addr = self.pop()
      let result = self.translate_simd_load(
        memidx,
        offset,
        addr,
        Opcode::V128Load16x4U(memidx, 0, offset),
      )
      self.push(result)
    }
    V128Load32x2S(memidx, _, offset) => {
      let addr = self.pop()
      let result = self.translate_simd_load(
        memidx,
        offset,
        addr,
        Opcode::V128Load32x2S(memidx, 0, offset),
      )
      self.push(result)
    }
    V128Load32x2U(memidx, _, offset) => {
      let addr = self.pop()
      let result = self.translate_simd_load(
        memidx,
        offset,
        addr,
        Opcode::V128Load32x2U(memidx, 0, offset),
      )
      self.push(result)
    }
    V128Load8Splat(memidx, _, offset) => {
      let addr = self.pop()
      let result = self.translate_simd_load(
        memidx,
        offset,
        addr,
        Opcode::V128Load8Splat(memidx, 0, offset),
      )
      self.push(result)
    }
    V128Load16Splat(memidx, _, offset) => {
      let addr = self.pop()
      let result = self.translate_simd_load(
        memidx,
        offset,
        addr,
        Opcode::V128Load16Splat(memidx, 0, offset),
      )
      self.push(result)
    }
    V128Load32Splat(memidx, _, offset) => {
      let addr = self.pop()
      let result = self.translate_simd_load(
        memidx,
        offset,
        addr,
        Opcode::V128Load32Splat(memidx, 0, offset),
      )
      self.push(result)
    }
    V128Load64Splat(memidx, _, offset) => {
      let addr = self.pop()
      let result = self.translate_simd_load(
        memidx,
        offset,
        addr,
        Opcode::V128Load64Splat(memidx, 0, offset),
      )
      self.push(result)
    }
    V128Load32Zero(memidx, _, offset) => {
      let addr = self.pop()
      let result = self.translate_simd_load(
        memidx,
        offset,
        addr,
        Opcode::V128Load32Zero(memidx, 0, offset),
      )
      self.push(result)
    }
    V128Load64Zero(memidx, _, offset) => {
      let addr = self.pop()
      let result = self.translate_simd_load(
        memidx,
        offset,
        addr,
        Opcode::V128Load64Zero(memidx, 0, offset),
      )
      self.push(result)
    }
    V128Load8Lane(memidx, _, offset, lane) => {
      let vec = self.pop()
      let addr = self.pop()
      let result = self.translate_simd_load_lane(
        memidx,
        offset,
        addr,
        vec,
        Opcode::V128Load8Lane(memidx, 0, offset, lane),
      )
      self.push(result)
    }
    V128Load16Lane(memidx, _, offset, lane) => {
      let vec = self.pop()
      let addr = self.pop()
      let result = self.translate_simd_load_lane(
        memidx,
        offset,
        addr,
        vec,
        Opcode::V128Load16Lane(memidx, 0, offset, lane),
      )
      self.push(result)
    }
    V128Load32Lane(memidx, _, offset, lane) => {
      let vec = self.pop()
      let addr = self.pop()
      let result = self.translate_simd_load_lane(
        memidx,
        offset,
        addr,
        vec,
        Opcode::V128Load32Lane(memidx, 0, offset, lane),
      )
      self.push(result)
    }
    V128Load64Lane(memidx, _, offset, lane) => {
      let vec = self.pop()
      let addr = self.pop()
      let result = self.translate_simd_load_lane(
        memidx,
        offset,
        addr,
        vec,
        Opcode::V128Load64Lane(memidx, 0, offset, lane),
      )
      self.push(result)
    }
    V128Store8Lane(memidx, _, offset, lane) => {
      let vec = self.pop()
      let addr = self.pop()
      self.translate_simd_store_lane(
        memidx,
        offset,
        addr,
        vec,
        Opcode::V128Store8Lane(memidx, 0, offset, lane),
      )
    }
    V128Store16Lane(memidx, _, offset, lane) => {
      let vec = self.pop()
      let addr = self.pop()
      self.translate_simd_store_lane(
        memidx,
        offset,
        addr,
        vec,
        Opcode::V128Store16Lane(memidx, 0, offset, lane),
      )
    }
    V128Store32Lane(memidx, _, offset, lane) => {
      let vec = self.pop()
      let addr = self.pop()
      self.translate_simd_store_lane(
        memidx,
        offset,
        addr,
        vec,
        Opcode::V128Store32Lane(memidx, 0, offset, lane),
      )
    }
    V128Store64Lane(memidx, _, offset, lane) => {
      let vec = self.pop()
      let addr = self.pop()
      self.translate_simd_store_lane(
        memidx,
        offset,
        addr,
        vec,
        Opcode::V128Store64Lane(memidx, 0, offset, lane),
      )
    }

    // Relaxed SIMD instructions
    I8x16RelaxedSwizzle => {
      // Same as regular swizzle on ARM
      let b = self.pop()
      let a = self.pop()
      let result = self.builder.emit_inst(
        Type::V128,
        Opcode::V128RelaxedSwizzle,
        [a, b],
      )
      self.push(result)
    }
    I32x4RelaxedTruncF32x4S =>
      self.translate_simd_unary(Opcode::V128RelaxedTruncF32toI32S)
    I32x4RelaxedTruncF32x4U =>
      self.translate_simd_unary(Opcode::V128RelaxedTruncF32toI32U)
    I32x4RelaxedTruncF64x2SZero =>
      self.translate_simd_unary(Opcode::V128RelaxedTruncF64toI32SZero)
    I32x4RelaxedTruncF64x2UZero =>
      self.translate_simd_unary(Opcode::V128RelaxedTruncF64toI32UZero)
    F32x4RelaxedMadd => {
      let c = self.pop()
      let b = self.pop()
      let a = self.pop()
      let result = self.builder.emit_inst(
        Type::V128,
        Opcode::V128RelaxedMaddF32,
        [a, b, c],
      )
      self.push(result)
    }
    F32x4RelaxedNmadd => {
      let c = self.pop()
      let b = self.pop()
      let a = self.pop()
      let result = self.builder.emit_inst(
        Type::V128,
        Opcode::V128RelaxedNmaddF32,
        [a, b, c],
      )
      self.push(result)
    }
    F64x2RelaxedMadd => {
      let c = self.pop()
      let b = self.pop()
      let a = self.pop()
      let result = self.builder.emit_inst(
        Type::V128,
        Opcode::V128RelaxedMaddF64,
        [a, b, c],
      )
      self.push(result)
    }
    F64x2RelaxedNmadd => {
      let c = self.pop()
      let b = self.pop()
      let a = self.pop()
      let result = self.builder.emit_inst(
        Type::V128,
        Opcode::V128RelaxedNmaddF64,
        [a, b, c],
      )
      self.push(result)
    }
    I8x16RelaxedLaneselect => {
      let c = self.pop()
      let b = self.pop()
      let a = self.pop()
      let result = self.builder.emit_inst(
        Type::V128,
        Opcode::V128RelaxedLaneselect8,
        [a, b, c],
      )
      self.push(result)
    }
    I16x8RelaxedLaneselect => {
      let c = self.pop()
      let b = self.pop()
      let a = self.pop()
      let result = self.builder.emit_inst(
        Type::V128,
        Opcode::V128RelaxedLaneselect16,
        [a, b, c],
      )
      self.push(result)
    }
    I32x4RelaxedLaneselect => {
      let c = self.pop()
      let b = self.pop()
      let a = self.pop()
      let result = self.builder.emit_inst(
        Type::V128,
        Opcode::V128RelaxedLaneselect32,
        [a, b, c],
      )
      self.push(result)
    }
    I64x2RelaxedLaneselect => {
      let c = self.pop()
      let b = self.pop()
      let a = self.pop()
      let result = self.builder.emit_inst(
        Type::V128,
        Opcode::V128RelaxedLaneselect64,
        [a, b, c],
      )
      self.push(result)
    }
    F32x4RelaxedMin => self.translate_simd_binary(Opcode::V128RelaxedMinF32)
    F32x4RelaxedMax => self.translate_simd_binary(Opcode::V128RelaxedMaxF32)
    F64x2RelaxedMin => self.translate_simd_binary(Opcode::V128RelaxedMinF64)
    F64x2RelaxedMax => self.translate_simd_binary(Opcode::V128RelaxedMaxF64)
    I16x8RelaxedQ15mulrS =>
      self.translate_simd_binary(Opcode::V128RelaxedQ15MulrS)
    I16x8RelaxedDotI8x16I7x16S =>
      self.translate_simd_binary(Opcode::V128RelaxedDot8to16S)
    I32x4RelaxedDotI8x16I7x16AddS => {
      let c = self.pop()
      let b = self.pop()
      let a = self.pop()
      let result = self.builder.emit_inst(
        Type::V128,
        Opcode::V128RelaxedDot8to32AddS,
        [a, b, c],
      )
      self.push(result)
    }
  }
}

///|
fn Translator::translate_atomic(
  self : Translator,
  subopcode : Int,
  memidx : Int,
  offset : Int64,
) -> Unit {
  fn bounds_ptr(addr : Value, access_size : Int) -> Value {
    self.func_env.emit_bounds_check(
      self.builder,
      self.vmctx,
      memidx,
      addr,
      offset,
      access_size,
    )
  }

  fn align_check(addr : Value, access_size : Int) -> Unit {
    self.func_env.emit_atomic_alignment_check(
      self.builder,
      memidx,
      addr,
      offset,
      access_size,
    )
  }

  fn load_u32(bits : Int, addr : Value) -> Value {
    align_check(addr, bits / 8)
    let ptr = bounds_ptr(addr, bits / 8)
    let zero = self.builder.iconst(Type::I64, 0L)
    self.builder.load_ptr_narrow(Type::I32, bits, false, ptr, zero)
  }

  fn store_u32(bits : Int, addr : Value, value : Value) -> Unit {
    align_check(addr, bits / 8)
    let ptr = bounds_ptr(addr, bits / 8)
    let zero = self.builder.iconst(Type::I64, 0L)
    self.builder.store_ptr_narrow(bits, ptr, value, zero)
  }

  fn load_u64(bits : Int, addr : Value) -> Value {
    align_check(addr, bits / 8)
    let ptr = bounds_ptr(addr, bits / 8)
    let zero = self.builder.iconst(Type::I64, 0L)
    self.builder.load_ptr_narrow(Type::I64, bits, false, ptr, zero)
  }

  fn store_u64(bits : Int, addr : Value, value : Value) -> Unit {
    align_check(addr, bits / 8)
    let ptr = bounds_ptr(addr, bits / 8)
    let zero = self.builder.iconst(Type::I64, 0L)
    self.builder.store_ptr_narrow(bits, ptr, value, zero)
  }

  // NOTE: wasm-tools/wasmparser encodes most atomic subopcodes starting at 0x10.
  // The IR lowering table is indexed starting at 0x04, so shift accordingly.
  let op = if subopcode >= 0x10 { subopcode - 12 } else { subopcode }
  match op {
    // memory.atomic.notify
    0 => {
      let _count = self.pop()
      let addr = self.pop()
      align_check(addr, 4)
      ignore(bounds_ptr(addr, 4))
      self.push(self.builder.iconst_i32(0))
    }

    // memory.atomic.wait32
    1 => {
      let _timeout = self.pop()
      let expected = self.pop()
      let addr = self.pop()
      align_check(addr, 4)
      let ptr = bounds_ptr(addr, 4)
      let zero = self.builder.iconst(Type::I64, 0L)
      let actual = self.builder.load_ptr(Type::I32, ptr, zero)
      let eq = self.builder.icmp(IntCC::Eq, actual, expected)
      let not_equal = self.builder.iconst_i32(1)
      let timed_out = self.builder.iconst_i32(2)
      let result = self.builder.select(eq, timed_out, not_equal)
      self.push(result)
    }

    // memory.atomic.wait64
    2 => {
      let _timeout = self.pop()
      let expected = self.pop()
      let addr = self.pop()
      align_check(addr, 8)
      let ptr = bounds_ptr(addr, 8)
      let zero = self.builder.iconst(Type::I64, 0L)
      let actual = self.builder.load_ptr(Type::I64, ptr, zero)
      let eq = self.builder.icmp(IntCC::Eq, actual, expected)
      let not_equal = self.builder.iconst_i32(1)
      let timed_out = self.builder.iconst_i32(2)
      let result = self.builder.select(eq, timed_out, not_equal)
      self.push(result)
    }

    // atomic.fence
    3 => ()

    // Loads
    4 => {
      let addr = self.pop()
      align_check(addr, 4)
      let ptr = bounds_ptr(addr, 4)
      let zero = self.builder.iconst(Type::I64, 0L)
      self.push(self.builder.load_ptr(Type::I32, ptr, zero))
    }
    5 => {
      let addr = self.pop()
      align_check(addr, 8)
      let ptr = bounds_ptr(addr, 8)
      let zero = self.builder.iconst(Type::I64, 0L)
      self.push(self.builder.load_ptr(Type::I64, ptr, zero))
    }
    6 => {
      let addr = self.pop()
      self.push(load_u32(8, addr))
    }
    7 => {
      let addr = self.pop()
      self.push(load_u32(16, addr))
    }
    8 => {
      let addr = self.pop()
      self.push(load_u64(8, addr))
    }
    9 => {
      let addr = self.pop()
      self.push(load_u64(16, addr))
    }
    10 => {
      let addr = self.pop()
      self.push(load_u64(32, addr))
    }

    // Stores
    11 => {
      let value = self.pop()
      let addr = self.pop()
      align_check(addr, 4)
      let ptr = bounds_ptr(addr, 4)
      let zero = self.builder.iconst(Type::I64, 0L)
      self.builder.store_ptr(Type::I32, ptr, value, zero)
    }
    12 => {
      let value = self.pop()
      let addr = self.pop()
      align_check(addr, 8)
      let ptr = bounds_ptr(addr, 8)
      let zero = self.builder.iconst(Type::I64, 0L)
      self.builder.store_ptr(Type::I64, ptr, value, zero)
    }
    13 => {
      let value = self.pop()
      let addr = self.pop()
      store_u32(8, addr, value)
    }
    14 => {
      let value = self.pop()
      let addr = self.pop()
      store_u32(16, addr, value)
    }
    15 => {
      let value = self.pop()
      let addr = self.pop()
      store_u64(8, addr, value)
    }
    16 => {
      let value = self.pop()
      let addr = self.pop()
      store_u64(16, addr, value)
    }
    17 => {
      let value = self.pop()
      let addr = self.pop()
      store_u64(32, addr, value)
    }

    // i32 RMW operations
    18
    | 20
    | 21
    | 25
    | 27
    | 28
    | 32
    | 34
    | 35
    | 39
    | 41
    | 42
    | 46
    | 48
    | 49
    | 53
    | 55
    | 56 => {
      let value = self.pop()
      let addr = self.pop()
      let bits = if subopcode == 18 ||
        subopcode == 25 ||
        subopcode == 32 ||
        subopcode == 39 ||
        subopcode == 46 ||
        subopcode == 53 {
        32
      } else if subopcode == 20 ||
        subopcode == 27 ||
        subopcode == 34 ||
        subopcode == 41 ||
        subopcode == 48 ||
        subopcode == 55 {
        8
      } else {
        16
      }
      let access_size = bits / 8
      align_check(addr, access_size)
      let ptr = bounds_ptr(addr, access_size)
      let zero = self.builder.iconst(Type::I64, 0L)
      let old = if bits == 32 {
        self.builder.load_ptr(Type::I32, ptr, zero)
      } else {
        self.builder.load_ptr_narrow(Type::I32, bits, false, ptr, zero)
      }
      let mask = if bits == 32 {
        self.builder.iconst_i32(-1)
      } else if bits == 16 {
        self.builder.iconst_i32(0xFFFF)
      } else {
        self.builder.iconst_i32(0xFF)
      }
      let v_masked = if bits == 32 {
        value
      } else {
        self.builder.band(value, mask)
      }
      let computed = match subopcode {
        18 | 20 | 21 => self.builder.iadd(old, v_masked)
        25 | 27 | 28 => self.builder.isub(old, v_masked)
        32 | 34 | 35 => self.builder.band(old, v_masked)
        39 | 41 | 42 => self.builder.bor(old, v_masked)
        46 | 48 | 49 => self.builder.bxor(old, v_masked)
        53 | 55 | 56 => v_masked
        _ => old
      }
      let new = if bits == 32 {
        computed
      } else {
        self.builder.band(computed, mask)
      }
      if bits == 32 {
        self.builder.store_ptr(Type::I32, ptr, new, zero)
      } else {
        self.builder.store_ptr_narrow(bits, ptr, new, zero)
      }
      self.push(old)
    }

    // i64 RMW operations
    19
    | 22
    | 23
    | 24
    | 26
    | 29
    | 30
    | 31
    | 33
    | 36
    | 37
    | 38
    | 40
    | 43
    | 44
    | 45
    | 47
    | 50
    | 51
    | 52
    | 54
    | 57
    | 58
    | 59 => {
      let value = self.pop()
      let addr = self.pop()
      let bits = if subopcode == 19 ||
        subopcode == 26 ||
        subopcode == 33 ||
        subopcode == 40 ||
        subopcode == 47 ||
        subopcode == 54 {
        64
      } else if subopcode == 22 ||
        subopcode == 29 ||
        subopcode == 36 ||
        subopcode == 43 ||
        subopcode == 50 ||
        subopcode == 57 {
        8
      } else if subopcode == 23 ||
        subopcode == 30 ||
        subopcode == 37 ||
        subopcode == 44 ||
        subopcode == 51 ||
        subopcode == 58 {
        16
      } else {
        32
      }
      let access_size = bits / 8
      align_check(addr, access_size)
      let ptr = bounds_ptr(addr, access_size)
      let zero = self.builder.iconst(Type::I64, 0L)
      let old = if bits == 64 {
        self.builder.load_ptr(Type::I64, ptr, zero)
      } else {
        self.builder.load_ptr_narrow(Type::I64, bits, false, ptr, zero)
      }
      let mask = if bits == 64 {
        self.builder.iconst_i64(-1L)
      } else if bits == 32 {
        self.builder.iconst_i64(0xFFFF_FFFFL)
      } else if bits == 16 {
        self.builder.iconst_i64(0xFFFFL)
      } else {
        self.builder.iconst_i64(0xFFL)
      }
      let v_masked = if bits == 64 {
        value
      } else {
        self.builder.band(value, mask)
      }
      let computed = match subopcode {
        19 | 22 | 23 | 24 => self.builder.iadd(old, v_masked)
        26 | 29 | 30 | 31 => self.builder.isub(old, v_masked)
        33 | 36 | 37 | 38 => self.builder.band(old, v_masked)
        40 | 43 | 44 | 45 => self.builder.bor(old, v_masked)
        47 | 50 | 51 | 52 => self.builder.bxor(old, v_masked)
        54 | 57 | 58 | 59 => v_masked
        _ => old
      }
      let new = if bits == 64 {
        computed
      } else {
        self.builder.band(computed, mask)
      }
      if bits == 64 {
        self.builder.store_ptr(Type::I64, ptr, new, zero)
      } else {
        self.builder.store_ptr_narrow(bits, ptr, new, zero)
      }
      self.push(old)
    }

    // i32 cmpxchg
    60 | 62 | 63 => {
      let replacement = self.pop()
      let expected = self.pop()
      let addr = self.pop()
      let bits = if subopcode == 60 {
        32
      } else if subopcode == 62 {
        8
      } else {
        16
      }
      let access_size = bits / 8
      align_check(addr, access_size)
      let ptr = bounds_ptr(addr, access_size)
      let zero = self.builder.iconst(Type::I64, 0L)
      let old = if bits == 32 {
        self.builder.load_ptr(Type::I32, ptr, zero)
      } else {
        self.builder.load_ptr_narrow(Type::I32, bits, false, ptr, zero)
      }
      let mask = if bits == 32 {
        self.builder.iconst_i32(-1)
      } else if bits == 16 {
        self.builder.iconst_i32(0xFFFF)
      } else {
        self.builder.iconst_i32(0xFF)
      }
      let expected_m = if bits == 32 {
        expected
      } else {
        self.builder.band(expected, mask)
      }
      let replacement_m = if bits == 32 {
        replacement
      } else {
        self.builder.band(replacement, mask)
      }
      let eq = self.builder.icmp(IntCC::Eq, old, expected_m)
      let store_block = self.builder.create_block()
      let cont_block = self.builder.create_block()
      self.builder.brnz(eq, store_block, cont_block)
      self.builder.switch_to_block(store_block)
      if bits == 32 {
        self.builder.store_ptr(Type::I32, ptr, replacement_m, zero)
      } else {
        self.builder.store_ptr_narrow(bits, ptr, replacement_m, zero)
      }
      self.builder.jump(cont_block, [])
      self.builder.switch_to_block(cont_block)
      self.push(old)
    }

    // i64 cmpxchg
    61 | 64 | 65 | 66 => {
      let replacement = self.pop()
      let expected = self.pop()
      let addr = self.pop()
      let bits = if subopcode == 61 {
        64
      } else if subopcode == 64 {
        8
      } else if subopcode == 65 {
        16
      } else {
        32
      }
      let access_size = bits / 8
      align_check(addr, access_size)
      let ptr = bounds_ptr(addr, access_size)
      let zero = self.builder.iconst(Type::I64, 0L)
      let old = if bits == 64 {
        self.builder.load_ptr(Type::I64, ptr, zero)
      } else {
        self.builder.load_ptr_narrow(Type::I64, bits, false, ptr, zero)
      }
      let mask = if bits == 64 {
        self.builder.iconst_i64(-1L)
      } else if bits == 32 {
        self.builder.iconst_i64(0xFFFF_FFFFL)
      } else if bits == 16 {
        self.builder.iconst_i64(0xFFFFL)
      } else {
        self.builder.iconst_i64(0xFFL)
      }
      let expected_m = if bits == 64 {
        expected
      } else {
        self.builder.band(expected, mask)
      }
      let replacement_m = if bits == 64 {
        replacement
      } else {
        self.builder.band(replacement, mask)
      }
      let eq = self.builder.icmp(IntCC::Eq, old, expected_m)
      let store_block = self.builder.create_block()
      let cont_block = self.builder.create_block()
      self.builder.brnz(eq, store_block, cont_block)
      self.builder.switch_to_block(store_block)
      if bits == 64 {
        self.builder.store_ptr(Type::I64, ptr, replacement_m, zero)
      } else {
        self.builder.store_ptr_narrow(bits, ptr, replacement_m, zero)
      }
      self.builder.jump(cont_block, [])
      self.builder.switch_to_block(cont_block)
      self.push(old)
    }
    _ => {
      self.builder.trap("unsupported atomic")
      self.is_unreachable = true
    }
  }
}
