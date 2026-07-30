///|
fn variant_payload_layout(
  cases : Array[@component.VariantCase],
  types : Array[TypeDef?],
  mem_is_64 : Bool,
) -> (Int, Int) raise ComponentRuntimeError {
  let (tag_size, _) = discriminant_layout(cases.length())
  let mut payload_alignment = 1
  for case in cases {
    if case.ty is Some(payload_ty) {
      let (_, alignment) = canonical_memory_layout(payload_ty, types, mem_is_64)
      if alignment > payload_alignment {
        payload_alignment = alignment
      }
    }
  }
  (align_to(tag_size, payload_alignment), payload_alignment)
}

///|
fn store_flat_component_value_to_memory(
  mem : @runtime.Memory,
  addr : Int,
  ty : ValType,
  values : Array[@types.Value],
  types : Array[TypeDef?],
  mem_is_64 : Bool,
) -> Unit raise ComponentRuntimeError {
  let mut cursor = 0
  fn take() -> @types.Value raise ComponentRuntimeError {
    if cursor >= values.length() {
      raise HostCallError("type mismatch")
    }
    let value = values[cursor]
    cursor += 1
    value
  }

  fn store_simple(
    value_ty : ValType,
    value_addr : Int,
  ) -> Unit raise ComponentRuntimeError {
    let storage = flat_storage_for_valtype(value_ty, types, mem_is_64)
    let (offsets, _, _) = layout_of_flat_storage_fields(storage)
    for i in 0..<storage.length() {
      store_storage_value(mem, value_addr + offsets[i], take(), storage[i])
    }
  }

  fn store_inner(
    value_ty : ValType,
    value_addr : Int,
  ) -> Unit raise ComponentRuntimeError {
    match resolve_valtype(value_ty, types) {
      Prim(_) => store_simple(value_ty, value_addr)
      TypeIdx(type_idx) =>
        match types.get(type_idx) {
          Some(Some(Tuple(items))) => {
            let mut offset = 0
            for item in items {
              let (size, alignment) = canonical_memory_layout(
                item, types, mem_is_64,
              )
              offset = align_to(offset, alignment)
              store_inner(item, value_addr + offset)
              offset += size
            }
          }
          Some(Some(Record(fields))) => {
            let mut offset = 0
            for field in fields {
              let (size, alignment) = canonical_memory_layout(
                field.ty,
                types,
                mem_is_64,
              )
              offset = align_to(offset, alignment)
              store_inner(field.ty, value_addr + offset)
              offset += size
            }
          }
          Some(Some(Variant(cases))) => {
            let tag = match take() {
              I32(value) => value
              _ => raise HostCallError("type mismatch")
            }
            if tag < 0 || tag >= cases.length() {
              raise CanonCallError("invalid variant discriminant")
            }
            let (tag_size, tag_alignment) = discriminant_layout(cases.length())
            store_storage_value(mem, value_addr, I32(tag), {
              vt: I32,
              size: tag_size,
              align: tag_alignment,
            })
            let all_flat = core_types_for_valtype(
              TypeIdx(type_idx),
              types,
              mem_is_64,
            )
            let joined_values : Array[@types.Value] = []
            for _ in 1..<all_flat.length() {
              joined_values.push(take())
            }
            if cases[tag].ty is Some(payload_ty) {
              let payload_types = core_types_for_valtype(
                payload_ty, types, mem_is_64,
              )
              let payload_values : Array[@types.Value] = []
              for i in 0..<payload_types.length() {
                payload_values.push(
                  coerce_flat_value(
                    joined_values[i],
                    all_flat[i + 1],
                    payload_types[i],
                  ),
                )
              }
              let (payload_offset, _) = variant_payload_layout(
                cases, types, mem_is_64,
              )
              store_flat_component_value_to_memory(
                mem,
                value_addr + payload_offset,
                payload_ty,
                payload_values,
                types,
                mem_is_64,
              )
            }
          }
          Some(Some(Option(payload_ty))) => {
            let tag = match take() {
              I32(value) => value
              _ => raise HostCallError("type mismatch")
            }
            if tag != 0 && tag != 1 {
              raise CanonCallError("invalid variant discriminant")
            }
            store_storage_value(mem, value_addr, I32(tag), {
              vt: I32,
              size: 1,
              align: 1,
            })
            let payload_types = core_types_for_valtype(
              payload_ty, types, mem_is_64,
            )
            let payload_values : Array[@types.Value] = []
            for _ in payload_types {
              payload_values.push(take())
            }
            if tag == 1 {
              let (_, payload_alignment) = canonical_memory_layout(
                payload_ty, types, mem_is_64,
              )
              store_flat_component_value_to_memory(
                mem,
                value_addr + align_to(1, payload_alignment),
                payload_ty,
                payload_values,
                types,
                mem_is_64,
              )
            }
          }
          Some(Some(Result(ok_ty, error_ty))) => {
            let tag = match take() {
              I32(value) => value
              _ => raise HostCallError("type mismatch")
            }
            if tag != 0 && tag != 1 {
              raise CanonCallError("invalid variant discriminant")
            }
            store_storage_value(mem, value_addr, I32(tag), {
              vt: I32,
              size: 1,
              align: 1,
            })
            let all_flat = core_types_for_valtype(
              TypeIdx(type_idx),
              types,
              mem_is_64,
            )
            let joined_values : Array[@types.Value] = []
            for _ in 1..<all_flat.length() {
              joined_values.push(take())
            }
            let payload_ty = if tag == 0 { ok_ty } else { error_ty }
            if payload_ty is Some(payload) {
              let payload_types = core_types_for_valtype(
                payload, types, mem_is_64,
              )
              let payload_values : Array[@types.Value] = []
              for i in 0..<payload_types.length() {
                payload_values.push(
                  coerce_flat_value(
                    joined_values[i],
                    all_flat[i + 1],
                    payload_types[i],
                  ),
                )
              }
              let mut payload_alignment = 1
              for candidate in [ok_ty, error_ty] {
                if candidate is Some(candidate_ty) {
                  let (_, alignment) = canonical_memory_layout(
                    candidate_ty, types, mem_is_64,
                  )
                  if alignment > payload_alignment {
                    payload_alignment = alignment
                  }
                }
              }
              store_flat_component_value_to_memory(
                mem,
                value_addr + align_to(1, payload_alignment),
                payload,
                payload_values,
                types,
                mem_is_64,
              )
            }
          }
          Some(Some(List(_)))
          | Some(Some(Enum(_)))
          | Some(Some(Flags(_)))
          | Some(Some(Own(_)))
          | Some(Some(Borrow(_)))
          | Some(Some(ResourceType(_, _, _, _)))
          | Some(Some(Stream(_)))
          | Some(Some(Future(_)))
          | Some(Some(DefValType(_))) => store_simple(value_ty, value_addr)
          _ => raise HostCallError("unsupported memory value type")
        }
    }
  }

  store_inner(ty, addr)
  if cursor != values.length() {
    raise HostCallError("type mismatch")
  }
}

