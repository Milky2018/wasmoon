// WASM to IR Translator
// Converts WebAssembly stack-based instructions to SSA-form IR

///|
/// Translator state for converting a single WASM function to IR
pub(all) struct Translator {
  builder : IRBuilder
  // Value stack - simulates WASM's operand stack
  value_stack : Array[Value]
  // Local variables - mutable in WASM, need SSA tracking
  locals : Array[Value]
  // Block stack for control flow
  block_stack : Array[BlockFrame]
  // Function types from the module
  func_types : Array[@types.FuncType]
  // Type indices for functions
  func_type_indices : Array[Int]
  // Number of imported functions
  num_imports : Int
  // Type indices for imported functions
  import_func_type_indices : Array[Int]
  // Unreachable code flag - set after br/return/unreachable
  // When true, skip translating instructions until block end
  mut is_unreachable : Bool
  // Return continuation block - lazily created when br/br_table jumps to function level
  mut return_continuation : Block?
  // Function result types - needed for lazy return continuation creation
  func_result_types : Array[Type]
  // Memory max pages limit (None = no limit)
  memory_max : Int?
}

///|
/// Block frame for tracking control flow constructs
#warnings("-unused_field")
struct BlockFrame {
  kind : BlockKind
  block : Block // The continuation block
  result_types : Array[Type]
  // For loops, the header block
  loop_header : Block?
  // Stack height at block entry
  stack_height : Int
}

///|
/// Kind of block frame
#warnings("-unused_constructor")
priv enum BlockKind {
  Block
  Loop
  If(Block?) // else block if present
}

///|
pub fn Translator::new(
  name : String,
  func_type : @types.FuncType,
  locals : Array[@types.ValueType],
  func_types : Array[@types.FuncType],
  func_type_indices : Array[Int],
  num_imports : Int,
  import_func_type_indices : Array[Int],
  memory_max? : Int? = None,
) -> Translator {
  let builder = IRBuilder::new(name)
  // Add function parameters
  let local_values : Array[Value] = []
  for param in func_type.params {
    let p = builder.add_param(Type::from_wasm(param))
    local_values.push(p)
  }
  // Add result types
  let func_result_types : Array[Type] = []
  for result in func_type.results {
    builder.add_result(Type::from_wasm(result))
    func_result_types.push(Type::from_wasm(result))
  }
  // Initialize locals with zero values - we'll handle them specially
  for local_ty in locals {
    // Create placeholder values for locals
    // In SSA, we need to track the current value of each local
    local_values.push(
      Value::new(
        -1 - local_values.length(), // Temporary IDs for locals
        Type::from_wasm(local_ty),
      ),
    )
  }
  {
    builder,
    value_stack: [],
    locals: local_values,
    block_stack: [],
    func_types,
    func_type_indices,
    num_imports,
    import_func_type_indices,
    is_unreachable: false,
    return_continuation: None,
    func_result_types,
    memory_max,
  }
}

///|
/// Push a value onto the operand stack
fn Translator::push(self : Translator, v : Value) -> Unit {
  self.value_stack.push(v)
}

///|
/// Pop a value from the operand stack
fn Translator::pop(self : Translator) -> Value {
  match self.value_stack.pop() {
    Some(v) => v
    None => abort("Stack underflow")
  }
}

///|
/// Peek at the top of the stack
fn Translator::peek(self : Translator) -> Value {
  match self.value_stack.last() {
    Some(v) => v
    None => abort("Stack underflow")
  }
}

///|
/// Get the result types from a block type
fn get_block_result_types(
  block_type : @types.BlockType,
  func_types : Array[@types.FuncType],
) -> Array[Type] {
  match block_type {
    Empty => []
    Value(vt) => [Type::from_wasm(vt)]
    MultiValue(vts) => vts.map(Type::from_wasm)
    InlineType(_, results) => results.map(Type::from_wasm)
    TypeIndex(idx) =>
      if idx < func_types.length() {
        func_types[idx].results.map(Type::from_wasm)
      } else {
        []
      }
  }
}

