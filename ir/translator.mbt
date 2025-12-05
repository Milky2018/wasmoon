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
) -> Translator {
  let builder = IRBuilder::new(name)
  // Add function parameters
  let local_values : Array[Value] = []
  for param in func_type.params {
    let p = builder.add_param(Type::from_wasm(param))
    local_values.push(p)
  }
  // Add result types
  for result in func_type.results {
    builder.add_result(Type::from_wasm(result))
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
  for instr in instrs {
    self.translate_instruction(instr)
  }
  // If no terminator, add implicit return
  match self.builder.current_block() {
    Some(block) =>
      match block.terminator {
        None => {
          let results = self.builder.get_function().results
          let return_vals : Array[Value] = []
          for _ in 0..<results.length() {
            if self.value_stack.length() > 0 {
              return_vals.push(self.pop())
            }
          }
          // Reverse since we popped in wrong order
          return_vals.rev_in_place()
          self.builder.return_(return_vals)
        }
        Some(_) => ()
      }
    None => ()
  }
  self.builder.get_function()
}

///|
/// Translate a single instruction
fn Translator::translate_instruction(
  self : Translator,
  instr : @types.Instruction,
) -> Unit {
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
fn Translator::translate_block(
  self : Translator,
  block_type : @types.BlockType,
  body : Array[@types.Instruction],
) -> Unit {
  let result_types = get_block_result_types(block_type, self.func_types)
  let continuation = self.builder.create_block()
  // Add block parameters for results
  for ty in result_types {
    self.builder.add_block_param(continuation, ty) |> ignore
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
  // Translate body
  for instr in body {
    self.translate_instruction(instr)
  }
  // Pop frame
  self.block_stack.pop() |> ignore
  // Fall through to continuation
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
          self.builder.jump(continuation, args)
        }
        Some(_) => ()
      }
    None => ()
  }
  // Switch to continuation
  self.builder.switch_to_block(continuation)
  // Push block results onto stack
  for i, _ty in result_types {
    self.push(continuation.params[i].0)
  }
}

///|
/// Translate a loop construct
fn Translator::translate_loop(
  self : Translator,
  block_type : @types.BlockType,
  body : Array[@types.Instruction],
) -> Unit {
  let result_types = get_block_result_types(block_type, self.func_types)
  let param_types = get_block_param_types(block_type, self.func_types)
  let loop_header = self.builder.create_block()
  let continuation = self.builder.create_block()
  // Add loop header parameters
  for ty in param_types {
    self.builder.add_block_param(loop_header, ty) |> ignore
  }
  // Add continuation parameters for results
  for ty in result_types {
    self.builder.add_block_param(continuation, ty) |> ignore
  }
  // Jump to loop header with current stack values
  let header_args : Array[Value] = []
  for _ in 0..<param_types.length() {
    header_args.push(self.pop())
  }
  header_args.rev_in_place()
  self.builder.jump(loop_header, header_args)
  // Switch to loop header
  self.builder.switch_to_block(loop_header)
  // Push header params onto stack
  for i, _ty in param_types {
    self.push(loop_header.params[i].0)
  }
  // Push block frame (br targets loop header for loops)
  let frame : BlockFrame = {
    kind: BlockKind::Loop,
    block: loop_header, // Loop's br target is the header
    result_types: param_types, // For br, we need params not results
    loop_header: Some(loop_header),
    stack_height: self.value_stack.length(),
  }
  self.block_stack.push(frame)
  // Translate body
  for instr in body {
    self.translate_instruction(instr)
  }
  // Pop frame
  self.block_stack.pop() |> ignore
  // Fall through to continuation
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
  // Switch to continuation
  self.builder.switch_to_block(continuation)
  // Push results onto stack
  for i, _ty in result_types {
    self.push(continuation.params[i].0)
  }
}

