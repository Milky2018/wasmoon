///|
/// Operand stack for type validation
/// Uses Option to represent polymorphic stack (after unreachable)
priv struct OperandStack {
  stack : Array[@types.ValueType]
  mut polymorphic : Bool // true after unreachable instruction
  subtyping_ctx : @types.SubtypingContext
}

///|
fn OperandStack::new_with_subtyping(
  subtyping_ctx : @types.SubtypingContext,
) -> OperandStack {
  { stack: [], polymorphic: false, subtyping_ctx, }
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
  match self.stack.pop() {
    Some(actual) =>
      if !is_type_subtype(actual, expected) &&
        !self.subtyping_ctx.value_type_subtype(actual, expected) {
        raise TypeMismatch("Expected \{expected}, got \{actual}")
      }
    None if self.polymorphic => ()
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
    ContRef => RefCont
    NullContRef => RefNoCont
    RefNullContTyped(idx) => RefContTyped(idx)
    FuncRef => RefFunc
    ExternRef => RefExtern
    AnyRef => RefAny
    StructRef => RefStruct(-1)
    ArrayRef => RefArray(-1)
    RefNullFuncTyped(idx) => RefFuncTyped(idx)
    RefNullStruct(idx) => if idx < 0 { RefStruct(-1) } else { RefStruct(idx) }
    RefNullArray(idx) => if idx < 0 { RefArray(-1) } else { RefArray(idx) }
    RefNullEq => RefEq
    RefNullI31 => RefI31
    NullRef | NullFuncRef | NullExternRef | NullExnRef => RefNone
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
  if source.is_nullable() && target.is_nullable() {
    return to_non_nullable_cast_diff_type(source)
  }
  source
}

///|
fn is_type_subtype(
  actual : @types.ValueType,
  expected : @types.ValueType,
) -> Bool {
  @types.value_type_subtype_without_context(actual, expected)
}

///|
fn is_subtype_of_eqref(value_type : @types.ValueType) -> Bool {
  is_type_subtype(value_type, RefNullEq)
}

///|
fn OperandStack::pop_any(
  self : OperandStack,
) -> @types.ValueType raise ValidationError {
  self.pop_any_or_unknown().unwrap_or(I32)
}

///|
/// Pop any value type from stack, or return `None` for synthesized values
/// in polymorphic-unreachable context.
fn OperandStack::pop_any_or_unknown(
  self : OperandStack,
) -> @types.ValueType? raise ValidationError {
  let actual = self.stack.pop()
  if actual is None && !self.polymorphic {
    raise StackUnderflow("Expected value, but stack is empty")
  }
  actual
}

///|
/// Pop a reference value type from the stack.
/// In polymorphic-unreachable state, synthesize `nullref` as the bottom ref.
fn OperandStack::pop_ref_any(
  self : OperandStack,
) -> @types.ValueType raise ValidationError {
  if self.polymorphic && self.stack.is_empty() {
    return NullRef
  }
  let actual = self.pop_any()
  if !actual.is_reference() {
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
}

///|
/// Check that stack has exactly the expected height
/// Polymorphic stacks may synthesize missing values, but cannot leave extra values.
fn OperandStack::check_height(
  self : OperandStack,
  expected : Int32,
  context : String,
) -> Unit raise ValidationError {
  let actual = self.stack.length()
  if self.polymorphic {
    if actual > expected {
      raise StackHeightMismatch(
        "\{context}: expected stack height \{expected}, got at least \{actual} values after unreachable code",
      )
    }
  } else if actual != expected {
    raise StackHeightMismatch(
      "\{context}: expected stack height \{expected}, got \{actual}",
    )
  }
}