///|
/// Get the parameter types from a block type
fn get_block_param_types(
  block_type : @types.BlockType,
  func_types : Array[@types.FuncType],
) -> Array[Type] {
  match block_type {
    Empty => []
    Value(_) => [] // Simple block types have no params
    MultiValue(_) => [] // MultiValue blocks have no params (result-only)
    InlineType(params, _) => params.map(Type::from_wasm)
    TypeIndex(idx) =>
      if idx < func_types.length() {
        func_types[idx].params.map(Type::from_wasm)
      } else {
        []
      }
  }
}

///|
/// Translate a sequence of WASM instructions
pub fn Translator::translate(
  self : Translator,
  instrs : Array[@types.Instruction],
) -> Function {
  // Create the entry block
  let entry = self.builder.create_block()
  self.builder.switch_to_block(entry)
  // Initialize locals with default values
  for i, loc in self.locals {
    // Skip parameters - they already have values
    let num_params = self.builder.get_function().params.length()
    if i >= num_params {
      let zero_val = match loc.ty {
        I32 => self.builder.iconst_i32(0)
        I64 => self.builder.iconst_i64(0L)
        F32 => self.builder.fconst_f32(0.0)
        F64 => self.builder.fconst_f64(0.0)
        _ => self.builder.iconst_i32(0) // Fallback
      }
      self.locals[i] = zero_val
    }
  }

  // Translate instructions
  // Note: block_stack does NOT include a function-level frame
  // translate_br/translate_br_table handle function-level jumps specially
  for instr in instrs {
    self.translate_instruction(instr)
  }

  // Handle function end
  if !self.is_unreachable {
    match self.builder.current_block() {
      Some(block) =>
        match block.terminator {
          None =>
            // Normal fall-through: check if return_continuation was created
            match self.return_continuation {
              Some(ret_cont) => {
                // Someone jumped to function level, need to go through continuation
                let args : Array[Value] = []
                for _ in 0..<self.func_result_types.length() {
                  if self.value_stack.length() > 0 {
                    args.push(self.pop())
                  }
                }
                args.rev_in_place()
                for loc in self.locals {
                  args.push(loc)
                }
                self.builder.jump(ret_cont, args)
              }
              None => {
                // No one jumped to function level, just return directly
                let return_vals : Array[Value] = []
                for _ in 0..<self.func_result_types.length() {
                  if self.value_stack.length() > 0 {
                    return_vals.push(self.pop())
                  }
                }
                return_vals.rev_in_place()
                self.builder.return_(return_vals)
              }
            }
          Some(_) => ()
        }
      None => ()
    }
  }

  // If return_continuation was created, emit it
  match self.return_continuation {
    Some(ret_cont) => {
      self.builder.switch_to_block(ret_cont)
      let return_vals : Array[Value] = []
      for i in 0..<self.func_result_types.length() {
        return_vals.push(ret_cont.params[i].0)
      }
      self.builder.return_(return_vals)
    }
    None => ()
  }
  self.builder.get_function()
}

