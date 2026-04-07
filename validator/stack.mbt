///|
/// Operand stack for type validation
/// Uses Option to represent polymorphic stack (after unreachable)
priv struct OperandStack {
  stack : Array[@types.ValueType]
  mut polymorphic : Bool // true after unreachable instruction
  mut underflow_limit : Int // stack height at which polymorphism was enabled
  subtyping_ctx : @types.SubtypingContext?
}

///|
fn OperandStack::new_with_subtyping(
  subtyping_ctx : @types.SubtypingContext,
) -> OperandStack {
  {
    stack: [],
    polymorphic: false,
    underflow_limit: 0,
    subtyping_ctx: Some(subtyping_ctx),
  }
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
    Some(a) => {
      let basic_subtype = is_type_subtype(a, expected)
      let ctx_subtype = if basic_subtype {
        true
      } else if self.subtyping_ctx is Some(subtyping_ctx) {
        subtyping_ctx.value_type_subtype(a, expected)
      } else {
        false
      }
      if !ctx_subtype {
        raise TypeMismatch("Expected \{expected}, got \{a}")
      }
    }
    None => raise StackUnderflow("Expected \{expected}, but stack is empty")
  }
}

///|
/// Check if actual type is a subtype of expected type
/// Handles reference type subtyping for GC proposal
/// Type hierarchy:
///   anyref: eqref, i31ref, structref, arrayref, (ref $struct), (ref $array)
///   eqref: i31ref, structref, arrayref, (ref $struct), (ref $array)
///   funcref: (ref $func), (ref func)
///   externref: (ref extern)

///|
fn to_non_nullable_cast_diff_type(ty : @types.ValueType) -> @types.ValueType {
  match ty {
    FuncRef => @types.ValueType::RefFunc
    ExternRef => @types.ValueType::RefExtern
    AnyRef => @types.ValueType::RefAny
    StructRef => @types.ValueType::RefStruct(-1)
    ArrayRef => @types.ValueType::RefArray(-1)
    RefNullFuncTyped(idx) => @types.ValueType::RefFuncTyped(idx)
    RefNullStruct(idx) =>
      if idx < 0 {
        @types.ValueType::RefStruct(-1)
      } else {
        @types.ValueType::RefStruct(idx)
      }
    RefNullArray(idx) =>
      if idx < 0 {
        @types.ValueType::RefArray(-1)
      } else {
        @types.ValueType::RefArray(idx)
      }
    RefNullEq => @types.ValueType::RefEq
    RefNullI31 => @types.ValueType::RefI31
    NullRef | NullFuncRef | NullExternRef | NullExnRef =>
      @types.ValueType::RefNone
    _ => ty
  }
}

///|
/// Compute the diff type for br_on_cast_fail.
/// The diff type represents values that would fail the cast from source to target.
/// Key rule: if source is nullable but target is non-nullable, null can fail the cast,
/// so the diff type must be nullable.
fn compute_br_on_cast_fail_diff_type(
  source : @types.ValueType,
  target : @types.ValueType,
) -> @types.ValueType {
  // If both are nullable, success path consumes null, so fail path is non-null.
  // If source is nullable and target is non-null, null can fail the cast,
  // so fail path remains nullable.
  let source_nullable = source.is_nullable()
  let target_nullable = target.is_nullable()
  if source_nullable && target_nullable {
    return to_non_nullable_cast_diff_type(source)
  }
  if source_nullable && !target_nullable {
    return source
  }
  source
}

///|
fn is_type_subtype(
  actual : @types.ValueType,
  expected : @types.ValueType,
) -> Bool {
  if actual == expected {
    return true
  }
  // Bottom types for reference hierarchies.
  if actual == @types.ValueType::RefNone && is_reference_type(expected) {
    return true
  }
  if actual == @types.ValueType::NullRef && expected.is_nullable() {
    return true
  }
  // Helper: check if a type is a subtype of anyref (AnyRef = ref null any)
  fn is_internal_ref(t : @types.ValueType) -> Bool {
    match t {
      RefAny | AnyRef | RefEq | RefNullEq | RefI31 | RefNullI31 => true
      RefStruct(_) | RefNullStruct(_) | RefArray(_) | RefNullArray(_) => true
      _ => false
    }
  }

  match (actual, expected) {
    // Null bottoms for specific hierarchies
    (NullFuncRef, FuncRef) => true
    (NullFuncRef, RefNullFuncTyped(_)) => true
    (NullExternRef, ExternRef) => true
    (NullExnRef, ExnRef) => true

    // Non-null to nullable of same base type
    (RefFuncTyped(t1), RefNullFuncTyped(t2)) => t1 == t2
    (RefStruct(t1), RefNullStruct(t2)) => t1 == t2 || t2 == -1
    (RefArray(t1), RefNullArray(t2)) => t1 == t2 || t2 == -1
    (RefI31, RefNullI31) => true
    (RefEq, RefNullEq) => true
    (RefAny, AnyRef) => true
    (RefFunc, FuncRef) => true
    (RefExtern, ExternRef) => true

    // Typed to abstract struct/array
    (RefStruct(_), RefStruct(-1)) => true
    (RefNullStruct(_), RefNullStruct(-1)) => true
    (RefArray(_), RefArray(-1)) => true
    (RefNullArray(_), RefNullArray(-1)) => true

    // Struct/array/i31 to eqref (RefEq = ref eq, RefNullEq = ref null eq)
    (RefStruct(_), RefEq) => true
    (RefStruct(_), RefNullEq) => true
    (RefNullStruct(_), RefNullEq) => true
    (RefArray(_), RefEq) => true
    (RefArray(_), RefNullEq) => true
    (RefNullArray(_), RefNullEq) => true
    (RefI31, RefEq) => true
    (RefI31, RefNullEq) => true
    (RefNullI31, RefNullEq) => true

    // Everything internal to anyref (RefAny = ref any, AnyRef = ref null any)
    (_, RefAny) => is_internal_ref(actual) && !actual.is_nullable()
    (_, AnyRef) => is_internal_ref(actual)

    // RefFuncTyped to funcref hierarchy
    (RefFuncTyped(_), FuncRef) => true
    (RefNullFuncTyped(_), FuncRef) => true
    (RefFuncTyped(_), RefFunc) => true
    _ => false
  }
}

