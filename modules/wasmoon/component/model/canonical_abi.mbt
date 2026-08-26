///|
/// Return the Canonical ABI flat core value types for one component value.
///
/// `pointer_type` must be `I32` or `I64` and represents the selected canonical
/// memory. `None` means the type index is invalid, recursive, or does not name
/// a value type.
pub fn canonical_flat_types(
  ty : ValType,
  types : Array[TypeDef?],
  pointer_type : @types.ValueType,
) -> Array[@types.ValueType]? {
  match pointer_type {
    I32 | I64 => ()
    _ => return None
  }
  let visiting : Map[Int, Unit] = Map([])
  fn join_flat(a : @types.ValueType, b : @types.ValueType) -> @types.ValueType {
    if a == b {
      return a
    }
    match (a, b) {
      (I64, _) | (_, I64) | (F64, _) | (_, F64) => I64
      (F32, I32) | (I32, F32) => I32
      (I32, _) | (_, I32) => I32
      _ => I64
    }
  }

  fn flat_primitive(p : PrimValType) -> Array[@types.ValueType] {
    match p {
      Bool | S8 | U8 | S16 | U16 | S32 | U32 | Char => [I32]
      S64 | U64 => [I64]
      F32 => [F32]
      F64 => [F64]
      String | ErrorContext => [pointer_type, pointer_type]
    }
  }

  fn flatten(value_type : ValType) -> Array[@types.ValueType]? {
    match value_type {
      Prim(p) => Some(flat_primitive(p))
      TypeIdx(idx) => {
        if idx < 0 || idx >= types.length() || visiting.get(idx) is Some(_) {
          return None
        }
        visiting.set(idx, ())
        let result = match types[idx] {
          Some(DefValType(p)) => Some(flat_primitive(p))
          Some(Tuple(values)) => {
            let output : Array[@types.ValueType] = []
            for value in values {
              match flatten(value) {
                Some(flat) =>
                  for core_type in flat {
                    output.push(core_type)
                  }
                None => return None
              }
            }
            Some(output)
          }
          Some(Record(fields)) => {
            let output : Array[@types.ValueType] = []
            for field in fields {
              match flatten(field.ty) {
                Some(flat) =>
                  for core_type in flat {
                    output.push(core_type)
                  }
                None => return None
              }
            }
            Some(output)
          }
          Some(Variant(cases)) => {
            let payloads : Array[Array[@types.ValueType]] = []
            let mut max_length = 0
            for case in cases {
              let payload = match case.ty {
                Some(case_type) =>
                  match flatten(case_type) {
                    Some(flat) => flat
                    None => return None
                  }
                None => []
              }
              if payload.length() > max_length {
                max_length = payload.length()
              }
              payloads.push(payload)
            }
            let joined : Array[@types.ValueType] = []
            for index in 0..<max_length {
              let mut current : @types.ValueType? = None
              for payload in payloads {
                if index < payload.length() {
                  current = match current {
                    Some(previous) => Some(join_flat(previous, payload[index]))
                    None => Some(payload[index])
                  }
                }
              }
              match current {
                Some(core_type) => joined.push(core_type)
                None => ()
              }
            }
            Some([I32] + joined)
          }
          Some(Option(payload_type)) =>
            match flatten(payload_type) {
              Some(payload) => Some([I32] + payload)
              None => None
            }
          Some(Result(ok_type, err_type)) => {
            let ok_payload = match ok_type {
              Some(value) =>
                match flatten(value) {
                  Some(flat) => flat
                  None => return None
                }
              None => []
            }
            let err_payload = match err_type {
              Some(value) =>
                match flatten(value) {
                  Some(flat) => flat
                  None => return None
                }
              None => []
            }
            let max_length = if ok_payload.length() > err_payload.length() {
              ok_payload.length()
            } else {
              err_payload.length()
            }
            let joined : Array[@types.ValueType] = []
            for index in 0..<max_length {
              let current = match
                (ok_payload.get(index), err_payload.get(index)) {
                (Some(ok), Some(err)) => Some(join_flat(ok, err))
                (Some(ok), None) => Some(ok)
                (None, Some(err)) => Some(err)
                (None, None) => None
              }
              match current {
                Some(core_type) => joined.push(core_type)
                None => ()
              }
            }
            Some([I32] + joined)
          }
          Some(Flags(labels)) =>
            Some(if labels.length() <= 32 { [I32] } else { [I64] })
          Some(Enum(_))
          | Some(Own(_))
          | Some(Borrow(_))
          | Some(ResourceType(_, _, _, _))
          | Some(Stream(_))
          | Some(Future(_)) => Some([I32])
          Some(List(_)) => Some([pointer_type, pointer_type])
          _ => None
        }
        visiting.remove(idx)
        result
      }
    }
  }

  flatten(ty)
}

///|
/// Return the Canonical ABI core signature produced by `canon lower`.
///
/// More than sixteen flat parameters use one indirect pointer. A result with
/// more than one flat value appends an indirect result pointer to the core
/// parameters.
pub fn canonical_lower_core_func_type(
  func_type : FuncType,
  types : Array[TypeDef?],
  pointer_type : @types.ValueType,
) -> @types.FuncType? {
  let flat_params : Array[@types.ValueType] = []
  for param in func_type.params {
    match canonical_flat_types(param.ty, types, pointer_type) {
      Some(flat) =>
        for core_type in flat {
          flat_params.push(core_type)
        }
      None => return None
    }
  }
  let flat_results = match func_type.result {
    Some(result) =>
      match canonical_flat_types(result, types, pointer_type) {
        Some(flat) => flat
        None => return None
      }
    None => []
  }
  let params : Array[@types.ValueType] = if flat_params.length() > 16 {
    [pointer_type]
  } else {
    flat_params
  }
  let results : Array[@types.ValueType] = if flat_results.length() == 1 {
    flat_results
  } else if flat_results.length() == 0 {
    []
  } else {
    params.push(pointer_type)
    []
  }
  Some({ params, results, })
}

///|
/// Return the Canonical ABI core signature consumed by `canon lift`.
///
/// More than sixteen flat parameters use one indirect pointer. A result with
/// more than one flat value is returned as a pointer to the result area.
pub fn canonical_lift_core_func_type(
  func_type : FuncType,
  types : Array[TypeDef?],
  pointer_type : @types.ValueType,
) -> @types.FuncType? {
  let flat_params : Array[@types.ValueType] = []
  for param in func_type.params {
    match canonical_flat_types(param.ty, types, pointer_type) {
      Some(flat) =>
        for core_type in flat {
          flat_params.push(core_type)
        }
      None => return None
    }
  }
  let flat_results = match func_type.result {
    Some(result) =>
      match canonical_flat_types(result, types, pointer_type) {
        Some(flat) => flat
        None => return None
      }
    None => []
  }
  let params = if flat_params.length() > 16 {
    [pointer_type]
  } else {
    flat_params
  }
  let results = if flat_results.length() > 1 {
    [pointer_type]
  } else {
    flat_results
  }
  Some({ params, results, })
}