///|
/// Get or create the return continuation block for function-level jumps
fn Translator::get_or_create_return_continuation(self : Translator) -> Block {
  match self.return_continuation {
    Some(block) => block
    None => {
      let ret_cont = self.builder.create_block()
      // Add block parameters for function results
      for ty in self.func_result_types {
        self.builder.add_block_param(ret_cont, ty) |> ignore
      }
      // Add block parameters for ALL locals (SSA phi nodes)
      for loc in self.locals {
        self.builder.add_block_param(ret_cont, loc.ty) |> ignore
      }
      self.return_continuation = Some(ret_cont)
      ret_cont
    }
  }
}

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

    // Memory operations
    I32Load(_, offset) => {
      let addr = self.pop()
      let result = self.builder.load(Type::I32, addr, offset)
      self.push(result)
    }
    I64Load(_, offset) => {
      let addr = self.pop()
      let result = self.builder.load(Type::I64, addr, offset)
      self.push(result)
    }
    F32Load(_, offset) => {
      let addr = self.pop()
      let result = self.builder.load(Type::F32, addr, offset)
      self.push(result)
    }
    F64Load(_, offset) => {
      let addr = self.pop()
      let result = self.builder.load(Type::F64, addr, offset)
      self.push(result)
    }

    // Narrow load operations (8/16/32-bit with sign/zero extension)
    I32Load8S(_, offset) => {
      let addr = self.pop()
      let result = self.builder.load8_s(Type::I32, addr, offset)
      self.push(result)
    }
    I32Load8U(_, offset) => {
      let addr = self.pop()
      let result = self.builder.load8_u(Type::I32, addr, offset)
      self.push(result)
    }
    I32Load16S(_, offset) => {
      let addr = self.pop()
      let result = self.builder.load16_s(Type::I32, addr, offset)
      self.push(result)
    }
    I32Load16U(_, offset) => {
      let addr = self.pop()
      let result = self.builder.load16_u(Type::I32, addr, offset)
      self.push(result)
    }
    I64Load8S(_, offset) => {
      let addr = self.pop()
      let result = self.builder.load8_s(Type::I64, addr, offset)
      self.push(result)
    }
    I64Load8U(_, offset) => {
      let addr = self.pop()
      let result = self.builder.load8_u(Type::I64, addr, offset)
      self.push(result)
    }
    I64Load16S(_, offset) => {
      let addr = self.pop()
      let result = self.builder.load16_s(Type::I64, addr, offset)
      self.push(result)
    }
    I64Load16U(_, offset) => {
      let addr = self.pop()
      let result = self.builder.load16_u(Type::I64, addr, offset)
      self.push(result)
    }
    I64Load32S(_, offset) => {
      let addr = self.pop()
      let result = self.builder.load32_s(addr, offset)
      self.push(result)
    }
    I64Load32U(_, offset) => {
      let addr = self.pop()
      let result = self.builder.load32_u(addr, offset)
      self.push(result)
    }
    I32Store(_, offset) => {
      let value = self.pop()
      let addr = self.pop()
      self.builder.store(Type::I32, addr, value, offset)
    }
    I64Store(_, offset) => {
      let value = self.pop()
      let addr = self.pop()
      self.builder.store(Type::I64, addr, value, offset)
    }
    F32Store(_, offset) => {
      let value = self.pop()
      let addr = self.pop()
      self.builder.store(Type::F32, addr, value, offset)
    }
    F64Store(_, offset) => {
      let value = self.pop()
      let addr = self.pop()
      self.builder.store(Type::F64, addr, value, offset)
    }

    // Narrow store operations (8/16/32-bit)
    I32Store8(_, offset) => {
      let value = self.pop()
      let addr = self.pop()
      self.builder.store8(addr, value, offset)
    }
    I32Store16(_, offset) => {
      let value = self.pop()
      let addr = self.pop()
      self.builder.store16(addr, value, offset)
    }
    I64Store8(_, offset) => {
      let value = self.pop()
      let addr = self.pop()
      self.builder.store8(addr, value, offset)
    }
    I64Store16(_, offset) => {
      let value = self.pop()
      let addr = self.pop()
      self.builder.store16(addr, value, offset)
    }
    I64Store32(_, offset) => {
      let value = self.pop()
      let addr = self.pop()
      self.builder.store32(addr, value, offset)
    }

    // Control flow
    Unreachable => self.builder.trap("unreachable")
    Nop => () // No operation
    Return => {
      let results = self.builder.get_function().results
      let return_vals : Array[Value] = []
      for _ in 0..<results.length() {
        return_vals.push(self.pop())
      }
      return_vals.rev_in_place()
      self.builder.return_(return_vals)
    }
    Block(block_type, body) => self.translate_block(block_type, body)
    Loop(block_type, body) => self.translate_loop(block_type, body)
    If(block_type, then_body, else_body) =>
      self.translate_if(block_type, then_body, else_body)
    Br(depth) => self.translate_br(depth)
    BrIf(depth) => self.translate_br_if(depth)
    BrTable(labels, default_) => self.translate_br_table(labels, default_)

    // Function calls
    Call(func_idx) => self.translate_call(func_idx)
    CallIndirect(type_idx, _table_idx) => self.translate_call_indirect(type_idx)

    // Memory management
    MemoryGrow => {
      let delta = self.pop()
      let result = match self.memory_max {
        Some(max) => self.builder.memory_grow(delta, max_pages=max)
        None => self.builder.memory_grow(delta)
      }
      self.push(result)
    }
    MemorySize => {
      let result = self.builder.memory_size()
      self.push(result)
    }

    // Not yet implemented
    _ => () // Skip unimplemented instructions
  }
}

