///|
fn lift_component_value_from_flat(
  ty : ValType,
  flat_vals : Array[@types.Value],
  types : Array[TypeDef?],
  mem : @runtime.Memory?,
  mem_is_64 : Bool,
  encoding : StringEncoding,
) -> ComponentValue raise ComponentRuntimeError {
  let mut idx = 0
  fn take(
    vals : Array[@types.Value],
  ) -> @types.Value raise ComponentRuntimeError {
    if idx < 0 || idx >= vals.length() {
      raise HostCallError("type mismatch")
    }
    let v = vals[idx]
    idx += 1
    v
  }

  fn lift_inner(
    ty : ValType,
    vals : Array[@types.Value],
  ) -> ComponentValue raise ComponentRuntimeError {
    match resolve_valtype(ty, types) {
      Prim(p) =>
        match p {
          String | ErrorContext => {
            let m = match mem {
              Some(m) => m
              None => raise MissingCanonMemory
            }
            let (ptr, len) = if mem_is_64 {
              match (take(vals), take(vals)) {
                (@types.Value::I64(p), @types.Value::I64(l)) =>
                  (p.to_int(), l.to_int())
                _ => raise HostCallError("type mismatch")
              }
            } else {
              match (take(vals), take(vals)) {
                (@types.Value::I32(p), @types.Value::I32(l)) => (p, l)
                _ => raise HostCallError("type mismatch")
              }
            }
            let s = read_string_from_memory_with_encoding(m, ptr, len, encoding)
            if p == String {
              ComponentValue::String(s)
            } else {
              ComponentValue::ErrorContext(s)
            }
          }
          _ =>
            match (p, take(vals)) {
              (Bool, @types.Value::I32(n)) => ComponentValue::Bool(n != 0)
              (S8, @types.Value::I32(n)) => ComponentValue::S8(trunc_s8(n))
              (U8, @types.Value::I32(n)) => ComponentValue::U8(trunc_u8(n))
              (S16, @types.Value::I32(n)) => ComponentValue::S16(trunc_s16(n))
              (U16, @types.Value::I32(n)) => ComponentValue::U16(trunc_u16(n))
              (S32, @types.Value::I32(n)) => ComponentValue::S32(n)
              (U32, @types.Value::I32(n)) => ComponentValue::U32(trunc_u32(n))
              (Char, @types.Value::I32(n)) =>
                ComponentValue::Char(char_from_canon_i32(n))
              (S64, @types.Value::I64(n)) => ComponentValue::S64(n)
              (U64, @types.Value::I64(n)) => ComponentValue::U64(n)
              (F32, @types.Value::F32(f)) => ComponentValue::F32(f)
              (F64, @types.Value::F64(f)) => ComponentValue::F64(f)
              _ => raise HostCallError("type mismatch")
            }
        }
      TypeIdx(ti) =>
        match types.get(ti) {
          Some(Some(TypeDef::Tuple(tys))) => {
            let items : Array[ComponentValue] = []
            for t in tys {
              items.push(lift_inner(t, vals))
            }
            ComponentValue::Tuple(items)
          }
          Some(Some(TypeDef::Record(fields))) => {
            let items : Array[ComponentValue] = []
            for f in fields {
              items.push(lift_inner(f.ty, vals))
            }
            ComponentValue::Tuple(items)
          }
          Some(Some(TypeDef::List(elem_ty))) => {
            let m = match mem {
              Some(m) => m
              None => raise MissingCanonMemory
            }
            let (ptr, len) = if mem_is_64 {
              match (take(vals), take(vals)) {
                (@types.Value::I64(p), @types.Value::I64(l)) =>
                  (p.to_int(), l.to_int())
                _ => raise HostCallError("type mismatch")
              }
            } else {
              match (take(vals), take(vals)) {
                (@types.Value::I32(p), @types.Value::I32(l)) => (p, l)
                _ => raise HostCallError("type mismatch")
              }
            }
            let elem_flat_types = core_types_for_valtype(
              elem_ty, types, mem_is_64,
            )
            let (offsets, elem_size, elem_align) = layout_of_flat_types(
              elem_flat_types,
            )
            let stride = align_to(elem_size, elem_align)
            let items : Array[ComponentValue] = []
            for i in 0..<len {
              let base = ptr + stride * i
              let elem_vals : Array[@types.Value] = []
              for j in 0..<elem_flat_types.length() {
                elem_vals.push(
                  load_flat_value(m, base + offsets[j], elem_flat_types[j]),
                )
              }
              items.push(
                lift_component_value_from_flat(
                  elem_ty, elem_vals, types, mem, mem_is_64, encoding,
                ),
              )
            }
            ComponentValue::List(items)
          }
          Some(Some(TypeDef::Stream(_))) | Some(Some(TypeDef::Future(_))) =>
            match take(vals) {
              @types.Value::I32(n) => ComponentValue::U32(n)
              _ => raise HostCallError("type mismatch")
            }
          Some(Some(TypeDef::Variant(cases))) => {
            let tag = match take(vals) {
              @types.Value::I32(n) => n
              _ => raise HostCallError("type mismatch")
            }
            if tag < 0 || tag >= cases.length() {
              raise CanonCallError("invalid variant discriminant")
            }
            let all_flat = core_types_for_valtype(TypeIdx(ti), types, mem_is_64)
            let joined_types : Array[@types.ValueType] = []
            for i in 1..<all_flat.length() {
              joined_types.push(all_flat[i])
            }
            let joined_vals : Array[@types.Value] = []
            for vt in joined_types {
              let v = take(vals)
              joined_vals.push(coerce_flat_value(v, vt, vt))
            }
            match cases[tag].ty {
              None => ComponentValue::Variant(tag, None)
              Some(payload_ty) => {
                let payload_flat_types = core_types_for_valtype(
                  payload_ty, types, mem_is_64,
                )
                let payload_vals : Array[@types.Value] = []
                for i in 0..<payload_flat_types.length() {
                  payload_vals.push(
                    coerce_flat_value(
                      joined_vals[i],
                      joined_types[i],
                      payload_flat_types[i],
                    ),
                  )
                }
                let payload = lift_component_value_from_flat(
                  payload_ty, payload_vals, types, mem, mem_is_64, encoding,
                )
                ComponentValue::Variant(tag, Some(payload))
              }
            }
          }
          Some(Some(TypeDef::Option(payload_ty))) => {
            let tag = match take(vals) {
              @types.Value::I32(n) => n
              _ => raise HostCallError("type mismatch")
            }
            if tag != 0 && tag != 1 {
              raise CanonCallError("invalid variant discriminant")
            }
            let all_flat = core_types_for_valtype(TypeIdx(ti), types, mem_is_64)
            let joined_types : Array[@types.ValueType] = []
            for i in 1..<all_flat.length() {
              joined_types.push(all_flat[i])
            }
            let joined_vals : Array[@types.Value] = []
            for vt in joined_types {
              let v = take(vals)
              joined_vals.push(coerce_flat_value(v, vt, vt))
            }
            if tag == 0 {
              ComponentValue::Variant(0, None)
            } else {
              let payload_flat_types = core_types_for_valtype(
                payload_ty, types, mem_is_64,
              )
              let payload_vals : Array[@types.Value] = []
              for i in 0..<payload_flat_types.length() {
                payload_vals.push(
                  coerce_flat_value(
                    joined_vals[i],
                    joined_types[i],
                    payload_flat_types[i],
                  ),
                )
              }
              let payload = lift_component_value_from_flat(
                payload_ty, payload_vals, types, mem, mem_is_64, encoding,
              )
              ComponentValue::Variant(1, Some(payload))
            }
          }
          Some(Some(TypeDef::Result(ok_ty, err_ty))) => {
            let tag = match take(vals) {
              @types.Value::I32(n) => n
              _ => raise HostCallError("type mismatch")
            }
            if tag != 0 && tag != 1 {
              raise CanonCallError("invalid variant discriminant")
            }
            let all_flat = core_types_for_valtype(TypeIdx(ti), types, mem_is_64)
            let joined_types : Array[@types.ValueType] = []
            for i in 1..<all_flat.length() {
              joined_types.push(all_flat[i])
            }
            let joined_vals : Array[@types.Value] = []
            for vt in joined_types {
              let v = take(vals)
              joined_vals.push(coerce_flat_value(v, vt, vt))
            }
            let payload_ty = if tag == 0 { ok_ty } else { err_ty }
            match payload_ty {
              None => ComponentValue::Variant(tag, None)
              Some(pt) => {
                let payload_flat_types = core_types_for_valtype(
                  pt, types, mem_is_64,
                )
                let payload_vals : Array[@types.Value] = []
                for i in 0..<payload_flat_types.length() {
                  payload_vals.push(
                    coerce_flat_value(
                      joined_vals[i],
                      joined_types[i],
                      payload_flat_types[i],
                    ),
                  )
                }
                let payload = lift_component_value_from_flat(
                  pt, payload_vals, types, mem, mem_is_64, encoding,
                )
                ComponentValue::Variant(tag, Some(payload))
              }
            }
          }
          Some(Some(TypeDef::Flags(labels))) => {
            let nbits = labels.length()
            if nbits <= 32 {
              let raw = match take(vals) {
                @types.Value::I32(n) => n.reinterpret_as_uint()
                _ => raise HostCallError("type mismatch")
              }
              let masked = if nbits == 32 {
                raw
              } else {
                raw & ((1U << nbits) - 1U)
              }
              ComponentValue::U32(masked.reinterpret_as_int())
            } else {
              let raw = match take(vals) {
                @types.Value::I64(n) => n.reinterpret_as_uint64()
                _ => raise HostCallError("type mismatch")
              }
              let masked = if nbits == 64 {
                raw
              } else {
                raw & ((1UL << nbits) - 1UL)
              }
              ComponentValue::U64(masked.reinterpret_as_int64())
            }
          }
          Some(Some(TypeDef::Enum(labels))) => {
            let n = match take(vals) {
              @types.Value::I32(n) => n
              _ => raise HostCallError("type mismatch")
            }
            if n < 0 || n >= labels.length() {
              raise CanonCallError("invalid enum discriminant")
            }
            ComponentValue::U32(n)
          }
          Some(Some(TypeDef::Own(_)))
          | Some(Some(TypeDef::Borrow(_)))
          | Some(Some(TypeDef::ResourceType(_, _, _, _))) =>
            match take(vals) {
              @types.Value::I32(handle) => ComponentValue::U32(handle)
              _ => raise HostCallError("type mismatch")
            }
          _ => raise HostCallError("type mismatch")
        }
    }
  }

  let v = lift_inner(ty, flat_vals)
  if idx != flat_vals.length() {
    raise HostCallError("type mismatch")
  }
  v
}

