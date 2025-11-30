// IR Validator
// Validates that IR is well-formed and type-correct

///|
/// Result of IR validation
pub(all) struct ValidationResult {
  mut valid : Bool
  errors : Array[String]
}

///|
pub fn ValidationResult::new() -> ValidationResult {
  { valid: true, errors: [] }
}

///|
fn ValidationResult::add_error(self : ValidationResult, error : String) -> Unit {
  self.valid = false
  self.errors.push(error)
}

///|
/// Validate a function's IR
pub fn validate_function(func : Function) -> ValidationResult {
  let result = ValidationResult::new()
  // Track all defined values
  let defined_values : @hashmap.HashMap[Int, Type] = @hashmap.new()
  // Add function parameters as defined
  for param in func.params {
    let (v, ty) = param
    defined_values.set(v.id, ty)
  }
  // Validate each block
  for block in func.blocks {
    // Add block parameters as defined
    for param in block.params {
      let (v, ty) = param
      defined_values.set(v.id, ty)
    }
    // Validate instructions
    for inst in block.instructions {
      validate_instruction(inst, defined_values, result)
      // Add result to defined values
      match inst.result {
        Some(v) => defined_values.set(v.id, v.ty)
        None => ()
      }
    }
    // Validate terminator
    match block.terminator {
      Some(term) => validate_terminator(term, defined_values, func, result)
      None => result.add_error("Block \{block.id} has no terminator")
    }
  }
  // Check that entry block exists
  if func.blocks.length() == 0 {
    result.add_error("Function has no blocks")
  }
  result
}

///|
/// Validate an instruction
fn validate_instruction(
  inst : Inst,
  defined : @hashmap.HashMap[Int, Type],
  result : ValidationResult,
) -> Unit {
  // Check that all operands are defined
  for op in inst.operands {
    if not(defined.contains(op.id)) {
      result.add_error("Operand v\{op.id} is not defined")
    }
  }
  // Type-check based on opcode
  match inst.opcode {
    // Binary integer operations
    Iadd
    | Isub
    | Imul
    | Sdiv
    | Udiv
    | Srem
    | Urem
    | Band
    | Bor
    | Bxor
    | Ishl
    | Sshr
    | Ushr
    | Rotl
    | Rotr =>
      if inst.operands.length() != 2 {
        result.add_error(
          "Binary operation expects 2 operands, got \{inst.operands.length()}",
        )
      } else {
        let a = inst.operands[0]
        let b = inst.operands[1]
        // Operands should have matching integer types
        if not(is_integer_type(a.ty)) {
          result.add_error(
            "Binary integer op expects integer operand, got \{a.ty}",
          )
        }
        if not(types_match(a.ty, b.ty)) {
          result.add_error(
            "Binary op operands have mismatched types: \{a.ty} vs \{b.ty}",
          )
        }
      }

    // Bitwise not (unary)
    Bnot =>
      if inst.operands.length() != 1 {
        result.add_error(
          "Bnot expects 1 operand, got \{inst.operands.length()}",
        )
      }

    // Integer comparisons
    Icmp(_) => {
      if inst.operands.length() != 2 {
        result.add_error(
          "Icmp expects 2 operands, got \{inst.operands.length()}",
        )
      }
      // Result should be i32
      match inst.result {
        Some(r) =>
          if not(types_match(r.ty, Type::I32)) {
            result.add_error("Icmp result should be i32, got \{r.ty}")
          }
        None => ()
      }
    }

    // Binary float operations
    Fadd | Fsub | Fmul | Fdiv | Fmin | Fmax =>
      if inst.operands.length() != 2 {
        result.add_error(
          "Binary float operation expects 2 operands, got \{inst.operands.length()}",
        )
      } else {
        let a = inst.operands[0]
        let b = inst.operands[1]
        if not(is_float_type(a.ty)) {
          result.add_error("Binary float op expects float operand, got \{a.ty}")
        }
        if not(types_match(a.ty, b.ty)) {
          result.add_error(
            "Binary op operands have mismatched types: \{a.ty} vs \{b.ty}",
          )
        }
      }

    // Float comparisons
    Fcmp(_) => {
      if inst.operands.length() != 2 {
        result.add_error(
          "Fcmp expects 2 operands, got \{inst.operands.length()}",
        )
      }
      // Result should be i32
      match inst.result {
        Some(r) =>
          if not(types_match(r.ty, Type::I32)) {
            result.add_error("Fcmp result should be i32, got \{r.ty}")
          }
        None => ()
      }
    }

    // Unary float operations
    Fneg | Fabs | Fsqrt | Fceil | Ffloor | Ftrunc | Fnearest =>
      if inst.operands.length() != 1 {
        result.add_error(
          "Unary float op expects 1 operand, got \{inst.operands.length()}",
        )
      }

    // Constants don't have operands
    Iconst(_) | Fconst(_) =>
      if inst.operands.length() != 0 {
        result.add_error(
          "Constant expects 0 operands, got \{inst.operands.length()}",
        )
      }

    // Select needs 3 operands (cond, true_val, false_val)
    Select =>
      if inst.operands.length() != 3 {
        result.add_error(
          "Select expects 3 operands, got \{inst.operands.length()}",
        )
      }

    // Load needs 1 operand (address)
    Load(_, _) =>
      if inst.operands.length() != 1 {
        result.add_error(
          "Load expects 1 operand (address), got \{inst.operands.length()}",
        )
      }

    // Store needs 2 operands (address, value)
    Store(_, _) =>
      if inst.operands.length() != 2 {
        result.add_error(
          "Store expects 2 operands (address, value), got \{inst.operands.length()}",
        )
      }

    // Conversions need 1 operand
    Ireduce
    | Sextend
    | Uextend
    | Fpromote
    | Fdemote
    | FcvtToSint
    | FcvtToUint
    | SintToFcvt
    | UintToFcvt
    | Bitcast =>
      if inst.operands.length() != 1 {
        result.add_error(
          "Conversion expects 1 operand, got \{inst.operands.length()}",
        )
      }

    // Copy needs 1 operand
    Copy =>
      if inst.operands.length() != 1 {
        result.add_error(
          "Copy expects 1 operand, got \{inst.operands.length()}",
        )
      }

    // Calls can have any number of operands
    Call(_) | CallIndirect(_) => ()
  }
}