///|
/// Helper for binary i32 operations
fn Translator::translate_binary_i32(
  self : Translator,
  op : (IRBuilder, Value, Value) -> Value,
) -> Unit {
  let b = self.pop()
  let a = self.pop()
  let result = op(self.builder, a, b)
  self.push(result)
}

///|
/// Helper for binary i64 operations
fn Translator::translate_binary_i64(
  self : Translator,
  op : (IRBuilder, Value, Value) -> Value,
) -> Unit {
  let b = self.pop()
  let a = self.pop()
  let result = op(self.builder, a, b)
  self.push(result)
}

///|
/// Helper for binary f32 operations
fn Translator::translate_binary_f32(
  self : Translator,
  op : (IRBuilder, Value, Value) -> Value,
) -> Unit {
  let b = self.pop()
  let a = self.pop()
  let result = op(self.builder, a, b)
  self.push(result)
}

///|
/// Helper for binary f64 operations
fn Translator::translate_binary_f64(
  self : Translator,
  op : (IRBuilder, Value, Value) -> Value,
) -> Unit {
  let b = self.pop()
  let a = self.pop()
  let result = op(self.builder, a, b)
  self.push(result)
}

///|
/// Helper for unary f32 operations
fn Translator::translate_unary_f32(
  self : Translator,
  op : (IRBuilder, Value) -> Value,
) -> Unit {
  let a = self.pop()
  let result = op(self.builder, a)
  self.push(result)
}

///|
/// Helper for unary f64 operations
fn Translator::translate_unary_f64(
  self : Translator,
  op : (IRBuilder, Value) -> Value,
) -> Unit {
  let a = self.pop()
  let result = op(self.builder, a)
  self.push(result)
}

///|
/// Helper for unary i32 operations
fn Translator::translate_unary_i32(
  self : Translator,
  op : (IRBuilder, Value) -> Value,
) -> Unit {
  let a = self.pop()
  let result = op(self.builder, a)
  self.push(result)
}

///|
/// Helper for unary i64 operations
fn Translator::translate_unary_i64(
  self : Translator,
  op : (IRBuilder, Value) -> Value,
) -> Unit {
  let a = self.pop()
  let result = op(self.builder, a)
  self.push(result)
}

///|
/// Helper for integer comparisons
fn Translator::translate_icmp(self : Translator, cc : IntCC) -> Unit {
  let b = self.pop()
  let a = self.pop()
  let result = self.builder.icmp(cc, a, b)
  self.push(result)
}

///|
/// Helper for float comparisons
fn Translator::translate_fcmp(self : Translator, cc : FloatCC) -> Unit {
  let b = self.pop()
  let a = self.pop()
  let result = self.builder.fcmp(cc, a, b)
  self.push(result)
}

