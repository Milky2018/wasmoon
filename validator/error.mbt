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
  InvalidDataIndex(Int) // Unknown data segment index
  UnknownTag(Int) // Unknown tag index
  UnknownType(Int) // Forward type reference outside rec group
  UnreachableCode
  MultipleMemories // More than one memory is not allowed in MVP
  MultipleTables // More than one table is not allowed in MVP
  InvalidLimits(String) // Invalid limits (e.g., min > max)
  InvalidAlignment(String) // Alignment must not be larger than natural
  InvalidLaneIndex(Int, Int) // lane index, max lanes
  ConstantExpressionRequired // Non-constant instruction in init expression
  MutableGlobalInConstExpr // Mutable global referenced in constant expression
  DuplicateExportName(String) // Same export name used more than once
  UnknownExport(String) // Export references unknown entity
  UninitializedLocal(Int) // Non-nullable ref local read before initialization
  InvalidStartFunction(String) // Start function has invalid signature
  UndeclaredFunctionReference(Int) // ref.func used on function not declared in elem/global
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
    InvalidTypeIndex(idx) => "unknown type: \{idx}"
    InvalidLocalIndex(idx) => "invalid local index: \{idx}"
    InvalidGlobalIndex(idx) => "invalid global index: \{idx}"
    InvalidTableIndex(idx) => "invalid table index: \{idx}"
    InvalidMemoryIndex(idx) => "invalid memory index: \{idx}"
    InvalidLabelIndex(idx) => "invalid label index: \{idx}"
    InvalidElemIndex(idx) => "unknown elem segment \{idx}"
    InvalidDataIndex(idx) => "unknown data segment \{idx}"
    UnknownTag(idx) => "unknown tag \{idx}"
    UnknownType(_) => "unknown type"
    UnreachableCode => "unreachable code"
    MultipleMemories => "multiple memories not allowed in MVP"
    MultipleTables => "multiple tables not allowed in MVP"
    InvalidLimits(m) => "invalid limits: \{m}"
    InvalidAlignment(m) => "alignment must not be larger than natural: \{m}"
    InvalidLaneIndex(lane, max) =>
      "invalid lane index: \{lane} (max: \{max - 1})"
    ConstantExpressionRequired => "constant expression required"
    MutableGlobalInConstExpr => "constant expression required"
    DuplicateExportName(name) => "duplicate export name: \{name}"
    UnknownExport(m) => m
    UninitializedLocal(_) => "uninitialized local"
    InvalidStartFunction(m) => m
    UndeclaredFunctionReference(_) => "undeclared function reference"
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
