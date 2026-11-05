// Unified Subtyping API for WebAssembly GC
//
// This module provides a unified API for checking type subtyping,
// used by both the validator (compile-time) and executor (runtime).
// Implements the GC proposal subtyping rules including:
// - Function subtyping (contravariant params, covariant results)
// - Struct width + depth subtyping
// - Array element invariance for mutable, covariance for immutable
// - Field mutability variance

///|
/// Context for subtyping checks.
/// Can be used for same-module or cross-module comparisons.
pub struct SubtypingContext {
  types1 : ArrayView[SubType]
  types2 : ArrayView[SubType]
  rec_groups1 : ArrayView[Int32]
  rec_groups2 : ArrayView[Int32]
  canonical1 : ArrayView[Int32]
  canonical2 : ArrayView[Int32]
  cross_module : Bool
  visited : Map[(Int32, Int32), Bool]
}

///|
/// Create a context for same-module subtyping.
pub fn SubtypingContext::same_module(
  types : ArrayView[SubType],
  rec_groups~ : ArrayView[Int32] = [],
  canonical~ : ArrayView[Int32] = [],
) -> SubtypingContext {
  {
    types1: types,
    types2: types,
    rec_groups1: rec_groups,
    rec_groups2: rec_groups,
    canonical1: canonical,
    canonical2: canonical,
    cross_module: false,
    visited: Map([]),
  }
}

///|
/// Create a context for cross-module subtyping (e.g., import validation).
pub fn SubtypingContext::cross_module(
  types1 : ArrayView[SubType],
  types2 : ArrayView[SubType],
  rec_groups1~ : ArrayView[Int32] = [],
  rec_groups2~ : ArrayView[Int32] = [],
  canonical1~ : ArrayView[Int32] = [],
  canonical2~ : ArrayView[Int32] = [],
) -> SubtypingContext {
  {
    types1,
    types2,
    rec_groups1,
    rec_groups2,
    canonical1,
    canonical2,
    cross_module: true,
    visited: Map([]),
  }
}

///|
/// Check if type at idx1 is a subtype of type at idx2.
/// This is the main entry point for runtime type subtyping.
/// For WebAssembly GC isorecursive types, subtyping is based on:
/// 1. Type equality (via canonical indices)
/// 2. Declared supertype chain
/// Structural subtyping is NOT considered at runtime (only for validation).
pub fn SubtypingContext::is_subtype(
  self : SubtypingContext,
  idx1 : Int32,
  idx2 : Int32,
) -> Bool {
  if idx1 < 0 ||
    idx1 >= self.types1.length() ||
    idx2 < 0 ||
    idx2 >= self.types2.length() {
    return false
  }
  if !self.cross_module && idx1 == idx2 {
    return true
  }
  // Check cache to handle cycles
  let key = (idx1, idx2)
  if self.visited.get(key) is Some(result) {
    return result
  }
  // Assume true to break cycles (if we reach here again, types are compatible)
  self.visited[key] = true

  if self.types_equivalent(idx1, idx2) {
    self.visited[key] = true
    return true
  }
  let t1 = self.types1[idx1]
  // 2. Check if idx2 is in idx1's supertype chain (declared subtyping)
  for super_idx in t1.supertypes {
    if self.is_subtype(super_idx, idx2) {
      self.visited[key] = true
      return true
    }
  }
  // Isorecursive types: no structural subtyping at runtime
  self.visited[key] = false
  false
}

///|
/// Check if two composite types satisfy the subtyping relation.
fn SubtypingContext::composite_subtype(
  self : SubtypingContext,
  c1 : CompositeType,
  c2 : CompositeType,
  idx1 : Int32,
  idx2 : Int32,
) -> Bool {
  match (c1, c2) {
    (Func(f1), Func(f2)) => self.func_subtype(f1, f2, idx1, idx2)
    (Struct(s1), Struct(s2)) => self.struct_subtype(s1, s2, idx1, idx2)
    (Array(a1), Array(a2)) => self.array_subtype(a1, a2, idx1, idx2)
    (Cont(f1), Cont(f2)) => self.is_subtype(f1, f2)
    _ => false // Different composite types are never subtypes
  }
}