///|
/// Translate a block construct
///
/// For proper SSA form, we need to pass all mutable locals through the
/// continuation block as parameters. This ensures locals modified inside the
/// block (or nested loops) are properly threaded through phi nodes.
fn Translator::translate_block(
  self : Translator,
  block_type : @types.BlockType,
  body : Array[@types.Instruction],
) -> Unit {
  // Save the unreachable state from outer context
  let outer_is_unreachable = self.is_unreachable
  let result_types = get_block_result_types(block_type, self.func_types)
  let continuation = self.builder.create_block()

  // Add block parameters for explicit results
  for ty in result_types {
    self.builder.add_block_param(continuation, ty) |> ignore
  }

  // Add block parameters for ALL locals (SSA phi nodes)
  let local_param_start = result_types.length()
  for loc in self.locals {
    self.builder.add_block_param(continuation, loc.ty) |> ignore
  }

  // Push block frame
  let frame : BlockFrame = {
    kind: BlockKind::Block,
    block: continuation,
    result_types,
    loop_header: None,
    stack_height: self.value_stack.length(),
  }
  self.block_stack.push(frame)

  // Reset unreachable for block body (block entry is reachable if outer is)
  // If outer is unreachable, the whole block is dead code
  self.is_unreachable = outer_is_unreachable

  // Translate body
  for instr in body {
    self.translate_instruction(instr)
  }

  // Pop frame
  self.block_stack.pop() |> ignore

  // Fall through to continuation (only if not unreachable)
  if !self.is_unreachable {
    match self.builder.current_block() {
      Some(block) =>
        match block.terminator {
          None => {
            // Collect results from stack
            let args : Array[Value] = []
            for _ in 0..<result_types.length() {
              args.push(self.pop())
            }
            args.rev_in_place()
            // Then, all locals
            for loc in self.locals {
              args.push(loc)
            }
            self.builder.jump(continuation, args)
          }
          Some(_) => ()
        }
      None => ()
    }
  }

  // When unreachable, we need to restore stack to block entry height
  // because unreachable code may have pushed values that shouldn't persist
  while self.value_stack.length() > frame.stack_height {
    self.pop() |> ignore
  }

  // Switch to continuation
  self.builder.switch_to_block(continuation)

  // Continuation is reachable (either from fall-through or from br)
  // unless the outer context was unreachable
  self.is_unreachable = outer_is_unreachable

  // Push block results onto stack
  for i, _ty in result_types {
    self.push(continuation.params[i].0)
  }

  // Update locals to use the continuation's phi values
  for i, _loc in self.locals {
    self.locals[i] = continuation.params[local_param_start + i].0
  }
}

///|
/// Translate a loop construct
///
/// For proper SSA form, we need to pass all mutable locals through the loop
/// header as parameters. This creates phi nodes for loop-carried variables.
fn Translator::translate_loop(
  self : Translator,
  block_type : @types.BlockType,
  body : Array[@types.Instruction],
) -> Unit {
  // Save the unreachable state from outer context
  let outer_is_unreachable = self.is_unreachable
  let result_types = get_block_result_types(block_type, self.func_types)
  let param_types = get_block_param_types(block_type, self.func_types)
  let loop_header = self.builder.create_block()
  let continuation = self.builder.create_block()

  // Add loop header parameters for explicit block params
  for ty in param_types {
    self.builder.add_block_param(loop_header, ty) |> ignore
  }

  // Add loop header parameters for ALL locals (SSA phi nodes for loop-carried values)
  let local_param_start = param_types.length()
  for loc in self.locals {
    self.builder.add_block_param(loop_header, loc.ty) |> ignore
  }

  // Add continuation parameters for results
  for ty in result_types {
    self.builder.add_block_param(continuation, ty) |> ignore
  }

  // Jump to loop header with current stack values AND current local values
  // (only if not unreachable)
  if !outer_is_unreachable {
    let header_args : Array[Value] = []
    // First, explicit block params from stack
    for _ in 0..<param_types.length() {
      header_args.push(self.pop())
    }
    header_args.rev_in_place()
    // Then, all locals
    for loc in self.locals {
      header_args.push(loc)
    }
    self.builder.jump(loop_header, header_args)
  }

  // Switch to loop header
  self.builder.switch_to_block(loop_header)

  // Push header params onto stack
  for i, _ty in param_types {
    self.push(loop_header.params[i].0)
  }

  // Update locals to use the loop header's phi values
  for i, _loc in self.locals {
    self.locals[i] = loop_header.params[local_param_start + i].0
  }

  // Push block frame (br targets loop header for loops)
  // Store local_param_start so br can pass locals too
  let frame : BlockFrame = {
    kind: BlockKind::Loop,
    block: loop_header, // Loop's br target is the header
    result_types: param_types, // For br, we need params not results
    loop_header: Some(loop_header),
    stack_height: self.value_stack.length(),
  }
  self.block_stack.push(frame)

  // Reset unreachable for loop body
  self.is_unreachable = outer_is_unreachable

  // Translate body
  for instr in body {
    self.translate_instruction(instr)
  }

  // Pop frame
  self.block_stack.pop() |> ignore

  // Fall through to continuation (only if not unreachable)
  if !self.is_unreachable {
    match self.builder.current_block() {
      Some(block) =>
        match block.terminator {
          None => {
            let args : Array[Value] = []
            for _ in 0..<result_types.length() {
              args.push(self.pop())
            }
            args.rev_in_place()
            self.builder.jump(continuation, args)
          }
          Some(_) => ()
        }
      None => ()
    }
  }

  // Restore stack to entry height (for unreachable code cleanup)
  while self.value_stack.length() > frame.stack_height {
    self.pop() |> ignore
  }

  // Switch to continuation
  self.builder.switch_to_block(continuation)

  // Continuation is reachable unless outer was unreachable
  self.is_unreachable = outer_is_unreachable

  // Push results onto stack
  for i, _ty in result_types {
    self.push(continuation.params[i].0)
  }
}