///|
/// Check if a type is a subtype of eqref.
/// eqref hierarchy: eqref > i31ref, structref, arrayref
/// anyref is NOT a subtype of eqref (it's a supertype)
/// funcref and externref are NOT subtypes of eqref
fn is_subtype_of_eqref(value_type : @types.ValueType) -> Bool {
  match value_type {
    // Direct eqref types
    RefEq | RefNullEq => true
    // i31ref is subtype of eqref
    RefI31 | RefNullI31 => true
    // structref is subtype of eqref
    RefStruct(_) | RefNullStruct(_) => true
    // arrayref is subtype of eqref
    RefArray(_) | RefNullArray(_) => true
    // Bottom types are subtypes of everything
    RefNone | NullRef => true
    // anyref is a SUPERtype of eqref, not subtype
    AnyRef | RefAny => false
    // funcref and externref are not related to eqref
    FuncRef | RefFunc | RefFuncTyped(_) | RefNullFuncTyped(_) | NullFuncRef =>
      false
    ExternRef | RefExtern | NullExternRef => false
    // Other types
    _ => false
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
/// Pop any value type from stack, or return `None` for synthesized values
/// in polymorphic-unreachable context.
fn OperandStack::pop_any_or_unknown(
  self : OperandStack,
) -> @types.ValueType? raise ValidationError {
  if self.polymorphic && self.stack.is_empty() {
    return None
  }
  if self.stack.is_empty() {
    raise StackUnderflow("Expected value, but stack is empty")
  }
  self.stack.pop()
}

///|
fn is_reference_type(ty : @types.ValueType) -> Bool {
  match ty {
    FuncRef
    | ExternRef
    | RefFunc
    | RefExtern
    | RefFuncTyped(_)
    | RefNullFuncTyped(_)
    | AnyRef
    | ExnRef
    | StructRef
    | ArrayRef
    | RefStruct(_)
    | RefNullStruct(_)
    | RefArray(_)
    | RefNullArray(_)
    | RefAny
    | RefEq
    | RefNullEq
    | RefI31
    | RefNullI31
    | RefStructAbs
    | RefArrayAbs
    | RefNone
    | NullRef
    | NullFuncRef
    | NullExnRef
    | NullExternRef => true
    _ => false
  }
}

///|
/// Pop a reference value type from the stack.
/// In polymorphic-unreachable state, synthesize `nullref` as the bottom ref.
fn OperandStack::pop_ref_any(
  self : OperandStack,
) -> @types.ValueType raise ValidationError {
  if self.polymorphic && self.stack.is_empty() {
    return @types.ValueType::NullRef
  }
  let actual = self.pop_any()
  if !is_reference_type(actual) {
    raise TypeMismatch("Expected reference type, got \{actual}")
  }
  actual
}

///|
fn OperandStack::set_polymorphic(self : OperandStack) -> Unit {
  // Entering unreachable code resets the operand stack to the
  // current control-frame base (which is 0 for each validation stack
  // used by validate_function / validate block bodies).
  self.stack.clear()
  self.polymorphic = true
  self.underflow_limit = 0
}

///|
/// Check that stack has exactly the expected height
/// In polymorphic mode, we can synthesize values from below the underflow_limit,
/// but actual values pushed after unreachable still count.
fn OperandStack::check_height(
  self : OperandStack,
  expected : Int,
  context : String,
) -> Unit raise ValidationError {
  let actual = self.stack.length()
  if self.polymorphic {
    // Values above underflow_limit are real values that were pushed after unreachable
    let real_values = actual - self.underflow_limit
    // We can synthesize up to (expected - real_values) values from the polymorphic stack,
    // but if we have more real values than expected, that's an error
    if real_values > expected {
      raise StackHeightMismatch(
        "\{context}: expected stack height \{expected}, got at least \{real_values} values after unreachable code",
      )
    }
  } else if actual != expected {
    raise StackHeightMismatch(
      "\{context}: expected stack height \{expected}, got \{actual}",
    )
  }
}
