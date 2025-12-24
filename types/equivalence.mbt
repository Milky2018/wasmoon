// Type Equivalence - Unified type comparison for WebAssembly GC
//
// This module provides a unified API for checking type equivalence,
// handling both same-module and cross-module comparisons with proper
// support for recursive types, rec groups, and all composite types.

///|
/// Context for type equivalence checking.
/// Now uses SubType to properly handle func, struct, and array types.
pub struct TypeEquivalenceContext {
  types1 : Array[SubType]
  types2 : Array[SubType]
  rec_groups1 : Array[Int]
  rec_groups2 : Array[Int]
  cross_module : Bool
  visited : Map[(Int, Int), Bool]
}

///|
/// Create a context for same-module type comparison.
pub fn TypeEquivalenceContext::same_module(
  types : Array[SubType],
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
  types1 : Array[SubType],
  types2 : Array[SubType],
  rec_groups1? : Array[Int] = [],
  rec_groups2? : Array[Int] = [],
) -> TypeEquivalenceContext {
  { types1, types2, rec_groups1, rec_groups2, cross_module: true, visited: {} }
}

///|
/// Check if two types at given indices are equivalent.
/// This is the main entry point for type equivalence checking.
/// For isorecursive typing, types are equivalent iff they are in
/// pairwise-equivalent rec groups at the same position.
pub fn TypeEquivalenceContext::types_equivalent(
  self : TypeEquivalenceContext,
  idx1 : Int,
  idx2 : Int,
) -> Bool {
  // Same index in same module is trivially equivalent
  if not(self.cross_module) && idx1 == idx2 {
    return true
  }
  // First check rec group info - types can only be equivalent if
  // they have the same position and size within their rec groups
  let rec_info1 = get_rec_group_info(self.rec_groups1, idx1)
  let rec_info2 = get_rec_group_info(self.rec_groups2, idx2)
  if rec_info1 != rec_info2 {
    return false
  }
  // Types can only be equivalent if their rec groups are pairwise equivalent
  let rec_id1 = if idx1 < self.rec_groups1.length() {
    self.rec_groups1[idx1]
  } else {
    idx1 // singleton rec group
  }
  let rec_id2 = if idx2 < self.rec_groups2.length() {
    self.rec_groups2[idx2]
  } else {
    idx2 // singleton rec group
  }

  // For same-module, same rec group ID means same rec group
  if not(self.cross_module) && rec_id1 == rec_id2 {
    // Same rec group, same position (since rec_info1 == rec_info2)
    return rec_info1.0 == rec_info2.0
  }

  // Check if the rec groups are pairwise equivalent
  // This works for both same-module (different rec groups) and cross-module
  let n_types = if self.types1.length() > self.types2.length() {
    self.types1.length()
  } else {
    self.types2.length()
  }
  rec_groups_equivalent(
    self,
    self.rec_groups1,
    self.rec_groups2,
    rec_id1,
    rec_id2,
    n_types,
  )
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
  // Assume equal to break cycles (recursive types)
  self.visited[key] = true
  let t1 = self.types1[idx1]
  let t2 = self.types2[idx2]
  // Check finality matches
  if t1.final_ != t2.final_ {
    self.visited[key] = false
    return false
  }
  // Check supertypes match (with proper internal/external reference handling)
  if not(
      self.supertypes_equal_with_context(
        t1.supertypes,
        t2.supertypes,
        idx1,
        idx2,
      ),
    ) {
    self.visited[key] = false
    return false
  }
  // Check composite types
  let result = self.composite_types_equal(
    t1.composite,
    t2.composite,
    idx1,
    idx2,
  )
  self.visited[key] = result
  result
}

///|
/// Check if supertypes are equivalent.
/// For isorecursive typing, supertype references need special handling:
/// - Internal references (within the same rec group) must match by position
/// - External references (outside rec group) must refer to equivalent types
fn TypeEquivalenceContext::supertypes_equal_with_context(
  self : TypeEquivalenceContext,
  s1 : Array[Int],
  s2 : Array[Int],
  idx1 : Int,
  idx2 : Int,
) -> Bool {
  if s1.length() != s2.length() {
    return false
  }
  for i, sup1 in s1 {
    // Use type_refs_equal to properly handle internal vs external references
    if not(self.type_refs_equal(sup1, s2[i], idx1, idx2)) {
      return false
    }
  }
  true
}