///|
fn component_args_to_core(
  args : Array[ComponentValue],
  func_type : FuncType,
  types : Array[TypeDef?],
  resources : CanonResources,
  store : @runtime.Store,
  caller_table : ResourceTable,
  callee_table : ResourceTable,
) -> Array[@types.Value] raise ComponentRuntimeError {
  // Cache memory/realloc handles (if provided) for canonical ABI operations.
  let mut mem : @runtime.Memory? = None
  let mut mem_is_64 = false
  match resources.mem_addr {
    Some(addr) => {
      let m = store.get_mem(addr) catch {
        e => raise CanonCallError(e.to_string())
      }
      mem_is_64 = m.is_memory64()
      mem = Some(m)
    }
    None => ()
  }
  fn lower_value(
    val : ComponentValue,
    ty : ValType,
  ) -> Array[@types.Value] raise ComponentRuntimeError {
    match resolve_valtype(ty, types) {
      Prim(p) =>
        match (p, val) {
          (Bool, ComponentValue::Bool(b)) =>
            [@types.Value::I32(if b { 1 } else { 0 })]
          (S8, ComponentValue::S8(n))
          | (U8, ComponentValue::U8(n))
          | (S16, ComponentValue::S16(n))
          | (U16, ComponentValue::U16(n))
          | (S32, ComponentValue::S32(n))
          | (U32, ComponentValue::U32(n)) => [@types.Value::I32(n)]
          (S64, ComponentValue::S64(n)) | (U64, ComponentValue::U64(n)) =>
            [@types.Value::I64(n)]
          (F32, ComponentValue::F32(f)) => [@types.Value::F32(f)]
          (F64, ComponentValue::F64(f)) => [@types.Value::F64(f)]
          (Char, ComponentValue::Char(c)) => [@types.Value::I32(c.to_int())]
          (String, ComponentValue::String(s))
          | (ErrorContext, ComponentValue::ErrorContext(s)) => {
            let m = match mem {
              Some(m) => m
              None => raise MissingCanonMemory
            }
            let realloc = match resources.realloc {
              Some(r) => r
              None => raise MissingCanonRealloc
            }
            let (bytes, canon_len, align) = encode_string_for_canon(
              s,
              resources.encoding,
            )
            let ptr = write_bytes_to_memory_with_align(
              store, m, realloc, mem_is_64, bytes, align,
            )
            if mem_is_64 {
              [
                @types.Value::I64(ptr.to_int64()),
                @types.Value::I64(canon_len.to_int64()),
              ]
            } else {
              [@types.Value::I32(ptr), @types.Value::I32(canon_len)]
            }
          }
          _ => raise HostCallError("argument type mismatch")
        }
      TypeIdx(ti) =>
        match types.get(ti) {
          Some(Some(TypeDef::Tuple(tys))) =>
            match val {
              ComponentValue::Tuple(items) =>
                if items.length() != tys.length() {
                  raise HostCallError("argument type mismatch")
                } else {
                  let out : Array[@types.Value] = []
                  for i in 0..<tys.length() {
                    for v in lower_value(items[i], tys[i]) {
                      out.push(v)
                    }
                  }
                  out
                }
              _ => raise HostCallError("argument type mismatch")
            }
          Some(Some(TypeDef::Record(fields))) =>
            match val {
              ComponentValue::Tuple(items) =>
                if items.length() != fields.length() {
                  raise HostCallError("argument type mismatch")
                } else {
                  let out : Array[@types.Value] = []
                  for i in 0..<fields.length() {
                    for v in lower_value(items[i], fields[i].ty) {
                      out.push(v)
                    }
                  }
                  out
                }
              _ => raise HostCallError("argument type mismatch")
            }
          Some(Some(TypeDef::List(elem_ty))) =>
            match val {
              ComponentValue::List(items) => {
                let m = match mem {
                  Some(m) => m
                  None => raise MissingCanonMemory
                }
                let realloc = match resources.realloc {
                  Some(r) => r
                  None => raise MissingCanonRealloc
                }
                let elem_flat = core_types_for_valtype(
                  elem_ty, types, mem_is_64,
                )
                let (_offs, elem_size, elem_align) = layout_of_flat_types(
                  elem_flat,
                )
                let stride = align_to(elem_size, elem_align)
                let total_size = stride * items.length()
                let ptr = alloc_realloc_area(
                  store, m, realloc, mem_is_64, total_size, elem_align,
                )
                // TODO: store list elements for non-empty lists.
                if items.length() > 0 {
                  raise HostCallError("unsupported param type")
                }
                let len = items.length()
                if mem_is_64 {
                  [
                    @types.Value::I64(ptr.to_int64()),
                    @types.Value::I64(len.to_int64()),
                  ]
                } else {
                  [@types.Value::I32(ptr), @types.Value::I32(len)]
                }
              }
              _ => raise HostCallError("argument type mismatch")
            }
          Some(Some(TypeDef::Variant(cases))) => {
            let all_flat = core_types_for_valtype(TypeIdx(ti), types, mem_is_64)
            let joined_types : Array[@types.ValueType] = []
            for i in 1..<all_flat.length() {
              joined_types.push(all_flat[i])
            }
            match val {
              ComponentValue::Variant(tag, payload_opt) => {
                if tag < 0 || tag >= cases.length() {
                  raise HostCallError("invalid variant discriminant")
                }
                let payload_vals : Array[@types.Value] = match cases[tag].ty {
                  None =>
                    match payload_opt {
                      None => []
                      Some(_) => raise HostCallError("argument type mismatch")
                    }
                  Some(payload_ty) =>
                    match payload_opt {
                      None => raise HostCallError("argument type mismatch")
                      Some(pv) => lower_value(pv, payload_ty)
                    }
                }
                let out : Array[@types.Value] = [@types.Value::I32(tag)]
                for i in 0..<joined_types.length() {
                  if i < payload_vals.length() {
                    let actual = payload_vals[i]
                    let actual_vt = match actual {
                      @types.Value::I32(_) => @types.ValueType::I32
                      @types.Value::I64(_) => @types.ValueType::I64
                      @types.Value::F32(_) => @types.ValueType::F32
                      @types.Value::F64(_) => @types.ValueType::F64
                      _ => @types.ValueType::I32
                    }
                    out.push(
                      coerce_flat_value(actual, actual_vt, joined_types[i]),
                    )
                  } else {
                    out.push(zero_flat_value(joined_types[i]))
                  }
                }
                out
              }
              _ => raise HostCallError("argument type mismatch")
            }
          }
          Some(Some(TypeDef::Option(payload_ty))) =>
            match val {
              ComponentValue::Variant(tag, payload_opt) =>
                if tag == 0 {
                  // none
                  if payload_opt is Some(_) {
                    raise HostCallError("argument type mismatch")
                  }
                  // tag + payload slots (same as payload flat types)
                  let out : Array[@types.Value] = [@types.Value::I32(0)]
                  let payload_flat = core_types_for_valtype(
                    payload_ty, types, mem_is_64,
                  )
                  for vt in payload_flat {
                    out.push(zero_flat_value(vt))
                  }
                  out
                } else if tag == 1 {
                  let payload = match payload_opt {
                    Some(p) => p
                    None => raise HostCallError("argument type mismatch")
                  }
                  let payload_vals = lower_value(payload, payload_ty)
                  [@types.Value::I32(1)] + payload_vals
                } else {
                  raise HostCallError("invalid variant discriminant")
                }
              _ => raise HostCallError("argument type mismatch")
            }
          Some(Some(TypeDef::Result(ok_ty, err_ty))) =>
            match val {
              ComponentValue::Variant(tag, payload_opt) => {
                let payload_ty = if tag == 0 {
                  ok_ty
                } else if tag == 1 {
                  err_ty
                } else {
                  raise HostCallError("invalid variant discriminant")
                }
                let payload_vals : Array[@types.Value] = match payload_ty {
                  None =>
                    match payload_opt {
                      None => []
                      Some(_) => raise HostCallError("argument type mismatch")
                    }
                  Some(pt) =>
                    match payload_opt {
                      Some(p) => lower_value(p, pt)
                      None => raise HostCallError("argument type mismatch")
                    }
                }
                // Join ok/err payload slots by using the result's flattened payload types.
                let all_flat = core_types_for_valtype(
                  TypeIdx(ti),
                  types,
                  mem_is_64,
                )
                let joined_types : Array[@types.ValueType] = []
                for i in 1..<all_flat.length() {
                  joined_types.push(all_flat[i])
                }
                let out : Array[@types.Value] = [@types.Value::I32(tag)]
                for i in 0..<joined_types.length() {
                  if i < payload_vals.length() {
                    let actual = payload_vals[i]
                    let actual_vt = match actual {
                      @types.Value::I32(_) => @types.ValueType::I32
                      @types.Value::I64(_) => @types.ValueType::I64
                      @types.Value::F32(_) => @types.ValueType::F32
                      @types.Value::F64(_) => @types.ValueType::F64
                      _ => @types.ValueType::I32
                    }
                    out.push(
                      coerce_flat_value(actual, actual_vt, joined_types[i]),
                    )
                  } else {
                    out.push(zero_flat_value(joined_types[i]))
                  }
                }
                out
              }
              _ => raise HostCallError("argument type mismatch")
            }
          Some(Some(TypeDef::Flags(labels))) => {
            let nbits = labels.length()
            if nbits <= 32 {
              let raw = match val {
                ComponentValue::U32(n) => n.reinterpret_as_uint()
                ComponentValue::S32(n) => n.reinterpret_as_uint()
                _ => raise HostCallError("argument type mismatch")
              }
              let masked = if nbits == 32 {
                raw
              } else {
                raw & ((1U << nbits) - 1U)
              }
              [@types.Value::I32(masked.reinterpret_as_int())]
            } else {
              let raw = match val {
                ComponentValue::U64(n) => n.reinterpret_as_uint64()
                ComponentValue::S64(n) => n.reinterpret_as_uint64()
                _ => raise HostCallError("argument type mismatch")
              }
              let masked = if nbits == 64 {
                raw
              } else {
                raw & ((1UL << nbits) - 1UL)
              }
              [@types.Value::I64(masked.reinterpret_as_int64())]
            }
          }
          Some(Some(TypeDef::Enum(labels))) => {
            let n = match val {
              ComponentValue::U32(n) => n
              ComponentValue::S32(n) => n
              _ => raise HostCallError("argument type mismatch")
            }
            if n < 0 || n >= labels.length() {
              raise HostCallError("invalid enum discriminant")
            }
            [@types.Value::I32(n)]
          }
          Some(Some(TypeDef::Borrow(resource_tyidx))) => {
            let expected_type_id = match types.get(resource_tyidx) {
              Some(Some(TypeDef::ResourceType(id, _, _, _))) => id
              _ => raise HostCallError("unsupported param type")
            }
            let handle = match val {
              ComponentValue::U32(h) => h
              ComponentValue::S32(h) => h
              _ => raise HostCallError("argument type mismatch")
            }
            match caller_table.get(handle) {
              Some(entry) =>
                if entry.type_id != expected_type_id {
                  raise CanonCallError(
                    "handle index \{handle} used with the wrong type",
                  )
                } else {
                  [@types.Value::I32(entry.rep)]
                }
              None => raise CanonCallError("unknown handle index \{handle}")
            }
          }
          Some(Some(TypeDef::Own(resource_tyidx))) => {
            let expected_type_id = match types.get(resource_tyidx) {
              Some(Some(TypeDef::ResourceType(id, _, _, _))) => id
              _ => raise HostCallError("unsupported param type")
            }
            let handle = match val {
              ComponentValue::U32(h) => h
              ComponentValue::S32(h) => h
              _ => raise HostCallError("argument type mismatch")
            }
            if caller_table.id == callee_table.id {
              [@types.Value::I32(handle)]
            } else {
              let entry = match caller_table.free(handle) {
                Some(e) => e
                None => raise CanonCallError("unknown handle index \{handle}")
              }
              if entry.type_id != expected_type_id {
                raise CanonCallError(
                  "handle index \{handle} used with the wrong type",
                )
              }
              let new_handle = callee_table.alloc(entry)
              [@types.Value::I32(new_handle)]
            }
          }
          Some(Some(TypeDef::ResourceType(_, _, _, _))) =>
            match val {
              ComponentValue::U32(handle) => [@types.Value::I32(handle)]
              ComponentValue::S32(handle) => [@types.Value::I32(handle)]
              _ => raise HostCallError("argument type mismatch")
            }
          Some(Some(TypeDef::Stream(_))) | Some(Some(TypeDef::Future(_))) =>
            match val {
              ComponentValue::U32(handle) => [@types.Value::I32(handle)]
              ComponentValue::S32(handle) => [@types.Value::I32(handle)]
              _ => raise HostCallError("argument type mismatch")
            }
          _ => raise HostCallError("unsupported param type")
        }
    }
  }

  // Determine whether we must pass a pointer to the flattened arguments.
  let flat_param_types : Array[@types.ValueType] = []
  for p in func_type.params {
    for t in core_types_for_valtype(p.ty, types, mem_is_64) {
      flat_param_types.push(t)
    }
  }
  let indirect_params = flat_param_types.length() > 16
  let flat_vals : Array[@types.Value] = []
  for i, param in func_type.params {
    let val = if i < args.length() {
      args[i]
    } else {
      raise InvalidValueIndex(i)
    }
    for v in lower_value(val, param.ty) {
      flat_vals.push(v)
    }
  }
  if !indirect_params {
    return flat_vals
  }
  let m = match mem {
    Some(m) => m
    None => raise MissingCanonMemory
  }
  let realloc = match resources.realloc {
    Some(r) => r
    None => raise MissingCanonRealloc
  }
  let (offsets, size, struct_align) = layout_of_flat_types(flat_param_types)
  let ptr = alloc_realloc_area(store, m, realloc, mem_is_64, size, struct_align)
  if ptr.reinterpret_as_uint() % struct_align.reinterpret_as_uint() != 0U {
    raise CanonCallError("unaligned pointer")
  }
  for i in 0..<flat_vals.length() {
    store_flat_value(m, ptr + offsets[i], flat_vals[i])
  }
  if mem_is_64 {
    [@types.Value::I64(ptr.to_int64())]
  } else {
    [@types.Value::I32(ptr)]
  }
}