///|
/// Translate an if-else construct
///
/// For proper SSA form, we need to pass all mutable locals through the
/// continuation block as parameters.
fn Translator::translate_if(
  self : Translator,
  block_type : @types.BlockType,
  then_body : Array[@types.Instruction],
  else_body : Array[@types.Instruction],
) -> Unit {
  // Save the unreachable state from outer context
  let outer_is_unreachable = self.is_unreachable
  let result_types = get_block_result_types(block_type, self.func_types)
  let cond = if outer_is_unreachable {
    // Create a dummy value when unreachable
    self.builder.iconst_i32(0)
  } else {
    self.pop()
  }
  let then_block = self.builder.create_block()
  let else_block = self.builder.create_block()
  let continuation = self.builder.create_block()

  // Add continuation parameters for explicit results
  for ty in result_types {
    self.builder.add_block_param(continuation, ty) |> ignore
  }

  // Add continuation parameters for ALL locals (SSA phi nodes)
  let local_param_start = result_types.length()
  for loc in self.locals {
    self.builder.add_block_param(continuation, loc.ty) |> ignore
  }

  // Branch (only if not unreachable)
  if !outer_is_unreachable {
    self.builder.brnz(cond, then_block, else_block)
  }

  // Push frame for then branch (else block as the "else" continuation)
  let frame : BlockFrame = {
    kind: BlockKind::If(Some(else_block)),
    block: continuation,
    result_types,
    loop_header: None,
    stack_height: self.value_stack.length(),
  }
  self.block_stack.push(frame)

  // Save locals at entry for else branch
  let saved_locals = self.locals.copy()

  // Translate then body
  self.builder.switch_to_block(then_block)
  self.is_unreachable = outer_is_unreachable // Reset for then body
  for instr in then_body {
    self.translate_instruction(instr)
  }
  let then_is_unreachable = self.is_unreachable

  // Jump to continuation from then block with locals (only if not unreachable)
  if !self.is_unreachable {
    match self.builder.current_block() {
      Some(block) =>
        match block.terminator {
          None => {
            let args : Array[Value] = []
            for _ in 0..<result_types.length() {
              args.push(self.pop())
            }
            args.rev_in_place()
            // Pass locals
            for loc in self.locals {
              args.push(loc)
            }
            self.builder.jump(continuation, args)
          }
          Some(_) => ()
        }
      None => ()
    }
  }

  // Restore stack to original height for else branch
  while self.value_stack.length() > frame.stack_height {
    self.pop() |> ignore
  }

  // Restore locals to entry state for else branch
  for i, loc in saved_locals {
    self.locals[i] = loc
  }

  // Translate else body
  self.builder.switch_to_block(else_block)
  self.is_unreachable = outer_is_unreachable // Reset for else body
  for instr in else_body {
    self.translate_instruction(instr)
  }
  let else_is_unreachable = self.is_unreachable

  // Jump to continuation from else block with locals (only if not unreachable)
  if !self.is_unreachable {
    match self.builder.current_block() {
      Some(block) =>
        match block.terminator {
          None => {
            let args : Array[Value] = []
            for _ in 0..<result_types.length() {
              args.push(self.pop())
            }
            args.rev_in_place()
            // Pass locals
            for loc in self.locals {
              args.push(loc)
            }
            self.builder.jump(continuation, args)
          }
          Some(_) => ()
        }
      None => ()
    }
  }

  // Pop frame
  self.block_stack.pop() |> ignore

  // Switch to continuation
  self.builder.switch_to_block(continuation)

  // Continuation is reachable if either branch is reachable
  // (unless outer was unreachable)
  self.is_unreachable = outer_is_unreachable ||
    (then_is_unreachable && else_is_unreachable)

  // Push results onto stack
  for i, _ty in result_types {
    self.push(continuation.params[i].0)
  }

  // Update locals to use the continuation's phi values
  for i, _loc in self.locals {
    self.locals[i] = continuation.params[local_param_start + i].0
  }
}

