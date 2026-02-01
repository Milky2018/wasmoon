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
        // ref.func produces (ref $t) where $t is the function's type index
        let type_idx = funcs[func_idx]
        type_stack.push(@types.ValueType::RefFuncTyped(type_idx))
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

  // Check the result type matches expected (with subtyping for references)
  let result_type = type_stack[0]
  if !is_const_expr_type_compatible(result_type, expected_type) {
    raise TypeMismatch(
      "constant expression: expected \{expected_type}, got \{result_type}",
    )
  }
}

///|
/// Check if a result type is compatible with an expected type in constant expressions
/// Handles reference type subtyping:
/// - RefFuncTyped(t) <: RefNullFuncTyped(t) <: FuncRef
/// - RefFuncTyped(t) <: FuncRef
fn is_const_expr_type_compatible(
  result : @types.ValueType,
  expected : @types.ValueType,
) -> Bool {
  if result == expected {
    return true
  }
  match (result, expected) {
    // RefFuncTyped(t) is subtype of RefNullFuncTyped(t)
    (RefFuncTyped(t1), RefNullFuncTyped(t2)) => t1 == t2
    // RefFuncTyped(t) is subtype of FuncRef (nullable abstract)
    (RefFuncTyped(_), FuncRef) => true
    // RefNullFuncTyped(t) is subtype of FuncRef
    (RefNullFuncTyped(_), FuncRef) => true
    // RefFunc is subtype of FuncRef
    (RefFunc, FuncRef) => true
    // RefExtern is subtype of ExternRef
    (RefExtern, ExternRef) => true
    _ => false
  }
}
