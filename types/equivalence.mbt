// Type Equivalence - Unified type comparison for WebAssembly
//
// This module provides a unified API for checking type equivalence,
// handling both same-module and cross-module comparisons with proper
// support for recursive types and rec groups.

///|
/// Context for type equivalence checking.
/// Encapsulates all information needed for comparing types.
pub struct TypeEquivalenceContext {
  types1 : Array[FuncType]
  types2 : Array[FuncType]
  rec_groups1 : Array[Int]
  rec_groups2 : Array[Int]
  cross_module : Bool
  visited : Map[(Int, Int), Bool]
}

///|
/// Create a context for same-module type comparison.
pub fn TypeEquivalenceContext::same_module(
  types : Array[FuncType],
  type_rec_groups? : Array[Int] = [],
) -> TypeEquivalenceContext {
  {
    types1: types,
    types2: types,
    rec_groups1: type_rec_groups,
    rec_groups2: type_rec_groups,
    cross_module: false,
    visited: {},
  }
}

///|
/// Create a context for cross-module type comparison.
pub fn TypeEquivalenceContext::cross_module(
  types1 : Array[FuncType],
  types2 : Array[FuncType],
  rec_groups1? : Array[Int] = [],
  rec_groups2? : Array[Int] = [],
) -> TypeEquivalenceContext {
  { types1, types2, rec_groups1, rec_groups2, cross_module: true, visited: {} }
}

///|
/// Check if two types at given indices are equivalent.
/// This is the main entry point for type equivalence checking.
pub fn TypeEquivalenceContext::types_equivalent(
  self : TypeEquivalenceContext,
  idx1 : Int,
  idx2 : Int,
) -> Bool {
  // First check rec group info - types can only be equivalent if
  // they have the same position and size within their rec groups
  let rec_info1 = get_rec_group_info(self.rec_groups1, idx1)
  let rec_info2 = get_rec_group_info(self.rec_groups2, idx2)
  if rec_info1 != rec_info2 {
    return false
  }
  // Then check structural equivalence
  self.types_structurally_equal(idx1, idx2)
}

///|
/// Check if two types are structurally equal (without rec group check).
/// Use types_equivalent for full equivalence checking including rec groups.
fn TypeEquivalenceContext::types_structurally_equal(
  self : TypeEquivalenceContext,
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
  // Check cache
  let key = if self.cross_module {
    (idx1, idx2)
  } else if idx1 <= idx2 {
    (idx1, idx2)
  } else {
    (idx2, idx1)
  }
  match self.visited.get(key) {
    Some(result) => return result
    None => ()
  }
  // Assume equal to break cycles
  self.visited[key] = true
  let t1 = self.types1[idx1]
  let t2 = self.types2[idx2]
  let result = self.func_types_equal(t1, t2, idx1, idx2)
  self.visited[key] = result
  result
}

///|
/// Compare two function types for structural equality.
fn TypeEquivalenceContext::func_types_equal(
  self : TypeEquivalenceContext,
  t1 : FuncType,
  t2 : FuncType,
  idx1 : Int,
  idx2 : Int,
) -> Bool {
  // Check param/result counts
  if t1.params.length() != t2.params.length() ||
    t1.results.length() != t2.results.length() {
    return false
  }
  // Compare params
  for i, p1 in t1.params {
    if not(self.value_types_equal(p1, t2.params[i], idx1, idx2)) {
      return false
    }
  }
  // Compare results
  for i, r1 in t1.results {
    if not(self.value_types_equal(r1, t2.results[i], idx1, idx2)) {
      return false
    }
  }
  true
}

///|
/// Compare two value types for structural equality.
fn TypeEquivalenceContext::value_types_equal(
  self : TypeEquivalenceContext,
  v1 : ValueType,
  v2 : ValueType,
  self_idx : Int,
  other_idx : Int,
) -> Bool {
  match (v1, v2) {
    // Basic types must match exactly
    (I32, I32)
    | (I64, I64)
    | (F32, F32)
    | (F64, F64)
    | (V128, V128)
    | (FuncRef, FuncRef)
    | (ExternRef, ExternRef)
    | (RefFunc, RefFunc)
    | (RefExtern, RefExtern)
    | (AnyRef, AnyRef)
    | (ExnRef, ExnRef)
    | (NullRef, NullRef)
    | (NullFuncRef, NullFuncRef)
    | (NullExnRef, NullExnRef)
    | (NullExternRef, NullExternRef) => true
    // Typed function references
    (RefFuncTyped(ref1), RefFuncTyped(ref2))
    | (RefNullFuncTyped(ref1), RefNullFuncTyped(ref2)) =>
      self.type_refs_equal(ref1, ref2, self_idx, other_idx)
    _ => false
  }
}

