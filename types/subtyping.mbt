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
  types1 : Array[SubType]
  types2 : Array[SubType]
  rec_groups1 : Array[Int]
  rec_groups2 : Array[Int]
  canonical1 : Array[Int]
  canonical2 : Array[Int]
  cross_module : Bool
  visited : Map[(Int, Int), Bool]
}

///|
/// Create a context for same-module subtyping.
pub fn SubtypingContext::same_module(
  types : Array[SubType],
  rec_groups? : Array[Int] = [],
  canonical? : Array[Int] = [],
) -> SubtypingContext {
  {
    types1: types,
    types2: types,
    rec_groups1: rec_groups,
    rec_groups2: rec_groups,
    canonical1: canonical,
    canonical2: canonical,
    cross_module: false,
    visited: {},
  }
}

///|
/// Create a context for cross-module subtyping (e.g., import validation).
pub fn SubtypingContext::cross_module(
  types1 : Array[SubType],
  types2 : Array[SubType],
  rec_groups1? : Array[Int] = [],
  rec_groups2? : Array[Int] = [],
  canonical1? : Array[Int] = [],
  canonical2? : Array[Int] = [],
) -> SubtypingContext {
  {
    types1,
    types2,
    rec_groups1,
    rec_groups2,
    canonical1,
    canonical2,
    cross_module: true,
    visited: {},
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
  idx1 : Int,
  idx2 : Int,
) -> Bool {
  // Same index in same module means same type
  if not(self.cross_module) && idx1 == idx2 {
    return true
  }
  // Bounds check
  if idx1 < 0 ||
    idx1 >= self.types1.length() ||
    idx2 < 0 ||
    idx2 >= self.types2.length() {
    return false
  }
  // Check cache to handle cycles
  let key = (idx1, idx2)
  match self.visited.get(key) {
    Some(result) => return result
    None => ()
  }
  // Assume true to break cycles (if we reach here again, types are compatible)
  self.visited[key] = true

  // 1. Check type equality
  if self.cross_module {
    // For cross-module, use structural equivalence with rec group handling
    let equiv_ctx = TypeEquivalenceContext::cross_module(
      self.types1,
      self.types2,
      rec_groups1=self.rec_groups1,
      rec_groups2=self.rec_groups2,
    )
    if equiv_ctx.types_equivalent(idx1, idx2) {
      self.visited[key] = true
      return true
    }
    // For same-module, use canonical indices
  } else if self.canonical1.length() > 0 &&
    self.canonical2.length() > 0 &&
    idx1 < self.canonical1.length() &&
    idx2 < self.canonical2.length() {
    if self.canonical1[idx1] == self.canonical2[idx2] {
      self.visited[key] = true
      return true
    }
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
  idx1 : Int,
  idx2 : Int,
) -> Bool {
  match (c1, c2) {
    (Func(f1), Func(f2)) => self.func_subtype(f1, f2, idx1, idx2)
    (Struct(s1), Struct(s2)) => self.struct_subtype(s1, s2, idx1, idx2)
    (Array(a1), Array(a2)) => self.array_subtype(a1, a2, idx1, idx2)
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
  _idx1 : Int,
  _idx2 : Int,
) -> Bool {
  // Parameter and result counts must match
  if f1.params.length() != f2.params.length() ||
    f1.results.length() != f2.results.length() {
    return false
  }
  // Contravariant params: f2.params[i] <: f1.params[i]
  for i, p2 in f2.params {
    if not(self.value_type_subtype(p2, f1.params[i])) {
      return false
    }
  }
  // Covariant results: f1.results[i] <: f2.results[i]
  for i, r1 in f1.results {
    if not(self.value_type_subtype(r1, f2.results[i])) {
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
  idx1 : Int,
  idx2 : Int,
) -> Bool {
  // Width: subtype must have at least as many fields
  if s1.fields.length() < s2.fields.length() {
    return false
  }
  // Depth: each corresponding field must satisfy field subtyping
  for i, f2 in s2.fields {
    if not(self.field_subtype(s1.fields[i], f2, idx1, idx2)) {
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
  idx1 : Int,
  idx2 : Int,
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
  idx1 : Int,
  idx2 : Int,
) -> Bool {
  if f2.mutable {
    // Mutable fields require exact type equality (invariance)
    // Both must be mutable and storage types must be equal
    f1.mutable &&
    self.storage_types_equal(f1.storage_type, f2.storage_type, idx1, idx2)
  } else {
    // Immutable fields allow covariance
    // f1 can be mutable or immutable, but f1.type must be subtype of f2.type
    not(f1.mutable) &&
    self.storage_type_subtype(f1.storage_type, f2.storage_type, idx1, idx2)
  }
}

///|
/// Storage type subtyping.
fn SubtypingContext::storage_type_subtype(
  self : SubtypingContext,
  s1 : StorageType,
  s2 : StorageType,
  _idx1 : Int,
  _idx2 : Int,
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
  idx1 : Int,
  idx2 : Int,
) -> Bool {
  match (s1, s2) {
    (Val(v1), Val(v2)) => self.value_types_equal(v1, v2, idx1, idx2)
    (Packed(p1), Packed(p2)) => p1 == p2
    _ => false
  }
}

///|
/// Value type subtyping including abstract heap type hierarchy.
pub fn SubtypingContext::value_type_subtype(
  self : SubtypingContext,
  v1 : ValueType,
  v2 : ValueType,
  _idx1? : Int = 0,
  _idx2? : Int = 0,
) -> Bool {
  if v1 == v2 {
    return true
  }
  // Helper: check if a type is an internal reference type
  fn is_internal_ref(t : ValueType) -> Bool {
    match t {
      RefAny | AnyRef | RefEq | RefNullEq | RefI31 | RefNullI31 => true
      RefStruct(_) | RefNullStruct(_) | RefArray(_) | RefNullArray(_) => true
      RefNone | NullRef => true
      _ => false
    }
  }

  match (v1, v2) {
    // Non-null to nullable of same base type
    (RefFuncTyped(t1), RefNullFuncTyped(t2)) => self.is_subtype(t1, t2)
    (RefStruct(t1), RefNullStruct(t2)) => t2 == -1 || self.is_subtype(t1, t2)
    (RefArray(t1), RefNullArray(t2)) => t2 == -1 || self.is_subtype(t1, t2)
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
    // Struct/array/i31 to eqref
    (RefStruct(_), RefEq) => true
    (RefStruct(_), RefNullEq) => true
    (RefNullStruct(_), RefNullEq) => true
    (RefArray(_), RefEq) => true
    (RefArray(_), RefNullEq) => true
    (RefNullArray(_), RefNullEq) => true
    (RefI31, RefEq) => true
    (RefI31, RefNullEq) => true
    (RefNullI31, RefNullEq) => true
    // Everything internal to anyref
    (_, RefAny) => is_internal_ref(v1) && not(v1.is_nullable())
    (_, AnyRef) => is_internal_ref(v1)
    // Typed func refs to funcref
    (RefFuncTyped(_), RefFunc) => true
    (RefFuncTyped(_), FuncRef) => true
    (RefNullFuncTyped(_), FuncRef) => true
    // bottom types
    (RefNone, RefNullStruct(_)) => true
    (RefNone, RefNullArray(_)) => true
    (RefNone, RefNullEq) => true
    (RefNone, RefNullI31) => true
    (NullFuncRef, FuncRef) => true
    (NullExternRef, ExternRef) => true
    // Typed references subtyping via declared supertypes
    (RefFuncTyped(t1), RefFuncTyped(t2)) => self.is_subtype(t1, t2)
    (RefNullFuncTyped(t1), RefNullFuncTyped(t2)) => self.is_subtype(t1, t2)
    (RefStruct(t1), RefStruct(t2)) => self.is_subtype(t1, t2)
    (RefNullStruct(t1), RefNullStruct(t2)) => self.is_subtype(t1, t2)
    (RefArray(t1), RefArray(t2)) => self.is_subtype(t1, t2)
    (RefNullArray(t1), RefNullArray(t2)) => self.is_subtype(t1, t2)
    _ => false
  }
}

///|
/// Value type equality (for invariant contexts like mutable fields).
fn SubtypingContext::value_types_equal(
  self : SubtypingContext,
  v1 : ValueType,
  v2 : ValueType,
  _idx1 : Int,
  _idx2 : Int,
) -> Bool {
  if v1 == v2 {
    return true
  }
  // For typed references, check if they refer to equivalent types
  match (v1, v2) {
    (RefFuncTyped(t1), RefFuncTyped(t2)) => self.types_equivalent(t1, t2)
    (RefNullFuncTyped(t1), RefNullFuncTyped(t2)) =>
      self.types_equivalent(t1, t2)
    (RefStruct(t1), RefStruct(t2)) => self.types_equivalent(t1, t2)
    (RefNullStruct(t1), RefNullStruct(t2)) => self.types_equivalent(t1, t2)
    (RefArray(t1), RefArray(t2)) => self.types_equivalent(t1, t2)
    (RefNullArray(t1), RefNullArray(t2)) => self.types_equivalent(t1, t2)
    _ => false
  }
}

///|
/// Check type equivalence for invariant contexts.
/// Two types are equivalent if they have the same canonical index
/// or are structurally identical.
fn SubtypingContext::types_equivalent(
  self : SubtypingContext,
  t1 : Int,
  t2 : Int,
) -> Bool {
  // Same index in same module
  if not(self.cross_module) && t1 == t2 {
    return true
  }
  // Check canonical indices
  if self.canonical1.length() > 0 &&
    self.canonical2.length() > 0 &&
    t1 < self.canonical1.length() &&
    t2 < self.canonical2.length() {
    return self.canonical1[t1] == self.canonical2[t2]
  }
  // For cross-module without canonical indices, require exact structural match
  // This is a simplified check; full check would need TypeEquivalenceContext
  if t1 < 0 ||
    t1 >= self.types1.length() ||
    t2 < 0 ||
    t2 >= self.types2.length() {
    return false
  }
  self.types1[t1].composite == self.types2[t2].composite
}

///|
/// Validate that a declared subtype relationship is structurally valid.
/// This should be called during validation to ensure that when a type
/// declares a supertype, the subtype's structure is compatible.
pub fn SubtypingContext::validate_declared_subtype(
  self : SubtypingContext,
  sub_idx : Int,
  super_idx : Int,
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
    _ => false
  }
  if not(kind_matches) {
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