///|
fn core_results_to_component(
  results : Array[@types.Value],
  func_type : FuncType,
  types : Array[TypeDef?],
  resources : CanonResources,
  store : @runtime.Store,
  resource_table : ResourceTable,
) -> Array[ComponentValue] raise ComponentRuntimeError {
  fn resource_type_info(
    tyidx : Int,
    types : Array[TypeDef?],
  ) -> (Int, ResourceKind) raise ComponentRuntimeError {
    match types.get(tyidx) {
      Some(Some(TypeDef::ResourceType(id, _, _, kind))) => (id, kind)
      _ => raise HostCallError("invalid resource type")
    }
  }

  fn validate_resource_handle(
    handle : Int,
    expected_type_id : Int,
    expected_kind : ResourceKind,
    table : ResourceTable,
  ) -> Unit raise ComponentRuntimeError {
    match table.get(handle) {
      None =>
        raise CanonCallError(
          "unknown handle index \{handle}; index \{handle} is not a resource",
        )
      Some(entry) =>
        if entry.type_id < 0 {
          raise CanonCallError(
            "unknown handle index \{handle}; index \{handle} is not a resource",
          )
        } else if entry.type_id != expected_type_id {
          let expected_desc = if expected_kind == ResourceKind::GuestDefined {
            "guest-defined resource"
          } else {
            "host-defined resource"
          }
          let found_desc = if entry.kind == ResourceKind::GuestDefined {
            "guest-defined resource"
          } else {
            "host-defined resource"
          }
          let suffix = if entry.kind == expected_kind {
            "a different \{found_desc}"
          } else {
            found_desc
          }
          raise CanonCallError(
            "handle index \{handle} used with the wrong type, expected \{expected_desc} but found \{suffix}",
          )
        }
    }
  }

  match func_type.result {
    None => []
    Some(r) =>
      match resolve_valtype(r, types) {
        Prim(p) =>
          match p {
            Bool =>
              match results {
                [@types.Value::I32(n)] => [ComponentValue::Bool(n != 0)]
                _ => raise HostCallError("result type mismatch")
              }
            S8 | U8 | S16 | U16 | S32 | U32 | Char =>
              match results {
                [@types.Value::I32(n)] =>
                  match p {
                    Char => [ComponentValue::Char(char_from_canon_i32(n))]
                    S8 => [ComponentValue::S8(trunc_s8(n))]
                    U8 => [ComponentValue::U8(trunc_u8(n))]
                    S16 => [ComponentValue::S16(trunc_s16(n))]
                    U16 => [ComponentValue::U16(trunc_u16(n))]
                    S32 => [ComponentValue::S32(n)]
                    U32 => [ComponentValue::U32(trunc_u32(n))]
                    _ => raise HostCallError("result type mismatch")
                  }
                _ => raise HostCallError("result type mismatch")
              }
            S64 | U64 =>
              match results {
                [@types.Value::I64(n)] =>
                  if p == S64 {
                    [ComponentValue::S64(n)]
                  } else {
                    [ComponentValue::U64(n)]
                  }
                _ => raise HostCallError("result type mismatch")
              }
            F32 =>
              match results {
                [@types.Value::F32(n)] => [ComponentValue::F32(n)]
                _ => raise HostCallError("result type mismatch")
              }
            F64 =>
              match results {
                [@types.Value::F64(n)] => [ComponentValue::F64(n)]
                _ => raise HostCallError("result type mismatch")
              }
            String | ErrorContext => {
              let mem = match resources.mem_addr {
                Some(addr) =>
                  store.get_mem(addr) catch {
                    e => raise CanonCallError(e.to_string())
                  }
                None => raise MissingCanonMemory
              }
              let mem_is_64 = mem.is_memory64()
              let (ptr, len) = if mem_is_64 {
                match results {
                  [@types.Value::I64(p), @types.Value::I64(l)] =>
                    (p.to_int(), l.to_int())
                  [@types.Value::I64(p)] => {
                    let base = p.to_int()
                    let ptr64 = mem.load_i64(base) catch {
                      e => raise CanonCallError(e.to_string())
                    }
                    let len64 = mem.load_i64(base + 8) catch {
                      e => raise CanonCallError(e.to_string())
                    }
                    (ptr64.to_int(), len64.to_int())
                  }
                  _ => raise HostCallError("result type mismatch")
                }
              } else {
                match results {
                  [@types.Value::I32(p), @types.Value::I32(l)] => (p, l)
                  [@types.Value::I32(p)] => {
                    let ptr32 = mem.load_i32(p) catch {
                      e => raise CanonCallError(e.to_string())
                    }
                    let len32 = mem.load_i32(p + 4) catch {
                      e => raise CanonCallError(e.to_string())
                    }
                    (ptr32, len32)
                  }
                  _ => raise HostCallError("result type mismatch")
                }
              }
              let s = read_string_from_memory_with_encoding(
                mem,
                ptr,
                len,
                resources.encoding,
              )
              if p == String {
                [ComponentValue::String(s)]
              } else {
                [ComponentValue::ErrorContext(s)]
              }
            }
          }
        TypeIdx(_ti) => {
          let mut mem_is_64 = false
          let mut mem : @runtime.Memory? = None
          match resources.mem_addr {
            Some(addr) => {
              let m = store.get_mem(addr) catch {
                e => raise CanonCallError(e.to_string())
              }
              mem_is_64 = m.is_memory64()
              mem = Some(m)
            }
            None => ()
          }
          let flat_types = core_types_for_valtype(r, types, mem_is_64)
          let flat_vals : Array[@types.Value] = if flat_types.length() == 1 {
            results
          } else if results.length() == flat_types.length() {
            results
          } else if results.length() == 1 {
            let m = match mem {
              Some(m) => m
              None => raise MissingCanonMemory
            }
            let ptr = match results[0] {
              @types.Value::I32(n) => n
              @types.Value::I64(n) => n.to_int()
              _ => raise HostCallError("result type mismatch")
            }
            let (offsets, _size, struct_align) = layout_of_flat_types(
              flat_types,
            )
            if struct_align > 1 &&
              ptr.reinterpret_as_uint() % struct_align.reinterpret_as_uint() !=
              0U {
              raise CanonCallError("unaligned pointer")
            }
            let out : Array[@types.Value] = []
            for i in 0..<flat_types.length() {
              out.push(load_flat_value(m, ptr + offsets[i], flat_types[i]))
            }
            out
          } else {
            raise HostCallError("result type mismatch")
          }
          let v = lift_component_value_from_flat(
            r,
            flat_vals,
            types,
            mem,
            mem_is_64,
            resources.encoding,
          )
          // Validate top-level resource handles so type mismatches trap instead of
          // escaping as raw integers.
          match resolve_valtype(r, types) {
            TypeIdx(ti) =>
              match types.get(ti) {
                Some(Some(TypeDef::Own(resource_tyidx)))
                | Some(Some(TypeDef::Borrow(resource_tyidx))) => {
                  let (type_id, kind) = resource_type_info(
                    resource_tyidx, types,
                  )
                  match v {
                    ComponentValue::U32(h) =>
                      validate_resource_handle(h, type_id, kind, resource_table)
                    ComponentValue::S32(h) =>
                      validate_resource_handle(h, type_id, kind, resource_table)
                    _ => ()
                  }
                }
                _ => ()
              }
            _ => ()
          }
          [v]
        }
      }
  }
}