///|
/// Function subtyping: contravariant params, covariant results.
/// f1 <: f2 iff
///   |params| == |params| && |results| == |results| &&
///   forall i: f2.params[i] <: f1.params[i] (contravariant) &&
///   forall i: f1.results[i] <: f2.results[i] (covariant)
fn SubtypingContext::func_subtype(
  self : SubtypingContext,
  f1 : FuncType,
  f2 : FuncType,
  _idx1 : Int32,
  _idx2 : Int32,
) -> Bool {
  // Parameter and result counts must match
  if f1.params.length() != f2.params.length() ||
    f1.results.length() != f2.results.length() {
    return false
  }
  // Contravariant params: f2.params[i] <: f1.params[i]
  for i, p2 in f2.params {
    if !self.value_type_subtype(p2, f1.params[i]) {
      return false
    }
  }
  // Covariant results: f1.results[i] <: f2.results[i]
  for i, r1 in f1.results {
    if !self.value_type_subtype(r1, f2.results[i]) {
      return false
    }
  }
  true
}

///|
/// Struct subtyping: width + depth subtyping.
/// s1 <: s2 iff
///   |s1.fields| >= |s2.fields| &&
///   forall i < |s2.fields|: field_subtype(s1.fields[i], s2.fields[i])
fn SubtypingContext::struct_subtype(
  self : SubtypingContext,
  s1 : StructType,
  s2 : StructType,
  idx1 : Int32,
  idx2 : Int32,
) -> Bool {
  // Width: subtype must have at least as many fields
  if s1.fields.length() < s2.fields.length() {
    return false
  }
  // Depth: each corresponding field must satisfy field subtyping
  for i, f2 in s2.fields {
    if !self.field_subtype(s1.fields[i], f2, idx1, idx2) {
      return false
    }
  }
  true
}

///|
/// Array subtyping: invariant for mutable, covariant for immutable.
/// a1 <: a2 iff
///   if a2.element.mutable: element types must be equal (invariant)
///   else: a1.element <: a2.element (covariant)
fn SubtypingContext::array_subtype(
  self : SubtypingContext,
  a1 : ArrayType,
  a2 : ArrayType,
  idx1 : Int32,
  idx2 : Int32,
) -> Bool {
  self.field_subtype(a1.element, a2.element, idx1, idx2)
}

///|
/// Field subtyping with mutability variance rules.
/// For mutable fields: types must be exactly equal (invariant)
/// For immutable fields: f1.type <: f2.type (covariant)
fn SubtypingContext::field_subtype(
  self : SubtypingContext,
  f1 : FieldType,
  f2 : FieldType,
  idx1 : Int32,
  idx2 : Int32,
) -> Bool {
  if f2.mutable {
    // Mutable fields require exact type equality (invariance)
    // Both must be mutable and storage types must be equal
    f1.mutable &&
    self.storage_types_equal(f1.storage_type, f2.storage_type, idx1, idx2)
  } else {
    // Immutable fields allow covariance
    // f1 can be mutable or immutable, but f1.type must be subtype of f2.type
    !f1.mutable &&
    self.storage_type_subtype(f1.storage_type, f2.storage_type, idx1, idx2)
  }
}

///|
/// Storage type subtyping.
fn SubtypingContext::storage_type_subtype(
  self : SubtypingContext,
  s1 : StorageType,
  s2 : StorageType,
  _idx1 : Int32,
  _idx2 : Int32,
) -> Bool {
  match (s1, s2) {
    (Val(v1), Val(v2)) => self.value_type_subtype(v1, v2)
    (Packed(p1), Packed(p2)) => p1 == p2
    _ => false
  }
}

