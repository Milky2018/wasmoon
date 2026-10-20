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
  // Duplicate groups share fingerprints; this control also distinguishes
  // the multi-member groups from the singleton groups.
  inspect(fingerprints[1] == fingerprints[0], content="true")
  inspect(fingerprints[3] == fingerprints[2], content="true")
  inspect(fingerprints[0] == fingerprints[2], content="false")
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
  inspect(fingerprints[2] == fingerprints[1], content="true")
  inspect(fingerprints[4] == fingerprints[1], content="false")
  // Only external references ask for identities.
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

///|
test "fingerprint collisions still compare the complete recursive group" {
  let types = func_types_to_subtypes([
    { params: [I32], results: [], },
    { params: [I64], results: [], },
    { params: [I32], results: [], },
    { params: [F64], results: [], },
    { params: [I32], results: [], },
    { params: [F64], results: [], },
  ])
  let ctx = TypeEquivalenceContext::same_module(types, type_rec_groups=[
    0, 0, 1, 1, 2, 2,
  ])
  // Inject the candidates of a colliding bucket. The first members match,
  // but only the second candidate has an equivalent second member.
  let candidates = [[0, 1], [2, 3]]
  assert_eq(equivalent_type_group(ctx, [4, 5], candidates), Some([2, 3]))
  assert_eq(equivalent_type_group(ctx, [2, 3], [[0, 1]]), None)
}

///|
test "fingerprints and canonical equality agree for all value type forms" {
  let values : Array[ValueType] = [
    I32,
    I64,
    F32,
    F64,
    V128,
    FuncRef,
    ExternRef,
    RefFunc,
    RefExtern,
    RefFuncTyped(0),
    RefNullFuncTyped(0),
    ContRef,
    RefCont,
    RefContTyped(0),
    RefNullContTyped(0),
    NullContRef,
    RefNoCont,
    AnyRef,
    ExnRef,
    StructRef,
    ArrayRef,
    RefStruct(0),
    RefNullStruct(0),
    RefArray(0),
    RefNullArray(0),
    RefAny,
    RefEq,
    RefNullEq,
    RefI31,
    RefNullI31,
    RefStructAbs,
    RefArrayAbs,
    RefNone,
    NullRef,
    NullFuncRef,
    NullExnRef,
    NullExternRef,
  ]
  let types = [SubType::func([], [])]
  for _ in 0..<2 {
    for value in values {
      types.push(SubType::func([value], []))
    }
    for packed in [PackedType::I8, I16] {
      for mutable in [false, true] {
        types.push(
          SubType::simple(
            Struct({ fields: [{ storage_type: Packed(packed), mutable, }], }),
          ),
        )
        types.push(
          SubType::simple(
            Array({ element: { storage_type: Packed(packed), mutable, }, }),
          ),
        )
      }
    }
    types.push(SubType::simple(Cont(0)))
    types.push({
      final_: false,
      supertypes: [],
      composite: Func({ params: [], results: [], }),
    })
    types.push({
      final_: true,
      supertypes: [types.length() - 1],
      composite: Func({ params: [], results: [], }),
    })
  }
  let canonical = compute_canonical_type_indices(types)
  let ctx = TypeEquivalenceContext::same_module(types)
  for i in 0..<types.length() {
    for j in 0..<types.length() {
      assert_eq(canonical[i] == canonical[j], ctx.types_equivalent(i, j))
    }
  }
}

///|
test "canonicalization preserves unvalidated reference handling without indexing errors" {
  for reference in [-2147483648, -1, 100, 1] {
    let types = [
      SubType::func([RefNullFuncTyped(reference)], []),
      SubType::func([RefNullFuncTyped(reference)], []),
    ]
    assert_eq(
      compute_canonical_type_indices(types),
      canonical_type_indices_pairwise(types, []),
    )
  }
}
