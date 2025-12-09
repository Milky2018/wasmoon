// WebAssembly Module Validator - Type Checking

///|
/// Validation error types
pub(all) suberror ValidationError {
  TypeMismatch(String) // Expected vs actual type mismatch
  StackUnderflow(String) // Not enough values on validation stack
  StackHeightMismatch(String) // Stack height doesn't match expected
  InvalidFunctionIndex(Int)
  InvalidTypeIndex(Int)
  InvalidLocalIndex(Int)
  InvalidGlobalIndex(Int)
  InvalidTableIndex(Int)
  InvalidMemoryIndex(Int)
  InvalidLabelIndex(Int)
  InvalidElemIndex(Int)
  UnreachableCode
  MultipleMemories // More than one memory is not allowed in MVP
  MultipleTables // More than one table is not allowed in MVP
  InvalidLimits(String) // Invalid limits (e.g., min > max)
  InvalidAlignment(String) // Alignment must not be larger than natural
  ConstantExpressionRequired // Non-constant instruction in init expression
  MutableGlobalInConstExpr // Mutable global referenced in constant expression
  DuplicateExportName(String) // Same export name used more than once
  UnknownExport(String) // Export references unknown entity
  UninitializedLocal(Int) // Non-nullable ref local read before initialization
  // Error with location context
  WithContext(ValidationErrorContext)
} derive(Show)

///|
/// Validation error with location context for debugging
pub(all) struct ValidationErrorContext {
  error_msg : String // The original error message
  func_idx : Int? // The function index where validation failed
  instr_offset : Int? // The instruction offset within the function body
  instruction : String? // The instruction that caused the error
}

///|
pub fn ValidationErrorContext::new(msg : String) -> ValidationErrorContext {
  { error_msg: msg, func_idx: None, instr_offset: None, instruction: None }
}

///|
pub fn ValidationErrorContext::from_error(
  error : ValidationError,
) -> ValidationErrorContext {
  let msg = match error {
    TypeMismatch(m) => "type mismatch: \{m}"
    StackUnderflow(m) => "stack underflow: \{m}"
    StackHeightMismatch(m) => "stack height mismatch: \{m}"
    InvalidFunctionIndex(idx) => "invalid function index: \{idx}"
    InvalidTypeIndex(idx) => "invalid type index: \{idx}"
    InvalidLocalIndex(idx) => "invalid local index: \{idx}"
    InvalidGlobalIndex(idx) => "invalid global index: \{idx}"
    InvalidTableIndex(idx) => "invalid table index: \{idx}"
    InvalidMemoryIndex(idx) => "invalid memory index: \{idx}"
    InvalidLabelIndex(idx) => "invalid label index: \{idx}"
    InvalidElemIndex(idx) => "invalid element index: \{idx}"
    UnreachableCode => "unreachable code"
    MultipleMemories => "multiple memories not allowed in MVP"
    MultipleTables => "multiple tables not allowed in MVP"
    InvalidLimits(m) => "invalid limits: \{m}"
    InvalidAlignment(m) => "alignment must not be larger than natural: \{m}"
    ConstantExpressionRequired => "constant expression required"
    MutableGlobalInConstExpr => "constant expression required"
    DuplicateExportName(name) => "duplicate export name: \{name}"
    UnknownExport(m) => m
    UninitializedLocal(_) => "uninitialized local"
    WithContext(ctx) => ctx.error_msg
  }
  { error_msg: msg, func_idx: None, instr_offset: None, instruction: None }
}

///|
pub fn ValidationErrorContext::with_func_idx(
  self : ValidationErrorContext,
  idx : Int,
) -> ValidationErrorContext {
  { ..self, func_idx: Some(idx) }
}

///|
pub fn ValidationErrorContext::with_instr_offset(
  self : ValidationErrorContext,
  offset : Int,
) -> ValidationErrorContext {
  { ..self, instr_offset: Some(offset) }
}

///|
pub fn ValidationErrorContext::with_instruction(
  self : ValidationErrorContext,
  instr : String,
) -> ValidationErrorContext {
  { ..self, instruction: Some(instr) }
}