///|
/// Compare composite types for structural equality.
fn TypeEquivalenceContext::composite_types_equal(
  self : TypeEquivalenceContext,
  c1 : CompositeType,
  c2 : CompositeType,
  idx1 : Int,
  idx2 : Int,
) -> Bool {
  match (c1, c2) {
    (Func(f1), Func(f2)) => self.func_types_equal(f1, f2, idx1, idx2)
    (Struct(s1), Struct(s2)) => self.struct_types_equal(s1, s2, idx1, idx2)
    (Array(a1), Array(a2)) => self.array_types_equal(a1, a2, idx1, idx2)
    _ => false // Different composite types are never equivalent
  }
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
/// Compare two struct types for structural equality.
fn TypeEquivalenceContext::struct_types_equal(
  self : TypeEquivalenceContext,
  s1 : StructType,
  s2 : StructType,
  idx1 : Int,
  idx2 : Int,
) -> Bool {
  // Must have same number of fields
  if s1.fields.length() != s2.fields.length() {
    return false
  }
  // Each field must be equivalent
  for i, f1 in s1.fields {
    if not(self.field_types_equal(f1, s2.fields[i], idx1, idx2)) {
      return false
    }
  }
  true
}

///|
/// Compare two array types for structural equality.
fn TypeEquivalenceContext::array_types_equal(
  self : TypeEquivalenceContext,
  a1 : ArrayType,
  a2 : ArrayType,
  idx1 : Int,
  idx2 : Int,
) -> Bool {
  self.field_types_equal(a1.element, a2.element, idx1, idx2)
}

///|
/// Compare two field types for equality.
fn TypeEquivalenceContext::field_types_equal(
  self : TypeEquivalenceContext,
  f1 : FieldType,
  f2 : FieldType,
  idx1 : Int,
  idx2 : Int,
) -> Bool {
  // Mutability must match
  if f1.mutable != f2.mutable {
    return false
  }
  // Storage types must be equal
  self.storage_types_equal(f1.storage_type, f2.storage_type, idx1, idx2)
}

///|
/// Compare two storage types for equality.
fn TypeEquivalenceContext::storage_types_equal(
  self : TypeEquivalenceContext,
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
    | (NullExternRef, NullExternRef)
    | (RefAny, RefAny)
    | (RefEq, RefEq)
    | (RefNullEq, RefNullEq)
    | (RefI31, RefI31)
    | (RefNullI31, RefNullI31)
    | (RefNone, RefNone) => true
    // Typed references
    (RefFuncTyped(ref1), RefFuncTyped(ref2))
    | (RefNullFuncTyped(ref1), RefNullFuncTyped(ref2)) =>
      self.type_refs_equal(ref1, ref2, self_idx, other_idx)
    (RefStruct(ref1), RefStruct(ref2))
    | (RefNullStruct(ref1), RefNullStruct(ref2)) =>
      self.type_refs_equal(ref1, ref2, self_idx, other_idx)
    (RefArray(ref1), RefArray(ref2))
    | (RefNullArray(ref1), RefNullArray(ref2)) =>
      self.type_refs_equal(ref1, ref2, self_idx, other_idx)
    _ => false
  }
}

///|
/// Compare two type references for structural equality.
/// Handles references within rec groups (internal) vs outside (external) correctly.
/// For isorecursive type equivalence:
/// - References to types WITHIN the same rec group must match by position
/// - References to types OUTSIDE the rec group must refer to equivalent types
fn TypeEquivalenceContext::type_refs_equal(
  self : TypeEquivalenceContext,
  ref1 : Int,
  ref2 : Int,
  self_idx : Int,
  other_idx : Int,
) -> Bool {
  // Get rec group info for the types being compared
  let rec_id1 = if self_idx >= 0 && self_idx < self.rec_groups1.length() {
    self.rec_groups1[self_idx]
  } else {
    -1
  }
  let rec_id2 = if other_idx >= 0 && other_idx < self.rec_groups2.length() {
    self.rec_groups2[other_idx]
  } else {
    -1
  }
  // Check if ref1 is within self_idx's rec group
  let ref1_in_group = ref1 >= 0 &&
    ref1 < self.rec_groups1.length() &&
    rec_id1 >= 0 &&
    self.rec_groups1[ref1] == rec_id1
  // Check if ref2 is within other_idx's rec group
  let ref2_in_group = ref2 >= 0 &&
    ref2 < self.rec_groups2.length() &&
    rec_id2 >= 0 &&
    self.rec_groups2[ref2] == rec_id2
  if ref1_in_group && ref2_in_group {
    // Both references are within their respective rec groups
    // They must be at the same relative position
    let pos1 = get_rec_group_position(self.rec_groups1, ref1, rec_id1)
    let pos2 = get_rec_group_position(self.rec_groups2, ref2, rec_id2)
    return pos1 == pos2
  }
  if ref1_in_group || ref2_in_group {
    // One reference is within its rec group, the other is external
    // They cannot be equivalent
    return false
  }
  // Both references are external (outside their rec groups)
  // For isorecursive typing, external references must point to types
  // that are in equivalent rec groups at equivalent positions.
  // Use types_equivalent which checks rec group info.
  self.types_equivalent(ref1, ref2)
}

