///|
pub(all) suberror RuntimeError {
  StackUnderflow
  StackOverflow
  TypeMismatch
  OutOfBoundsMemoryAccess
  OutOfBoundsTableAccess
  OutOfBoundsArrayAccess // GC array access out of bounds
  UndefinedElement
  UninitializedElement
  IndirectCallTypeMismatch
  DivisionByZero
  IntegerOverflow
  InvalidConversion
  Unreachable
  CallStackExhausted
  UnknownImport(String, String) // Import not found: (module_name, field_name)
  LinkError // Import type mismatch during linking
  NullReference // Null exception reference (null exnref thrown)
  UnalignedAtomic
}

///|
/// Custom Show implementation for WebAssembly-spec-compliant error messages
pub impl Show for RuntimeError with output(self, logger) {
  let msg = match self {
    StackUnderflow => "stack underflow"
    StackOverflow => "stack overflow"
    TypeMismatch => "type mismatch"
    OutOfBoundsMemoryAccess => "out of bounds memory access"
    OutOfBoundsTableAccess => "out of bounds table access"
    OutOfBoundsArrayAccess => "out of bounds array access"
    UndefinedElement => "undefined element"
    UninitializedElement => "uninitialized element"
    IndirectCallTypeMismatch => "indirect call type mismatch"
    DivisionByZero => "integer divide by zero"
    IntegerOverflow => "integer overflow"
    InvalidConversion => "invalid conversion to integer"
    Unreachable => "unreachable"
    CallStackExhausted => "call stack exhausted"
    UnknownImport(mod_name, field_name) =>
      "unknown import: \{mod_name}.\{field_name}"
    LinkError => "link error"
    NullReference => "null reference"
    UnalignedAtomic => "unaligned atomic"
  }
  logger.write_string(msg)
}

///|
/// A stack frame entry for error reporting
pub(all) struct CallStackEntry {
  func_idx : Int
  func_name : String? // Optional function name from debug info
}

///|
fn CallStackEntry::to_string(self : CallStackEntry) -> String {
  match self.func_name {
    Some(name) => "func[\{self.func_idx}] \{name}"
    None => "func[\{self.func_idx}]"
  }
}

///|
/// Runtime error with additional context for debugging
pub struct RuntimeErrorContext {
  error : RuntimeError
  call_stack : Array[CallStackEntry]
  instruction : String? // The instruction that caused the error
  func_idx : Int? // The function index where error occurred
}

///|
pub fn RuntimeErrorContext::new(error : RuntimeError) -> RuntimeErrorContext {
  { error, call_stack: [], instruction: None, func_idx: None }
}

///|
pub fn RuntimeErrorContext::with_call_stack(
  self : RuntimeErrorContext,
  stack : Array[CallStackEntry],
) -> RuntimeErrorContext {
  { ..self, call_stack: stack }
}

///|
pub fn RuntimeErrorContext::with_instruction(
  self : RuntimeErrorContext,
  instr : String,
) -> RuntimeErrorContext {
  { ..self, instruction: Some(instr) }
}

///|
pub fn RuntimeErrorContext::with_func_idx(
  self : RuntimeErrorContext,
  idx : Int,
) -> RuntimeErrorContext {
  { ..self, func_idx: Some(idx) }
}

///|
/// Format the runtime error with full context for display
pub fn RuntimeErrorContext::format(self : RuntimeErrorContext) -> String {
  let result = StringBuilder::new()
  result.write_string("runtime error: ")
  result.write_string(self.error.to_string())
  result.write_string("\n")

  // Show instruction if available
  if self.instruction is Some(instr) {
    result.write_string("  at instruction: ")
    result.write_string(instr)
    result.write_string("\n")
  }

  // Show function index if available
  if self.func_idx is Some(idx) {
    result.write_string("  in function: func[\{idx}]\n")
  }

  // Show call stack
  if self.call_stack.length() > 0 {
    result.write_string("\ncall stack (most recent call last):\n")
    for i, entry in self.call_stack {
      result.write_string("  \{i}: ")
      result.write_string(entry.to_string())
      result.write_string("\n")
    }
  }
  result.to_string()
}

///|
pub impl Show for RuntimeErrorContext with output(self, logger) {
  logger.write_string(self.format())
}

///|
/// Format a basic RuntimeError without context
pub fn format_runtime_error(error : RuntimeError) -> String {
  RuntimeErrorContext::new(error).format()
}