///|
fn load_flat_component_value_from_memory(
  mem : @runtime.Memory,
  addr : Int,
  ty : ValType,
  types : Array[TypeDef?],
  mem_is_64 : Bool,
) -> Array[@types.Value] raise ComponentRuntimeError {
  fn load_simple(
    value_ty : ValType,
    value_addr : Int,
  ) -> Array[@types.Value] raise ComponentRuntimeError {
    let storage = flat_storage_for_valtype(value_ty, types, mem_is_64)
    let (offsets, _, _) = layout_of_flat_storage_fields(storage)
    let out : Array[@types.Value] = []
    for i in 0..<storage.length() {
      out.push(load_storage_value(mem, value_addr + offsets[i], storage[i]))
    }
    out
  }

  match resolve_valtype(ty, types) {
    Prim(_) => load_simple(ty, addr)
    TypeIdx(type_idx) =>
      match types.get(type_idx) {
        Some(Some(Tuple(items))) => {
          let out : Array[@types.Value] = []
          let mut offset = 0
          for item in items {
            let (size, alignment) = canonical_memory_layout(
              item, types, mem_is_64,
            )
            offset = align_to(offset, alignment)
            for
              value in load_flat_component_value_from_memory(
                mem,
                addr + offset,
                item,
                types,
                mem_is_64,
              ) {
              out.push(value)
            }
            offset += size
          }
          out
        }
        Some(Some(Record(fields))) => {
          let out : Array[@types.Value] = []
          let mut offset = 0
          for field in fields {
            let (size, alignment) = canonical_memory_layout(
              field.ty,
              types,
              mem_is_64,
            )
            offset = align_to(offset, alignment)
            for
              value in load_flat_component_value_from_memory(
                mem,
                addr + offset,
                field.ty,
                types,
                mem_is_64,
              ) {
              out.push(value)
            }
            offset += size
          }
          out
        }
        Some(Some(Variant(cases))) => {
          let (tag_size, tag_alignment) = discriminant_layout(cases.length())
          let tag = match
            load_storage_value(mem, addr, {
              vt: I32,
              size: tag_size,
              align: tag_alignment,
            }) {
            I32(value) => value
            _ => raise HostCallError("type mismatch")
          }
          if tag < 0 || tag >= cases.length() {
            raise CanonCallError("invalid variant discriminant")
          }
          let all_flat = core_types_for_valtype(
            TypeIdx(type_idx),
            types,
            mem_is_64,
          )
          let out : Array[@types.Value] = [I32(tag)]
          for i in 1..<all_flat.length() {
            out.push(zero_flat_value(all_flat[i]))
          }
          if cases[tag].ty is Some(payload_ty) {
            let (payload_offset, _) = variant_payload_layout(
              cases, types, mem_is_64,
            )
            let payload_values = load_flat_component_value_from_memory(
              mem,
              addr + payload_offset,
              payload_ty,
              types,
              mem_is_64,
            )
            let payload_types = core_types_for_valtype(
              payload_ty, types, mem_is_64,
            )
            for i in 0..<payload_values.length() {
              out[i + 1] = coerce_flat_value(
                payload_values[i],
                payload_types[i],
                all_flat[i + 1],
              )
            }
          }
          out
        }
        Some(Some(Option(payload_ty))) => {
          let tag = match
            load_storage_value(mem, addr, { vt: I32, size: 1, align: 1 }) {
            I32(value) => value
            _ => raise HostCallError("type mismatch")
          }
          if tag != 0 && tag != 1 {
            raise CanonCallError("invalid variant discriminant")
          }
          let payload_types = core_types_for_valtype(
            payload_ty, types, mem_is_64,
          )
          let out : Array[@types.Value] = [I32(tag)]
          if tag == 0 {
            for payload_type in payload_types {
              out.push(zero_flat_value(payload_type))
            }
          } else {
            let (_, payload_alignment) = canonical_memory_layout(
              payload_ty, types, mem_is_64,
            )
            for
              value in load_flat_component_value_from_memory(
                mem,
                addr + align_to(1, payload_alignment),
                payload_ty,
                types,
                mem_is_64,
              ) {
              out.push(value)
            }
          }
          out
        }
        Some(Some(Result(ok_ty, error_ty))) => {
          let tag = match
            load_storage_value(mem, addr, { vt: I32, size: 1, align: 1 }) {
            I32(value) => value
            _ => raise HostCallError("type mismatch")
          }
          if tag != 0 && tag != 1 {
            raise CanonCallError("invalid variant discriminant")
          }
          let all_flat = core_types_for_valtype(
            TypeIdx(type_idx),
            types,
            mem_is_64,
          )
          let out : Array[@types.Value] = [I32(tag)]
          for i in 1..<all_flat.length() {
            out.push(zero_flat_value(all_flat[i]))
          }
          let payload_ty = if tag == 0 { ok_ty } else { error_ty }
          if payload_ty is Some(payload) {
            let mut payload_alignment = 1
            for candidate in [ok_ty, error_ty] {
              if candidate is Some(candidate_ty) {
                let (_, alignment) = canonical_memory_layout(
                  candidate_ty, types, mem_is_64,
                )
                if alignment > payload_alignment {
                  payload_alignment = alignment
                }
              }
            }
            let payload_values = load_flat_component_value_from_memory(
              mem,
              addr + align_to(1, payload_alignment),
              payload,
              types,
              mem_is_64,
            )
            let payload_types = core_types_for_valtype(
              payload, types, mem_is_64,
            )
            for i in 0..<payload_values.length() {
              out[i + 1] = coerce_flat_value(
                payload_values[i],
                payload_types[i],
                all_flat[i + 1],
              )
            }
          }
          out
        }
        Some(Some(List(_)))
        | Some(Some(Enum(_)))
        | Some(Some(Flags(_)))
        | Some(Some(Own(_)))
        | Some(Some(Borrow(_)))
        | Some(Some(ResourceType(_, _, _, _)))
        | Some(Some(Stream(_)))
        | Some(Some(Future(_)))
        | Some(Some(DefValType(_))) => load_simple(ty, addr)
        _ => raise HostCallError("unsupported memory value type")
      }
  }
}
