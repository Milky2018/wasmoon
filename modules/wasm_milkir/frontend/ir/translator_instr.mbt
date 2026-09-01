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
    I32Eq => self.translate_icmp(Eq)
    I32Ne => self.translate_icmp(Ne)
    I32LtS => self.translate_icmp(Slt)
    I32LtU => self.translate_icmp(Ult)
    I32GtS => self.translate_icmp(Sgt)
    I32GtU => self.translate_icmp(Ugt)
    I32LeS => self.translate_icmp(Sle)
    I32LeU => self.translate_icmp(Ule)
    I32GeS => self.translate_icmp(Sge)
    I32GeU => self.translate_icmp(Uge)

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
    I64Eq => self.translate_icmp(Eq)
    I64Ne => self.translate_icmp(Ne)
    I64LtS => self.translate_icmp(Slt)
    I64LtU => self.translate_icmp(Ult)
    I64GtS => self.translate_icmp(Sgt)
    I64GtU => self.translate_icmp(Ugt)
    I64LeS => self.translate_icmp(Sle)
    I64LeU => self.translate_icmp(Ule)
    I64GeS => self.translate_icmp(Sge)
    I64GeU => self.translate_icmp(Uge)

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
      let x_bits = self.builder.bitcast(I32, x)
      let y_bits = self.builder.bitcast(I32, y)
      let magnitude = self.builder.band(
        x_bits,
        self.builder.iconst_i32(0x7FFFFFFF),
      )
      let sign = self.builder.band(
        y_bits,
        self.builder.iconst_i32(0x80000000U.reinterpret_as_int()),
      )
      let result_bits = self.builder.bor(magnitude, sign)
      let result = self.builder.bitcast(F32, result_bits)
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
    F32Eq => self.translate_fcmp(Eq)
    F32Ne => self.translate_fcmp(Ne)
    F32Lt => self.translate_fcmp(Lt)
    F32Gt => self.translate_fcmp(Gt)
    F32Le => self.translate_fcmp(Le)
    F32Ge => self.translate_fcmp(Ge)

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
      let x_bits = self.builder.bitcast(I64, x)
      let y_bits = self.builder.bitcast(I64, y)
      let magnitude = self.builder.band(
        x_bits,
        self.builder.iconst_i64(0x7FFFFFFFFFFFFFFFL),
      )
      let sign = self.builder.band(
        y_bits,
        self.builder.iconst_i64(0x8000000000000000UL.reinterpret_as_int64()),
      )
      let result_bits = self.builder.bor(magnitude, sign)
      let result = self.builder.bitcast(F64, result_bits)
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
    F64Eq => self.translate_fcmp(Eq)
    F64Ne => self.translate_fcmp(Ne)
    F64Lt => self.translate_fcmp(Lt)
    F64Gt => self.translate_fcmp(Gt)
    F64Le => self.translate_fcmp(Le)
    F64Ge => self.translate_fcmp(Ge)

    // Conversions
    I32WrapI64 => {
      let a = self.pop()
      let result = self.builder.ireduce(I32, a)
      self.push(result)
    }
    I64ExtendI32S => {
      let a = self.pop()
      let result = self.builder.sextend(I64, a)
      self.push(result)
    }
    I64ExtendI32U => {
      let a = self.pop()
      let result = self.builder.uextend(I64, a)
      self.push(result)
    }
    // In-place sign extension instructions 
    I32Extend8S => {
      let a = self.pop()
      let result = self.builder.sextend8(I32, a)
      self.push(result)
    }
    I32Extend16S => {
      let a = self.pop()
      let result = self.builder.sextend16(I32, a)
      self.push(result)
    }
    I64Extend8S => {
      let a = self.pop()
      let result = self.builder.sextend8(I64, a)
      self.push(result)
    }
    I64Extend16S => {
      let a = self.pop()
      let result = self.builder.sextend16(I64, a)
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
      let result = self.builder.fcvt_to_sint(I32, a)
      self.push(result)
    }
    I32TruncF32U | I32TruncF64U => {
      let a = self.pop()
      let result = self.builder.fcvt_to_uint(I32, a)
      self.push(result)
    }
    I64TruncF32S | I64TruncF64S => {
      let a = self.pop()
      let result = self.builder.fcvt_to_sint(I64, a)
      self.push(result)
    }
    I64TruncF32U | I64TruncF64U => {
      let a = self.pop()
      let result = self.builder.fcvt_to_uint(I64, a)
      self.push(result)
    }
    F32ConvertI32S | F32ConvertI64S => {
      let a = self.pop()
      let result = self.builder.sint_to_fcvt(F32, a)
      self.push(result)
    }
    F32ConvertI32U | F32ConvertI64U => {
      let a = self.pop()
      let result = self.builder.uint_to_fcvt(F32, a)
      self.push(result)
    }
    F64ConvertI32S | F64ConvertI64S => {
      let a = self.pop()
      let result = self.builder.sint_to_fcvt(F64, a)
      self.push(result)
    }
    F64ConvertI32U | F64ConvertI64U => {
      let a = self.pop()
      let result = self.builder.uint_to_fcvt(F64, a)
      self.push(result)
    }
    // Saturating truncation operations
    I32TruncSatF32S | I32TruncSatF64S => {
      let a = self.pop()
      let result = self.builder.fcvt_to_sint_sat(I32, a)
      self.push(result)
    }
    I32TruncSatF32U | I32TruncSatF64U => {
      let a = self.pop()
      let result = self.builder.fcvt_to_uint_sat(I32, a)
      self.push(result)
    }
    I64TruncSatF32S | I64TruncSatF64S => {
      let a = self.pop()
      let result = self.builder.fcvt_to_sint_sat(I64, a)
      self.push(result)
    }
    I64TruncSatF32U | I64TruncSatF64U => {
      let a = self.pop()
      let result = self.builder.fcvt_to_uint_sat(I64, a)
      self.push(result)
    }
    I32ReinterpretF32
    | I64ReinterpretF64
    | F32ReinterpretI32
    | F64ReinterpretI64 => {
      let a = self.pop()
      let target_ty = match instr {
        I32ReinterpretF32 => Type::I32
        I64ReinterpretF64 => I64
        F32ReinterpretI32 => F32
        F64ReinterpretI64 => F64
        _ => I32
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
        I32,
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
        I64,
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
        F32,
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
        F64,
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
        I32,
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
        I32,
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
        I32,
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
        I32,
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
        I64,
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
        I64,
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
        I64,
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
        I64,
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
        I64,
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
        I64,
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
        I32,
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
        I64,
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
        F32,
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
        F64,
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
      self.unwind_try_handlers_to_depth(0)
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
      self.unwind_try_handlers_to_depth(0)
      self.translate_return_call(func_idx)
    }
    ReturnCallIndirect(type_idx, table_idx) => {
      self.spill_locals_if_in_try()
      self.unwind_try_handlers_to_depth(0)
      self.translate_return_call_indirect(type_idx, table_idx)
    }
    ReturnCallRef(type_idx) => {
      self.spill_locals_if_in_try()
      self.unwind_try_handlers_to_depth(0)
      self.translate_return_call_ref(type_idx)
    }

    // Memory management (multi-memory support via memidx)
    // Note: These use IR opcodes instead of desugaring because they require
    // libcalls that are handled during native lowering
    MemoryGrow(memidx) => {
      let delta = self.pop()
      let is_mem64 = memidx < self.memory_is_64.length() &&
        self.memory_is_64[memidx]

      // Use the module/override maximum for memory 0.
      // For other memories, rely on the runtime descriptor's max.
      let max_pages = if memidx == 0 { self.memory_max } else { None }
      let result = match max_pages {
        Some(max) =>
          @wasm_milkir.memory_grow(
            self.builder,
            self.func_env.runtime_symbols,
            self.vmctx,
            memidx,
            delta,
            max_pages=max,
            is_memory64=is_mem64,
          )
        None =>
          @wasm_milkir.memory_grow(
            self.builder,
            self.func_env.runtime_symbols,
            self.vmctx,
            memidx,
            delta,
            is_memory64=is_mem64,
          )
      }
      self.push(result)
    }
    MemorySize(memidx) => {
      let is_mem64 = memidx < self.memory_is_64.length() &&
        self.memory_is_64[memidx]
      let result = @wasm_milkir.memory_size(
        self.builder,
        self.func_env.runtime_symbols,
        self.vmctx,
        memidx,
        is_memory64=is_mem64,
      )
      self.push(result)
    }
    MemoryFill(memidx) => {
      let n = self.pop() // size
      let val = self.pop() // value (byte)
      let d = self.pop() // destination
      @wasm_milkir.memory_fill(
        self.builder,
        self.func_env.runtime_symbols,
        self.vmctx,
        memidx,
        d,
        val,
        n,
      )
    }
    MemoryCopy(dst_memidx, src_memidx) => {
      let n = self.pop() // size
      let s = self.pop() // source
      let d = self.pop() // destination
      @wasm_milkir.memory_copy(
        self.builder,
        self.func_env.runtime_symbols,
        self.vmctx,
        dst_memidx,
        src_memidx,
        d,
        s,
        n,
      )
    }
    MemoryInit(memidx, data_idx) => {
      let n = self.pop() // size
      let s = self.pop() // source offset in data segment
      let d = self.pop() // destination offset in memory
      @wasm_milkir.memory_init(
        self.builder,
        self.func_env.runtime_symbols,
        self.vmctx,
        memidx,
        data_idx,
        d,
        s,
        n,
      )
    }
    DataDrop(data_idx) =>
      @wasm_milkir.data_drop(
        self.builder,
        self.func_env.runtime_symbols,
        self.vmctx,
        data_idx,
      )

    // Table bulk operations
    TableFill(table_idx) => {
      let n = self.pop() // size
      let val = self.pop() // value (ref)
      let d = self.pop() // destination
      @wasm_milkir.table_fill(
        self.builder,
        self.func_env.runtime_symbols,
        self.vmctx,
        table_idx,
        d,
        val,
        n,
      )
    }
    TableCopy(dst_table_idx, src_table_idx) => {
      let n = self.pop() // size
      let s = self.pop() // source
      let d = self.pop() // destination
      @wasm_milkir.table_copy(
        self.builder,
        self.func_env.runtime_symbols,
        self.vmctx,
        dst_table_idx,
        src_table_idx,
        d,
        s,
        n,
      )
    }
    TableInit(table_idx, elem_idx) => {
      let n = self.pop() // size
      let s = self.pop() // source offset in element segment
      let d = self.pop() // destination offset in table
      @wasm_milkir.table_init(
        self.builder,
        self.func_env.runtime_symbols,
        self.vmctx,
        table_idx,
        elem_idx,
        d,
        s,
        n,
      )
    }
    ElemDrop(elem_idx) =>
      @wasm_milkir.elem_drop(
        self.builder,
        self.func_env.runtime_symbols,
        self.vmctx,
        elem_idx,
      )

    // Reference types
    RefNull(ref_type) => {
      // Lowered reference encoding uses 0 for null.
      let result_ty = type_from_wasm(ref_type)
      let result = self.builder.iconst(result_ty, @wasm_milkir.NULL_REF)
      self.push(result)
    }
    RefIsNull => {
      let ref_val = self.pop()
      let null_sentinel = self.builder.iconst(ref_val.ty, @wasm_milkir.NULL_REF)
      let result = self.builder.icmp_eq(ref_val, null_sentinel)
      self.push(result)
    }
    RefFunc(func_idx) => {
      // Create a function reference - use GetFuncRef to get tagged function pointer
      // The pointer is tagged with FUNCREF_TAG (bit 61) for ref.test detection
      let result = @wasm_milkir.get_func_ref(
        self.builder,
        self.remap_func_idx(func_idx),
      )
      self.push(result)
    }
    RefAsNonNull => {
      // ref.as_non_null: convert nullable ref to non-null ref
      // Pop the reference, check if null, trap if so, otherwise push back
      let ref_val = self.pop()
      let null_sentinel = self.builder.iconst(ref_val.ty, @wasm_milkir.NULL_REF)
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
      let result = @wasm_milkir.ref_eq(self.builder, ref1, ref2)
      self.push(result)
    }
    TableGet(table_idx) => {
      // Desugar to load from vmctx.tables[table_idx][elem_idx]
      let elem_idx = self.pop()
      let is_table64 = table_idx < self.table_is_64.length() &&
        self.table_is_64[table_idx]
      let result_type = self.table_elem_types[table_idx]
      let result = self.func_env.translate_table_get(
        self.builder,
        self.vmctx,
        table_idx,
        elem_idx,
        result_type,
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
      // a libcall that is handled during native lowering
      // Stack: [init_value, delta] -> [result]
      let delta = self.pop()
      let init_value = self.pop()
      let is_table64 = table_idx < self.table_is_64.length() &&
        self.table_is_64[table_idx]
      let result = @wasm_milkir.table_grow(
        self.builder,
        self.func_env.runtime_symbols,
        self.vmctx,
        table_idx,
        delta,
        init_value,
        is_table64~,
      )
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
      let result = @wasm_milkir.struct_new(self.builder, type_idx, fields)
      self.push(result)
    }
    StructNewDefault(type_idx) => {
      let result = @wasm_milkir.struct_new_default(self.builder, type_idx)
      self.push(result)
    }
    StructGet(type_idx, field_idx) => {
      let struct_ref = self.pop()
      let field_type = self.get_struct_field_ir_type(type_idx, field_idx)
      let result = @wasm_milkir.struct_get(
        self.builder,
        type_idx,
        field_idx,
        struct_ref,
        field_type,
      )
      self.push(result)
    }
    StructGetS(type_idx, field_idx) => {
      let struct_ref = self.pop()
      let byte_width = self.get_struct_field_byte_width(type_idx, field_idx)
      let result = @wasm_milkir.struct_get_s(
        self.builder,
        type_idx,
        field_idx,
        struct_ref,
        byte_width,
      )
      self.push(result)
    }
    StructGetU(type_idx, field_idx) => {
      let struct_ref = self.pop()
      let byte_width = self.get_struct_field_byte_width(type_idx, field_idx)
      let result = @wasm_milkir.struct_get_u(
        self.builder,
        type_idx,
        field_idx,
        struct_ref,
        byte_width,
      )
      self.push(result)
    }
    StructSet(type_idx, field_idx) => {
      let value = self.pop()
      let struct_ref = self.pop()
      @wasm_milkir.struct_set(
        self.builder,
        type_idx,
        field_idx,
        struct_ref,
        value,
      )
    }

    // GC instructions - array operations
    ArrayNew(type_idx) => {
      // Stack: [init_value, length] -> [arrayref]
      let length = self.pop()
      let init_value = self.pop()
      let result = @wasm_milkir.array_new(
        self.builder,
        type_idx,
        init_value,
        length,
      )
      self.push(result)
    }
    ArrayNewDefault(type_idx) => {
      // Stack: [length] -> [arrayref]
      let length = self.pop()
      let result = @wasm_milkir.array_new_default(
        self.builder,
        type_idx,
        length,
      )
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
      let result = @wasm_milkir.array_new_fixed(
        self.builder,
        type_idx,
        count,
        elements,
      )
      self.push(result)
    }
    ArrayGet(type_idx) => {
      // Stack: [arrayref, index] -> [value]
      let index = self.pop()
      let array_ref = self.pop()
      let elem_type = self.get_array_element_ir_type(type_idx)
      let result = @wasm_milkir.array_get(
        self.builder,
        type_idx,
        array_ref,
        index,
        elem_type,
      )
      self.push(result)
    }
    ArrayGetS(type_idx) => {
      let index = self.pop()
      let array_ref = self.pop()
      let byte_width = self.get_array_element_byte_width(type_idx)
      let result = @wasm_milkir.array_get_s(
        self.builder,
        type_idx,
        array_ref,
        index,
        byte_width,
      )
      self.push(result)
    }
    ArrayGetU(type_idx) => {
      let index = self.pop()
      let array_ref = self.pop()
      let byte_width = self.get_array_element_byte_width(type_idx)
      let result = @wasm_milkir.array_get_u(
        self.builder,
        type_idx,
        array_ref,
        index,
        byte_width,
      )
      self.push(result)
    }
    ArraySet(type_idx) => {
      // Stack: [arrayref, index, value] -> []
      let value = self.pop()
      let index = self.pop()
      let array_ref = self.pop()
      @wasm_milkir.array_set(self.builder, type_idx, array_ref, index, value)
    }
    ArrayLen => {
      let array_ref = self.pop()
      let result = @wasm_milkir.array_len(self.builder, array_ref)
      self.push(result)
    }
    ArrayFill(type_idx) => {
      // Stack: [arrayref, offset, value, count] -> []
      let count = self.pop()
      let value = self.pop()
      let offset = self.pop()
      let array_ref = self.pop()
      @wasm_milkir.array_fill(
        self.builder,
        type_idx,
        array_ref,
        offset,
        value,
        count,
      )
    }
    ArrayCopy(dst_type_idx, src_type_idx) => {
      // Stack: [dst, dst_offset, src, src_offset, count] -> []
      let count = self.pop()
      let src_offset = self.pop()
      let src = self.pop()
      let dst_offset = self.pop()
      let dst = self.pop()
      @wasm_milkir.array_copy(
        self.builder,
        dst_type_idx,
        src_type_idx,
        dst,
        dst_offset,
        src,
        src_offset,
        count,
      )
    }
    ArrayNewData(type_idx, data_idx) => {
      // Stack: [data_offset, length] -> [arrayref]
      let length = self.pop()
      let data_offset = self.pop()
      let result = @wasm_milkir.array_new_data(
        self.builder,
        type_idx,
        data_idx,
        data_offset,
        length,
      )
      self.push(result)
    }
    ArrayNewElem(type_idx, elem_idx) => {
      // Stack: [elem_offset, length] -> [arrayref]
      let length = self.pop()
      let elem_offset = self.pop()
      let result = @wasm_milkir.array_new_elem(
        self.builder,
        type_idx,
        elem_idx,
        elem_offset,
        length,
      )
      self.push(result)
    }
    ArrayInitData(type_idx, data_idx) => {
      // Stack: [arrayref, arr_offset, data_offset, length] -> []
      let length = self.pop()
      let data_offset = self.pop()
      let arr_offset = self.pop()
      let array_ref = self.pop()
      @wasm_milkir.array_init_data(
        self.builder,
        type_idx,
        data_idx,
        array_ref,
        arr_offset,
        data_offset,
        length,
      )
    }
    ArrayInitElem(type_idx, elem_idx) => {
      // Stack: [arrayref, arr_offset, elem_offset, length] -> []
      let length = self.pop()
      let elem_offset = self.pop()
      let arr_offset = self.pop()
      let array_ref = self.pop()
      @wasm_milkir.array_init_elem(
        self.builder,
        type_idx,
        elem_idx,
        array_ref,
        arr_offset,
        elem_offset,
        length,
      )
    }

    // GC instructions - i31 operations
    RefI31 => {
      let value = self.pop()
      let result = @wasm_milkir.i31_new(self.builder, value)
      self.push(result)
    }
    I31GetS => {
      let i31_ref = self.pop()
      let result = @wasm_milkir.i31_get_s(self.builder, i31_ref)
      self.push(result)
    }
    I31GetU => {
      let i31_ref = self.pop()
      let result = @wasm_milkir.i31_get_u(self.builder, i31_ref)
      self.push(result)
    }

    // GC instructions - type conversions
    AnyConvertExtern => {
      let extern_ref = self.pop()
      let result = @wasm_milkir.any_convert_extern(self.builder, extern_ref)
      self.push(result)
    }
    ExternConvertAny => {
      let any_ref = self.pop()
      let result = @wasm_milkir.extern_convert_any(self.builder, any_ref)
      self.push(result)
    }

    // Type testing/casting - these are more complex, need runtime support
    RefTest(value_type) => {
      let ref_val = self.pop()
      let type_idx = self.extract_type_idx(value_type)
      let result = @wasm_milkir.ref_test(self.builder, type_idx, false, ref_val)
      self.push(result)
    }
    RefTestNull(value_type) => {
      let ref_val = self.pop()
      let type_idx = self.extract_type_idx(value_type)
      let result = @wasm_milkir.ref_test(self.builder, type_idx, true, ref_val)
      self.push(result)
    }
    RefCast(value_type) => {
      let ref_val = self.pop()
      let type_idx = self.extract_type_idx(value_type)
      let result = @wasm_milkir.ref_cast(
        self.builder,
        type_idx,
        false,
        ref_val,
        type_from_wasm(value_type),
      )
      self.push(result)
    }
    RefCastNull(value_type) => {
      let ref_val = self.pop()
      let type_idx = self.extract_type_idx(value_type)
      let result = @wasm_milkir.ref_cast(
        self.builder,
        type_idx,
        true,
        ref_val,
        type_from_wasm(value_type),
      )
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

      // Pop exception values from stack, then restore declaration order.
      let values : Array[Value] = []
      for _ in 0..<tag_types.length() {
        values.push(self.pop())
      }
      values.rev_in_place()

      // Spill all locals before throw so catch handlers see throw-time values
      self.spill_locals_if_in_try()

      // Emit Throw IR opcode with the exception values
      @wasm_milkir.emit_throw(self.builder, tag_idx, values)
      self.builder.trap("unreachable after throw")
      self.is_unreachable = true
    }
    ThrowRef => {
      // Pop exnref from stack
      let exnref = self.pop()
      // Spill all locals before throw so catch handlers see throw-time values
      self.spill_locals_if_in_try()
      // Emit ThrowRef IR opcode
      @wasm_milkir.emit_throw_ref(self.builder, exnref)
      self.builder.trap("unreachable after throw_ref")
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
      let result_types = get_block_result_types(block_type, self.func_types)

      // Create blocks for control flow
      let try_body_block = self.builder.create_block()
      let catch_dispatch = self.builder.create_block()
      let try_continuation = self.builder.create_block()
      for ty in result_types {
        self.builder.add_block_param(try_continuation, ty) |> ignore
      }

      // Emit TryTableBegin - sets up exception handler and calls setjmp
      let setjmp_result = @wasm_milkir.try_table_begin(self.builder, handler_id)

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
      self.try_handler_stack.push(handler_id)

      // Translate the body using normal block translation
      self.translate_block(block_type, body)

      // Save post-body locals for the normal continuation path
      // (locals modified in try body should be visible after try_table)
      let post_body_locals = self.locals.copy()

      // Emit TryTableEnd - pops exception handler
      @wasm_milkir.try_table_end(self.builder, handler_id)

      // Jump to continuation after try body
      let normal_args : Array[Value] = []
      let blk = self.builder.current_block()
      let normal_falls_through = !self.is_unreachable && blk.terminator is None
      if normal_falls_through {
        for _ in 0..<result_types.length() {
          normal_args.push(self.pop())
        }
        normal_args.rev_in_place()
        self.builder.jump(try_continuation, normal_args)
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
            let lo = @wasm_milkir.get_spilled_local(self.builder, spill_idx)
            let hi = @wasm_milkir.get_spilled_local(self.builder, spill_idx + 1)
            spill_idx += 2
            self.locals.push(self.spill_words_to_v128(lo, hi))
          }
          ty => {
            let spilled_bits = @wasm_milkir.get_spilled_local(
              self.builder,
              spill_idx,
            )
            spill_idx += 1
            let restored_val = self.i64_bits_to_local(spilled_bits, ty)
            self.locals.push(restored_val)
          }
        }
      }

      // Get exception tag for matching
      let exn_tag = @wasm_milkir.get_exception_tag(self.builder)

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
            self.emit_catch_branch(tag_idx, label_depth)
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
            self.emit_catch_ref_branch(tag_idx, label_depth)
            self.builder.switch_to_block(next_check)
          }
          CatchAll(label_depth) => {
            // Catch any exception - no tag check needed
            self.emit_catch_all_branch(label_depth)
            // No need to continue checking after catch_all
            break
          }
          CatchAllRef(label_depth) => {
            // Catch any exception with exnref
            self.emit_catch_all_ref_branch(label_depth)
            break
          }
        }
      }

      // If no handler matched, rethrow (delegate to outer handler)
      // Use depth=1 to skip this handler and propagate to the next outer one
      // (depth=0 would cause infinite loop by re-entering this same handler)
      let blk = self.builder.current_block()
      if blk.terminator is None {
        @wasm_milkir.delegate(self.builder, 1) // Propagate to outer handler
        self.builder.trap("unreachable after exception delegate")
      }

      // Decrement try_table_depth AFTER all catch handlers are translated
      // This ensures catch handlers can still spill for outer try_tables
      self.try_table_depth = self.try_table_depth - 1
      self.try_handler_stack.pop() |> ignore

      // === Continuation block ===
      self.builder.switch_to_block(try_continuation)

      // Restore post-body locals for the normal continuation path
      // This ensures locals modified in the try body are visible after try_table
      self.locals.clear()
      for loc in post_body_locals {
        self.locals.push(loc)
      }
      if normal_falls_through {
        for i, _ty in result_types {
          self.push(try_continuation.params[i].0)
        }
      } else {
        self.builder.trap("unreachable try_table continuation")
      }
      self.is_unreachable = !normal_falls_through
    }
    // ============ SIMD Instructions ============
    _ => self.translate_instruction_simd(instr)
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
    let zero = self.builder.iconst(I64, 0L)
    self.builder.load_ptr_narrow(I32, bits, false, ptr, zero)
  }

  fn store_u32(bits : Int, addr : Value, value : Value) -> Unit {
    align_check(addr, bits / 8)
    let ptr = bounds_ptr(addr, bits / 8)
    let zero = self.builder.iconst(I64, 0L)
    self.builder.store_ptr_narrow(bits, ptr, value, zero)
  }

  fn load_u64(bits : Int, addr : Value) -> Value {
    align_check(addr, bits / 8)
    let ptr = bounds_ptr(addr, bits / 8)
    let zero = self.builder.iconst(I64, 0L)
    self.builder.load_ptr_narrow(I64, bits, false, ptr, zero)
  }

  fn store_u64(bits : Int, addr : Value, value : Value) -> Unit {
    align_check(addr, bits / 8)
    let ptr = bounds_ptr(addr, bits / 8)
    let zero = self.builder.iconst(I64, 0L)
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
      let zero = self.builder.iconst(I64, 0L)
      let actual = self.builder.load_ptr(I32, ptr, zero)
      let eq = self.builder.icmp(Eq, actual, expected)
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
      let zero = self.builder.iconst(I64, 0L)
      let actual = self.builder.load_ptr(I64, ptr, zero)
      let eq = self.builder.icmp(Eq, actual, expected)
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
      let zero = self.builder.iconst(I64, 0L)
      self.push(self.builder.load_ptr(I32, ptr, zero))
    }
    5 => {
      let addr = self.pop()
      align_check(addr, 8)
      let ptr = bounds_ptr(addr, 8)
      let zero = self.builder.iconst(I64, 0L)
      self.push(self.builder.load_ptr(I64, ptr, zero))
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
      let zero = self.builder.iconst(I64, 0L)
      self.builder.store_ptr(I32, ptr, value, zero)
    }
    12 => {
      let value = self.pop()
      let addr = self.pop()
      align_check(addr, 8)
      let ptr = bounds_ptr(addr, 8)
      let zero = self.builder.iconst(I64, 0L)
      self.builder.store_ptr(I64, ptr, value, zero)
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
      let zero = self.builder.iconst(I64, 0L)
      let old = if bits == 32 {
        self.builder.load_ptr(I32, ptr, zero)
      } else {
        self.builder.load_ptr_narrow(I32, bits, false, ptr, zero)
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
        self.builder.store_ptr(I32, ptr, new, zero)
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
      let zero = self.builder.iconst(I64, 0L)
      let old = if bits == 64 {
        self.builder.load_ptr(I64, ptr, zero)
      } else {
        self.builder.load_ptr_narrow(I64, bits, false, ptr, zero)
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
        self.builder.store_ptr(I64, ptr, new, zero)
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
      let zero = self.builder.iconst(I64, 0L)
      let old = if bits == 32 {
        self.builder.load_ptr(I32, ptr, zero)
      } else {
        self.builder.load_ptr_narrow(I32, bits, false, ptr, zero)
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
      let eq = self.builder.icmp(Eq, old, expected_m)
      let store_block = self.builder.create_block()
      let cont_block = self.builder.create_block()
      self.builder.brnz(eq, store_block, cont_block)
      self.builder.switch_to_block(store_block)
      if bits == 32 {
        self.builder.store_ptr(I32, ptr, replacement_m, zero)
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
      let zero = self.builder.iconst(I64, 0L)
      let old = if bits == 64 {
        self.builder.load_ptr(I64, ptr, zero)
      } else {
        self.builder.load_ptr_narrow(I64, bits, false, ptr, zero)
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
      let eq = self.builder.icmp(Eq, old, expected_m)
      let store_block = self.builder.create_block()
      let cont_block = self.builder.create_block()
      self.builder.brnz(eq, store_block, cont_block)
      self.builder.switch_to_block(store_block)
      if bits == 64 {
        self.builder.store_ptr(I64, ptr, replacement_m, zero)
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