///|
/// Compare two type references for structural equality.
fn TypeEquivalenceContext::type_refs_equal(
  self : TypeEquivalenceContext,
  ref1 : Int,
  ref2 : Int,
  self_idx : Int,
  other_idx : Int,
) -> Bool {
  // Both are self-references
  if ref1 == self_idx && ref2 == other_idx {
    return true
  }
  // One is self-reference, other is not
  if ref1 == self_idx || ref2 == other_idx {
    return false
  }
  // Neither is self-reference, compare referenced types
  self.types_structurally_equal(ref1, ref2)
}

///|
/// Get rec group info (position, size) for a type at given index.
/// Returns (position_in_group, group_size) tuple.
pub fn get_rec_group_info(
  rec_groups : Array[Int],
  type_idx : Int,
) -> (Int, Int) {
  if type_idx < 0 || rec_groups.length() == 0 || type_idx >= rec_groups.length() {
    return (0, 1) // Default to singleton rec group
  }
  let rec_id = rec_groups[type_idx]
  let mut size = 0
  let mut position = 0
  for i, id in rec_groups {
    if id == rec_id {
      if i < type_idx {
        position = position + 1
      }
      size = size + 1
    }
  }
  (position, size)
}

///|
/// Compute canonical type indices for a module's types.
/// Structurally equivalent types (with matching rec group info) will be
/// assigned the same canonical index.
pub fn compute_canonical_type_indices(
  types : Array[SubType],
  type_rec_groups? : Array[Int] = [],
) -> Array[Int] {
  let n = types.length()
  let canonical : Array[Int] = Array::make(n, -1)
  // Extract function types for equivalence checking (GC types not yet supported)
  let func_types : Array[FuncType] = []
  for subtype in types {
    match subtype.composite {
      Func(ft) => func_types.push(ft)
      // For struct/array types, push a placeholder empty function type
      // TODO: implement proper structural equivalence for GC types
      _ => func_types.push({ params: [], results: [] })
    }
  }
  let ctx = TypeEquivalenceContext::same_module(func_types, type_rec_groups~)
  for i in 0..<n {
    let mut found = false
    let rec_info_i = get_rec_group_info(type_rec_groups, i)
    for j in 0..<i {
      let rec_info_j = get_rec_group_info(type_rec_groups, j)
      // Types can only be equivalent if rec group info matches
      if rec_info_i == rec_info_j {
        if ctx.types_structurally_equal(i, j) {
          canonical[i] = canonical[j]
          found = true
          break
        }
      }
    }
    if not(found) {
      canonical[i] = i
    }
  }
  canonical
}

///|
/// Compare two function types for simple structural equality.
/// This is for direct type comparison without type indices (e.g., host functions).
/// Note: This does NOT handle typed function references properly - use
/// TypeEquivalenceContext for full recursive type comparison.
pub fn func_types_equal(t1 : FuncType, t2 : FuncType) -> Bool {
  if t1.params.length() != t2.params.length() ||
    t1.results.length() != t2.results.length() {
    return false
  }
  for i, p1 in t1.params {
    if not(value_types_simple_equal(p1, t2.params[i])) {
      return false
    }
  }
  for i, r1 in t1.results {
    if not(value_types_simple_equal(r1, t2.results[i])) {
      return false
    }
  }
  true
}

///|
/// Compare two value types for simple equality.
/// For typed references, compares indices directly (only valid for same module).
fn value_types_simple_equal(v1 : ValueType, v2 : ValueType) -> Bool {
  match (v1, v2) {
    (I32, I32)
    | (I64, I64)
    | (F32, F32)
    | (F64, F64)
    | (V128, V128)
    | (FuncRef, FuncRef)
    | (ExternRef, ExternRef)
    | (RefFunc, RefFunc)
    | (RefExtern, RefExtern)
    | (AnyRef, AnyRef)
    | (ExnRef, ExnRef)
    | (NullRef, NullRef)
    | (NullFuncRef, NullFuncRef)
    | (NullExnRef, NullExnRef)
    | (NullExternRef, NullExternRef)
    // GC types
    | (RefAny, RefAny)
    | (RefEq, RefEq)
    | (RefNullEq, RefNullEq)
    | (RefI31, RefI31)
    | (RefNullI31, RefNullI31)
    | (RefNone, RefNone) => true
    (RefFuncTyped(ref1), RefFuncTyped(ref2)) => ref1 == ref2
    (RefNullFuncTyped(ref1), RefNullFuncTyped(ref2)) => ref1 == ref2
    (RefStruct(ref1), RefStruct(ref2)) => ref1 == ref2
    (RefNullStruct(ref1), RefNullStruct(ref2)) => ref1 == ref2
    (RefArray(ref1), RefArray(ref2)) => ref1 == ref2
    (RefNullArray(ref1), RefNullArray(ref2)) => ref1 == ref2
    _ => false
  }
}