///|
/// Storage type equality (for invariant contexts).
fn SubtypingContext::storage_types_equal(
  self : SubtypingContext,
  s1 : StorageType,
  s2 : StorageType,
  idx1 : Int32,
  idx2 : Int32,
) -> Bool {
  match (s1, s2) {
    (Val(v1), Val(v2)) => self.value_types_equal(v1, v2, idx1, idx2)
    (Packed(p1), Packed(p2)) => p1 == p2
    _ => false
  }
}

///|
pub fn ValueType::is_reference(self : ValueType) -> Bool {
  match self {
    I32 | I64 | F32 | F64 | V128 => false
    _ => true
  }
}

///|
/// Concrete type indices must be compared in their defining modules.
fn indexed_reference_pair(
  actual : ValueType,
  expected : ValueType,
) -> (Int32, Int32)? {
  match (actual, expected) {
    (RefFuncTyped(a), RefFuncTyped(b) | RefNullFuncTyped(b))
    | (RefNullFuncTyped(a), RefNullFuncTyped(b))
    | (RefContTyped(a), RefContTyped(b) | RefNullContTyped(b))
    | (RefNullContTyped(a), RefNullContTyped(b)) => Some((a, b))
    (RefStruct(a), RefStruct(b) | RefNullStruct(b))
    | (RefNullStruct(a), RefNullStruct(b))
    | (RefArray(a), RefArray(b) | RefNullArray(b))
    | (RefNullArray(a), RefNullArray(b)) if b != -1 => Some((a, b))
    _ => None
  }
}

///|
fn ValueType::is_internal_reference(self : ValueType) -> Bool {
  match self {
    RefAny
    | AnyRef
    | RefEq
    | RefNullEq
    | RefI31
    | RefNullI31
    | RefStruct(_)
    | RefNullStruct(_)
    | RefArray(_)
    | RefNullArray(_)
    | RefNone
    | NullRef => true
    _ => false
  }
}

///|
fn non_indexed_subtype(actual : ValueType, expected : ValueType) -> Bool {
  if actual == expected {
    return true
  }
  match (actual, expected) {
    (RefNoCont, _) => expected.is_continuation_ref()
    (NullContRef, _) => expected.is_continuation_ref() && expected.is_nullable()
    (RefCont | RefContTyped(_) | RefNullContTyped(_), ContRef)
    | (RefContTyped(_), RefCont) => true
    (RefI31, RefNullI31)
    | (RefEq, RefNullEq)
    | (RefAny, AnyRef)
    | (RefFunc | RefFuncTyped(_) | RefNullFuncTyped(_) | NullFuncRef, FuncRef)
    | (RefFuncTyped(_), RefFunc)
    | (RefExtern | NullExternRef, ExternRef) => true
    (RefStruct(_), RefStruct(-1) | RefNullStruct(-1))
    | (RefNullStruct(_), RefNullStruct(-1))
    | (RefArray(_), RefArray(-1) | RefNullArray(-1))
    | (RefNullArray(_), RefNullArray(-1)) => true
    (RefStruct(_) | RefArray(_) | RefI31, RefEq | RefNullEq)
    | (RefNullStruct(_) | RefNullArray(_) | RefNullI31, RefNullEq)
    | (RefNone, RefNullStruct(_) | RefNullArray(_) | RefNullEq | RefNullI31) =>
      true
    (_, RefAny) => actual.is_internal_reference() && !actual.is_nullable()
    (_, AnyRef) => actual.is_internal_reference()
    _ => false
  }
}

///|
/// Compare types whose concrete indices are already in the same index space.
/// The validator also uses generalized bottom types for its operand stack.
pub fn value_type_subtype_without_context(
  actual : ValueType,
  expected : ValueType,
) -> Bool {
  if actual == expected {
    return true
  }
  if !expected.is_continuation_ref() &&
    (
      (actual == RefNone && expected.is_reference()) ||
      (actual == NullRef && expected.is_nullable())
    ) {
    return true
  }
  if indexed_reference_pair(actual, expected) is Some((a, b)) {
    return a == b
  }
  match (actual, expected) {
    (NullFuncRef, RefNullFuncTyped(_)) | (NullExnRef, ExnRef) => true
    _ => non_indexed_subtype(actual, expected)
  }
}

