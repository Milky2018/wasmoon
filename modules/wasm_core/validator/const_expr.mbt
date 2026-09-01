///|
/// Validate a constant expression (used in data/elem offsets and global init)
/// Returns the result type of the expression
/// Supports extended-const proposal: allows i32/i64 arithmetic (add, sub, mul)
fn validate_const_expr(
  globals : ArrayView[@types.GlobalType],
  expr : Array[@types.Instruction],
  expected_type : @types.ValueType,
  funcs? : Array[Int] = [],
  types? : Array[@types.SubType] = [],
  subtyping_ctx? : @types.SubtypingContext? = None,
) -> Unit raise ValidationError {
  if expr.is_empty() {
    raise TypeMismatch("empty constant expression")
  }

  // Use stack-based type checking for extended constant expressions
  let type_stack : Array[@types.ValueType] = []
  fn pop_expected(
    expected : @types.ValueType,
    op : String,
  ) -> Unit raise ValidationError {
    if type_stack.length() < 1 {
      raise StackUnderflow("\{op} in constant expression")
    }
    let actual = type_stack.pop().unwrap()
    if !is_const_expr_type_compatible(actual, expected, subtyping_ctx~) {
      raise TypeMismatch("\{op}: expected \{expected}, got \{actual}")
    }
  }
  for instr in expr {
    match instr {
      I32Const(_) => type_stack.push(I32)
      I64Const(_) => type_stack.push(I64)
      F32Const(_) => type_stack.push(F32)
      F64Const(_) => type_stack.push(F64)
      V128Const(_) => type_stack.push(V128)
      RefNull(t) => type_stack.push(t)
      RefFunc(func_idx) => {
        if func_idx >= funcs.length() {
          raise InvalidFunctionIndex(func_idx)
        }
        // ref.func produces (ref $t) where $t is the function's type index
        let type_idx = funcs[func_idx]
        type_stack.push(RefFuncTyped(type_idx))
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
      RefI31 => {
        pop_expected(I32, "ref.i31")
        type_stack.push(RefI31)
      }
      AnyConvertExtern => {
        pop_expected(ExternRef, "any.convert_extern")
        type_stack.push(AnyRef)
      }
      ExternConvertAny => {
        pop_expected(AnyRef, "extern.convert_any")
        type_stack.push(ExternRef)
      }
      StructNew(type_idx) => {
        let struct_type = get_const_expr_struct_type(types, type_idx)
        for i = struct_type.fields.length() - 1; i >= 0; i = i - 1 {
          let field_ty = const_expr_storage_type_to_value_type(
            struct_type.fields[i].storage_type,
          )
          pop_expected(field_ty, "struct.new")
        }
        type_stack.push(RefStruct(type_idx))
      }
      StructNewDefault(type_idx) => {
        ignore(get_const_expr_struct_type(types, type_idx))
        type_stack.push(RefStruct(type_idx))
      }
      ArrayNew(type_idx) => {
        let array_type = get_const_expr_array_type(types, type_idx)
        pop_expected(I32, "array.new length")
        let elem_ty = const_expr_storage_type_to_value_type(
          array_type.element.storage_type,
        )
        pop_expected(elem_ty, "array.new value")
        type_stack.push(RefArray(type_idx))
      }
      ArrayNewDefault(type_idx) => {
        ignore(get_const_expr_array_type(types, type_idx))
        pop_expected(I32, "array.new_default length")
        type_stack.push(RefArray(type_idx))
      }
      ArrayNewFixed(type_idx, len) => {
        let array_type = get_const_expr_array_type(types, type_idx)
        let elem_ty = const_expr_storage_type_to_value_type(
          array_type.element.storage_type,
        )
        for _ in 0..<len {
          pop_expected(elem_ty, "array.new_fixed value")
        }
        type_stack.push(RefArray(type_idx))
      }
      // Extended-const: i32 arithmetic
      I32Add | I32Sub | I32Mul => {
        if type_stack.length() < 2 {
          raise StackUnderflow("i32 arithmetic in constant expression")
        }
        let b = type_stack.pop().unwrap()
        let a = type_stack.pop().unwrap()
        if a != I32 || b != I32 {
          raise TypeMismatch("i32 arithmetic requires i32 operands")
        }
        type_stack.push(I32)
      }
      // Extended-const: i64 arithmetic
      I64Add | I64Sub | I64Mul => {
        if type_stack.length() < 2 {
          raise StackUnderflow("i64 arithmetic in constant expression")
        }
        let b = type_stack.pop().unwrap()
        let a = type_stack.pop().unwrap()
        if a != I64 || b != I64 {
          raise TypeMismatch("i64 arithmetic requires i64 operands")
        }
        type_stack.push(I64)
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
  if !is_const_expr_type_compatible(result_type, expected_type, subtyping_ctx~) {
    raise TypeMismatch(
      "constant expression: expected \{expected_type}, got \{result_type}",
    )
  }
}

///|
fn const_expr_storage_type_to_value_type(
  storage_type : @types.StorageType,
) -> @types.ValueType {
  match storage_type {
    Val(v) => v
    Packed(_) => I32
  }
}

///|
fn get_const_expr_struct_type(
  types : Array[@types.SubType],
  type_idx : Int,
) -> @types.StructType raise ValidationError {
  if type_idx < 0 || type_idx >= types.length() {
    raise InvalidTypeIndex(type_idx)
  }
  match types[type_idx].composite {
    Struct(s) => s
    _ =>
      raise TypeMismatch(
        "constant expression type \{type_idx} is not a struct type",
      )
  }
}

///|
fn get_const_expr_array_type(
  types : Array[@types.SubType],
  type_idx : Int,
) -> @types.ArrayType raise ValidationError {
  if type_idx < 0 || type_idx >= types.length() {
    raise InvalidTypeIndex(type_idx)
  }
  match types[type_idx].composite {
    Array(a) => a
    _ =>
      raise TypeMismatch(
        "constant expression type \{type_idx} is not an array type",
      )
  }
}

///|
/// Check if a result type is compatible with an expected type in constant expressions
fn is_const_expr_type_compatible(
  result : @types.ValueType,
  expected : @types.ValueType,
  subtyping_ctx? : @types.SubtypingContext? = None,
) -> Bool {
  if subtyping_ctx is Some(ctx) {
    if ctx.value_type_subtype(result, expected) {
      return true
    }
  }
  is_type_subtype(result, expected)
}