///|
/// Get the position of a type within its rec group.
fn get_rec_group_position(
  rec_groups : Array[Int],
  type_idx : Int,
  rec_id : Int,
) -> Int {
  let mut position = 0
  for i in 0..<type_idx {
    if i < rec_groups.length() && rec_groups[i] == rec_id {
      position = position + 1
    }
  }
  position
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
/// Structurally equivalent types (in equivalent rec groups) will be
/// assigned the same canonical index.
/// For isorecursive typing, entire rec groups must be pairwise equivalent.
pub fn compute_canonical_type_indices(
  types : Array[SubType],
  type_rec_groups? : Array[Int] = [],
) -> Array[Int] {
  let n = types.length()
  let canonical : Array[Int] = Array::make(n, -1)
  // Track which rec groups we've processed and their canonical mapping
  // Key: rec_group_id, Value: (canonical_rec_id, first_type_idx)
  let rec_group_canonical : Map[Int, (Int, Int)] = {}
  let ctx = TypeEquivalenceContext::same_module(types, type_rec_groups~)
  for i in 0..<n {
    let rec_id_i = if i < type_rec_groups.length() {
      type_rec_groups[i]
    } else {
      i // singleton rec group
    }
    // Check if we've already determined this rec group's canonical mapping
    match rec_group_canonical.get(rec_id_i) {
      Some((canon_rec_id, first_idx)) => {
        // This rec group already mapped - compute relative canonical index
        let pos_i = get_rec_group_position(type_rec_groups, i, rec_id_i)
        canonical[i] = first_idx +
          pos_i -
          get_rec_group_position(type_rec_groups, first_idx, canon_rec_id)
        continue
      }
      None => ()
    }
    // This is the first type we've seen from this rec group
    // Try to find an equivalent rec group we've already processed
    let rec_info_i = get_rec_group_info(type_rec_groups, i)
    let mut found = false
    for j in 0..<i {
      let rec_id_j = if j < type_rec_groups.length() {
        type_rec_groups[j]
      } else {
        j
      }
      let rec_info_j = get_rec_group_info(type_rec_groups, j)
      // Rec groups can only be equivalent if they have the same size
      if rec_info_i.1 != rec_info_j.1 {
        continue
      }
      // Check if this is the first type of rec_group j
      if rec_info_j.0 != 0 {
        continue
      }
      // Check if entire rec groups are pairwise equivalent
      if rec_groups_equivalent(
          ctx, type_rec_groups, type_rec_groups, rec_id_i, rec_id_j, n,
        ) {
        // Map this rec group to j's rec group
        let pos_i = get_rec_group_position(type_rec_groups, i, rec_id_i)
        canonical[i] = j + pos_i
        rec_group_canonical[rec_id_i] = (rec_id_j, j)
        found = true
        break
      }
    }
    if not(found) {
      canonical[i] = i
      rec_group_canonical[rec_id_i] = (rec_id_i, i)
    }
  }
  canonical
}

///|
/// Check if two entire rec groups are pairwise structurally equivalent.
fn rec_groups_equivalent(
  ctx : TypeEquivalenceContext,
  rec_groups1 : Array[Int],
  rec_groups2 : Array[Int],
  rec_id1 : Int,
  rec_id2 : Int,
  n_types : Int,
) -> Bool {
  // Collect types in each rec group
  let types1 : Array[Int] = []
  let types2 : Array[Int] = []
  // Handle empty rec_groups (each type is singleton)
  if rec_groups1.length() == 0 {
    // rec_id is the type index itself for singleton
    if rec_id1 >= 0 && rec_id1 < n_types {
      types1.push(rec_id1)
    }
  } else {
    for i, id in rec_groups1 {
      if id == rec_id1 {
        types1.push(i)
      }
    }
  }
  if rec_groups2.length() == 0 {
    if rec_id2 >= 0 && rec_id2 < n_types {
      types2.push(rec_id2)
    }
  } else {
    for i, id in rec_groups2 {
      if id == rec_id2 {
        types2.push(i)
      }
    }
  }
  // Must have same number of types
  if types1.length() != types2.length() {
    return false
  }
  // All types must be pairwise structurally equivalent
  for k, idx1 in types1 {
    if not(ctx.types_structurally_equal(idx1, types2[k])) {
      return false
    }
  }
  true
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
