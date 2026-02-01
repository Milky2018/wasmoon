///|
/// Operand stack for type validation
/// Uses Option to represent polymorphic stack (after unreachable)
priv struct OperandStack {
  stack : Array[@types.ValueType]
  mut polymorphic : Bool // true after unreachable instruction
  mut underflow_limit : Int // stack height at which polymorphism was enabled
}

///|
fn OperandStack::new() -> OperandStack {
  { stack: [], polymorphic: false, underflow_limit: 0 }
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
      if !is_type_subtype(a, expected) {
        raise TypeMismatch("Expected \{expected}, got \{a}")
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
/// Compute the diff type for br_on_cast_fail.
/// The diff type represents values that would fail the cast from source to target.
/// Key rule: if source is nullable but target is non-nullable, null can fail the cast,
/// so the diff type must be nullable.
fn compute_br_on_cast_fail_diff_type(
  source : @types.ValueType,
  target : @types.ValueType,
) -> @types.ValueType {
  // If source is nullable and target is non-nullable, diff keeps source's nullability
  // This is because null values would fail the cast to non-nullable target
  let source_nullable = source.is_nullable()
  let target_nullable = target.is_nullable()
  if source_nullable && not(target_nullable) {
    // Source is nullable, target is not -> null can fail, diff is source (nullable)
    return source
  }
  // Otherwise diff type is source
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
  // Helper: check if a type is a subtype of anyref (AnyRef = ref null any)
  fn is_internal_ref(t : @types.ValueType) -> Bool {
    match t {
      RefAny | AnyRef | RefEq | RefNullEq | RefI31 | RefNullI31 => true
      RefStruct(_) | RefNullStruct(_) | RefArray(_) | RefNullArray(_) => true
      _ => false
    }
  }

  match (actual, expected) {
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
    (_, RefAny) => is_internal_ref(actual) && not(actual.is_nullable())
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
fn OperandStack::set_polymorphic(self : OperandStack) -> Unit {
  self.polymorphic = true
  self.underflow_limit = self.stack.length()
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
