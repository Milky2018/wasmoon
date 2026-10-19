// Regression coverage for fingerprint-based type canonicalization.

///|
test "fold_type_groups: partition and duplicate-group fingerprints" {
  // Two identical 2-member rec groups plus two identical singletons.
  let types = func_types_to_subtypes([
    { params: [I32], results: [], }, // group 0 pos 0
    { params: [I64], results: [], }, // group 0 pos 1
    { params: [I32], results: [], }, // group 1 pos 0 (duplicate of group 0)
    { params: [I64], results: [], }, // group 1 pos 1
    { params: [], results: [F32], }, // group 2 singleton
    { params: [], results: [F32], }, // group 3 singleton (duplicate)
  ])
  let groups : Array[Array[Int32]] = []
  let fingerprints : Array[Int64] = []
  fold_type_groups(
    types,
    type_rec_groups=[0, 0, 1, 1, 2, 3],
    external_identity=fn(_) { -1 },
    visit=fn(members, fingerprint) {
      groups.push(members.to_owned())
      fingerprints.push(fingerprint)
    },
  )
  debug_inspect(groups, content="[[0, 1], [2, 3], [4], [5]]")
  inspect(fingerprints[0] == fingerprints[1], content="true")
  inspect(fingerprints[2] == fingerprints[3], content="true")
  inspect(fingerprints[0] != fingerprints[2], content="true")
}

///|
test "fold_type_groups: external references resolve through identities" {
  // Groups referencing the same earlier type hash equal; referencing
  // different earlier types must hash differently.
  let types : Array[SubType] = [
    SubType::simple(Func({ params: [I32], results: [], })), // 0
    SubType::simple(Func({ params: [RefNullFuncTyped(0)], results: [], })), // 1
    SubType::simple(Func({ params: [RefNullFuncTyped(0)], results: [], })), // 2 duplicate of 1
    SubType::simple(Func({ params: [I32], results: [], })), // 3
    SubType::simple(Func({ params: [RefNullFuncTyped(3)], results: [], })), // 4 different ref
  ]
  let identity : Array[Int32] = [7, -1, -1, 9, -1]
  let fingerprints : Array[Int64] = []
  let resolved : Array[Int32] = []
  fold_type_groups(
    types,
    external_identity=fn(type_index) {
      resolved.push(type_index)
      identity[type_index]
    },
    visit=fn(_, fingerprint) { fingerprints.push(fingerprint) },
  )
  inspect(fingerprints[1] == fingerprints[2], content="true")
  inspect(fingerprints[1] != fingerprints[4], content="true")
  // Only the two external references asked for identities.
  debug_inspect(resolved, content="[0, 0, 3]")
}

///|
test "compute_canonical_type_indices: abstract heap type references" {
  // `(array (mut arrayref))` parses to RefNullArray(-1); negative references
  // must be fingerprinted as abstract heap types, never resolved.
  let types : Array[SubType] = [
    SubType::simple(
      Array({
        element: { storage_type: Val(RefNullArray(-1)), mutable: true, },
      }),
    ),
    SubType::simple(Func({ params: [], results: [I32], })),
  ]
  debug_inspect(
    compute_canonical_type_indices(types, type_rec_groups=[0, 1]),
    content="[0, 1]",
  )
  // A concrete element type is a different type and canonicalizes apart.
  let concrete : Array[SubType] = [
    SubType::simple(
      Array({ element: { storage_type: Val(RefNullArray(1)), mutable: true, }, }),
    ),
    SubType::simple(Func({ params: [], results: [I32], })),
  ]
  debug_inspect(
    compute_canonical_type_indices(concrete, type_rec_groups=[0, 1]),
    content="[0, 1]",
  )
}

///|
test "compute_canonical_type_indices: agrees with structural equivalence" {
  // Mix of duplicates, distinct signatures, typed references to earlier
  // types, and multi-member rec groups; canonical equality must exactly
  // match TypeEquivalenceContext across every pair.
  let types : Array[SubType] = []
  let rec_groups : Array[Int32] = []
  for i in 0..<96 {
    let params : Array[ValueType] = match i % 4 {
      0 => [I32]
      1 => [I64, F32]
      2 => [RefNullFuncTyped(i / 4 * 4)] // reference an earlier type
      _ => []
    }
    types.push(
      SubType::simple(
        Func({ params: ReadOnlyArray::from_array(params), results: [], }),
      ),
    )
    rec_groups.push(i)
  }
  // Two identical two-member groups appended at the end.
  let group_a = types.length()
  for i in 0..<2 {
    let params : Array[ValueType] = if i == 0 {
      [RefNullStruct(group_a)]
    } else {
      [F64]
    }
    types.push(
      SubType::simple(
        Func({ params: ReadOnlyArray::from_array(params), results: [], }),
      ),
    )
    rec_groups.push(group_a)
  }
  for i in 0..<2 {
    // Self-reference inside this group, mirroring the first group's shape.
    let params : Array[ValueType] = if i == 0 {
      [RefNullStruct(group_a + 2)]
    } else {
      [F64]
    }
    types.push(
      SubType::simple(
        Func({ params: ReadOnlyArray::from_array(params), results: [], }),
      ),
    )
    rec_groups.push(group_a + 1)
  }
  let canonical = compute_canonical_type_indices(
    types,
    type_rec_groups=rec_groups,
  )
  let ctx = TypeEquivalenceContext::same_module(
    types,
    type_rec_groups=rec_groups,
  )
  for i in 0..<types.length() {
    for j in 0..<types.length() {
      let equivalent = ctx.types_equivalent(i, j)
      if (canonical[i] == canonical[j]) != equivalent {
        fail(
          "canonical disagreement at (\{i}, \{j}): canonical \{canonical[i]} vs \{canonical[j]}, equivalent \{equivalent}",
        )
      }
    }
  }
  // The duplicated groups share canonical indices position by position.
  inspect(canonical[group_a] == canonical[group_a + 2], content="true")
  inspect(canonical[group_a + 1] == canonical[group_a + 3], content="true")
}