///|
/// Translate a br instruction
/// We need to pass both explicit params AND current local values
fn Translator::translate_br(self : Translator, depth : Int) -> Unit {
  let idx = self.block_stack.length() - 1 - depth
  if idx >= 0 && idx < self.block_stack.length() {
    // Jump to a block within the function
    let frame = self.block_stack[idx]
    let args : Array[Value] = []
    // Pop explicit block params
    for _ in 0..<frame.result_types.length() {
      args.push(self.pop())
    }
    args.rev_in_place()
    // Always pass current local values
    for loc in self.locals {
      args.push(loc)
    }
    self.builder.jump(frame.block, args)
  } else if idx == -1 {
    // Jump to function level (early return)
    let ret_cont = self.get_or_create_return_continuation()
    let args : Array[Value] = []
    // Pop function result values
    for _ in 0..<self.func_result_types.length() {
      args.push(self.pop())
    }
    args.rev_in_place()
    // Always pass current local values
    for loc in self.locals {
      args.push(loc)
    }
    self.builder.jump(ret_cont, args)
  }
  // After br, code is unreachable
  self.is_unreachable = true
}

///|
/// Translate a br_if instruction
/// Critical edge splitting is needed because brnz doesn't support block args
fn Translator::translate_br_if(self : Translator, depth : Int) -> Unit {
  let cond = self.pop()
  let idx = self.block_stack.length() - 1 - depth

  // For br_if, we need a fallthrough block and a taken block (critical edge split)
  let fallthrough = self.builder.create_block()
  let taken = self.builder.create_block()
  if idx >= 0 && idx < self.block_stack.length() {
    // Jump to a block within the function
    let frame = self.block_stack[idx]

    // Collect values that would be passed on branch
    let args : Array[Value] = []
    for i in 0..<frame.result_types.length() {
      args.push(
        self.value_stack[self.value_stack.length() -
        frame.result_types.length() +
        i],
      )
    }

    // Always pass current local values
    for loc in self.locals {
      args.push(loc)
    }

    // Branch: taken goes to intermediate block, not-taken falls through
    self.builder.brnz(cond, taken, fallthrough)

    // Critical edge split: taken block jumps to target with args
    self.builder.switch_to_block(taken)
    self.builder.jump(frame.block, args)

    // Continue with fallthrough
    self.builder.switch_to_block(fallthrough)
  } else if idx == -1 {
    // Jump to function level (early return)
    let ret_cont = self.get_or_create_return_continuation()

    // Collect values that would be passed on branch
    let args : Array[Value] = []
    for i in 0..<self.func_result_types.length() {
      args.push(
        self.value_stack[self.value_stack.length() -
        self.func_result_types.length() +
        i],
      )
    }

    // Always pass current local values
    for loc in self.locals {
      args.push(loc)
    }

    // Branch: taken goes to intermediate block, not-taken falls through
    self.builder.brnz(cond, taken, fallthrough)

    // Critical edge split: taken block jumps to return continuation
    self.builder.switch_to_block(taken)
    self.builder.jump(ret_cont, args)

    // Continue with fallthrough
    self.builder.switch_to_block(fallthrough)
  }
}

