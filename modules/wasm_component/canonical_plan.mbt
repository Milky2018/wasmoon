///|
/// A value's ABI representation in its defining type environment. Flat output
/// may be bounded by the caller's ABI arity limit; memory layout never expands
/// fixed-length lists. An absent layout means the value exceeds the supported
/// addressable area, while its bounded call signature can still be inspected.
pub(all) struct CanonicalAbiPlan {
  value_type : ValType
  types : Array[TypeDef?]
  memory64 : Bool
  flat : Array[@types.ValueType]
  layout : (Int, Int)?
  contains_memory : Bool
}

///|
pub fn canonical_abi_plan(
  ty : ValType,
  types : Array[TypeDef?],
  memory64 : Bool,
  max_flat? : Int = 2147483647,
) -> CanonicalAbiPlan? {
  guard canonical_flat_types(
      ty,
      types,
      if memory64 {
        I64
      } else {
        I32
      },
      max_flat~,
    )
    is Some(flat) else {
    return None
  }
  Some({
    value_type: ty,
    types,
    memory64,
    flat,
    layout: canonical_memory_layout(ty, types, memory64),
    contains_memory: canonical_value_contains_memory(ty, types),
  })
}

///|
pub fn canonical_value_contains_memory(
  ty : ValType,
  types : Array[TypeDef?],
) -> Bool {
  let visited : Map[Int, Unit] = Map([])
  fn contains(ty : ValType) -> Bool {
    match ty {
      Prim(String) => true
      Prim(_) => false
      TypeIdx(idx) => {
        if visited.get(idx) is Some(_) {
          return false
        }
        visited.set(idx, ())
        match types.get(idx) {
          Some(Some(DefValType(p))) => contains(Prim(p))
          Some(Some(List(_))) => true
          Some(Some(FixedList(element, _))) | Some(Some(Option(element))) =>
            contains(element)
          Some(Some(Tuple(items))) => items.any(contains)
          Some(Some(Record(fields))) => fields.any(field => contains(field.ty))
          Some(Some(Variant(cases))) =>
            cases.any(case => case.ty is Some(ty) && contains(ty))
          Some(Some(Result(ok, err))) =>
            (ok is Some(ty) && contains(ty)) ||
            (err is Some(ty) && contains(ty))
          _ => false
        }
      }
    }
  }
  contains(ty)
}
