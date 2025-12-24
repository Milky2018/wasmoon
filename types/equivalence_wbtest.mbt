///|
/// Tests for type equivalence API

///|
test "TypeEquivalenceContext: identical simple types" {
  let t1 : FuncType = { params: [I32, I64], results: [F32] }
  let t2 : FuncType = { params: [I32, I64], results: [F32] }
  let types = func_types_to_subtypes([t1, t2])
  let ctx = TypeEquivalenceContext::same_module(types)
  inspect(ctx.types_equivalent(0, 1), content="true")
}

///|
test "TypeEquivalenceContext: different param counts" {
  let t1 : FuncType = { params: [I32], results: [] }
  let t2 : FuncType = { params: [I32, I64], results: [] }
  let types = func_types_to_subtypes([t1, t2])
  let ctx = TypeEquivalenceContext::same_module(types)
  inspect(ctx.types_equivalent(0, 1), content="false")
}

///|
test "TypeEquivalenceContext: different result counts" {
  let t1 : FuncType = { params: [], results: [I32] }
  let t2 : FuncType = { params: [], results: [I32, I64] }
  let types = func_types_to_subtypes([t1, t2])
  let ctx = TypeEquivalenceContext::same_module(types)
  inspect(ctx.types_equivalent(0, 1), content="false")
}

///|
test "TypeEquivalenceContext: different param types" {
  let t1 : FuncType = { params: [I32], results: [] }
  let t2 : FuncType = { params: [I64], results: [] }
  let types = func_types_to_subtypes([t1, t2])
  let ctx = TypeEquivalenceContext::same_module(types)
  inspect(ctx.types_equivalent(0, 1), content="false")
}

///|
test "TypeEquivalenceContext: self-referential types are equal" {
  // (type $t1 (func (result (ref null $t1))))
  // (type $t2 (func (result (ref null $t2))))
  // These should be structurally equal because both reference "self"
  let t1 : FuncType = { params: [], results: [RefNullFuncTyped(0)] }
  let t2 : FuncType = { params: [], results: [RefNullFuncTyped(1)] }
  let types = func_types_to_subtypes([t1, t2])
  let ctx = TypeEquivalenceContext::same_module(types)
  inspect(ctx.types_equivalent(0, 1), content="true")
}

///|
test "TypeEquivalenceContext: indirect types with same referenced type" {
  // (type $s0 (func (param i32)))
  // (type $s1 (func (param i32 (ref $s0))))
  // (type $s2 (func (param i32 (ref $s0))))
  // $s1 and $s2 should be structurally equal
  let s0 : FuncType = { params: [I32], results: [] }
  let s1 : FuncType = { params: [I32, RefFuncTyped(0)], results: [] }
  let s2 : FuncType = { params: [I32, RefFuncTyped(0)], results: [] }
  let types = func_types_to_subtypes([s0, s1, s2])
  let ctx = TypeEquivalenceContext::same_module(types)
  inspect(ctx.types_equivalent(1, 2), content="true")
}

///|
test "TypeEquivalenceContext: different referenced types" {
  // (type $s0 (func (param i32)))
  // (type $s1 (func (param i64)))  ; different from $s0
  // (type $t1 (func (param (ref $s0))))
  // (type $t2 (func (param (ref $s1))))
  // $t1 and $t2 should NOT be equal
  let s0 : FuncType = { params: [I32], results: [] }
  let s1 : FuncType = { params: [I64], results: [] }
  let t1 : FuncType = { params: [RefFuncTyped(0)], results: [] }
  let t2 : FuncType = { params: [RefFuncTyped(1)], results: [] }
  let types = func_types_to_subtypes([s0, s1, t1, t2])
  let ctx = TypeEquivalenceContext::same_module(types)
  inspect(ctx.types_equivalent(2, 3), content="false")
}

///|
test "get_rec_group_info: singleton rec group" {
  let rec_groups : Array[Int] = [0, 1, 2]
  inspect(get_rec_group_info(rec_groups, 0), content="(0, 1)")
  inspect(get_rec_group_info(rec_groups, 1), content="(0, 1)")
  inspect(get_rec_group_info(rec_groups, 2), content="(0, 1)")
}

///|
test "get_rec_group_info: multi-type rec group" {
  // (rec (type $t0 ...) (type $t1 ...))
  // (type $t2 ...)
  let rec_groups : Array[Int] = [0, 0, 1]
  inspect(get_rec_group_info(rec_groups, 0), content="(0, 2)")
  inspect(get_rec_group_info(rec_groups, 1), content="(1, 2)")
  inspect(get_rec_group_info(rec_groups, 2), content="(0, 1)")
}

///|
test "get_rec_group_info: empty rec groups" {
  let rec_groups : Array[Int] = []
  inspect(get_rec_group_info(rec_groups, 0), content="(0, 1)")
}

///|
test "TypeEquivalenceContext: rec group position matters" {
  // Two types with same structure but different rec group positions should not match
  let t1 : FuncType = { params: [], results: [] }
  let t2 : FuncType = { params: [], results: [] }
  let t3 : FuncType = { params: [], results: [] }
  let types = func_types_to_subtypes([t1, t2, t3])
  // t1 is at position 0 in a 2-type rec group
  // t2 is at position 1 in a 2-type rec group
  // t3 is at position 0 in a 1-type rec group
  let rec_groups : Array[Int] = [0, 0, 1]
  let ctx = TypeEquivalenceContext::same_module(
    types,
    type_rec_groups=rec_groups,
  )
  // t1 (pos=0, size=2) vs t2 (pos=1, size=2) - different positions
  inspect(ctx.types_equivalent(0, 1), content="false")
  // t1 (pos=0, size=2) vs t3 (pos=0, size=1) - different sizes
  inspect(ctx.types_equivalent(0, 2), content="false")
}

///|
test "TypeEquivalenceContext: cross-module comparison" {
  let t1 : FuncType = { params: [I32], results: [I64] }
  let t2 : FuncType = { params: [I32], results: [I64] }
  let types1 = func_types_to_subtypes([t1])
  let types2 = func_types_to_subtypes([t2])
  let ctx = TypeEquivalenceContext::cross_module(types1, types2)
  inspect(ctx.types_equivalent(0, 0), content="true")
}

///|
test "compute_canonical_type_indices: basic" {
  let t1 : FuncType = { params: [I32], results: [] }
  let t2 : FuncType = { params: [I64], results: [] }
  let t3 : FuncType = { params: [I32], results: [] } // same as t1
  let types : Array[FuncType] = [t1, t2, t3]
  let canonical = compute_canonical_type_indices(func_types_to_subtypes(types))
  inspect(canonical[0], content="0")
  inspect(canonical[1], content="1")
  inspect(canonical[2], content="0") // maps to t1
}

///|
test "compute_canonical_type_indices: with rec groups" {
  let t1 : FuncType = { params: [], results: [] }
  let t2 : FuncType = { params: [], results: [] }
  let t3 : FuncType = { params: [], results: [] }
  let types : Array[FuncType] = [t1, t2, t3]
  // t1 and t2 are in same rec group, t3 is separate
  let rec_groups : Array[Int] = [0, 0, 1]
  let canonical = compute_canonical_type_indices(
    func_types_to_subtypes(types),
    type_rec_groups=rec_groups,
  )
  // t1 is at pos=0, size=2 - unique
  inspect(canonical[0], content="0")
  // t2 is at pos=1, size=2 - unique
  inspect(canonical[1], content="1")
  // t3 is at pos=0, size=1 - different from t1 (size differs)
  inspect(canonical[2], content="2")
}