///|
/// Translate a br_table instruction
/// Uses critical edge splitting to pass block arguments properly
fn Translator::translate_br_table(
  self : Translator,
  labels : Array[Int],
  default_ : Int,
) -> Unit {
  let index = self.pop()

  // Helper to get target block and result types for a given depth
  // Returns (target_block, result_types, is_function_level)
  fn get_target(self : Translator, depth : Int) -> (Block, Array[Type], Bool) {
    let idx = self.block_stack.length() - 1 - depth
    if idx >= 0 && idx < self.block_stack.length() {
      let frame = self.block_stack[idx]
      (frame.block, frame.result_types, false)
    } else {
      // Function level
      let ret_cont = self.get_or_create_return_continuation()
      (ret_cont, self.func_result_types, true)
    }
  }

  // Get default target info
  let (default_block, default_result_types, _) = get_target(self, default_)

  // Collect arguments that would be passed on branch (same for all targets)
  // All targets must have the same result type as the default
  let args : Array[Value] = []
  let num_results = default_result_types.length()
  // Only collect results if we have enough values on the stack
  if self.value_stack.length() >= num_results {
    for i in 0..<num_results {
      args.push(self.value_stack[self.value_stack.length() - num_results + i])
    }
  }
  // Always pass current local values
  for loc in self.locals {
    args.push(loc)
  }

  // Save the original block
  let original_block = self.builder.current_block()

  // Phase 1: Create all intermediate blocks (without filling them)
  let intermediate_blocks : Array[Block] = []
  let target_blocks : Array[Block] = []
  for depth in labels {
    let (target_block, _, _) = get_target(self, depth)
    target_blocks.push(target_block)
    intermediate_blocks.push(self.builder.create_block())
  }
  // Create intermediate block for default
  let default_intermediate = self.builder.create_block()

  // Phase 2: Emit br_table in original block
  match original_block {
    Some(_) =>
      self.builder.br_table(index, intermediate_blocks, default_intermediate)
    None => ()
  }

  // Phase 3: Fill in intermediate blocks with jumps to real targets
  for i, intermediate in intermediate_blocks {
    self.builder.switch_to_block(intermediate)
    self.builder.jump(target_blocks[i], args)
  }

  // Fill in default intermediate
  self.builder.switch_to_block(default_intermediate)
  self.builder.jump(default_block, args)

  // br_table is a terminator, code after it is unreachable
  // Don't switch back to original - leave current_block as the last intermediate
  self.is_unreachable = true
}

///|
/// Translate a direct call
fn Translator::translate_call(self : Translator, func_idx : Int) -> Unit {
  // Get function type
  let type_idx = if func_idx < self.num_imports {
    // Look up import function type
    if func_idx < self.import_func_type_indices.length() {
      self.import_func_type_indices[func_idx]
    } else {
      0 // Fallback
    }
  } else {
    let local_idx = func_idx - self.num_imports
    if local_idx < self.func_type_indices.length() {
      self.func_type_indices[local_idx]
    } else {
      0
    }
  }
  if type_idx < self.func_types.length() {
    let func_type = self.func_types[type_idx]
    // Pop arguments
    let args : Array[Value] = []
    for _ in 0..<func_type.params.length() {
      args.push(self.pop())
    }
    args.rev_in_place()
    // Get result types
    let result_types : Array[Type] = func_type.results.map(Type::from_wasm)
    // Emit call with multi-value support
    let results = self.builder.call_multi(func_idx, result_types, args)
    // Push all results onto the stack
    for v in results {
      self.push(v)
    }
  }
}

///|
/// Translate an indirect call
fn Translator::translate_call_indirect(
  self : Translator,
  type_idx : Int,
) -> Unit {
  if type_idx < self.func_types.length() {
    let func_type = self.func_types[type_idx]
    // Pop callee (function reference)
    let callee = self.pop()
    // Pop arguments
    let args : Array[Value] = []
    for _ in 0..<func_type.params.length() {
      args.push(self.pop())
    }
    args.rev_in_place()
    // Get result types
    let result_types : Array[Type] = func_type.results.map(Type::from_wasm)
    // Emit call_indirect with multi-value support
    let results = self.builder.call_indirect_multi(
      type_idx, result_types, callee, args,
    )
    // Push all results onto the stack
    for v in results {
      self.push(v)
    }
  }
}