///|
/// Translate an if-else construct
fn Translator::translate_if(
  self : Translator,
  block_type : @types.BlockType,
  then_body : Array[@types.Instruction],
  else_body : Array[@types.Instruction],
) -> Unit {
  let result_types = get_block_result_types(block_type, self.func_types)
  let cond = self.pop()
  let then_block = self.builder.create_block()
  let else_block = self.builder.create_block()
  let continuation = self.builder.create_block()
  // Add continuation parameters for results
  for ty in result_types {
    self.builder.add_block_param(continuation, ty) |> ignore
  }
  // Branch
  self.builder.brnz(cond, then_block, else_block)
  // Push frame for then branch (else block as the "else" continuation)
  let frame : BlockFrame = {
    kind: BlockKind::If(Some(else_block)),
    block: continuation,
    result_types,
    loop_header: None,
    stack_height: self.value_stack.length(),
  }
  self.block_stack.push(frame)
  // Translate then body
  self.builder.switch_to_block(then_block)
  for instr in then_body {
    self.translate_instruction(instr)
  }
  // Jump to continuation from then block
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
  // Restore stack to original height for else branch
  while self.value_stack.length() > frame.stack_height {
    self.pop() |> ignore
  }
  // Translate else body
  self.builder.switch_to_block(else_block)
  for instr in else_body {
    self.translate_instruction(instr)
  }
  // Jump to continuation from else block
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
  // Pop frame
  self.block_stack.pop() |> ignore
  // Switch to continuation
  self.builder.switch_to_block(continuation)
  // Push results onto stack
  for i, _ty in result_types {
    self.push(continuation.params[i].0)
  }
}

///|
/// Translate a br instruction
fn Translator::translate_br(self : Translator, depth : Int) -> Unit {
  let idx = self.block_stack.length() - 1 - depth
  if idx >= 0 && idx < self.block_stack.length() {
    let frame = self.block_stack[idx]
    let args : Array[Value] = []
    for _ in 0..<frame.result_types.length() {
      args.push(self.pop())
    }
    args.rev_in_place()
    self.builder.jump(frame.block, args)
  }
}

///|
/// Translate a br_if instruction
fn Translator::translate_br_if(self : Translator, depth : Int) -> Unit {
  let cond = self.pop()
  let idx = self.block_stack.length() - 1 - depth
  if idx >= 0 && idx < self.block_stack.length() {
    let frame = self.block_stack[idx]
    // For br_if, we need a fallthrough block
    let fallthrough = self.builder.create_block()
    // Collect values that would be passed on branch
    let args : Array[Value] = []
    for i in 0..<frame.result_types.length() {
      args.push(
        self.value_stack[self.value_stack.length() -
        frame.result_types.length() +
        i],
      )
    }
    // If we actually take the branch, need to add block params
    for ty in frame.result_types {
      self.builder.add_block_param(fallthrough, ty) |> ignore
    }
    self.builder.brnz(cond, frame.block, fallthrough)
    self.builder.switch_to_block(fallthrough)
    // Push the fallthrough values back
    for i, _ty in frame.result_types {
      self.value_stack[self.value_stack.length() -
      frame.result_types.length() +
      i] = fallthrough.params[i].0
    }
  }
}

///|
/// Translate a br_table instruction
fn Translator::translate_br_table(
  self : Translator,
  labels : Array[Int],
  default_ : Int,
) -> Unit {
  let index = self.pop()
  // For simplicity, just use the default target
  // A full implementation would create a proper switch
  let idx = self.block_stack.length() - 1 - default_
  if idx >= 0 && idx < self.block_stack.length() {
    let frame = self.block_stack[idx]
    // Build target blocks array
    let targets : Array[Block] = []
    for depth in labels {
      let target_idx = self.block_stack.length() - 1 - depth
      if target_idx >= 0 && target_idx < self.block_stack.length() {
        targets.push(self.block_stack[target_idx].block)
      } else {
        targets.push(frame.block) // Fallback to default
      }
    }
    self.builder.br_table(index, targets, frame.block)
  }
}

///|
/// Translate a direct call
fn Translator::translate_call(self : Translator, func_idx : Int) -> Unit {
  // Get function type
  let type_idx = if func_idx < self.num_imports {
    // This would need to look up import types
    0 // Placeholder
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
    // Get result type
    let result_ty : Type? = if func_type.results.length() > 0 {
      Some(Type::from_wasm(func_type.results[0]))
    } else {
      None
    }
    // Emit call
    let result = self.builder.call(func_idx, result_ty, args)
    match result {
      Some(v) => self.push(v)
      None => ()
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
    // Get result type
    let result_ty : Type? = if func_type.results.length() > 0 {
      Some(Type::from_wasm(func_type.results[0]))
    } else {
      None
    }
    // Emit call_indirect
    let result = self.builder.call_indirect(type_idx, result_ty, callee, args)
    match result {
      Some(v) => self.push(v)
      None => ()
    }
  }
}