///|
/// Format the validation error with full context for display
pub fn ValidationErrorContext::format(self : ValidationErrorContext) -> String {
  let result = StringBuilder::new()
  result.write_string("validation error: ")
  result.write_string(self.error_msg)
  result.write_string("\n")

  // Show function index if available
  if self.func_idx is Some(idx) {
    result.write_string("  in function: func[\{idx}]\n")
  }

  // Show instruction offset if available
  if self.instr_offset is Some(offset) {
    result.write_string("  at instruction offset: \{offset}\n")
  }

  // Show instruction if available
  if self.instruction is Some(instr) {
    result.write_string("  instruction: \{instr}\n")
  }
  result.to_string()
}

///|
pub impl Show for ValidationErrorContext with output(self, logger) {
  logger.write_string(self.format())
}

///|
/// Format a basic ValidationError without context
pub fn format_validation_error(error : ValidationError) -> String {
  ValidationErrorContext::from_error(error).format()
}

///|
/// Label information for control flow validation
priv struct LabelInfo {
  kind : LabelKind // block or loop
  block_type : @types.BlockType
}

///|
/// Kind of control structure for label resolution
priv enum LabelKind {
  BlockLabel // br jumps to end, uses results
  LoopLabel // br jumps to start, uses params
}

///|
/// Validation context for a module
priv struct ValidationContext {
  types : Array[@types.FuncType]
  funcs : Array[Int] // type indices
  tables : Array[@types.TableType]
  mems : Array[@types.MemoryType]
  globals : Array[@types.GlobalType]
  elems : Array[@types.ValueType] // element segment types
  locals : Array[@types.ValueType] // current function's locals
  labels : Array[LabelInfo] // label stack for control flow
  returns : Array[@types.ValueType] // current function's return types
  local_init : Array[Bool] // tracks which locals have been initialized (for non-nullable refs)
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
  // Collect elem segment types
  let elems : Array[@types.ValueType] = []
  for elem in mod.elems {
    elems.push(elem.type_)
  }
  {
    types: mod.types,
    funcs,
    tables,
    mems,
    globals,
    elems,
    locals: [],
    labels: [],
    returns: [],
    local_init: [],
  }
}

///|
/// Check if a value type is a non-nullable reference type
fn is_non_nullable_ref(ty : @types.ValueType) -> Bool {
  match ty {
    RefFunc | RefExtern => true
    _ => false
  }
}

