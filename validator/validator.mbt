// WebAssembly Module Validator - Type Checking

///|
/// Validation error types
pub(all) suberror ValidationError {
  TypeMismatch(String) // Expected vs actual type mismatch
  StackUnderflow(String) // Not enough values on validation stack
  InvalidFunctionIndex(Int)
  InvalidTypeIndex(Int)
  InvalidLocalIndex(Int)
  InvalidGlobalIndex(Int)
  InvalidTableIndex(Int)
  InvalidMemoryIndex(Int)
  InvalidLabelIndex(Int)
  UnreachableCode
} derive(Show)

///|
/// Validation context for a module
struct ValidationContext {
  types : Array[@types.FuncType]
  funcs : Array[Int] // type indices
  tables : Array[@types.TableType]
  mems : Array[@types.MemoryType]
  globals : Array[@types.GlobalType]
  locals : Array[@types.ValueType] // current function's locals
  labels : Array[@types.BlockType] // label stack for control flow
  returns : Array[@types.ValueType] // current function's return types
}

///|
fn ValidationContext::new(mod : @types.Module) -> ValidationContext {
  // Collect function types (imports + defined functions)
  let funcs : Array[Int] = []
  for imp in mod.imports {
    match imp.desc {
      Func(type_idx) => funcs.push(type_idx)
      _ => ()
    }
  }
  for type_idx in mod.funcs {
    funcs.push(type_idx)
  }
  // Collect tables
  let tables : Array[@types.TableType] = []
  for imp in mod.imports {
    match imp.desc {
      Table(table_type) => tables.push(table_type)
      _ => ()
    }
  }
  for table in mod.tables {
    tables.push(table)
  }
  // Collect memories
  let mems : Array[@types.MemoryType] = []
  for imp in mod.imports {
    match imp.desc {
      Memory(mem_type) => mems.push(mem_type)
      _ => ()
    }
  }
  for mem in mod.memories {
    mems.push(mem)
  }
  // Collect globals
  let globals : Array[@types.GlobalType] = []
  for imp in mod.imports {
    match imp.desc {
      Global(global_type) => globals.push(global_type)
      _ => ()
    }
  }
  for global in mod.globals {
    globals.push(global.type_)
  }
  {
    types: mod.types,
    funcs,
    tables,
    mems,
    globals,
    locals: [],
    labels: [],
    returns: [],
  }
}

///|
/// Operand stack for type validation
/// Uses Option to represent polymorphic stack (after unreachable)
struct OperandStack {
  stack : Array[@types.ValueType]
  mut polymorphic : Bool // true after unreachable instruction
}

///|
fn OperandStack::new() -> OperandStack {
  { stack: [], polymorphic: false }
}

///|
fn OperandStack::push(self : OperandStack, ty : @types.ValueType) -> Unit {
  self.stack.push(ty)
}

///|
fn OperandStack::pop(
  self : OperandStack,
  expected : @types.ValueType,
) -> Unit raise ValidationError {
  if self.polymorphic && self.stack.is_empty() {
    return // Polymorphic stack accepts any type
  }
  if self.stack.is_empty() {
    raise StackUnderflow("Expected \{expected}, but stack is empty")
  }
  let actual = self.stack.pop()
  match actual {
    Some(a) =>
      if a != expected {
        raise TypeMismatch("Expected \{expected}, got \{a}")
      }
    None => raise StackUnderflow("Expected \{expected}, but stack is empty")
  }
}

///|
fn OperandStack::pop_any(
  self : OperandStack,
) -> @types.ValueType raise ValidationError {
  if self.polymorphic && self.stack.is_empty() {
    return @types.ValueType::I32 // Return arbitrary type for polymorphic stack
  }
  if self.stack.is_empty() {
    raise StackUnderflow("Expected value, but stack is empty")
  }
  match self.stack.pop() {
    Some(v) => v
    None => raise StackUnderflow("Expected value, but stack is empty")
  }
}

///|
fn OperandStack::set_polymorphic(self : OperandStack) -> Unit {
  self.polymorphic = true
}

///|
/// Validate a complete module
pub fn validate_module(mod : @types.Module) -> Unit raise ValidationError {
  let ctx = ValidationContext::new(mod)

  // Validate all function bodies
  let num_imports = count_func_imports(mod.imports)
  for i, code in mod.codes {
    let func_idx = num_imports + i
    let type_idx = ctx.funcs[func_idx]
    if type_idx >= ctx.types.length() {
      raise InvalidTypeIndex(type_idx)
    }
    let func_type = ctx.types[type_idx]
    validate_function(ctx, func_type, code)
  }
}