///|
/// Validate a terminator
fn validate_terminator(
  term : Terminator,
  defined : @hashmap.HashMap[Int, Type],
  func : Function,
  result : ValidationResult,
) -> Unit {
  match term {
    Jump(target, args) => {
      // Check target block exists
      if target >= func.blocks.length() {
        result.add_error("Jump target block\{target} does not exist")
      } else {
        let target_block = func.blocks[target]
        // Check argument count matches
        if args.length() != target_block.params.length() {
          result.add_error(
            "Jump to block\{target} expects \{target_block.params.length()} args, got \{args.length()}",
          )
        }
      }
      // Check all args are defined
      for arg in args {
        if not(defined.contains(arg.id)) {
          result.add_error("Jump argument v\{arg.id} is not defined")
        }
      }
    }
    Brz(cond, then_target, else_target)
    | Brnz(cond, then_target, else_target) => {
      // Check condition is defined
      if not(defined.contains(cond.id)) {
        result.add_error("Branch condition v\{cond.id} is not defined")
      }
      // Check targets exist
      if then_target >= func.blocks.length() {
        result.add_error(
          "Branch then target block\{then_target} does not exist",
        )
      }
      if else_target >= func.blocks.length() {
        result.add_error(
          "Branch else target block\{else_target} does not exist",
        )
      }
    }
    BrTable(index, targets, default_target) => {
      // Check index is defined
      if not(defined.contains(index.id)) {
        result.add_error("BrTable index v\{index.id} is not defined")
      }
      // Check all targets exist
      for t in targets {
        if t >= func.blocks.length() {
          result.add_error("BrTable target block\{t} does not exist")
        }
      }
      if default_target >= func.blocks.length() {
        result.add_error(
          "BrTable default target block\{default_target} does not exist",
        )
      }
    }
    Return(values) => {
      // Check return value count matches function signature
      if values.length() != func.results.length() {
        result.add_error(
          "Return expects \{func.results.length()} values, got \{values.length()}",
        )
      }
      // Check all values are defined
      for v in values {
        if not(defined.contains(v.id)) {
          result.add_error("Return value v\{v.id} is not defined")
        }
      }
    }
    Trap(_) => () // Always valid
  }
}

///|
/// Check if a type is an integer type
fn is_integer_type(ty : Type) -> Bool {
  match ty {
    I32 | I64 => true
    _ => false
  }
}

///|
/// Check if a type is a float type
fn is_float_type(ty : Type) -> Bool {
  match ty {
    F32 | F64 => true
    _ => false
  }
}

///|
/// Check if two types match
fn types_match(a : Type, b : Type) -> Bool {
  match (a, b) {
    (I32, I32)
    | (I64, I64)
    | (F32, F32)
    | (F64, F64)
    | (FuncRef, FuncRef)
    | (ExternRef, ExternRef) => true
    _ => false
  }
}