///|
/// Operand stack for type validation
/// Uses Option to represent polymorphic stack (after unreachable)
priv struct OperandStack {
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
/// Check that stack has exactly the expected height
fn OperandStack::check_height(
  self : OperandStack,
  expected : Int,
  context : String,
) -> Unit raise ValidationError {
  if !self.polymorphic && self.stack.length() != expected {
    raise StackHeightMismatch(
      "\{context}: expected stack height \{expected}, got \{self.stack.length()}",
    )
  }
}

///|
/// Validate a constant expression (used in data/elem offsets and global init)
/// Returns the result type of the expression
/// Supports extended-const proposal: allows i32/i64 arithmetic (add, sub, mul)
fn validate_const_expr(
  globals : Array[@types.GlobalType],
  expr : Array[@types.Instruction],
  expected_type : @types.ValueType,
  funcs? : Array[Int] = [],
) -> Unit raise ValidationError {
  if expr.is_empty() {
    raise TypeMismatch("empty constant expression")
  }

  // Use stack-based type checking for extended constant expressions
  let type_stack : Array[@types.ValueType] = []
  for instr in expr {
    match instr {
      I32Const(_) => type_stack.push(@types.ValueType::I32)
      I64Const(_) => type_stack.push(@types.ValueType::I64)
      F32Const(_) => type_stack.push(@types.ValueType::F32)
      F64Const(_) => type_stack.push(@types.ValueType::F64)
      RefNull(t) => type_stack.push(t)
      RefFunc(func_idx) => {
        if func_idx >= funcs.length() {
          raise InvalidFunctionIndex(func_idx)
        }
        type_stack.push(@types.ValueType::FuncRef)
      }
      GlobalGet(idx) => {
        if idx >= globals.length() {
          raise InvalidGlobalIndex(idx)
        }
        let global = globals[idx]
        if global.mutable {
          raise MutableGlobalInConstExpr
        }
        type_stack.push(global.value_type)
      }
      // Extended-const: i32 arithmetic
      I32Add | I32Sub | I32Mul => {
        if type_stack.length() < 2 {
          raise StackUnderflow("i32 arithmetic in constant expression")
        }
        let b = type_stack.pop().unwrap()
        let a = type_stack.pop().unwrap()
        if a != @types.ValueType::I32 || b != @types.ValueType::I32 {
          raise TypeMismatch("i32 arithmetic requires i32 operands")
        }
        type_stack.push(@types.ValueType::I32)
      }
      // Extended-const: i64 arithmetic
      I64Add | I64Sub | I64Mul => {
        if type_stack.length() < 2 {
          raise StackUnderflow("i64 arithmetic in constant expression")
        }
        let b = type_stack.pop().unwrap()
        let a = type_stack.pop().unwrap()
        if a != @types.ValueType::I64 || b != @types.ValueType::I64 {
          raise TypeMismatch("i64 arithmetic requires i64 operands")
        }
        type_stack.push(@types.ValueType::I64)
      }
      _ =>
        // Any other instruction is not allowed in constant expressions
        raise ConstantExpressionRequired
    }
  }

  // Constant expression must produce exactly one value
  if type_stack.length() != 1 {
    raise TypeMismatch(
      "constant expression must produce exactly one value, got \{type_stack.length()}",
    )
  }

  // Check the result type matches expected
  let result_type = type_stack[0]
  if result_type != expected_type {
    raise TypeMismatch(
      "constant expression: expected \{expected_type}, got \{result_type}",
    )
  }
}

///|
/// Validate a complete module
pub fn validate_module(mod : @types.Module) -> Unit raise ValidationError {
  let ctx = ValidationContext::new(mod)

  // Validate that all function type indices are valid
  for i, type_idx in ctx.funcs {
    if type_idx >= ctx.types.length() {
      raise InvalidTypeIndex(type_idx)
    }
    ignore(i)
  }

  // Check for multiple memories (not allowed in MVP)
  if ctx.mems.length() > 1 {
    raise MultipleMemories
  }

  // Check for multiple tables (not allowed in MVP)
  if ctx.tables.length() > 1 {
    raise MultipleTables
  }

  // Validate memory limits
  for mem in ctx.mems {
    validate_memory_limits(mem.limits)
  }

  // Validate global initialization expressions
  // For each global, its init expression can only reference previously defined globals
  // (imported globals are already in ctx.globals from imports)
  let num_imported_globals = count_global_imports(mod.imports)
  for i, global in mod.globals {
    // Available globals for this init: imports + module globals before index i
    let available_globals : Array[@types.GlobalType] = []
    // Add all imported globals
    for j in 0..<num_imported_globals {
      available_globals.push(ctx.globals[j])
    }
    // Add module globals defined before this one
    for j in 0..<i {
      available_globals.push(mod.globals[j].type_)
    }
    // Validate init expression
    validate_const_expr(available_globals, global.init, global.type_.value_type)
  }

  // Validate data segments reference valid memory and have valid offset expressions
  for data in mod.datas {
    if data.memory_idx >= ctx.mems.length() {
      raise InvalidMemoryIndex(data.memory_idx)
    }
    // Validate offset expression is a constant expression producing i32
    validate_const_expr(ctx.globals, data.offset, @types.ValueType::I32)
  }

  // Validate elem segments
  for elem in mod.elems {
    // Validate offset expression for active elem segments
    if elem.mode is Active(table_idx, offset_expr) {
      // Check table index is valid
      if table_idx >= ctx.tables.length() {
        raise InvalidTableIndex(table_idx)
      }
      // Check element type matches table element type
      let table_elem_type = ctx.tables[table_idx].elem_type
      if elem.type_ != table_elem_type {
        raise TypeMismatch(
          "element segment type \{elem.type_} does not match table element type \{table_elem_type}",
        )
      }
      // Validate offset expression is a constant expression producing i32
      validate_const_expr(ctx.globals, offset_expr, @types.ValueType::I32)
    }
    // Validate each init expression is a constant expression producing the element type
    for init in elem.init {
      validate_const_expr(ctx.globals, init, elem.type_, funcs=ctx.funcs)
    }
  }

  // Validate exports
  let export_names : Map[String, Unit] = {}
  for exp in mod.exports {
    // Check for duplicate export names
    if export_names.contains(exp.name) {
      raise DuplicateExportName(exp.name)
    }
    export_names.set(exp.name, ())
    // Check that export references a valid entity
    match exp.desc {
      Func(idx) =>
        if idx >= ctx.funcs.length() {
          raise UnknownExport("unknown function \{idx}")
        }
      Global(idx) =>
        if idx >= ctx.globals.length() {
          raise UnknownExport("unknown global \{idx}")
        }
      Table(idx) =>
        if idx >= ctx.tables.length() {
          raise UnknownExport("unknown table \{idx}")
        }
      Memory(idx) =>
        if idx >= ctx.mems.length() {
          raise UnknownExport("unknown memory \{idx}")
        }
    }
  }

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
/// Validate a complete module and return detailed error context on failure
pub fn validate_module_with_context(
  mod : @types.Module,
) -> Unit raise ValidationError {
  let ctx = ValidationContext::new(mod)

  // Validate that all function type indices are valid
  for i, type_idx in ctx.funcs {
    if type_idx >= ctx.types.length() {
      raise WithContext(
        ValidationErrorContext::from_error(InvalidTypeIndex(type_idx)),
      )
    }
    ignore(i)
  }

  // Check for multiple memories (not allowed in MVP)
  if ctx.mems.length() > 1 {
    raise WithContext(ValidationErrorContext::from_error(MultipleMemories))
  }

  // Check for multiple tables (not allowed in MVP)
  if ctx.tables.length() > 1 {
    raise WithContext(ValidationErrorContext::from_error(MultipleTables))
  }

  // Validate memory limits
  for mem in ctx.mems {
    validate_memory_limits(mem.limits) catch {
      e => raise WithContext(ValidationErrorContext::from_error(e))
    }
  }

  // Validate data segments reference valid memory and have valid offset expressions
  for data in mod.datas {
    if data.memory_idx >= ctx.mems.length() {
      raise WithContext(
        ValidationErrorContext::from_error(InvalidMemoryIndex(data.memory_idx)),
      )
    }
    // Validate offset expression is a constant expression producing i32
    validate_const_expr(ctx.globals, data.offset, @types.ValueType::I32) catch {
      e => raise WithContext(ValidationErrorContext::from_error(e))
    }
  }

  // Validate elem segments
  for elem in mod.elems {
    // Validate offset expression for active elem segments
    if elem.mode is Active(table_idx, offset_expr) {
      // Check table index is valid
      if table_idx >= ctx.tables.length() {
        raise WithContext(
          ValidationErrorContext::from_error(InvalidTableIndex(table_idx)),
        )
      }
      // Check element type matches table element type
      let table_elem_type = ctx.tables[table_idx].elem_type
      if elem.type_ != table_elem_type {
        raise WithContext(
          ValidationErrorContext::from_error(
            TypeMismatch(
              "element segment type \{elem.type_} does not match table element type \{table_elem_type}",
            ),
          ),
        )
      }
      // Validate offset expression is a constant expression producing i32
      validate_const_expr(ctx.globals, offset_expr, @types.ValueType::I32) catch {
        e => raise WithContext(ValidationErrorContext::from_error(e))
      }
    }
    // Validate each init expression is a constant expression producing the element type
    for init in elem.init {
      validate_const_expr(ctx.globals, init, elem.type_, funcs=ctx.funcs) catch {
        e => raise WithContext(ValidationErrorContext::from_error(e))
      }
    }
  }

  // Validate all function bodies with location tracking
  let num_imports = count_func_imports(mod.imports)
  for i, code in mod.codes {
    let func_idx = num_imports + i
    let type_idx = ctx.funcs[func_idx]
    if type_idx >= ctx.types.length() {
      raise WithContext(
        ValidationErrorContext::from_error(InvalidTypeIndex(type_idx)).with_func_idx(
          func_idx,
        ),
      )
    }
    let func_type = ctx.types[type_idx]
    validate_function_with_offset(ctx, func_type, code, func_idx)
  }
}

///|
/// Validate a function body with instruction offset tracking
fn validate_function_with_offset(
  ctx : ValidationContext,
  func_type : @types.FuncType,
  code : @types.FunctionCode,
  func_idx : Int,
) -> Unit raise ValidationError {
  // Set up locals: params + declared locals
  let locals : Array[@types.ValueType] = []
  let local_init : Array[Bool] = []
  // Parameters are always initialized (provided by caller)
  for param in func_type.params {
    locals.push(param)
    local_init.push(true)
  }
  // Declared locals: initialized only if they have a default value (not non-nullable ref)
  for local_type in code.locals {
    locals.push(local_type)
    // Non-nullable reference types don't have a default value, so they start uninitialized
    local_init.push(!is_non_nullable_ref(local_type))
  }

  // Create validation context for this function
  let func_ctx : ValidationContext = {
    types: ctx.types,
    funcs: ctx.funcs,
    tables: ctx.tables,
    mems: ctx.mems,
    globals: ctx.globals,
    elems: ctx.elems,
    locals,
    labels: [],
    returns: func_type.results,
    local_init,
  }
  let stack = OperandStack::new()

  // Validate function body with offset tracking
  validate_expr_with_offset(func_ctx, stack, code.body, func_idx)

  // Check that final stack has exactly the return types
  let expected_height = func_type.results.length()
  stack.check_height(expected_height, "function return") catch {
    e =>
      raise WithContext(
        ValidationErrorContext::from_error(e).with_func_idx(func_idx),
      )
  }

  // Pop and verify return types
  let num_results = func_type.results.length()
  for offset in 0..<num_results {
    let i = num_results - 1 - offset
    stack.pop(func_type.results[i]) catch {
      e =>
        raise WithContext(
          ValidationErrorContext::from_error(e).with_func_idx(func_idx),
        )
    }
  }
}

///|
/// Validate an expression with instruction offset tracking
fn validate_expr_with_offset(
  ctx : ValidationContext,
  stack : OperandStack,
  instrs : Array[@types.Instruction],
  func_idx : Int,
) -> Unit raise ValidationError {
  for i, instr in instrs {
    validate_instr(ctx, stack, instr) catch {
      e =>
        raise WithContext(
          ValidationErrorContext::from_error(e)
          .with_func_idx(func_idx)
          .with_instr_offset(i)
          .with_instruction(instr.to_string()),
        )
    }
  }
}

///|
/// Validate memory limits according to WASM spec
fn validate_memory_limits(limits : @types.Limits) -> Unit raise ValidationError {
  let max_pages = 65536 // 4GiB / 64KiB per page

  // Check min doesn't exceed max allowed
  // Use unsigned comparison since limits can be large values that overflow signed Int
  if limits.min.reinterpret_as_uint() > max_pages.reinterpret_as_uint() {
    raise InvalidLimits("memory size must be at most 65536 pages")
  }

  // Check max if specified
  match limits.max {
    Some(max_val) => {
      // max must not exceed allowed maximum (unsigned comparison)
      if max_val.reinterpret_as_uint() > max_pages.reinterpret_as_uint() {
        raise InvalidLimits("memory size must be at most 65536 pages")
      }
      // min must not be greater than max (unsigned comparison)
      if limits.min.reinterpret_as_uint() > max_val.reinterpret_as_uint() {
        raise InvalidLimits("size minimum must not be greater than maximum")
      }
    }
    None => ()
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
fn count_global_imports(imports : Array[@types.Import]) -> Int {
  let mut count = 0
  for imp in imports {
    match imp.desc {
      Global(_) => count = count + 1
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
  let local_init : Array[Bool] = []
  // Parameters are always initialized (provided by caller)
  for param in func_type.params {
    locals.push(param)
    local_init.push(true)
  }
  // Declared locals: initialized only if they have a default value (not non-nullable ref)
  for local_type in code.locals {
    locals.push(local_type)
    // Non-nullable reference types don't have a default value, so they start uninitialized
    local_init.push(!is_non_nullable_ref(local_type))
  }

  // Create validation context for this function
  let func_ctx : ValidationContext = {
    types: ctx.types,
    funcs: ctx.funcs,
    tables: ctx.tables,
    mems: ctx.mems,
    globals: ctx.globals,
    elems: ctx.elems,
    locals,
    labels: [],
    returns: func_type.results,
    local_init,
  }
  let stack = OperandStack::new()

  // Validate function body
  validate_expr(func_ctx, stack, code.body)

  // Check that final stack has exactly the return types
  let expected_height = func_type.results.length()
  stack.check_height(expected_height, "function return")

  // Pop and verify return types
  let results_count = func_type.results.length()
  for offset in 0..<results_count {
    let i = results_count - 1 - offset
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

    // Memory operations - all require memory index 0 to exist
    // Natural alignment: 8-bit=0, 16-bit=1, 32-bit=2, 64-bit=3
    I32Load(align, _) => {
      if ctx.mems.length() == 0 {
        raise InvalidMemoryIndex(0)
      }
      if align > 2 {
        raise InvalidAlignment(
          "i32.load alignment \{align} exceeds natural alignment 2",
        )
      }
      stack.pop(@types.ValueType::I32) // address
      stack.push(@types.ValueType::I32)
    }
    I32Load8S(align, _) | I32Load8U(align, _) => {
      if ctx.mems.length() == 0 {
        raise InvalidMemoryIndex(0)
      }
      if align > 0 {
        raise InvalidAlignment(
          "i32.load8 alignment \{align} exceeds natural alignment 0",
        )
      }
      stack.pop(@types.ValueType::I32) // address
      stack.push(@types.ValueType::I32)
    }
    I32Load16S(align, _) | I32Load16U(align, _) => {
      if ctx.mems.length() == 0 {
        raise InvalidMemoryIndex(0)
      }
      if align > 1 {
        raise InvalidAlignment(
          "i32.load16 alignment \{align} exceeds natural alignment 1",
        )
      }
      stack.pop(@types.ValueType::I32) // address
      stack.push(@types.ValueType::I32)
    }
    I64Load(align, _) => {
      if ctx.mems.length() == 0 {
        raise InvalidMemoryIndex(0)
      }
      if align > 3 {
        raise InvalidAlignment(
          "i64.load alignment \{align} exceeds natural alignment 3",
        )
      }
      stack.pop(@types.ValueType::I32) // address
      stack.push(@types.ValueType::I64)
    }
    I64Load8S(align, _) | I64Load8U(align, _) => {
      if ctx.mems.length() == 0 {
        raise InvalidMemoryIndex(0)
      }
      if align > 0 {
        raise InvalidAlignment(
          "i64.load8 alignment \{align} exceeds natural alignment 0",
        )
      }
      stack.pop(@types.ValueType::I32) // address
      stack.push(@types.ValueType::I64)
    }
    I64Load16S(align, _) | I64Load16U(align, _) => {
      if ctx.mems.length() == 0 {
        raise InvalidMemoryIndex(0)
      }
      if align > 1 {
        raise InvalidAlignment(
          "i64.load16 alignment \{align} exceeds natural alignment 1",
        )
      }
      stack.pop(@types.ValueType::I32) // address
      stack.push(@types.ValueType::I64)
    }
    I64Load32S(align, _) | I64Load32U(align, _) => {
      if ctx.mems.length() == 0 {
        raise InvalidMemoryIndex(0)
      }
      if align > 2 {
        raise InvalidAlignment(
          "i64.load32 alignment \{align} exceeds natural alignment 2",
        )
      }
      stack.pop(@types.ValueType::I32) // address
      stack.push(@types.ValueType::I64)
    }
    F32Load(align, _) => {
      if ctx.mems.length() == 0 {
        raise InvalidMemoryIndex(0)
      }
      if align > 2 {
        raise InvalidAlignment(
          "f32.load alignment \{align} exceeds natural alignment 2",
        )
      }
      stack.pop(@types.ValueType::I32) // address
      stack.push(@types.ValueType::F32)
    }
    F64Load(align, _) => {
      if ctx.mems.length() == 0 {
        raise InvalidMemoryIndex(0)
      }
      if align > 3 {
        raise InvalidAlignment(
          "f64.load alignment \{align} exceeds natural alignment 3",
        )
      }
      stack.pop(@types.ValueType::I32) // address
      stack.push(@types.ValueType::F64)
    }
    I32Store(align, _) => {
      if ctx.mems.length() == 0 {
        raise InvalidMemoryIndex(0)
      }
      if align > 2 {
        raise InvalidAlignment(
          "i32.store alignment \{align} exceeds natural alignment 2",
        )
      }
      stack.pop(@types.ValueType::I32) // value
      stack.pop(@types.ValueType::I32) // address
    }
    I32Store8(align, _) => {
      if ctx.mems.length() == 0 {
        raise InvalidMemoryIndex(0)
      }
      if align > 0 {
        raise InvalidAlignment(
          "i32.store8 alignment \{align} exceeds natural alignment 0",
        )
      }
      stack.pop(@types.ValueType::I32) // value
      stack.pop(@types.ValueType::I32) // address
    }
    I32Store16(align, _) => {
      if ctx.mems.length() == 0 {
        raise InvalidMemoryIndex(0)
      }
      if align > 1 {
        raise InvalidAlignment(
          "i32.store16 alignment \{align} exceeds natural alignment 1",
        )
      }
      stack.pop(@types.ValueType::I32) // value
      stack.pop(@types.ValueType::I32) // address
    }
    I64Store(align, _) => {
      if ctx.mems.length() == 0 {
        raise InvalidMemoryIndex(0)
      }
      if align > 3 {
        raise InvalidAlignment(
          "i64.store alignment \{align} exceeds natural alignment 3",
        )
      }
      stack.pop(@types.ValueType::I64) // value
      stack.pop(@types.ValueType::I32) // address
    }
    I64Store8(align, _) => {
      if ctx.mems.length() == 0 {
        raise InvalidMemoryIndex(0)
      }
      if align > 0 {
        raise InvalidAlignment(
          "i64.store8 alignment \{align} exceeds natural alignment 0",
        )
      }
      stack.pop(@types.ValueType::I64) // value
      stack.pop(@types.ValueType::I32) // address
    }
    I64Store16(align, _) => {
      if ctx.mems.length() == 0 {
        raise InvalidMemoryIndex(0)
      }
      if align > 1 {
        raise InvalidAlignment(
          "i64.store16 alignment \{align} exceeds natural alignment 1",
        )
      }
      stack.pop(@types.ValueType::I64) // value
      stack.pop(@types.ValueType::I32) // address
    }
    I64Store32(align, _) => {
      if ctx.mems.length() == 0 {
        raise InvalidMemoryIndex(0)
      }
      if align > 2 {
        raise InvalidAlignment(
          "i64.store32 alignment \{align} exceeds natural alignment 2",
        )
      }
      stack.pop(@types.ValueType::I64) // value
      stack.pop(@types.ValueType::I32) // address
    }
    F32Store(align, _) => {
      if ctx.mems.length() == 0 {
        raise InvalidMemoryIndex(0)
      }
      if align > 2 {
        raise InvalidAlignment(
          "f32.store alignment \{align} exceeds natural alignment 2",
        )
      }
      stack.pop(@types.ValueType::F32) // value
      stack.pop(@types.ValueType::I32) // address
    }
    F64Store(align, _) => {
      if ctx.mems.length() == 0 {
        raise InvalidMemoryIndex(0)
      }
      if align > 3 {
        raise InvalidAlignment(
          "f64.store alignment \{align} exceeds natural alignment 3",
        )
      }
      stack.pop(@types.ValueType::F64) // value
      stack.pop(@types.ValueType::I32) // address
    }
    MemorySize | MemoryGrow => {
      if ctx.mems.length() == 0 {
        raise InvalidMemoryIndex(0)
      }
      if instr == @types.Instruction::MemoryGrow {
        stack.pop(@types.ValueType::I32) // delta
      }
      stack.push(@types.ValueType::I32)
    }
    MemoryInit(_) => {
      if ctx.mems.length() == 0 {
        raise InvalidMemoryIndex(0)
      }
      stack.pop(@types.ValueType::I32) // n
      stack.pop(@types.ValueType::I32) // s
      stack.pop(@types.ValueType::I32) // d
    }
    DataDrop(_) => ()
    MemoryCopy => {
      if ctx.mems.length() == 0 {
        raise InvalidMemoryIndex(0)
      }
      stack.pop(@types.ValueType::I32) // n
      stack.pop(@types.ValueType::I32) // s
      stack.pop(@types.ValueType::I32) // d
    }
    MemoryFill => {
      if ctx.mems.length() == 0 {
        raise InvalidMemoryIndex(0)
      }
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
    TableInit(table_idx, elem_idx) => {
      // Validate table and elem indices
      if table_idx >= ctx.tables.length() {
        raise InvalidTableIndex(table_idx)
      }
      if elem_idx >= ctx.elems.length() {
        raise InvalidElemIndex(elem_idx)
      }
      // Check elem segment type matches table element type
      let table_elem_type = ctx.tables[table_idx].elem_type
      let elem_type = ctx.elems[elem_idx]
      if elem_type != table_elem_type {
        raise TypeMismatch(
          "element segment type \{elem_type} does not match table element type \{table_elem_type}",
        )
      }
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
      if table_idx >= ctx.tables.length() {
        raise InvalidTableIndex(table_idx)
      }
      // call_indirect requires a funcref table
      let table_type = ctx.tables[table_idx]
      if table_type.elem_type != @types.ValueType::FuncRef {
        raise TypeMismatch(
          "call_indirect requires funcref table, got \{table_type.elem_type}",
        )
      }
      if type_idx >= ctx.types.length() {
        raise InvalidTypeIndex(type_idx)
      }
      stack.pop(@types.ValueType::I32) // table index
      let func_type = ctx.types[type_idx]
      let num_ci_params = func_type.params.length()
      for offset in 0..<num_ci_params {
        let i = num_ci_params - 1 - offset
        stack.pop(func_type.params[i])
      }
      for result in func_type.results {
        stack.push(result)
      }
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
      // Push label for block (br jumps to end, uses results)
      let label : LabelInfo = { kind: BlockLabel, block_type: bt }
      ctx.labels.push(label)
      // Validate body
      validate_expr(ctx, block_stack, body)
      // Pop label
      let _ = ctx.labels.pop()
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
      // Push label for loop (br jumps to start, uses params)
      let label : LabelInfo = { kind: LoopLabel, block_type: bt }
      ctx.labels.push(label)
      // Validate body
      validate_expr(ctx, block_stack, body)
      // Pop label
      let _ = ctx.labels.pop()
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
      // Validate else branch
      let else_stack = OperandStack::new()
      for param in params {
        else_stack.push(param)
      }
      validate_expr(ctx, else_stack, else_body)
      else_stack.check_height(results.length(), "if-else exit")
      // Pop label
      let _ = ctx.labels.pop()
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
    MultiValue(types) => types
    InlineType(_, results) => results
    TypeIndex(idx) =>
      if idx < ctx.types.length() {
        ctx.types[idx].results
      } else {
        []
      }
  }
}

///|
fn get_block_params(
  ctx : ValidationContext,
  bt : @types.BlockType,
) -> Array[@types.ValueType] {
  match bt {
    Empty => []
    Value(_) => [] // Single value blocks have no params
    MultiValue(_) => [] // MultiValue blocks have no params (result-only)
    InlineType(params, _) => params
    TypeIndex(idx) =>
      if idx < ctx.types.length() {
        ctx.types[idx].params
      } else {
        []
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
) -> Array[@types.ValueType] {
  match label.kind {
    BlockLabel => get_block_results(ctx, label.block_type)
    LoopLabel => get_block_params(ctx, label.block_type)
  }
}