///|
fn count_func_imports(imports : Array[@types.Import]) -> Int {
  let mut count = 0
  for imp in imports {
    match imp.desc {
      Func(_) => count = count + 1
      _ => ()
    }
  }
  count
}

///|
/// Validate a function body
fn validate_function(
  ctx : ValidationContext,
  func_type : @types.FuncType,
  code : @types.FunctionCode,
) -> Unit raise ValidationError {
  // Set up locals: params + declared locals
  let locals : Array[@types.ValueType] = []
  for param in func_type.params {
    locals.push(param)
  }
  for local_type in code.locals {
    locals.push(local_type)
  }

  // Create validation context for this function
  let func_ctx : ValidationContext = {
    types: ctx.types,
    funcs: ctx.funcs,
    tables: ctx.tables,
    mems: ctx.mems,
    globals: ctx.globals,
    locals,
    labels: [],
    returns: func_type.results,
  }
  let stack = OperandStack::new()

  // Validate function body
  validate_expr(func_ctx, stack, code.body)

  // Check that final stack matches return types
  for i = func_type.results.length() - 1; i >= 0; i = i - 1 {
    stack.pop(func_type.results[i])
  }
}

///|
/// Validate an expression (sequence of instructions)
fn validate_expr(
  ctx : ValidationContext,
  stack : OperandStack,
  instrs : Array[@types.Instruction],
) -> Unit raise ValidationError {
  for instr in instrs {
    validate_instr(ctx, stack, instr)
  }
}

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
      stack.push(ctx.locals[idx])
    }
    LocalSet(idx) => {
      if idx >= ctx.locals.length() {
        raise InvalidLocalIndex(idx)
      }
      stack.pop(ctx.locals[idx])
    }
    LocalTee(idx) => {
      if idx >= ctx.locals.length() {
        raise InvalidLocalIndex(idx)
      }
      stack.pop(ctx.locals[idx])
      stack.push(ctx.locals[idx])
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

    // Memory operations
    I32Load(_, _)
    | I32Load8S(_, _)
    | I32Load8U(_, _)
    | I32Load16S(_, _)
    | I32Load16U(_, _) => {
      stack.pop(@types.ValueType::I32) // address
      stack.push(@types.ValueType::I32)
    }
    I64Load(_, _)
    | I64Load8S(_, _)
    | I64Load8U(_, _)
    | I64Load16S(_, _)
    | I64Load16U(_, _)
    | I64Load32S(_, _)
    | I64Load32U(_, _) => {
      stack.pop(@types.ValueType::I32) // address
      stack.push(@types.ValueType::I64)
    }
    F32Load(_, _) => {
      stack.pop(@types.ValueType::I32) // address
      stack.push(@types.ValueType::F32)
    }
    F64Load(_, _) => {
      stack.pop(@types.ValueType::I32) // address
      stack.push(@types.ValueType::F64)
    }
    I32Store(_, _) | I32Store8(_, _) | I32Store16(_, _) => {
      stack.pop(@types.ValueType::I32) // value
      stack.pop(@types.ValueType::I32) // address
    }
    I64Store(_, _) | I64Store8(_, _) | I64Store16(_, _) | I64Store32(_, _) => {
      stack.pop(@types.ValueType::I64) // value
      stack.pop(@types.ValueType::I32) // address
    }
    F32Store(_, _) => {
      stack.pop(@types.ValueType::F32) // value
      stack.pop(@types.ValueType::I32) // address
    }
    F64Store(_, _) => {
      stack.pop(@types.ValueType::F64) // value
      stack.pop(@types.ValueType::I32) // address
    }
    MemorySize | MemoryGrow => {
      if instr == @types.Instruction::MemoryGrow {
        stack.pop(@types.ValueType::I32) // delta
      }
      stack.push(@types.ValueType::I32)
    }
    MemoryInit(_) => {
      stack.pop(@types.ValueType::I32) // n
      stack.pop(@types.ValueType::I32) // s
      stack.pop(@types.ValueType::I32) // d
    }
    DataDrop(_) => ()
    MemoryCopy => {
      stack.pop(@types.ValueType::I32) // n
      stack.pop(@types.ValueType::I32) // s
      stack.pop(@types.ValueType::I32) // d
    }
    MemoryFill => {
      stack.pop(@types.ValueType::I32) // n
      stack.pop(@types.ValueType::I32) // val
      stack.pop(@types.ValueType::I32) // d
    }

    // Table operations
    TableGet(idx) => {
      if idx >= ctx.tables.length() {
        raise InvalidTableIndex(idx)
      }
      stack.pop(@types.ValueType::I32) // index
      stack.push(ctx.tables[idx].elem_type)
    }
    TableSet(idx) => {
      if idx >= ctx.tables.length() {
        raise InvalidTableIndex(idx)
      }
      stack.pop(ctx.tables[idx].elem_type) // value
      stack.pop(@types.ValueType::I32) // index
    }
    TableSize(_) => stack.push(@types.ValueType::I32)
    TableGrow(idx) => {
      if idx >= ctx.tables.length() {
        raise InvalidTableIndex(idx)
      }
      stack.pop(@types.ValueType::I32) // delta
      stack.pop(ctx.tables[idx].elem_type) // init value
      stack.push(@types.ValueType::I32) // old size or -1
    }
    TableFill(idx) => {
      if idx >= ctx.tables.length() {
        raise InvalidTableIndex(idx)
      }
      stack.pop(@types.ValueType::I32) // n
      stack.pop(ctx.tables[idx].elem_type) // value
      stack.pop(@types.ValueType::I32) // i
    }
    TableCopy(_, _) => {
      stack.pop(@types.ValueType::I32) // n
      stack.pop(@types.ValueType::I32) // s
      stack.pop(@types.ValueType::I32) // d
    }
    ElemDrop(_) => ()

    // Reference instructions
    RefNull(ref_type) => stack.push(ref_type)
    RefIsNull => {
      let _ = stack.pop_any() // any ref type
      stack.push(@types.ValueType::I32)
    }
    RefFunc(func_idx) => {
      if func_idx >= ctx.funcs.length() {
        raise InvalidFunctionIndex(func_idx)
      }
      stack.push(@types.ValueType::FuncRef)
    }

    // Control flow
    Nop => ()
    Unreachable => stack.set_polymorphic()
    Drop => {
      let _ = stack.pop_any()

    }
    Select => {
      stack.pop(@types.ValueType::I32) // condition
      let t2 = stack.pop_any()
      let t1 = stack.pop_any()
      if t1 != t2 {
        raise TypeMismatch(
          "select operands must have same type: \{t1} vs \{t2}",
        )
      }
      stack.push(t1)
    }

    // Function calls
    Call(func_idx) => {
      if func_idx >= ctx.funcs.length() {
        raise InvalidFunctionIndex(func_idx)
      }
      let type_idx = ctx.funcs[func_idx]
      let func_type = ctx.types[type_idx]
      // Pop parameters in reverse order
      for i = func_type.params.length() - 1; i >= 0; i = i - 1 {
        stack.pop(func_type.params[i])
      }
      // Push results
      for result in func_type.results {
        stack.push(result)
      }
    }
    CallIndirect(type_idx, table_idx) => {
      if table_idx >= ctx.tables.length() {
        raise InvalidTableIndex(table_idx)
      }
      if type_idx >= ctx.types.length() {
        raise InvalidTypeIndex(type_idx)
      }
      stack.pop(@types.ValueType::I32) // table index
      let func_type = ctx.types[type_idx]
      for i = func_type.params.length() - 1; i >= 0; i = i - 1 {
        stack.pop(func_type.params[i])
      }
      for result in func_type.results {
        stack.push(result)
      }
    }

    // Block, Loop, If - simplified validation (TODO: full control flow validation)
    Block(bt, body) | Loop(bt, body) => {
      let results = get_block_results(ctx, bt)
      // Recursively validate body
      let block_stack = OperandStack::new()
      validate_expr(ctx, block_stack, body)
      // Push results onto outer stack
      for result in results {
        stack.push(result)
      }
    }
    If(bt, then_body, else_body) => {
      stack.pop(@types.ValueType::I32) // condition
      let results = get_block_results(ctx, bt)
      // Validate both branches
      let then_stack = OperandStack::new()
      validate_expr(ctx, then_stack, then_body)
      let else_stack = OperandStack::new()
      validate_expr(ctx, else_stack, else_body)
      // Push results
      for result in results {
        stack.push(result)
      }
    }

    // Branch instructions - simplified (TODO: proper label tracking)
    Br(_) | BrIf(_) | BrTable(_, _) | Return =>
      // These require proper label stack tracking
      // For now, just mark as polymorphic after unconditional branch
      match instr {
        Br(_) | Return => stack.set_polymorphic()
        BrIf(_) => stack.pop(@types.ValueType::I32)
        BrTable(_, _) => {
          stack.pop(@types.ValueType::I32) // index
          stack.set_polymorphic()
        }
        _ => ()
      }
    _ => () // Other instructions not yet validated
  }
}

///|
fn get_block_results(
  ctx : ValidationContext,
  bt : @types.BlockType,
) -> Array[@types.ValueType] {
  match bt {
    Empty => []
    Value(t) => [t]
    TypeIndex(idx) =>
      if idx < ctx.types.length() {
        ctx.types[idx].results
      } else {
        []
      }
  }
}