///|
fn core_args_to_component(
  args : Array[@types.Value],
  func_type : FuncType,
  types : Array[TypeDef?],
  resources : CanonResources,
  store : @runtime.Store,
  resource_table : ResourceTable,
) -> Array[ComponentValue] raise ComponentRuntimeError {
  fn resource_type_info(
    tyidx : Int,
    types : Array[TypeDef?],
  ) -> (Int, ResourceKind) raise ComponentRuntimeError {
    match types.get(tyidx) {
      Some(Some(TypeDef::ResourceType(id, _, _, kind))) => (id, kind)
      _ => raise HostCallError("invalid resource type")
    }
  }

  fn validate_resource_handle(
    handle : Int,
    expected_type_id : Int,
    expected_kind : ResourceKind,
    table : ResourceTable,
  ) -> Unit raise ComponentRuntimeError {
    match table.get(handle) {
      None =>
        raise CanonCallError(
          "unknown handle index \{handle}; index \{handle} is not a resource",
        )
      Some(entry) =>
        if entry.type_id < 0 {
          raise CanonCallError(
            "unknown handle index \{handle}; index \{handle} is not a resource",
          )
        } else if entry.type_id != expected_type_id {
          let expected_desc = if expected_kind == ResourceKind::GuestDefined {
            "guest-defined resource"
          } else {
            "host-defined resource"
          }
          let found_desc = if entry.kind == ResourceKind::GuestDefined {
            "guest-defined resource"
          } else {
            "host-defined resource"
          }
          let suffix = if entry.kind == expected_kind {
            "a different \{found_desc}"
          } else {
            found_desc
          }
          raise CanonCallError(
            "handle index \{handle} used with the wrong type, expected \{expected_desc} but found \{suffix}",
          )
        }
    }
  }

  let mut mem_is_64 = false
  let mut mem : @runtime.Memory? = None
  match resources.mem_addr {
    Some(addr) => {
      let m = store.get_mem(addr) catch {
        e => raise CanonCallError(e.to_string())
      }
      mem_is_64 = m.is_memory64()
      mem = Some(m)
    }
    None => ()
  }
  let flat_param_types : Array[@types.ValueType] = []
  for p in func_type.params {
    for t in core_types_for_valtype(p.ty, types, mem_is_64) {
      flat_param_types.push(t)
    }
  }
  let indirect_params = flat_param_types.length() > 16
  let flat_result_types : Array[@types.ValueType] = match func_type.result {
    Some(r) => core_types_for_valtype(r, types, mem_is_64)
    None => []
  }
  let indirect_result = flat_result_types.length() > 1
  let arg_limit = if indirect_result {
    args.length() - 1
  } else {
    args.length()
  }
  let flat_vals : Array[@types.Value] = if indirect_params {
    if arg_limit < 1 {
      raise HostCallError("argument type mismatch")
    }
    let ptr = match args[0] {
      @types.Value::I32(n) => n
      @types.Value::I64(n) => n.to_int()
      _ => raise HostCallError("argument type mismatch")
    }
    let m = match mem {
      Some(m) => m
      None => raise MissingCanonMemory
    }
    let (offsets, _size, struct_align) = layout_of_flat_types(flat_param_types)
    if struct_align > 1 &&
      ptr.reinterpret_as_uint() % struct_align.reinterpret_as_uint() != 0U {
      raise CanonCallError("unaligned pointer")
    }
    let out : Array[@types.Value] = []
    for i in 0..<flat_param_types.length() {
      out.push(load_flat_value(m, ptr + offsets[i], flat_param_types[i]))
    }
    out
  } else {
    let out : Array[@types.Value] = []
    for i in 0..<arg_limit {
      out.push(args[i])
    }
    out
  }
  let values : Array[ComponentValue] = []
  let mut pos = 0
  for p in func_type.params {
    let flat_types = core_types_for_valtype(p.ty, types, mem_is_64)
    let n = flat_types.length()
    if pos + n > flat_vals.length() {
      raise HostCallError("argument type mismatch")
    }
    let seg : Array[@types.Value] = []
    for i in 0..<n {
      seg.push(flat_vals[pos + i])
    }
    let v = lift_component_value_from_flat(
      p.ty,
      seg,
      types,
      mem,
      mem_is_64,
      resources.encoding,
    )
    // Validate top-level resource handles to avoid passing invalid integers into
    // host/component functions.
    match resolve_valtype(p.ty, types) {
      TypeIdx(ti) =>
        match types.get(ti) {
          Some(Some(TypeDef::Own(resource_tyidx)))
          | Some(Some(TypeDef::Borrow(resource_tyidx))) => {
            let (type_id, kind) = resource_type_info(resource_tyidx, types)
            match v {
              ComponentValue::U32(h) =>
                validate_resource_handle(h, type_id, kind, resource_table)
              ComponentValue::S32(h) =>
                validate_resource_handle(h, type_id, kind, resource_table)
              _ => ()
            }
          }
          _ => ()
        }
      _ => ()
    }
    values.push(v)
    pos += n
  }
  if pos != flat_vals.length() {
    raise HostCallError("argument type mismatch")
  }
  values
}

