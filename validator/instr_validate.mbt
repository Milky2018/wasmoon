///|
/// Validate a single instruction
fn validate_instr(
  ctx : ValidationContext,
  stack : OperandStack,
  instr : @types.Instruction,
) -> Unit raise ValidationError {
  match instr {
    // Constants
    I32Const(_) => stack.push(@types.ValueType::I32)
    I64Const(_) => stack.push(@types.ValueType::I64)
    F32Const(_) => stack.push(@types.ValueType::F32)
    F64Const(_) => stack.push(@types.ValueType::F64)

    // Local operations
    LocalGet(idx) => {
      if idx >= ctx.locals.length() {
        raise InvalidLocalIndex(idx)
      }
      // Check if non-nullable ref local is initialized
      if idx < ctx.local_init.length() && !ctx.local_init[idx] {
        raise UninitializedLocal(idx)
      }
      stack.push(ctx.locals[idx])
    }
    LocalSet(idx) => {
      if idx >= ctx.locals.length() {
        raise InvalidLocalIndex(idx)
      }
      stack.pop(ctx.locals[idx])
      // Mark local as initialized
      if idx < ctx.local_init.length() {
        ctx.local_init[idx] = true
      }
    }
    LocalTee(idx) => {
      if idx >= ctx.locals.length() {
        raise InvalidLocalIndex(idx)
      }
      stack.pop(ctx.locals[idx])
      stack.push(ctx.locals[idx])
      // Mark local as initialized
      if idx < ctx.local_init.length() {
        ctx.local_init[idx] = true
      }
    }

    // Global operations
    GlobalGet(idx) => {
      if idx >= ctx.globals.length() {
        raise InvalidGlobalIndex(idx)
      }
      stack.push(ctx.globals[idx].value_type)
    }
    GlobalSet(idx) => {
      if idx >= ctx.globals.length() {
        raise InvalidGlobalIndex(idx)
      }
      // Global must be mutable to set
      if !ctx.globals[idx].mutable {
        raise TypeMismatch("cannot set immutable global")
      }
      stack.pop(ctx.globals[idx].value_type)
    }

    // i32 binary operations
    I32Add
    | I32Sub
    | I32Mul
    | I32DivS
    | I32DivU
    | I32RemS
    | I32RemU
    | I32And
    | I32Or
    | I32Xor
    | I32Shl
    | I32ShrS
    | I32ShrU
    | I32Rotl
    | I32Rotr => {
      stack.pop(@types.ValueType::I32)
      stack.pop(@types.ValueType::I32)
      stack.push(@types.ValueType::I32)
    }

    // i32 comparison operations
    I32Eq
    | I32Ne
    | I32LtS
    | I32LtU
    | I32GtS
    | I32GtU
    | I32LeS
    | I32LeU
    | I32GeS
    | I32GeU => {
      stack.pop(@types.ValueType::I32)
      stack.pop(@types.ValueType::I32)
      stack.push(@types.ValueType::I32)
    }

    // i32 unary operations
    I32Eqz => {
      stack.pop(@types.ValueType::I32)
      stack.push(@types.ValueType::I32)
    }
    I32Clz | I32Ctz | I32Popcnt => {
      stack.pop(@types.ValueType::I32)
      stack.push(@types.ValueType::I32)
    }
    // i32 sign-extension operations
    I32Extend8S | I32Extend16S => {
      stack.pop(@types.ValueType::I32)
      stack.push(@types.ValueType::I32)
    }

    // i64 binary operations
    I64MulWideS | I64MulWideU => {
      stack.pop(@types.ValueType::I64)
      stack.pop(@types.ValueType::I64)
      stack.push(@types.ValueType::I64)
      stack.push(@types.ValueType::I64)
    }

    // i64 binary operations
    I64Add
    | I64Sub
    | I64Mul
    | I64DivS
    | I64DivU
    | I64RemS
    | I64RemU
    | I64And
    | I64Or
    | I64Xor
    | I64Shl
    | I64ShrS
    | I64ShrU
    | I64Rotl
    | I64Rotr => {
      stack.pop(@types.ValueType::I64)
      stack.pop(@types.ValueType::I64)
      stack.push(@types.ValueType::I64)
    }

    // i64 comparison operations
    I64Eq
    | I64Ne
    | I64LtS
    | I64LtU
    | I64GtS
    | I64GtU
    | I64LeS
    | I64LeU
    | I64GeS
    | I64GeU => {
      stack.pop(@types.ValueType::I64)
      stack.pop(@types.ValueType::I64)
      stack.push(@types.ValueType::I32)
    }

    // i64 unary operations
    I64Eqz => {
      stack.pop(@types.ValueType::I64)
      stack.push(@types.ValueType::I32)
    }
    I64Clz | I64Ctz | I64Popcnt => {
      stack.pop(@types.ValueType::I64)
      stack.push(@types.ValueType::I64)
    }
    // i64 sign-extension operations
    I64Extend8S | I64Extend16S | I64Extend32S => {
      stack.pop(@types.ValueType::I64)
      stack.push(@types.ValueType::I64)
    }

    // f32 binary operations
    F32Add | F32Sub | F32Mul | F32Div | F32Min | F32Max | F32Copysign => {
      stack.pop(@types.ValueType::F32)
      stack.pop(@types.ValueType::F32)
      stack.push(@types.ValueType::F32)
    }

    // f32 comparison operations
    F32Eq | F32Ne | F32Lt | F32Gt | F32Le | F32Ge => {
      stack.pop(@types.ValueType::F32)
      stack.pop(@types.ValueType::F32)
      stack.push(@types.ValueType::I32)
    }

    // f32 unary operations
    F32Abs | F32Neg | F32Ceil | F32Floor | F32Trunc | F32Nearest | F32Sqrt => {
      stack.pop(@types.ValueType::F32)
      stack.push(@types.ValueType::F32)
    }

    // f64 binary operations
    F64Add | F64Sub | F64Mul | F64Div | F64Min | F64Max | F64Copysign => {
      stack.pop(@types.ValueType::F64)
      stack.pop(@types.ValueType::F64)
      stack.push(@types.ValueType::F64)
    }

    // f64 comparison operations
    F64Eq | F64Ne | F64Lt | F64Gt | F64Le | F64Ge => {
      stack.pop(@types.ValueType::F64)
      stack.pop(@types.ValueType::F64)
      stack.push(@types.ValueType::I32)
    }

    // f64 unary operations
    F64Abs | F64Neg | F64Ceil | F64Floor | F64Trunc | F64Nearest | F64Sqrt => {
      stack.pop(@types.ValueType::F64)
      stack.push(@types.ValueType::F64)
    }

    // Conversion operations
    I32WrapI64 => {
      stack.pop(@types.ValueType::I64)
      stack.push(@types.ValueType::I32)
    }
    I64ExtendI32S | I64ExtendI32U => {
      stack.pop(@types.ValueType::I32)
      stack.push(@types.ValueType::I64)
    }
    I32TruncF32S | I32TruncF32U | I32TruncSatF32S | I32TruncSatF32U => {
      stack.pop(@types.ValueType::F32)
      stack.push(@types.ValueType::I32)
    }
    I32TruncF64S | I32TruncF64U | I32TruncSatF64S | I32TruncSatF64U => {
      stack.pop(@types.ValueType::F64)
      stack.push(@types.ValueType::I32)
    }
    I64TruncF32S | I64TruncF32U | I64TruncSatF32S | I64TruncSatF32U => {
      stack.pop(@types.ValueType::F32)
      stack.push(@types.ValueType::I64)
    }
    I64TruncF64S | I64TruncF64U | I64TruncSatF64S | I64TruncSatF64U => {
      stack.pop(@types.ValueType::F64)
      stack.push(@types.ValueType::I64)
    }
    F32ConvertI32S | F32ConvertI32U => {
      stack.pop(@types.ValueType::I32)
      stack.push(@types.ValueType::F32)
    }
    F32ConvertI64S | F32ConvertI64U => {
      stack.pop(@types.ValueType::I64)
      stack.push(@types.ValueType::F32)
    }
    F64ConvertI32S | F64ConvertI32U => {
      stack.pop(@types.ValueType::I32)
      stack.push(@types.ValueType::F64)
    }
    F64ConvertI64S | F64ConvertI64U => {
      stack.pop(@types.ValueType::I64)
      stack.push(@types.ValueType::F64)
    }
    F32DemoteF64 => {
      stack.pop(@types.ValueType::F64)
      stack.push(@types.ValueType::F32)
    }
    F64PromoteF32 => {
      stack.pop(@types.ValueType::F32)
      stack.push(@types.ValueType::F64)
    }
    I32ReinterpretF32 => {
      stack.pop(@types.ValueType::F32)
      stack.push(@types.ValueType::I32)
    }
    I64ReinterpretF64 => {
      stack.pop(@types.ValueType::F64)
      stack.push(@types.ValueType::I64)
    }
    F32ReinterpretI32 => {
      stack.pop(@types.ValueType::I32)
      stack.push(@types.ValueType::F32)
    }
    F64ReinterpretI64 => {
      stack.pop(@types.ValueType::I64)
      stack.push(@types.ValueType::F64)
    }

    // Memory operations - validate memory index exists
    // Natural alignment: 8-bit=0, 16-bit=1, 32-bit=2, 64-bit=3
    I32Load(memidx, align, offset) => {
      if memidx >= ctx.mems.length() {
        raise InvalidMemoryIndex(memidx)
      }
      validate_mem_offset(ctx.mems[memidx], offset)
      if align > 2 {
        raise InvalidAlignment(
          "i32.load alignment \{align} exceeds natural alignment 2",
        )
      }
      stack.pop(ctx.mems[memidx].addr_type()) // address
      stack.push(@types.ValueType::I32)
    }
    I32Load8S(memidx, align, offset) | I32Load8U(memidx, align, offset) => {
      if memidx >= ctx.mems.length() {
        raise InvalidMemoryIndex(memidx)
      }
      validate_mem_offset(ctx.mems[memidx], offset)
      if align > 0 {
        raise InvalidAlignment(
          "i32.load8 alignment \{align} exceeds natural alignment 0",
        )
      }
      stack.pop(ctx.mems[memidx].addr_type()) // address
      stack.push(@types.ValueType::I32)
    }
    I32Load16S(memidx, align, offset) | I32Load16U(memidx, align, offset) => {
      if memidx >= ctx.mems.length() {
        raise InvalidMemoryIndex(memidx)
      }
      validate_mem_offset(ctx.mems[memidx], offset)
      if align > 1 {
        raise InvalidAlignment(
          "i32.load16 alignment \{align} exceeds natural alignment 1",
        )
      }
      stack.pop(ctx.mems[memidx].addr_type()) // address
      stack.push(@types.ValueType::I32)
    }
    I64Load(memidx, align, offset) => {
      if memidx >= ctx.mems.length() {
        raise InvalidMemoryIndex(memidx)
      }
      validate_mem_offset(ctx.mems[memidx], offset)
      if align > 3 {
        raise InvalidAlignment(
          "i64.load alignment \{align} exceeds natural alignment 3",
        )
      }
      stack.pop(ctx.mems[memidx].addr_type()) // address
      stack.push(@types.ValueType::I64)
    }
    I64Load8S(memidx, align, offset) | I64Load8U(memidx, align, offset) => {
      if memidx >= ctx.mems.length() {
        raise InvalidMemoryIndex(memidx)
      }
      validate_mem_offset(ctx.mems[memidx], offset)
      if align > 0 {
        raise InvalidAlignment(
          "i64.load8 alignment \{align} exceeds natural alignment 0",
        )
      }
      stack.pop(ctx.mems[memidx].addr_type()) // address
      stack.push(@types.ValueType::I64)
    }
    I64Load16S(memidx, align, offset) | I64Load16U(memidx, align, offset) => {
      if memidx >= ctx.mems.length() {
        raise InvalidMemoryIndex(memidx)
      }
      validate_mem_offset(ctx.mems[memidx], offset)
      if align > 1 {
        raise InvalidAlignment(
          "i64.load16 alignment \{align} exceeds natural alignment 1",
        )
      }
      stack.pop(ctx.mems[memidx].addr_type()) // address
      stack.push(@types.ValueType::I64)
    }
    I64Load32S(memidx, align, offset) | I64Load32U(memidx, align, offset) => {
      if memidx >= ctx.mems.length() {
        raise InvalidMemoryIndex(memidx)
      }
      validate_mem_offset(ctx.mems[memidx], offset)
      if align > 2 {
        raise InvalidAlignment(
          "i64.load32 alignment \{align} exceeds natural alignment 2",
        )
      }
      stack.pop(ctx.mems[memidx].addr_type()) // address
      stack.push(@types.ValueType::I64)
    }
    F32Load(memidx, align, offset) => {
      if memidx >= ctx.mems.length() {
        raise InvalidMemoryIndex(memidx)
      }
      validate_mem_offset(ctx.mems[memidx], offset)
      if align > 2 {
        raise InvalidAlignment(
          "f32.load alignment \{align} exceeds natural alignment 2",
        )
      }
      stack.pop(ctx.mems[memidx].addr_type()) // address
      stack.push(@types.ValueType::F32)
    }
    F64Load(memidx, align, offset) => {
      if memidx >= ctx.mems.length() {
        raise InvalidMemoryIndex(memidx)
      }
      validate_mem_offset(ctx.mems[memidx], offset)
      if align > 3 {
        raise InvalidAlignment(
          "f64.load alignment \{align} exceeds natural alignment 3",
        )
      }
      stack.pop(ctx.mems[memidx].addr_type()) // address
      stack.push(@types.ValueType::F64)
    }
    I32Store(memidx, align, offset) => {
      if memidx >= ctx.mems.length() {
        raise InvalidMemoryIndex(memidx)
      }
      validate_mem_offset(ctx.mems[memidx], offset)
      if align > 2 {
        raise InvalidAlignment(
          "i32.store alignment \{align} exceeds natural alignment 2",
        )
      }
      stack.pop(@types.ValueType::I32) // value
      stack.pop(ctx.mems[memidx].addr_type()) // address
    }
    I32Store8(memidx, align, offset) => {
      if memidx >= ctx.mems.length() {
        raise InvalidMemoryIndex(memidx)
      }
      validate_mem_offset(ctx.mems[memidx], offset)
      if align > 0 {
        raise InvalidAlignment(
          "i32.store8 alignment \{align} exceeds natural alignment 0",
        )
      }
      stack.pop(@types.ValueType::I32) // value
      stack.pop(ctx.mems[memidx].addr_type()) // address
    }
    I32Store16(memidx, align, offset) => {
      if memidx >= ctx.mems.length() {
        raise InvalidMemoryIndex(memidx)
      }
      validate_mem_offset(ctx.mems[memidx], offset)
      if align > 1 {
        raise InvalidAlignment(
          "i32.store16 alignment \{align} exceeds natural alignment 1",
        )
      }
      stack.pop(@types.ValueType::I32) // value
      stack.pop(ctx.mems[memidx].addr_type()) // address
    }
    I64Store(memidx, align, offset) => {
      if memidx >= ctx.mems.length() {
        raise InvalidMemoryIndex(memidx)
      }
      validate_mem_offset(ctx.mems[memidx], offset)
      if align > 3 {
        raise InvalidAlignment(
          "i64.store alignment \{align} exceeds natural alignment 3",
        )
      }
      stack.pop(@types.ValueType::I64) // value
      stack.pop(ctx.mems[memidx].addr_type()) // address
    }
    I64Store8(memidx, align, offset) => {
      if memidx >= ctx.mems.length() {
        raise InvalidMemoryIndex(memidx)
      }
      validate_mem_offset(ctx.mems[memidx], offset)
      if align > 0 {
        raise InvalidAlignment(
          "i64.store8 alignment \{align} exceeds natural alignment 0",
        )
      }
      stack.pop(@types.ValueType::I64) // value
      stack.pop(ctx.mems[memidx].addr_type()) // address
    }
    I64Store16(memidx, align, offset) => {
      if memidx >= ctx.mems.length() {
        raise InvalidMemoryIndex(memidx)
      }
      validate_mem_offset(ctx.mems[memidx], offset)
      if align > 1 {
        raise InvalidAlignment(
          "i64.store16 alignment \{align} exceeds natural alignment 1",
        )
      }
      stack.pop(@types.ValueType::I64) // value
      stack.pop(ctx.mems[memidx].addr_type()) // address
    }
    I64Store32(memidx, align, offset) => {
      if memidx >= ctx.mems.length() {
        raise InvalidMemoryIndex(memidx)
      }
      validate_mem_offset(ctx.mems[memidx], offset)
      if align > 2 {
        raise InvalidAlignment(
          "i64.store32 alignment \{align} exceeds natural alignment 2",
        )
      }
      stack.pop(@types.ValueType::I64) // value
      stack.pop(ctx.mems[memidx].addr_type()) // address
    }
    F32Store(memidx, align, offset) => {
      if memidx >= ctx.mems.length() {
        raise InvalidMemoryIndex(memidx)
      }
      validate_mem_offset(ctx.mems[memidx], offset)
      if align > 2 {
        raise InvalidAlignment(
          "f32.store alignment \{align} exceeds natural alignment 2",
        )
      }
      stack.pop(@types.ValueType::F32) // value
      stack.pop(ctx.mems[memidx].addr_type()) // address
    }
    F64Store(memidx, align, offset) => {
      if memidx >= ctx.mems.length() {
        raise InvalidMemoryIndex(memidx)
      }
      validate_mem_offset(ctx.mems[memidx], offset)
      if align > 3 {
        raise InvalidAlignment(
          "f64.store alignment \{align} exceeds natural alignment 3",
        )
      }
      stack.pop(@types.ValueType::F64) // value
      stack.pop(ctx.mems[memidx].addr_type()) // address
    }
    MemorySize(memidx) | MemoryGrow(memidx) => {
      if memidx >= ctx.mems.length() {
        raise InvalidMemoryIndex(memidx)
      }
      let addr_type = ctx.mems[memidx].addr_type()
      if instr is MemoryGrow(_) {
        stack.pop(addr_type) // delta
      }
      stack.push(addr_type)
    }
    MemoryInit(memidx, data_idx) => {
      if memidx >= ctx.mems.length() {
        raise InvalidMemoryIndex(memidx)
      }
      if data_idx >= ctx.data_count {
        raise InvalidDataIndex(data_idx)
      }
      let addr_type = ctx.mems[memidx].addr_type()
      stack.pop(@types.ValueType::I32) // n (always i32 for data segment offset)
      stack.pop(@types.ValueType::I32) // s (always i32 for data segment offset)
      stack.pop(addr_type) // d (memory address)
    }
    DataDrop(data_idx) =>
      if data_idx >= ctx.data_count {
        raise InvalidDataIndex(data_idx)
      }
    MemoryCopy(dst, src) => {
      if dst >= ctx.mems.length() {
        raise InvalidMemoryIndex(dst)
      }
      if src >= ctx.mems.length() {
        raise InvalidMemoryIndex(src)
      }
      let dst_addr_type = ctx.mems[dst].addr_type()
      let src_addr_type = ctx.mems[src].addr_type()
      // n uses the larger of the two address types
      let n_type = if dst_addr_type == @types.ValueType::I64 ||
        src_addr_type == @types.ValueType::I64 {
        @types.ValueType::I64
      } else {
        @types.ValueType::I32
      }
      stack.pop(n_type) // n
      stack.pop(src_addr_type) // s
      stack.pop(dst_addr_type) // d
    }
    MemoryFill(memidx) => {
      if memidx >= ctx.mems.length() {
        raise InvalidMemoryIndex(memidx)
      }
      let addr_type = ctx.mems[memidx].addr_type()
      stack.pop(addr_type) // n
      stack.pop(@types.ValueType::I32) // val (always i32)
      stack.pop(addr_type) // d
    }
    Atomic(subop, memidx, align, offset) => {
      // Atomics use memarg except atomic.fence (subop=3).
      if subop != 3 {
        if memidx >= ctx.mems.length() {
          raise InvalidMemoryIndex(memidx)
        }
        validate_mem_offset(ctx.mems[memidx], offset)
      }
      let addr_type = if memidx < ctx.mems.length() {
        ctx.mems[memidx].addr_type()
      } else {
        @types.ValueType::I32
      }
      fn check_align(
        natural : Int,
        name : String,
      ) -> Unit raise ValidationError {
        if align > natural {
          raise InvalidAlignment(
            "\{name} alignment \{align} exceeds natural alignment \{natural}",
          )
        }
      }

      // Reject the legacy/reserved encoding range [4, 0x10).
      // In the standard encoding, atomics (except notify/wait/fence) start at 0x10.
      if subop >= 4 && subop < 0x10 {
        raise TypeMismatch("unsupported atomic subopcode \{subop}")
      }

      // Normalize subopcode encoding: in the standard encoding most ops start at 0x10.
      let op = if subop >= 0x10 { subop - 12 } else { subop }
      match op {
        0 => {
          check_align(2, "memory.atomic.notify")
          stack.pop(@types.ValueType::I32) // count
          stack.pop(addr_type) // addr
          stack.push(@types.ValueType::I32)
        }
        1 => {
          check_align(2, "memory.atomic.wait32")
          stack.pop(@types.ValueType::I64) // timeout
          stack.pop(@types.ValueType::I32) // expected
          stack.pop(addr_type) // addr
          stack.push(@types.ValueType::I32)
        }
        2 => {
          check_align(3, "memory.atomic.wait64")
          stack.pop(@types.ValueType::I64) // timeout
          stack.pop(@types.ValueType::I64) // expected
          stack.pop(addr_type) // addr
          stack.push(@types.ValueType::I32)
        }
        3 => () // atomic.fence
        4 | 6 | 7 => {
          // i32.atomic.load / load8_u / load16_u
          let natural = if op == 4 { 2 } else if op == 6 { 0 } else { 1 }
          check_align(natural, "i32.atomic.load")
          stack.pop(addr_type)
          stack.push(@types.ValueType::I32)
        }
        5 | 8 | 9 | 10 => {
          // i64.atomic.load / load8_u / load16_u / load32_u
          let natural = if op == 5 {
            3
          } else if op == 8 {
            0
          } else if op == 9 {
            1
          } else {
            2
          }
          check_align(natural, "i64.atomic.load")
          stack.pop(addr_type)
          stack.push(@types.ValueType::I64)
        }
        11 | 13 | 14 => {
          // i32.atomic.store / store8 / store16
          let natural = if op == 11 { 2 } else if op == 13 { 0 } else { 1 }
          check_align(natural, "i32.atomic.store")
          stack.pop(@types.ValueType::I32)
          stack.pop(addr_type)
        }
        12 | 15 | 16 | 17 => {
          // i64.atomic.store / store8 / store16 / store32
          let natural = if op == 12 {
            3
          } else if op == 15 {
            0
          } else if op == 16 {
            1
          } else {
            2
          }
          check_align(natural, "i64.atomic.store")
          stack.pop(@types.ValueType::I64)
          stack.pop(addr_type)
        }

        // RMW add/sub/and/or/xor/xchg
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
          // i32 variants (32/8/16)
          let natural = if op == 18 ||
            op == 25 ||
            op == 32 ||
            op == 39 ||
            op == 46 ||
            op == 53 {
            2
          } else if op == 20 ||
            op == 27 ||
            op == 34 ||
            op == 41 ||
            op == 48 ||
            op == 55 {
            0
          } else {
            1
          }
          check_align(natural, "i32.atomic.rmw")
          stack.pop(@types.ValueType::I32)
          stack.pop(addr_type)
          stack.push(@types.ValueType::I32)
        }
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
          // i64 variants (64/8/16/32)
          let natural = if op == 19 ||
            op == 26 ||
            op == 33 ||
            op == 40 ||
            op == 47 ||
            op == 54 {
            3
          } else if op == 22 ||
            op == 29 ||
            op == 36 ||
            op == 43 ||
            op == 50 ||
            op == 57 {
            0
          } else if op == 23 ||
            op == 30 ||
            op == 37 ||
            op == 44 ||
            op == 51 ||
            op == 58 {
            1
          } else {
            2
          }
          check_align(natural, "i64.atomic.rmw")
          stack.pop(@types.ValueType::I64)
          stack.pop(addr_type)
          stack.push(@types.ValueType::I64)
        }

        // cmpxchg
        60 | 62 | 63 => {
          // i32 cmpxchg + 8/16
          let natural = if op == 60 { 2 } else if op == 62 { 0 } else { 1 }
          check_align(natural, "i32.atomic.rmw.cmpxchg")
          stack.pop(@types.ValueType::I32) // replacement
          stack.pop(@types.ValueType::I32) // expected
          stack.pop(addr_type)
          stack.push(@types.ValueType::I32)
        }
        61 | 64 | 65 | 66 => {
          // i64 cmpxchg + 8/16/32
          let natural = if op == 61 {
            3
          } else if op == 64 {
            0
          } else if op == 65 {
            1
          } else {
            2
          }
          check_align(natural, "i64.atomic.rmw.cmpxchg")
          stack.pop(@types.ValueType::I64) // replacement
          stack.pop(@types.ValueType::I64) // expected
          stack.pop(addr_type)
          stack.push(@types.ValueType::I64)
        }
        _ => raise TypeMismatch("unsupported atomic subopcode \{subop}")
      }
    }

    // Table operations
    TableGet(idx) => {
      if idx >= ctx.tables.length() {
        raise InvalidTableIndex(idx)
      }
      let table = ctx.tables[idx]
      let idx_type = if table.is_table64 {
        @types.ValueType::I64
      } else {
        @types.ValueType::I32
      }
      stack.pop(idx_type) // index
      stack.push(table.elem_type)
    }
    TableSet(idx) => {
      if idx >= ctx.tables.length() {
        raise InvalidTableIndex(idx)
      }
      let table = ctx.tables[idx]
      let idx_type = if table.is_table64 {
        @types.ValueType::I64
      } else {
        @types.ValueType::I32
      }
      stack.pop(table.elem_type) // value
      stack.pop(idx_type) // index
    }
    TableSize(idx) => {
      if idx >= ctx.tables.length() {
        raise InvalidTableIndex(idx)
      }
      let table = ctx.tables[idx]
      if table.is_table64 {
        stack.push(@types.ValueType::I64)
      } else {
        stack.push(@types.ValueType::I32)
      }
    }
    TableGrow(idx) => {
      if idx >= ctx.tables.length() {
        raise InvalidTableIndex(idx)
      }
      let table = ctx.tables[idx]
      let idx_type = if table.is_table64 {
        @types.ValueType::I64
      } else {
        @types.ValueType::I32
      }
      stack.pop(idx_type) // delta
      stack.pop(table.elem_type) // init value
      stack.push(idx_type) // old size or -1
    }
    TableFill(idx) => {
      if idx >= ctx.tables.length() {
        raise InvalidTableIndex(idx)
      }
      let table = ctx.tables[idx]
      let idx_type = if table.is_table64 {
        @types.ValueType::I64
      } else {
        @types.ValueType::I32
      }
      stack.pop(idx_type) // n
      stack.pop(table.elem_type) // value
      stack.pop(idx_type) // i
    }
    TableCopy(dst_idx, src_idx) => {
      if dst_idx >= ctx.tables.length() {
        raise InvalidTableIndex(dst_idx)
      }
      if src_idx >= ctx.tables.length() {
        raise InvalidTableIndex(src_idx)
      }
      // Check that source element type is subtype of destination element type
      let dst_table = ctx.tables[dst_idx]
      let src_table = ctx.tables[src_idx]
      if not(is_type_subtype(src_table.elem_type, dst_table.elem_type)) {
        raise TypeMismatch(
          "table.copy: source element type \{src_table.elem_type} is not subtype of destination element type \{dst_table.elem_type}",
        )
      }
      // Length uses i64 only if BOTH tables are table64 (minimum of both types)
      let len_type = if dst_table.is_table64 && src_table.is_table64 {
        @types.ValueType::I64
      } else {
        @types.ValueType::I32
      }
      stack.pop(len_type) // n
      // Source index uses source table's index type
      stack.pop(
        if src_table.is_table64 {
          @types.ValueType::I64
        } else {
          @types.ValueType::I32
        },
      ) // s
      // Dest index uses dest table's index type
      stack.pop(
        if dst_table.is_table64 {
          @types.ValueType::I64
        } else {
          @types.ValueType::I32
        },
      ) // d
    }
    TableInit(table_idx, elem_idx) => {
      // Validate table and elem indices
      if table_idx >= ctx.tables.length() {
        raise InvalidTableIndex(table_idx)
      }
      if elem_idx >= ctx.elems.length() {
        raise InvalidElemIndex(elem_idx)
      }
      // Check elem segment type matches table element type
      let table = ctx.tables[table_idx]
      let elem_type = ctx.elems[elem_idx]
      if elem_type != table.elem_type {
        raise TypeMismatch(
          "element segment type \{elem_type} does not match table element type \{table.elem_type}",
        )
      }
      // For table64: d uses table's index type, s and n are always i32
      // (s is offset into elem segment, n is count - both use i32 since elem is i32-indexed)
      let idx_type = if table.is_table64 {
        @types.ValueType::I64
      } else {
        @types.ValueType::I32
      }
      stack.pop(@types.ValueType::I32) // n (always i32 - elem segments are i32-indexed)
      stack.pop(@types.ValueType::I32) // s (always i32 - offset into elem segment)
      stack.pop(idx_type) // d (table's index type)
    }
    ElemDrop(elem_idx) =>
      if elem_idx >= ctx.elems.length() {
        raise InvalidElemIndex(elem_idx)
      }

    // Reference instructions
    RefNull(ref_type) => stack.push(ref_type)
    RefIsNull => {
      stack.pop_any() |> ignore // any ref type
      stack.push(@types.ValueType::I32)
    }
    RefEqInstr => {
      // ref.eq: compares two references for equality
      // Both operands must be subtypes of eqref
      let val2 = stack.pop_any()
      let val1 = stack.pop_any()
      // Check that both operands are subtypes of eqref
      if not(is_subtype_of_eqref(val1)) {
        raise TypeMismatch(
          "ref.eq operand must be subtype of eqref, got \{val1}",
        )
      }
      if not(is_subtype_of_eqref(val2)) {
        raise TypeMismatch(
          "ref.eq operand must be subtype of eqref, got \{val2}",
        )
      }
      stack.push(@types.ValueType::I32)
    }
    RefFunc(func_idx) => {
      if func_idx >= ctx.funcs.length() {
        raise InvalidFunctionIndex(func_idx)
      }
      // Check that function is declared (referenced in elem segment or global init)
      if !ctx.declared_funcs.contains(func_idx) {
        raise UndeclaredFunctionReference(func_idx)
      }
      // ref.func produces (ref $t) where $t is the function's type index
      let type_idx = ctx.funcs[func_idx]
      stack.push(@types.ValueType::RefFuncTyped(type_idx))
    }
    RefAsNonNull => {
      // ref.as_non_null: pops nullable ref, pushes non-null ref
      // In polymorphic context (after unreachable), any type is valid
      stack.pop_any() |> ignore
      // Push a non-null reference - using FuncRef as placeholder
      // The actual type depends on the input type
      stack.push(@types.ValueType::RefFunc)
    }
    BrOnNull(label_idx) => {
      // br_on_null: pops a ref, branches if null, otherwise continues with non-null ref
      if label_idx >= ctx.labels.length() {
        raise InvalidLabelIndex(label_idx)
      }
      // Pop the reference - in unreachable context this may be polymorphic
      stack.pop_any() |> ignore
      // If not null, the non-null reference remains on stack
      stack.push(@types.ValueType::RefFunc)
    }
    BrOnNonNull(label_idx) => {
      // br_on_non_null: pops a ref, branches with ref if non-null, otherwise continues
      if label_idx >= ctx.labels.length() {
        raise InvalidLabelIndex(label_idx)
      }
      // Pop the reference - in unreachable context this may be polymorphic
      stack.pop_any() |> ignore
      // If null, fall through with nothing on stack (ref is consumed)
      // If non-null, branch to target with the ref
    }

    // Control flow
    Nop => ()
    Unreachable => stack.set_polymorphic()
    Drop => stack.pop_any() |> ignore
    Select => {
      stack.pop(@types.ValueType::I32) // condition
      let t2 = stack.pop_any()
      let t1 = stack.pop_any()
      if t1 != t2 {
        raise TypeMismatch(
          "select operands must have same type: \{t1} vs \{t2}",
        )
      }
      // Untyped select (without explicit result type) only works with numeric types.
      // For reference types, the typed form `select t*` must be used.
      if is_ref_type(t1) {
        raise TypeMismatch(
          "type mismatch: select with reference type requires explicit type annotation",
        )
      }
      stack.push(t1)
    }
    SelectTyped(types) => {
      // Select must have exactly one result type
      if types.length() != 1 {
        raise TypeMismatch("invalid result arity")
      }
      // Validate type indices
      let num_types = ctx.types.length()
      for ty in types {
        validate_value_type(ty, num_types)
      }
      stack.pop(@types.ValueType::I32) // condition
      // Pop operands matching result types in reverse
      for i = types.length() - 1; i >= 0; i = i - 1 {
        stack.pop(types[i])
        stack.pop(types[i])
      }
      // Push results
      for ty in types {
        stack.push(ty)
      }
    }

    // Function calls
    Call(func_idx) => {
      if func_idx >= ctx.funcs.length() {
        raise InvalidFunctionIndex(func_idx)
      }
      let type_idx = ctx.funcs[func_idx]
      let func_type = ctx.get_func_type(type_idx)
      // Pop parameters in reverse order
      let num_params = func_type.params.length()
      for offset in 0..<num_params {
        let i = num_params - 1 - offset
        stack.pop(func_type.params[i])
      }
      // Push results
      for result in func_type.results {
        stack.push(result)
      }
    }
    CallIndirect(type_idx, table_idx) => {
      if table_idx < 0 || table_idx >= ctx.tables.length() {
        raise InvalidTableIndex(table_idx)
      }
      // call_indirect requires a funcref table
      let table = ctx.tables[table_idx]
      if table.elem_type != @types.ValueType::FuncRef {
        raise TypeMismatch(
          "call_indirect requires funcref table, got \{table.elem_type}",
        )
      }
      if type_idx < 0 || type_idx >= ctx.types.length() {
        raise InvalidTypeIndex(type_idx)
      }
      // Table index uses i64 for table64
      let idx_type = if table.is_table64 {
        @types.ValueType::I64
      } else {
        @types.ValueType::I32
      }
      stack.pop(idx_type) // table index
      let func_type = ctx.get_func_type(type_idx)
      let num_ci_params = func_type.params.length()
      for offset in 0..<num_ci_params {
        let i = num_ci_params - 1 - offset
        stack.pop(func_type.params[i])
      }
      for result in func_type.results {
        stack.push(result)
      }
    }
    CallRef(type_idx) => {
      if type_idx < 0 || type_idx >= ctx.types.length() {
        raise InvalidTypeIndex(type_idx)
      }
      let func_type = ctx.get_func_type(type_idx)
      // Pop the function reference (ref null $t)
      // In unreachable context, this may be a polymorphic type
      stack.pop(@types.ValueType::RefNullFuncTyped(type_idx))
      // Pop parameters in reverse order
      let num_params = func_type.params.length()
      for offset in 0..<num_params {
        let i = num_params - 1 - offset
        stack.pop(func_type.params[i])
      }
      // Push results
      for result in func_type.results {
        stack.push(result)
      }
    }
    ReturnCall(func_idx) => {
      if func_idx >= ctx.funcs.length() {
        raise InvalidFunctionIndex(func_idx)
      }
      let type_idx = ctx.funcs[func_idx]
      let func_type = ctx.get_func_type(type_idx)
      // Pop parameters in reverse order
      let num_params = func_type.params.length()
      for offset in 0..<num_params {
        let i = num_params - 1 - offset
        stack.pop(func_type.params[i])
      }
      // Validate results match current function's return type
      // (For tail calls, we return the called function's results)
      for i = 0; i < func_type.results.length(); i = i + 1 {
        if i >= ctx.returns.length() || func_type.results[i] != ctx.returns[i] {
          raise TypeMismatch("return_call result type mismatch")
        }
      }
      if func_type.results.length() != ctx.returns.length() {
        raise TypeMismatch("return_call result count mismatch")
      }
      // After return_call, the stack is unreachable
      stack.set_polymorphic()
    }
    ReturnCallIndirect(type_idx, table_idx) => {
      if table_idx < 0 || table_idx >= ctx.tables.length() {
        raise InvalidTableIndex(table_idx)
      }
      // return_call_indirect requires a funcref table
      let table = ctx.tables[table_idx]
      if table.elem_type != @types.ValueType::FuncRef {
        raise TypeMismatch(
          "return_call_indirect requires funcref table, got \{table.elem_type}",
        )
      }
      if type_idx < 0 || type_idx >= ctx.types.length() {
        raise InvalidTypeIndex(type_idx)
      }
      // Table index uses i64 for table64
      let idx_type = if table.is_table64 {
        @types.ValueType::I64
      } else {
        @types.ValueType::I32
      }
      stack.pop(idx_type) // table index
      let func_type = ctx.get_func_type(type_idx)
      let num_params = func_type.params.length()
      for offset in 0..<num_params {
        let i = num_params - 1 - offset
        stack.pop(func_type.params[i])
      }
      // Validate results match current function's return type
      for i = 0; i < func_type.results.length(); i = i + 1 {
        if i >= ctx.returns.length() || func_type.results[i] != ctx.returns[i] {
          raise TypeMismatch("return_call_indirect result type mismatch")
        }
      }
      if func_type.results.length() != ctx.returns.length() {
        raise TypeMismatch("return_call_indirect result count mismatch")
      }
      // After return_call_indirect, the stack is unreachable
      stack.set_polymorphic()
    }
    ReturnCallRef(type_idx) => {
      if type_idx < 0 || type_idx >= ctx.types.length() {
        raise InvalidTypeIndex(type_idx)
      }
      let func_type = ctx.get_func_type(type_idx)
      // Pop the function reference (ref null $t)
      stack.pop(@types.ValueType::RefNullFuncTyped(type_idx))
      // Pop parameters in reverse order
      let num_params = func_type.params.length()
      for offset in 0..<num_params {
        let i = num_params - 1 - offset
        stack.pop(func_type.params[i])
      }
      // Validate results match current function's return type
      for i = 0; i < func_type.results.length(); i = i + 1 {
        if i >= ctx.returns.length() || func_type.results[i] != ctx.returns[i] {
          raise TypeMismatch("return_call_ref result type mismatch")
        }
      }
      if func_type.results.length() != ctx.returns.length() {
        raise TypeMismatch("return_call_ref result count mismatch")
      }
      // After return_call_ref, the stack is unreachable
      stack.set_polymorphic()
    }

    // Block, Loop, If - with stack height validation and label tracking
    Block(bt, body) => {
      let results = get_block_results(ctx, bt)
      let params = get_block_params(ctx, bt)
      // Pop input params from outer stack
      for i = params.length() - 1; i >= 0; i = i - 1 {
        stack.pop(params[i])
      }
      // Create inner stack with params
      let block_stack = OperandStack::new()
      for param in params {
        block_stack.push(param)
      }
      // Save local_init state - locals initialized inside block don't count outside
      let saved_init = ctx.local_init.copy()
      // Push label for block (br jumps to end, uses results)
      let label : LabelInfo = { kind: BlockLabel, block_type: bt }
      ctx.labels.push(label)
      // Validate body
      validate_expr(ctx, block_stack, body)
      // Pop label
      ctx.labels.pop() |> ignore
      // Restore local_init state
      for i in 0..<saved_init.length() {
        ctx.local_init[i] = saved_init[i]
      }
      // Check stack height: should have exactly results.length() values
      block_stack.check_height(results.length(), "block exit")
      // Verify result types
      for i = results.length() - 1; i >= 0; i = i - 1 {
        block_stack.pop(results[i])
      }
      // Push results onto outer stack
      for result in results {
        stack.push(result)
      }
    }
    Loop(bt, body) => {
      let results = get_block_results(ctx, bt)
      let params = get_block_params(ctx, bt)
      // Pop input params from outer stack
      for i = params.length() - 1; i >= 0; i = i - 1 {
        stack.pop(params[i])
      }
      // Create inner stack with params
      let block_stack = OperandStack::new()
      for param in params {
        block_stack.push(param)
      }
      // Save local_init state - locals initialized inside loop don't count outside
      let saved_init = ctx.local_init.copy()
      // Push label for loop (br jumps to start, uses params)
      let label : LabelInfo = { kind: LoopLabel, block_type: bt }
      ctx.labels.push(label)
      // Validate body
      validate_expr(ctx, block_stack, body)
      // Pop label
      ctx.labels.pop() |> ignore
      // Restore local_init state
      for i in 0..<saved_init.length() {
        ctx.local_init[i] = saved_init[i]
      }
      // Check stack height: should have exactly results.length() values
      block_stack.check_height(results.length(), "loop exit")
      // Verify result types
      for i = results.length() - 1; i >= 0; i = i - 1 {
        block_stack.pop(results[i])
      }
      // Push results onto outer stack
      for result in results {
        stack.push(result)
      }
    }
    If(bt, then_body, else_body) => {
      stack.pop(@types.ValueType::I32) // condition
      let results = get_block_results(ctx, bt)
      let params = get_block_params(ctx, bt)
      // Pop input params from outer stack
      for i = params.length() - 1; i >= 0; i = i - 1 {
        stack.pop(params[i])
      }
      // Save local_init state - locals initialized inside if don't count outside
      let saved_init = ctx.local_init.copy()
      // Push label for if (br jumps to end, uses results)
      let label : LabelInfo = { kind: BlockLabel, block_type: bt }
      ctx.labels.push(label)
      // Validate then branch
      let then_stack = OperandStack::new()
      for param in params {
        then_stack.push(param)
      }
      validate_expr(ctx, then_stack, then_body)
      then_stack.check_height(results.length(), "if-then exit")
      // Verify then result types
      for i = results.length() - 1; i >= 0; i = i - 1 {
        then_stack.pop(results[i])
      }
      // Restore local_init state before else branch
      for i in 0..<saved_init.length() {
        ctx.local_init[i] = saved_init[i]
      }
      // Validate else branch
      let else_stack = OperandStack::new()
      for param in params {
        else_stack.push(param)
      }
      validate_expr(ctx, else_stack, else_body)
      else_stack.check_height(results.length(), "if-else exit")
      // Verify else result types
      for i = results.length() - 1; i >= 0; i = i - 1 {
        else_stack.pop(results[i])
      }
      // Pop label
      ctx.labels.pop() |> ignore
      // Restore local_init state - locals initialized in if don't count outside
      for i in 0..<saved_init.length() {
        ctx.local_init[i] = saved_init[i]
      }
      // Push results onto outer stack
      for result in results {
        stack.push(result)
      }
    }

    // Branch instructions with proper label validation
    Br(label_idx) => {
      if label_idx >= ctx.labels.length() {
        raise InvalidLabelIndex(label_idx)
      }
      // Get label from stack (index 0 is innermost)
      let label = ctx.labels[ctx.labels.length() - 1 - label_idx]
      let branch_types = get_label_types(ctx, label)
      // Pop values that will be passed to target
      for i = branch_types.length() - 1; i >= 0; i = i - 1 {
        stack.pop(branch_types[i])
      }
      stack.set_polymorphic()
    }
    BrIf(label_idx) => {
      stack.pop(@types.ValueType::I32) // condition
      if label_idx >= ctx.labels.length() {
        raise InvalidLabelIndex(label_idx)
      }
      let label = ctx.labels[ctx.labels.length() - 1 - label_idx]
      let branch_types = get_label_types(ctx, label)
      // Pop and push values (conditional branch)
      for i = branch_types.length() - 1; i >= 0; i = i - 1 {
        stack.pop(branch_types[i])
      }
      for ty in branch_types {
        stack.push(ty)
      }
    }
    BrTable(labels, default_label) => {
      stack.pop(@types.ValueType::I32) // index
      // Validate default label
      if default_label >= ctx.labels.length() {
        raise InvalidLabelIndex(default_label)
      }
      let default_info = ctx.labels[ctx.labels.length() - 1 - default_label]
      let default_types = get_label_types(ctx, default_info)
      // Validate all labels have same arity as default
      for label_idx in labels {
        if label_idx >= ctx.labels.length() {
          raise InvalidLabelIndex(label_idx)
        }
        let label_info = ctx.labels[ctx.labels.length() - 1 - label_idx]
        let label_types = get_label_types(ctx, label_info)
        if label_types.length() != default_types.length() {
          raise TypeMismatch(
            "br_table labels must have same arity: expected \{default_types.length()}, got \{label_types.length()}",
          )
        }
      }
      // Pop values
      for i = default_types.length() - 1; i >= 0; i = i - 1 {
        stack.pop(default_types[i])
      }
      stack.set_polymorphic()
    }
    Return => {
      // Validate return values match function signature
      for i = ctx.returns.length() - 1; i >= 0; i = i - 1 {
        stack.pop(ctx.returns[i])
      }
      stack.set_polymorphic()
    }

    // Exception handling instructions
    Throw(tag_idx) => {
      // Validate tag index is valid
      if tag_idx < 0 || tag_idx >= ctx.tags.length() {
        raise UnknownTag(tag_idx)
      }
      // Get the tag type and pop its parameters from the stack
      let tag_type = ctx.tags[tag_idx]
      for i = tag_type.params.length() - 1; i >= 0; i = i - 1 {
        stack.pop(tag_type.params[i])
      }
      // throw never returns, so set polymorphic
      stack.set_polymorphic()
    }
    ThrowRef => {
      // throw_ref pops an exnref and throws it
      stack.pop(@types.ValueType::ExnRef)
      stack.set_polymorphic()
    }
    TryTable(bt, handlers, body) => {
      let results = get_block_results(ctx, bt)
      let params = get_block_params(ctx, bt)

      // Pop params
      for i = params.length() - 1; i >= 0; i = i - 1 {
        stack.pop(params[i])
      }

      // Validate each handler BEFORE pushing try_table's label
      // (handlers reference labels visible at the try_table instruction,
      // NOT from inside the try_table body)
      for handler in handlers {
        match handler {
          @types.CatchHandler::Catch(tag_idx, label_idx) => {
            // Validate tag index
            if tag_idx < 0 || tag_idx >= ctx.tags.length() {
              raise UnknownTag(tag_idx)
            }
            // Validate label index (labels are indexed from innermost)
            if label_idx >= ctx.labels.length() {
              raise InvalidLabelIndex(label_idx)
            }
            // Get expected types at label
            let target_label = ctx.labels[ctx.labels.length() - 1 - label_idx]
            let expected_types = get_label_types(ctx, target_label)
            // Catch provides tag params
            let tag_type = ctx.tags[tag_idx]
            if tag_type.params.length() != expected_types.length() {
              raise TypeMismatch(
                "catch handler arity mismatch: tag has \{tag_type.params.length()} params, label expects \{expected_types.length()}",
              )
            }
            // Check that each tag param is a subtype of the expected label type
            for i, param_type in tag_type.params {
              if not(
                  ctx.subtyping_ctx.value_type_subtype(
                    param_type,
                    expected_types[i],
                  ),
                ) {
                raise TypeMismatch(
                  "catch handler type mismatch: tag param \{i} has type \{param_type}, label expects \{expected_types[i]}",
                )
              }
            }
          }
          @types.CatchHandler::CatchRef(tag_idx, label_idx) => {
            // Validate tag index
            if tag_idx < 0 || tag_idx >= ctx.tags.length() {
              raise UnknownTag(tag_idx)
            }
            // Validate label index
            if label_idx >= ctx.labels.length() {
              raise InvalidLabelIndex(label_idx)
            }
            // Get expected types at label
            let target_label = ctx.labels[ctx.labels.length() - 1 - label_idx]
            let expected_types = get_label_types(ctx, target_label)
            // CatchRef provides tag params + exnref
            let tag_type = ctx.tags[tag_idx]
            let expected_arity = tag_type.params.length() + 1
            if expected_arity != expected_types.length() {
              raise TypeMismatch(
                "catch_ref handler arity mismatch: tag has \{tag_type.params.length()} params + exnref, label expects \{expected_types.length()}",
              )
            }
            // Check that each tag param is a subtype of the expected label type
            for i, param_type in tag_type.params {
              if not(
                  ctx.subtyping_ctx.value_type_subtype(
                    param_type,
                    expected_types[i],
                  ),
                ) {
                raise TypeMismatch(
                  "catch_ref handler type mismatch: tag param \{i} has type \{param_type}, label expects \{expected_types[i]}",
                )
              }
            }
            // The last expected type should be ExnRef (exnref is always a subtype of itself)
          }
          @types.CatchHandler::CatchAll(label_idx) => {
            // Validate label index
            if label_idx >= ctx.labels.length() {
              raise InvalidLabelIndex(label_idx)
            }
            // CatchAll provides no values
            let target_label = ctx.labels[ctx.labels.length() - 1 - label_idx]
            let expected_types = get_label_types(ctx, target_label)
            if expected_types.length() != 0 {
              raise TypeMismatch(
                "catch_all handler arity mismatch: provides 0 values, label expects \{expected_types.length()}",
              )
            }
          }
          @types.CatchHandler::CatchAllRef(label_idx) => {
            // Validate label index
            if label_idx >= ctx.labels.length() {
              raise InvalidLabelIndex(label_idx)
            }
            // CatchAllRef provides exnref only
            let target_label = ctx.labels[ctx.labels.length() - 1 - label_idx]
            let expected_types = get_label_types(ctx, target_label)
            if expected_types.length() != 1 {
              raise TypeMismatch(
                "catch_all_ref handler arity mismatch: provides 1 value (exnref), label expects \{expected_types.length()}",
              )
            }
          }
        }
      }

      // Create inner stack with params (like Block)
      let block_stack = OperandStack::new()
      for param in params {
        block_stack.push(param)
      }

      // Save local_init state - locals initialized inside block don't count outside
      let saved_init = ctx.local_init.copy()

      // Now push try_table's label for body validation
      let label = { kind: BlockLabel, block_type: bt }
      ctx.labels.push(label)

      // Validate body with block_stack
      validate_expr(ctx, block_stack, body)

      // Remove label
      ctx.labels.pop() |> ignore

      // Restore local_init state
      for i in 0..<saved_init.length() {
        ctx.local_init[i] = saved_init[i]
      }

      // Check stack height: should have exactly results.length() values
      block_stack.check_height(results.length(), "try_table exit")

      // Verify result types
      for i = results.length() - 1; i >= 0; i = i - 1 {
        block_stack.pop(results[i])
      }

      // Push results onto outer stack
      for result in results {
        stack.push(result)
      }
    }

    // GC instructions - struct operations
    StructNew(type_idx) => {
      // Pop field values, push struct ref
      let struct_type = ctx.get_struct_type(type_idx)
      for i = struct_type.fields.length() - 1; i >= 0; i = i - 1 {
        stack.pop(
          storage_type_to_value_type(struct_type.fields[i].storage_type),
        )
      }
      stack.push(@types.ValueType::RefStruct(type_idx))
    }
    StructNewDefault(type_idx) => {
      // Just push struct ref (default values are implicit)
      ignore(ctx.get_struct_type(type_idx))
      stack.push(@types.ValueType::RefStruct(type_idx))
    }
    StructGet(type_idx, field_idx)
    | StructGetS(type_idx, field_idx)
    | StructGetU(type_idx, field_idx) => {
      // Pop struct ref, push field value
      stack.pop(@types.ValueType::RefNullStruct(type_idx))
      let struct_type = ctx.get_struct_type(type_idx)
      let field_type = struct_type.fields[field_idx].storage_type
      stack.push(storage_type_to_value_type(field_type))
    }
    StructSet(type_idx, field_idx) => {
      // Pop value, pop struct ref
      let struct_type = ctx.get_struct_type(type_idx)
      let field = struct_type.fields[field_idx]
      // Check that the field is mutable
      if not(field.mutable) {
        raise TypeMismatch("struct.set on immutable field")
      }
      stack.pop(storage_type_to_value_type(field.storage_type))
      stack.pop(@types.ValueType::RefNullStruct(type_idx))
    }

    // GC instructions - array operations
    ArrayNew(type_idx) => {
      // Pop length (i32), pop init value, push array ref
      ignore(ctx.get_array_type(type_idx))
      stack.pop(@types.ValueType::I32)
      let array_type = ctx.get_array_type(type_idx)
      stack.pop(storage_type_to_value_type(array_type.element.storage_type))
      stack.push(@types.ValueType::RefArray(type_idx))
    }
    ArrayNewDefault(type_idx) => {
      // Pop length (i32), push array ref
      ignore(ctx.get_array_type(type_idx))
      stack.pop(@types.ValueType::I32)
      stack.push(@types.ValueType::RefArray(type_idx))
    }
    ArrayNewFixed(type_idx, len) => {
      // Pop len elements, push array ref
      let array_type = ctx.get_array_type(type_idx)
      let elem_type = storage_type_to_value_type(
        array_type.element.storage_type,
      )
      for _ in 0..<len {
        stack.pop(elem_type)
      }
      stack.push(@types.ValueType::RefArray(type_idx))
    }
    ArrayNewData(type_idx, _) | ArrayNewElem(type_idx, _) => {
      // Pop size (i32), pop offset (i32), push array ref
      ignore(ctx.get_array_type(type_idx))
      stack.pop(@types.ValueType::I32)
      stack.pop(@types.ValueType::I32)
      stack.push(@types.ValueType::RefArray(type_idx))
    }
    ArrayGet(type_idx) | ArrayGetS(type_idx) | ArrayGetU(type_idx) => {
      // Pop index (i32), pop array ref, push element
      let array_type = ctx.get_array_type(type_idx)
      stack.pop(@types.ValueType::I32)
      stack.pop(@types.ValueType::RefNullArray(type_idx))
      stack.push(storage_type_to_value_type(array_type.element.storage_type))
    }
    ArraySet(type_idx) => {
      // Pop value, pop index (i32), pop array ref
      let array_type = ctx.get_array_type(type_idx)
      // Check that the array element is mutable
      if not(array_type.element.mutable) {
        raise TypeMismatch("array.set on immutable array")
      }
      stack.pop(storage_type_to_value_type(array_type.element.storage_type))
      stack.pop(@types.ValueType::I32)
      stack.pop(@types.ValueType::RefNullArray(type_idx))
    }
    ArrayLen => {
      // Pop array ref (any array type), push i32
      // RefNullArray(-1) matches any nullable array reference
      stack.pop(@types.ValueType::RefNullArray(-1))
      stack.push(@types.ValueType::I32)
    }
    ArrayFill(type_idx) => {
      // Pop n (i32), pop value, pop offset (i32), pop array ref
      let array_type = ctx.get_array_type(type_idx)
      // Check that the array element is mutable
      if not(array_type.element.mutable) {
        raise TypeMismatch("array.fill on immutable array")
      }
      stack.pop(@types.ValueType::I32)
      stack.pop(storage_type_to_value_type(array_type.element.storage_type))
      stack.pop(@types.ValueType::I32)
      stack.pop(@types.ValueType::RefNullArray(type_idx))
    }
    ArrayCopy(dst_type, src_type) => {
      // Pop n (i32), pop src_offset (i32), pop src, pop dst_offset (i32), pop dst
      let dst_array = ctx.get_array_type(dst_type)
      let src_array = ctx.get_array_type(src_type)
      // Check that the destination array element is mutable
      if not(dst_array.element.mutable) {
        raise TypeMismatch("array.copy to immutable array")
      }
      // Check that source element type is compatible with destination element type
      let dst_elem = dst_array.element.storage_type
      let src_elem = src_array.element.storage_type
      if dst_elem != src_elem {
        raise TypeMismatch("array.copy: array types do not match")
      }
      stack.pop(@types.ValueType::I32)
      stack.pop(@types.ValueType::I32)
      stack.pop(@types.ValueType::RefNullArray(src_type))
      stack.pop(@types.ValueType::I32)
      stack.pop(@types.ValueType::RefNullArray(dst_type))
    }
    ArrayInitData(type_idx, data_idx) => {
      // Pop n (i32), pop src_offset (i32), pop dst_offset (i32), pop array ref
      let array_type = ctx.get_array_type(type_idx)
      // Check that the array element is mutable
      if not(array_type.element.mutable) {
        raise TypeMismatch("array.init_data on immutable array")
      }
      // Check data segment exists
      if data_idx >= ctx.data_count {
        raise TypeMismatch(
          "array.init_data: invalid data segment index \{data_idx}",
        )
      }
      stack.pop(@types.ValueType::I32)
      stack.pop(@types.ValueType::I32)
      stack.pop(@types.ValueType::I32)
      stack.pop(@types.ValueType::RefNullArray(type_idx))
    }
    ArrayInitElem(type_idx, elem_idx) => {
      // Pop n (i32), pop src_offset (i32), pop dst_offset (i32), pop array ref
      let array_type = ctx.get_array_type(type_idx)
      // Check that the array element is mutable
      if not(array_type.element.mutable) {
        raise TypeMismatch("array.init_elem on immutable array")
      }
      // Check element segment exists and types match
      if elem_idx >= ctx.elems.length() {
        raise InvalidElemIndex(elem_idx)
      }
      let elem_type = ctx.elems[elem_idx]
      let array_elem_type = storage_type_to_value_type(
        array_type.element.storage_type,
      )
      // Check type compatibility - elem segment type must be subtype of array element type
      if not(is_type_subtype(elem_type, array_elem_type)) {
        raise TypeMismatch(
          "array.init_elem: element segment type \{elem_type} incompatible with array element type \{array_elem_type}",
        )
      }
      stack.pop(@types.ValueType::I32)
      stack.pop(@types.ValueType::I32)
      stack.pop(@types.ValueType::I32)
      stack.pop(@types.ValueType::RefNullArray(type_idx))
    }

    // GC instructions - reference casting (simplified validation)
    RefTest(_) | RefTestNull(_) => {
      // Pop ref, push i32
      ignore(stack.pop_any())
      stack.push(@types.ValueType::I32)
    }
    RefCast(target_type) => {
      // Pop ref, push target type
      ignore(stack.pop_any())
      stack.push(target_type)
    }
    RefCastNull(target_type) => {
      // Pop ref, push nullable target type
      ignore(stack.pop_any())
      stack.push(target_type)
    }
    BrOnCast(label_idx, source_type, target_type) => {
      // br_on_cast: Pop source, branch if cast succeeds (push target to label), push diff on fallthrough
      // Validate: target_type must be a subtype of source_type (can only downcast)
      if not(is_type_subtype(target_type, source_type)) {
        raise TypeMismatch(
          "br_on_cast: target type \{target_type} is not a subtype of source type \{source_type}",
        )
      }
      // Check that target_type is compatible with branch label
      if label_idx >= ctx.labels.length() {
        raise InvalidLabelIndex(label_idx)
      }
      let label = ctx.labels[ctx.labels.length() - 1 - label_idx]
      let branch_types = get_label_types(ctx, label)
      if branch_types.length() >= 1 {
        let expected = branch_types[branch_types.length() - 1]
        if not(is_type_subtype(target_type, expected)) {
          raise TypeMismatch(
            "br_on_cast: branch target type \{target_type} not subtype of label type \{expected}",
          )
        }
      }
      // Compute diff type for fallthrough (what's left when cast succeeds and branches)
      // Simplified: use source type since we only validate the branch path
      ignore(stack.pop_any())
      stack.push(source_type)
    }
    BrOnCastFail(label_idx, source_type, target_type) => {
      // br_on_cast_fail: Pop source, branch if cast fails (push diff to label), push target on fallthrough
      // Validate: target_type must be a subtype of source_type (can only downcast)
      if not(is_type_subtype(target_type, source_type)) {
        raise TypeMismatch(
          "br_on_cast_fail: target type \{target_type} is not a subtype of source type \{source_type}",
        )
      }
      // Check that diff_type is compatible with branch label
      // Diff type: if source is nullable and target is non-nullable, diff is nullable
      // The diff type represents values that fail the cast
      if label_idx >= ctx.labels.length() {
        raise InvalidLabelIndex(label_idx)
      }
      let label = ctx.labels[ctx.labels.length() - 1 - label_idx]
      let branch_types = get_label_types(ctx, label)
      if branch_types.length() >= 1 {
        let expected = branch_types[branch_types.length() - 1]
        // Compute diff type: if source is nullable but target is not, diff keeps nullability
        let diff_type = compute_br_on_cast_fail_diff_type(
          source_type, target_type,
        )
        if not(is_type_subtype(diff_type, expected)) {
          raise TypeMismatch(
            "br_on_cast_fail: diff type \{diff_type} not subtype of label type \{expected}",
          )
        }
      }
      ignore(stack.pop_any())
      stack.push(target_type)
    }

    // GC instructions - i31
    RefI31 => {
      // Pop i32, push i31ref
      stack.pop(@types.ValueType::I32)
      stack.push(@types.ValueType::RefI31)
    }
    I31GetS | I31GetU => {
      // Pop i31ref, push i32
      stack.pop(@types.ValueType::RefNullI31)
      stack.push(@types.ValueType::I32)
    }

    // GC instructions - type conversion
    AnyConvertExtern => {
      // Pop externref, push anyref
      stack.pop(@types.ValueType::ExternRef)
      stack.push(@types.ValueType::RefAny)
    }
    ExternConvertAny => {
      // Pop anyref, push externref
      stack.pop(@types.ValueType::RefAny)
      stack.push(@types.ValueType::ExternRef)
    }

    // SIMD instructions
    V128Const(_) => stack.push(V128)

    // SIMD load/store - natural alignments:
    // v128.load: 16 bytes = 4, load8x8/16x4/32x2: 8 bytes = 3
    // load8_splat: 0, load16_splat: 1, load32_splat/zero: 2, load64_splat/zero: 3
    V128Load(memidx, align, offset) => {
      if memidx >= ctx.mems.length() {
        raise InvalidMemoryIndex(memidx)
      }
      if align > 4 {
        raise InvalidAlignment(
          "v128.load alignment \{align} exceeds natural alignment 4",
        )
      }
      validate_mem_offset(ctx.mems[memidx], offset)
      let mem = ctx.mems[memidx]
      stack.pop(mem.addr_type())
      stack.push(V128)
    }
    V128Load8x8S(memidx, align, offset)
    | V128Load8x8U(memidx, align, offset)
    | V128Load16x4S(memidx, align, offset)
    | V128Load16x4U(memidx, align, offset)
    | V128Load32x2S(memidx, align, offset)
    | V128Load32x2U(memidx, align, offset) => {
      if memidx >= ctx.mems.length() {
        raise InvalidMemoryIndex(memidx)
      }
      if align > 3 {
        raise InvalidAlignment(
          "v128.load_extend alignment \{align} exceeds natural alignment 3",
        )
      }
      validate_mem_offset(ctx.mems[memidx], offset)
      let mem = ctx.mems[memidx]
      stack.pop(mem.addr_type())
      stack.push(V128)
    }
    V128Load8Splat(memidx, align, offset) => {
      if memidx >= ctx.mems.length() {
        raise InvalidMemoryIndex(memidx)
      }
      if align > 0 {
        raise InvalidAlignment(
          "v128.load8_splat alignment \{align} exceeds natural alignment 0",
        )
      }
      validate_mem_offset(ctx.mems[memidx], offset)
      let mem = ctx.mems[memidx]
      stack.pop(mem.addr_type())
      stack.push(V128)
    }
    V128Load16Splat(memidx, align, offset) => {
      if memidx >= ctx.mems.length() {
        raise InvalidMemoryIndex(memidx)
      }
      if align > 1 {
        raise InvalidAlignment(
          "v128.load16_splat alignment \{align} exceeds natural alignment 1",
        )
      }
      validate_mem_offset(ctx.mems[memidx], offset)
      let mem = ctx.mems[memidx]
      stack.pop(mem.addr_type())
      stack.push(V128)
    }
    V128Load32Splat(memidx, align, offset)
    | V128Load32Zero(memidx, align, offset) => {
      if memidx >= ctx.mems.length() {
        raise InvalidMemoryIndex(memidx)
      }
      if align > 2 {
        raise InvalidAlignment(
          "v128.load32 alignment \{align} exceeds natural alignment 2",
        )
      }
      validate_mem_offset(ctx.mems[memidx], offset)
      let mem = ctx.mems[memidx]
      stack.pop(mem.addr_type())
      stack.push(V128)
    }
    V128Load64Splat(memidx, align, offset)
    | V128Load64Zero(memidx, align, offset) => {
      if memidx >= ctx.mems.length() {
        raise InvalidMemoryIndex(memidx)
      }
      if align > 3 {
        raise InvalidAlignment(
          "v128.load64 alignment \{align} exceeds natural alignment 3",
        )
      }
      validate_mem_offset(ctx.mems[memidx], offset)
      let mem = ctx.mems[memidx]
      stack.pop(mem.addr_type())
      stack.push(V128)
    }
    V128Store(memidx, align, offset) => {
      if memidx >= ctx.mems.length() {
        raise InvalidMemoryIndex(memidx)
      }
      if align > 4 {
        raise InvalidAlignment(
          "v128.store alignment \{align} exceeds natural alignment 4",
        )
      }
      validate_mem_offset(ctx.mems[memidx], offset)
      let mem = ctx.mems[memidx]
      stack.pop(V128)
      stack.pop(mem.addr_type())
    }
    V128Load8Lane(memidx, align, offset, lane) => {
      if memidx >= ctx.mems.length() {
        raise InvalidMemoryIndex(memidx)
      }
      if align > 0 {
        raise InvalidAlignment(
          "v128.load8_lane alignment \{align} exceeds natural alignment 0",
        )
      }
      if lane >= 16 {
        raise InvalidLaneIndex(lane, 16)
      }
      validate_mem_offset(ctx.mems[memidx], offset)
      let mem = ctx.mems[memidx]
      stack.pop(V128)
      stack.pop(mem.addr_type())
      stack.push(V128)
    }
    V128Load16Lane(memidx, align, offset, lane) => {
      if memidx >= ctx.mems.length() {
        raise InvalidMemoryIndex(memidx)
      }
      if align > 1 {
        raise InvalidAlignment(
          "v128.load16_lane alignment \{align} exceeds natural alignment 1",
        )
      }
      if lane >= 8 {
        raise InvalidLaneIndex(lane, 8)
      }
      validate_mem_offset(ctx.mems[memidx], offset)
      let mem = ctx.mems[memidx]
      stack.pop(V128)
      stack.pop(mem.addr_type())
      stack.push(V128)
    }
    V128Load32Lane(memidx, align, offset, lane) => {
      if memidx >= ctx.mems.length() {
        raise InvalidMemoryIndex(memidx)
      }
      if align > 2 {
        raise InvalidAlignment(
          "v128.load32_lane alignment \{align} exceeds natural alignment 2",
        )
      }
      if lane >= 4 {
        raise InvalidLaneIndex(lane, 4)
      }
      validate_mem_offset(ctx.mems[memidx], offset)
      let mem = ctx.mems[memidx]
      stack.pop(V128)
      stack.pop(mem.addr_type())
      stack.push(V128)
    }
    V128Load64Lane(memidx, align, offset, lane) => {
      if memidx >= ctx.mems.length() {
        raise InvalidMemoryIndex(memidx)
      }
      if align > 3 {
        raise InvalidAlignment(
          "v128.load64_lane alignment \{align} exceeds natural alignment 3",
        )
      }
      if lane >= 2 {
        raise InvalidLaneIndex(lane, 2)
      }
      validate_mem_offset(ctx.mems[memidx], offset)
      let mem = ctx.mems[memidx]
      stack.pop(V128)
      stack.pop(mem.addr_type())
      stack.push(V128)
    }
    V128Store8Lane(memidx, align, offset, lane) => {
      if memidx >= ctx.mems.length() {
        raise InvalidMemoryIndex(memidx)
      }
      if align > 0 {
        raise InvalidAlignment(
          "v128.store8_lane alignment \{align} exceeds natural alignment 0",
        )
      }
      if lane >= 16 {
        raise InvalidLaneIndex(lane, 16)
      }
      validate_mem_offset(ctx.mems[memidx], offset)
      let mem = ctx.mems[memidx]
      stack.pop(V128)
      stack.pop(mem.addr_type())
    }
    V128Store16Lane(memidx, align, offset, lane) => {
      if memidx >= ctx.mems.length() {
        raise InvalidMemoryIndex(memidx)
      }
      if align > 1 {
        raise InvalidAlignment(
          "v128.store16_lane alignment \{align} exceeds natural alignment 1",
        )
      }
      if lane >= 8 {
        raise InvalidLaneIndex(lane, 8)
      }
      validate_mem_offset(ctx.mems[memidx], offset)
      let mem = ctx.mems[memidx]
      stack.pop(V128)
      stack.pop(mem.addr_type())
    }
    V128Store32Lane(memidx, align, offset, lane) => {
      if memidx >= ctx.mems.length() {
        raise InvalidMemoryIndex(memidx)
      }
      if align > 2 {
        raise InvalidAlignment(
          "v128.store32_lane alignment \{align} exceeds natural alignment 2",
        )
      }
      if lane >= 4 {
        raise InvalidLaneIndex(lane, 4)
      }
      validate_mem_offset(ctx.mems[memidx], offset)
      let mem = ctx.mems[memidx]
      stack.pop(V128)
      stack.pop(mem.addr_type())
    }
    V128Store64Lane(memidx, align, offset, lane) => {
      if memidx >= ctx.mems.length() {
        raise InvalidMemoryIndex(memidx)
      }
      if align > 3 {
        raise InvalidAlignment(
          "v128.store64_lane alignment \{align} exceeds natural alignment 3",
        )
      }
      if lane >= 2 {
        raise InvalidLaneIndex(lane, 2)
      }
      validate_mem_offset(ctx.mems[memidx], offset)
      let mem = ctx.mems[memidx]
      stack.pop(V128)
      stack.pop(mem.addr_type())
    }

    // Shuffle/Swizzle - lane indices must be 0-31 (selecting from two concatenated v128s)
    I8x16Shuffle(lanes) => {
      for i = 0; i < 16; i = i + 1 {
        if lanes[i] >= 32 {
          raise InvalidLaneIndex(lanes[i], 32)
        }
      }
      stack.pop(V128)
      stack.pop(V128)
      stack.push(V128)
    }
    I8x16Swizzle => {
      stack.pop(V128)
      stack.pop(V128)
      stack.push(V128)
    }

    // Splat (scalar -> vector)
    I8x16Splat | I16x8Splat | I32x4Splat => {
      stack.pop(I32)
      stack.push(V128)
    }
    I64x2Splat => {
      stack.pop(I64)
      stack.push(V128)
    }
    F32x4Splat => {
      stack.pop(F32)
      stack.push(V128)
    }
    F64x2Splat => {
      stack.pop(F64)
      stack.push(V128)
    }

    // Extract lane (vector -> scalar) with lane validation
    I8x16ExtractLaneS(lane) | I8x16ExtractLaneU(lane) => {
      if lane >= 16 {
        raise InvalidLaneIndex(lane, 16)
      }
      stack.pop(V128)
      stack.push(I32)
    }
    I16x8ExtractLaneS(lane) | I16x8ExtractLaneU(lane) => {
      if lane >= 8 {
        raise InvalidLaneIndex(lane, 8)
      }
      stack.pop(V128)
      stack.push(I32)
    }
    I32x4ExtractLane(lane) => {
      if lane >= 4 {
        raise InvalidLaneIndex(lane, 4)
      }
      stack.pop(V128)
      stack.push(I32)
    }
    I64x2ExtractLane(lane) => {
      if lane >= 2 {
        raise InvalidLaneIndex(lane, 2)
      }
      stack.pop(V128)
      stack.push(I64)
    }
    F32x4ExtractLane(lane) => {
      if lane >= 4 {
        raise InvalidLaneIndex(lane, 4)
      }
      stack.pop(V128)
      stack.push(F32)
    }
    F64x2ExtractLane(lane) => {
      if lane >= 2 {
        raise InvalidLaneIndex(lane, 2)
      }
      stack.pop(V128)
      stack.push(F64)
    }

    // Replace lane (vector, scalar -> vector) with lane validation
    I8x16ReplaceLane(lane) => {
      if lane >= 16 {
        raise InvalidLaneIndex(lane, 16)
      }
      stack.pop(I32)
      stack.pop(V128)
      stack.push(V128)
    }
    I16x8ReplaceLane(lane) => {
      if lane >= 8 {
        raise InvalidLaneIndex(lane, 8)
      }
      stack.pop(I32)
      stack.pop(V128)
      stack.push(V128)
    }
    I32x4ReplaceLane(lane) => {
      if lane >= 4 {
        raise InvalidLaneIndex(lane, 4)
      }
      stack.pop(I32)
      stack.pop(V128)
      stack.push(V128)
    }
    I64x2ReplaceLane(lane) => {
      if lane >= 2 {
        raise InvalidLaneIndex(lane, 2)
      }
      stack.pop(I64)
      stack.pop(V128)
      stack.push(V128)
    }
    F32x4ReplaceLane(lane) => {
      if lane >= 4 {
        raise InvalidLaneIndex(lane, 4)
      }
      stack.pop(F32)
      stack.pop(V128)
      stack.push(V128)
    }
    F64x2ReplaceLane(lane) => {
      if lane >= 2 {
        raise InvalidLaneIndex(lane, 2)
      }
      stack.pop(F64)
      stack.pop(V128)
      stack.push(V128)
    }

    // Comparison operations: v128 v128 -> v128
    I8x16Eq
    | I8x16Ne
    | I8x16LtS
    | I8x16LtU
    | I8x16GtS
    | I8x16GtU
    | I8x16LeS
    | I8x16LeU
    | I8x16GeS
    | I8x16GeU
    | I16x8Eq
    | I16x8Ne
    | I16x8LtS
    | I16x8LtU
    | I16x8GtS
    | I16x8GtU
    | I16x8LeS
    | I16x8LeU
    | I16x8GeS
    | I16x8GeU
    | I32x4Eq
    | I32x4Ne
    | I32x4LtS
    | I32x4LtU
    | I32x4GtS
    | I32x4GtU
    | I32x4LeS
    | I32x4LeU
    | I32x4GeS
    | I32x4GeU
    | I64x2Eq
    | I64x2Ne
    | I64x2LtS
    | I64x2GtS
    | I64x2LeS
    | I64x2GeS
    | F32x4Eq
    | F32x4Ne
    | F32x4Lt
    | F32x4Gt
    | F32x4Le
    | F32x4Ge
    | F64x2Eq
    | F64x2Ne
    | F64x2Lt
    | F64x2Gt
    | F64x2Le
    | F64x2Ge => {
      stack.pop(V128)
      stack.pop(V128)
      stack.push(V128)
    }

    // Unary v128 -> v128
    V128Not
    | I8x16Abs
    | I8x16Neg
    | I8x16Popcnt
    | I16x8Abs
    | I16x8Neg
    | I16x8ExtAddPairwiseI8x16S
    | I16x8ExtAddPairwiseI8x16U
    | I32x4Abs
    | I32x4Neg
    | I32x4ExtAddPairwiseI16x8S
    | I32x4ExtAddPairwiseI16x8U
    | I64x2Abs
    | I64x2Neg
    | F32x4Abs
    | F32x4Neg
    | F32x4Sqrt
    | F32x4Ceil
    | F32x4Floor
    | F32x4Trunc
    | F32x4Nearest
    | F64x2Abs
    | F64x2Neg
    | F64x2Sqrt
    | F64x2Ceil
    | F64x2Floor
    | F64x2Trunc
    | F64x2Nearest
    | I16x8ExtendLowI8x16S
    | I16x8ExtendHighI8x16S
    | I16x8ExtendLowI8x16U
    | I16x8ExtendHighI8x16U
    | I32x4ExtendLowI16x8S
    | I32x4ExtendHighI16x8S
    | I32x4ExtendLowI16x8U
    | I32x4ExtendHighI16x8U
    | I64x2ExtendLowI32x4S
    | I64x2ExtendHighI32x4S
    | I64x2ExtendLowI32x4U
    | I64x2ExtendHighI32x4U
    | I32x4TruncSatF32x4S
    | I32x4TruncSatF32x4U
    | F32x4ConvertI32x4S
    | F32x4ConvertI32x4U
    | I32x4TruncSatF64x2SZero
    | I32x4TruncSatF64x2UZero
    | F64x2ConvertLowI32x4S
    | F64x2ConvertLowI32x4U
    | F32x4DemoteF64x2Zero
    | F64x2PromoteLowF32x4
    // Relaxed SIMD: v128 -> v128
    | I32x4RelaxedTruncF32x4S
    | I32x4RelaxedTruncF32x4U
    | I32x4RelaxedTruncF64x2SZero
    | I32x4RelaxedTruncF64x2UZero => {
      stack.pop(V128)
      stack.push(V128)
    }

    // v128 -> i32 (boolean/bitmask)
    V128AnyTrue
    | I8x16AllTrue
    | I8x16Bitmask
    | I16x8AllTrue
    | I16x8Bitmask
    | I32x4AllTrue
    | I32x4Bitmask
    | I64x2AllTrue
    | I64x2Bitmask => {
      stack.pop(V128)
      stack.push(I32)
    }

    // Binary v128 v128 -> v128
    V128And
    | V128AndNot
    | V128Or
    | V128Xor
    | I8x16Add
    | I8x16AddSatS
    | I8x16AddSatU
    | I8x16Sub
    | I8x16SubSatS
    | I8x16SubSatU
    | I8x16MinS
    | I8x16MinU
    | I8x16MaxS
    | I8x16MaxU
    | I8x16AvgrU
    | I8x16NarrowI16x8S
    | I8x16NarrowI16x8U
    | I16x8Add
    | I16x8AddSatS
    | I16x8AddSatU
    | I16x8Sub
    | I16x8SubSatS
    | I16x8SubSatU
    | I16x8Mul
    | I16x8MinS
    | I16x8MinU
    | I16x8MaxS
    | I16x8MaxU
    | I16x8AvgrU
    | I16x8Q15MulrSatS
    | I16x8NarrowI32x4S
    | I16x8NarrowI32x4U
    | I16x8ExtMulLowI8x16S
    | I16x8ExtMulHighI8x16S
    | I16x8ExtMulLowI8x16U
    | I16x8ExtMulHighI8x16U
    | I32x4Add
    | I32x4Sub
    | I32x4Mul
    | I32x4MinS
    | I32x4MinU
    | I32x4MaxS
    | I32x4MaxU
    | I32x4DotI16x8S
    | I32x4ExtMulLowI16x8S
    | I32x4ExtMulHighI16x8S
    | I32x4ExtMulLowI16x8U
    | I32x4ExtMulHighI16x8U
    | I64x2Add
    | I64x2Sub
    | I64x2Mul
    | I64x2ExtMulLowI32x4S
    | I64x2ExtMulHighI32x4S
    | I64x2ExtMulLowI32x4U
    | I64x2ExtMulHighI32x4U
    | F32x4Add
    | F32x4Sub
    | F32x4Mul
    | F32x4Div
    | F32x4Min
    | F32x4Max
    | F32x4Pmin
    | F32x4Pmax
    | F64x2Add
    | F64x2Sub
    | F64x2Mul
    | F64x2Div
    | F64x2Min
    | F64x2Max
    | F64x2Pmin
    | F64x2Pmax
    // Relaxed SIMD: v128 v128 -> v128
    | I8x16RelaxedSwizzle
    | F32x4RelaxedMin
    | F32x4RelaxedMax
    | F64x2RelaxedMin
    | F64x2RelaxedMax
    | I16x8RelaxedQ15mulrS
    | I16x8RelaxedDotI8x16I7x16S => {
      stack.pop(V128)
      stack.pop(V128)
      stack.push(V128)
    }

    // Shift operations: v128 i32 -> v128
    I8x16Shl
    | I8x16ShrS
    | I8x16ShrU
    | I16x8Shl
    | I16x8ShrS
    | I16x8ShrU
    | I32x4Shl
    | I32x4ShrS
    | I32x4ShrU
    | I64x2Shl
    | I64x2ShrS
    | I64x2ShrU => {
      stack.pop(I32)
      stack.pop(V128)
      stack.push(V128)
    }

    // Bitselect: v128 v128 v128 -> v128
    V128Bitselect
    // Relaxed SIMD: v128 v128 v128 -> v128
    | F32x4RelaxedMadd
    | F32x4RelaxedNmadd
    | F64x2RelaxedMadd
    | F64x2RelaxedNmadd
    | I8x16RelaxedLaneselect
    | I16x8RelaxedLaneselect
    | I32x4RelaxedLaneselect
    | I64x2RelaxedLaneselect
    | I32x4RelaxedDotI8x16I7x16AddS => {
      stack.pop(V128)
      stack.pop(V128)
      stack.pop(V128)
      stack.push(V128)
    }
  }
}

