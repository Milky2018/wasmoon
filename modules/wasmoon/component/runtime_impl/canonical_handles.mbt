///|
/// One structural walk for handle validation, transfer, cloning, and lending.
/// The callback sees only handle-bearing leaves in their defining environment.
fn map_canonical_handles(
  ty : ValType,
  value : ComponentValue,
  types : Array[TypeDef?],
  visit : (TypeDef, ComponentValue) -> ComponentValue raise ComponentRuntimeError,
) -> ComponentValue raise ComponentRuntimeError {
  fn walk(
    ty : ValType,
    value : ComponentValue,
  ) -> ComponentValue raise ComponentRuntimeError {
    guard resolve_valtype(ty, types) is TypeIdx(idx) else { return value }
    guard types.get(idx) is Some(Some(definition)) else {
      raise InvalidTypeDef(idx)
    }
    fn tuple(
      fields : Array[ValType],
    ) -> ComponentValue raise ComponentRuntimeError {
      guard value is Tuple(items) && items.length() == fields.length() else {
        raise HostCallError("tuple type mismatch")
      }
      let result : Array[ComponentValue] = []
      for i, field in fields {
        result.push(walk(field, items[i]))
      }
      Tuple(result)
    }
    fn variant(
      cases : Array[ValType?],
    ) -> ComponentValue raise ComponentRuntimeError {
      guard value is Variant(tag, payload) && tag >= 0 && tag < cases.length() else {
        raise HostCallError("invalid variant discriminant")
      }
      match (cases[tag], payload) {
        (Some(ty), Some(value)) => Variant(tag, Some(walk(ty, value)))
        (None, None) => value
        _ => raise HostCallError("variant payload type mismatch")
      }
    }
    match definition {
      Tuple(fields) => tuple(fields)
      Record(fields) => tuple(fields.map(field => field.ty))
      List(element) | FixedList(element, _) => {
        guard value is List(items) else {
          raise HostCallError("list type mismatch")
        }
        if definition is FixedList(_, length) && length != items.length() {
          raise HostCallError("fixed list type mismatch: wrong length")
        }
        List(items.map(item => walk(element, item)))
      }
      MapType(key, element) => {
        guard value is List(entries) else {
          raise HostCallError("map type mismatch")
        }
        List(
          entries.map(entry => {
            guard entry is Tuple([k, v]) else {
              raise HostCallError("map entry type mismatch")
            }
            Tuple([walk(key, k), walk(element, v)])
          }),
        )
      }
      Variant(cases) => variant(cases.map(case => case.ty))
      Option(element) => variant([None, Some(element)])
      Result(ok, err) => variant([ok, err])
      Own(_) | Borrow(_) | ResourceType(_, _, _, _) | Stream(_) | Future(_) =>
        visit(definition, value)
      _ => value
    }
  }
  walk(ty, value)
}