///|
fn component_results_to_core(
  results : Array[ComponentValue],
  func_type : FuncType,
  types : Array[TypeDef?],
  resources : CanonResources,
  store : @runtime.Store,
  retptr : Int?,
) -> Array[@types.Value] raise ComponentRuntimeError {
  match func_type.result {
    None => []
    Some(r) => {
      if results.length() == 0 {
        raise HostCallError("missing result")
      }
      let val = results[0]
      let mem = match resources.mem_addr {
        Some(addr) =>
          store.get_mem(addr) catch {
            e => raise CanonCallError(e.to_string())
          }
        None => @runtime.Memory::new(0, None)
      }
      let mem_is_64 = mem.is_memory64()
      let flat_res_types = core_types_for_valtype(r, types, mem_is_64)
      if flat_res_types.length() > 1 {
        if resources.mem_addr is None {
          raise MissingCanonMemory
        }
        let out_ptr = match retptr {
          Some(p) => p
          None => raise HostCallError("missing retptr")
        }
        let (offsets, _size, struct_align) = layout_of_flat_types(
          flat_res_types,
        )
        if struct_align > 1 &&
          out_ptr.reinterpret_as_uint() % struct_align.reinterpret_as_uint() !=
          0U {
          raise CanonCallError("unaligned pointer")
        }
        fn lower_value(
          v : ComponentValue,
          ty : ValType,
        ) -> Array[@types.Value] raise ComponentRuntimeError {
          match resolve_valtype(ty, types) {
            Prim(p) =>
              match (p, v) {
                (Bool, ComponentValue::Bool(b)) =>
                  [@types.Value::I32(if b { 1 } else { 0 })]
                (S8, ComponentValue::S8(n))
                | (U8, ComponentValue::U8(n))
                | (S16, ComponentValue::S16(n))
                | (U16, ComponentValue::U16(n))
                | (S32, ComponentValue::S32(n))
                | (U32, ComponentValue::U32(n)) => [@types.Value::I32(n)]
                (S64, ComponentValue::S64(n)) | (U64, ComponentValue::U64(n)) =>
                  [@types.Value::I64(n)]
                (F32, ComponentValue::F32(f)) => [@types.Value::F32(f)]
                (F64, ComponentValue::F64(f)) => [@types.Value::F64(f)]
                (Char, ComponentValue::Char(c)) =>
                  [@types.Value::I32(c.to_int())]
                (String, ComponentValue::String(s))
                | (ErrorContext, ComponentValue::ErrorContext(s)) => {
                  if resources.mem_addr is None {
                    raise MissingCanonMemory
                  }
                  let realloc = match resources.realloc {
                    Some(rf) => rf
                    None => raise MissingCanonRealloc
                  }
                  let (bytes, canon_len, align) = encode_string_for_canon(
                    s,
                    resources.encoding,
                  )
                  let ptr = write_bytes_to_memory_with_align(
                    store, mem, realloc, mem_is_64, bytes, align,
                  )
                  if mem_is_64 {
                    [
                      @types.Value::I64(ptr.to_int64()),
                      @types.Value::I64(canon_len.to_int64()),
                    ]
                  } else {
                    [@types.Value::I32(ptr), @types.Value::I32(canon_len)]
                  }
                }
                _ => raise HostCallError("result type mismatch")
              }
            TypeIdx(ti) =>
              match types.get(ti) {
                Some(Some(TypeDef::Tuple(tys))) =>
                  match v {
                    ComponentValue::Tuple(items) =>
                      if items.length() != tys.length() {
                        raise HostCallError("result type mismatch")
                      } else {
                        let out : Array[@types.Value] = []
                        for i in 0..<tys.length() {
                          for vv in lower_value(items[i], tys[i]) {
                            out.push(vv)
                          }
                        }
                        out
                      }
                    _ => raise HostCallError("result type mismatch")
                  }
                Some(Some(TypeDef::Record(fields))) =>
                  match v {
                    ComponentValue::Tuple(items) =>
                      if items.length() != fields.length() {
                        raise HostCallError("result type mismatch")
                      } else {
                        let out : Array[@types.Value] = []
                        for i in 0..<fields.length() {
                          for vv in lower_value(items[i], fields[i].ty) {
                            out.push(vv)
                          }
                        }
                        out
                      }
                    _ => raise HostCallError("result type mismatch")
                  }
                Some(Some(TypeDef::Own(_)))
                | Some(Some(TypeDef::Borrow(_)))
                | Some(Some(TypeDef::ResourceType(_, _, _, _)))
                | Some(Some(TypeDef::Stream(_)))
                | Some(Some(TypeDef::Future(_))) =>
                  match v {
                    ComponentValue::U32(handle) => [@types.Value::I32(handle)]
                    ComponentValue::S32(handle) => [@types.Value::I32(handle)]
                    _ => raise HostCallError("result type mismatch")
                  }
                _ => raise HostCallError("unsupported result type")
              }
          }
        }

        let flat_vals = lower_value(val, r)
        if flat_vals.length() != flat_res_types.length() {
          raise HostCallError("result type mismatch")
        }
        for i in 0..<flat_vals.length() {
          store_flat_value(mem, out_ptr + offsets[i], flat_vals[i])
        }
        return []
      }
      match resolve_valtype(r, types) {
        Prim(p) =>
          match (p, val) {
            (Bool, ComponentValue::Bool(b)) =>
              [@types.Value::I32(if b { 1 } else { 0 })]
            (S8, ComponentValue::S8(n))
            | (U8, ComponentValue::U8(n))
            | (S16, ComponentValue::S16(n))
            | (U16, ComponentValue::U16(n))
            | (S32, ComponentValue::S32(n))
            | (U32, ComponentValue::U32(n)) => [@types.Value::I32(n)]
            (S64, ComponentValue::S64(n)) | (U64, ComponentValue::U64(n)) =>
              [@types.Value::I64(n)]
            (F32, ComponentValue::F32(n)) => [@types.Value::F32(n)]
            (F64, ComponentValue::F64(n)) => [@types.Value::F64(n)]
            (Char, ComponentValue::Char(c)) => [@types.Value::I32(c.to_int())]
            (String, ComponentValue::String(s))
            | (ErrorContext, ComponentValue::ErrorContext(s)) => {
              let mem = require_memory(resources, store)
              let mem_is_64 = mem.is_memory64()
              let realloc = match resources.realloc {
                Some(rf) => rf
                None => raise MissingCanonRealloc
              }
              let (bytes, canon_len, align) = encode_string_for_canon(
                s,
                resources.encoding,
              )
              let ptr = write_bytes_to_memory_with_align(
                store, mem, realloc, mem_is_64, bytes, align,
              )
              let len = canon_len
              if mem_is_64 {
                [
                  @types.Value::I64(ptr.to_int64()),
                  @types.Value::I64(len.to_int64()),
                ]
              } else {
                [@types.Value::I32(ptr), @types.Value::I32(len)]
              }
            }
            _ => raise HostCallError("result type mismatch")
          }
        TypeIdx(ti) =>
          match types.get(ti) {
            Some(Some(TypeDef::Own(_)))
            | Some(Some(TypeDef::Borrow(_)))
            | Some(Some(TypeDef::ResourceType(_, _, _, _)))
            | Some(Some(TypeDef::Stream(_)))
            | Some(Some(TypeDef::Future(_))) =>
              match val {
                ComponentValue::U32(handle) => [@types.Value::I32(handle)]
                ComponentValue::S32(handle) => [@types.Value::I32(handle)]
                _ => raise HostCallError("result type mismatch")
              }
            Some(Some(TypeDef::Variant(cases))) =>
              match val {
                ComponentValue::Variant(tag, payload_opt) => {
                  if tag < 0 || tag >= cases.length() {
                    raise HostCallError("invalid variant discriminant")
                  }
                  // Only variants with an empty payload flatten to a single i32 result here.
                  match cases[tag].ty {
                    None =>
                      match payload_opt {
                        None => [@types.Value::I32(tag)]
                        Some(_) => raise HostCallError("result type mismatch")
                      }
                    Some(_) => raise HostCallError("unsupported result type")
                  }
                }
                _ => raise HostCallError("result type mismatch")
              }
            Some(Some(TypeDef::Option(_payload_ty))) =>
              match val {
                ComponentValue::Variant(tag, payload_opt) =>
                  if tag == 0 {
                    if payload_opt is Some(_) {
                      raise HostCallError("result type mismatch")
                    }
                    [@types.Value::I32(0)]
                  } else if tag == 1 {
                    // Options with payload would have been handled by the indirect-result path.
                    if payload_opt is None {
                      raise HostCallError("result type mismatch")
                    }
                    raise HostCallError("unsupported result type")
                  } else {
                    raise HostCallError("invalid variant discriminant")
                  }
                _ => raise HostCallError("result type mismatch")
              }
            Some(Some(TypeDef::Result(_ok_ty, _err_ty))) =>
              match val {
                ComponentValue::Variant(tag, payload_opt) =>
                  if tag == 0 || tag == 1 {
                    if payload_opt is Some(_) {
                      // Payload results are indirect today.
                      raise HostCallError("unsupported result type")
                    }
                    [@types.Value::I32(tag)]
                  } else {
                    raise HostCallError("invalid variant discriminant")
                  }
                _ => raise HostCallError("result type mismatch")
              }
            Some(Some(TypeDef::Flags(labels))) => {
              let nbits = labels.length()
              if nbits <= 32 {
                let raw = match val {
                  ComponentValue::U32(n) => n.reinterpret_as_uint()
                  ComponentValue::S32(n) => n.reinterpret_as_uint()
                  _ => raise HostCallError("result type mismatch")
                }
                let masked = if nbits == 32 {
                  raw
                } else {
                  raw & ((1U << nbits) - 1U)
                }
                [@types.Value::I32(masked.reinterpret_as_int())]
              } else {
                let raw = match val {
                  ComponentValue::U64(n) => n.reinterpret_as_uint64()
                  ComponentValue::S64(n) => n.reinterpret_as_uint64()
                  _ => raise HostCallError("result type mismatch")
                }
                let masked = if nbits == 64 {
                  raw
                } else {
                  raw & ((1UL << nbits) - 1UL)
                }
                [@types.Value::I64(masked.reinterpret_as_int64())]
              }
            }
            Some(Some(TypeDef::Enum(labels))) => {
              let n = match val {
                ComponentValue::U32(n) => n
                ComponentValue::S32(n) => n
                _ => raise HostCallError("result type mismatch")
              }
              if n < 0 || n >= labels.length() {
                raise HostCallError("invalid enum discriminant")
              }
              [@types.Value::I32(n)]
            }
            _ => raise HostCallError("unsupported result type")
          }
      }
    }
  }
}