///|
/// Value type subtyping including abstract heap type hierarchy.
pub fn SubtypingContext::value_type_subtype(
  self : SubtypingContext,
  v1 : ValueType,
  v2 : ValueType,
  _idx1~ : Int32 = 0,
  _idx2~ : Int32 = 0,
) -> Bool {
  match indexed_reference_pair(v1, v2) {
    Some((a, b)) => self.is_subtype(a, b)
    None => non_indexed_subtype(v1, v2)
  }
}

///|
/// Value type equality (for invariant contexts like mutable fields).
fn SubtypingContext::value_types_equal(
  self : SubtypingContext,
  v1 : ValueType,
  v2 : ValueType,
  _idx1 : Int32,
  _idx2 : Int32,
) -> Bool {
  match (v1, v2) {
    (RefFuncTyped(t1), RefFuncTyped(t2))
    | (RefNullFuncTyped(t1), RefNullFuncTyped(t2))
    | (RefContTyped(t1), RefContTyped(t2))
    | (RefNullContTyped(t1), RefNullContTyped(t2)) =>
      self.types_equivalent(t1, t2)
    (RefStruct(t1), RefStruct(t2))
    | (RefNullStruct(t1), RefNullStruct(t2))
    | (RefArray(t1), RefArray(t2))
    | (RefNullArray(t1), RefNullArray(t2)) =>
      if t1 == -1 || t2 == -1 {
        t1 == t2
      } else {
        self.types_equivalent(t1, t2)
      }
    _ => v1 == v2
  }
}

///|
/// Compare invariant types in their defining recursive type graphs.
fn SubtypingContext::types_equivalent(
  self : SubtypingContext,
  t1 : Int32,
  t2 : Int32,
) -> Bool {
  if t1 < 0 ||
    t1 >= self.types1.length() ||
    t2 < 0 ||
    t2 >= self.types2.length() {
    return false
  }
  if !self.cross_module {
    if t1 == t2 {
      return true
    }
    if t1 < self.canonical1.length() && t2 < self.canonical2.length() {
      return self.canonical1[t1] == self.canonical2[t2]
    }
    TypeEquivalenceContext::same_module(
      self.types1,
      type_rec_groups=self.rec_groups1,
    ).types_equivalent(t1, t2)
  } else {
    TypeEquivalenceContext::cross_module(
      self.types1,
      self.types2,
      rec_groups1=self.rec_groups1,
      rec_groups2=self.rec_groups2,
    ).types_equivalent(t1, t2)
  }
}

///|
/// Validate that a declared subtype relationship is structurally valid.
/// This should be called during validation to ensure that when a type
/// declares a supertype, the subtype's structure is compatible.
pub fn SubtypingContext::validate_declared_subtype(
  self : SubtypingContext,
  sub_idx : Int32,
  super_idx : Int32,
) -> Bool {
  if sub_idx < 0 ||
    sub_idx >= self.types1.length() ||
    super_idx < 0 ||
    super_idx >= self.types2.length() {
    return false
  }
  let sub_type = self.types1[sub_idx]
  let super_type = self.types2[super_idx]
  // Supertype must not be final
  if super_type.final_ {
    return false
  }
  // Composite type kinds must match
  let kind_matches = match (sub_type.composite, super_type.composite) {
    (Func(_), Func(_)) => true
    (Struct(_), Struct(_)) => true
    (Array(_), Array(_)) => true
    (Cont(_), Cont(_)) => true
    _ => false
  }
  if !kind_matches {
    return false
  }
  // Structural subtyping must hold
  self.composite_subtype(
    sub_type.composite,
    super_type.composite,
    sub_idx,
    super_idx,
  )
}