///|
fn get_block_results(
  ctx : ValidationContext,
  bt : @types.BlockType,
) -> Array[@types.ValueType] raise ValidationError {
  match bt {
    Empty => []
    Value(t) => {
      validate_value_type(t, ctx.types.length())
      [t]
    }
    MultiValue(types) => {
      for t in types {
        validate_value_type(t, ctx.types.length())
      }
      types
    }
    InlineType(_, results) => {
      for t in results {
        validate_value_type(t, ctx.types.length())
      }
      results
    }
    TypeIndex(idx) =>
      if idx < ctx.types.length() {
        ctx.get_func_type(idx).results
      } else {
        raise InvalidTypeIndex(idx)
      }
  }
}

///|
fn get_block_params(
  ctx : ValidationContext,
  bt : @types.BlockType,
) -> Array[@types.ValueType] raise ValidationError {
  match bt {
    Empty => []
    Value(_) => [] // Single value blocks have no params
    MultiValue(_) => [] // MultiValue blocks have no params (result-only)
    InlineType(params, _) => {
      for t in params {
        validate_value_type(t, ctx.types.length())
      }
      params
    }
    TypeIndex(idx) =>
      if idx < ctx.types.length() {
        ctx.get_func_type(idx).params
      } else {
        raise InvalidTypeIndex(idx)
      }
  }
}

///|
/// Get the types that a branch to this label should carry
/// For block/if: uses results (br jumps to end)
/// For loop: uses params (br jumps to start)
fn get_label_types(
  ctx : ValidationContext,
  label : LabelInfo,
) -> Array[@types.ValueType] raise ValidationError {
  match label.kind {
    BlockLabel => get_block_results(ctx, label.block_type)
    LoopLabel => get_block_params(ctx, label.block_type)
  }
}
