///|
fn resolve_valtype(
  ty : ValType,
  types : Array[TypeDef?],
) -> ValType raise ComponentRuntimeError {
  match ty {
    Prim(p) => Prim(p)
    TypeIdx(idx) => {
      if idx < 0 || idx >= types.length() {
        raise InvalidTypeIndex(idx)
      }
      match types[idx] {
        Some(DefValType(p)) => Prim(p)
        _ => TypeIdx(idx)
      }
    }
  }
}

///|
fn discriminant_layout(case_count : Int) -> (Int, Int) {
  if case_count <= 0x100 {
    (1, 1)
  } else if case_count <= 0x10000 {
    (2, 2)
  } else {
    (4, 4)
  }
}

///|
fn canonical_memory_layout(
  ty : ValType,
  types : Array[TypeDef?],
  mem_is_64 : Bool,
) -> (Int, Int) raise ComponentRuntimeError {
  match resolve_valtype(ty, types) {
    Prim(p) =>
      match p {
        Bool | S8 | U8 => (1, 1)
        S16 | U16 => (2, 2)
        S32 | U32 | Char | F32 | ErrorContext => (4, 4)
        S64 | U64 | F64 => (8, 8)
        String => if mem_is_64 { (16, 8) } else { (8, 4) }
      }
    TypeIdx(idx) =>
      match types.get(idx) {
        Some(Some(DefValType(p))) =>
          canonical_memory_layout(Prim(p), types, mem_is_64)
        Some(Some(Tuple(items))) => {
          let mut size = 0
          let mut alignment = 1
          for item in items {
            let (item_size, item_alignment) = canonical_memory_layout(
              item, types, mem_is_64,
            )
            size = align_to(size, item_alignment) + item_size
            if item_alignment > alignment {
              alignment = item_alignment
            }
          }
          (align_to(size, alignment), alignment)
        }
        Some(Some(Record(fields))) => {
          let mut size = 0
          let mut alignment = 1
          for field in fields {
            let (field_size, field_alignment) = canonical_memory_layout(
              field.ty,
              types,
              mem_is_64,
            )
            size = align_to(size, field_alignment) + field_size
            if field_alignment > alignment {
              alignment = field_alignment
            }
          }
          (align_to(size, alignment), alignment)
        }
        Some(Some(List(_))) => if mem_is_64 { (16, 8) } else { (8, 4) }
        Some(Some(Enum(labels))) => discriminant_layout(labels.length())
        Some(Some(Flags(labels))) => {
          let words = (labels.length() + 31) / 32
          if words == 0 {
            (0, 1)
          } else if labels.length() <= 8 {
            (1, 1)
          } else if labels.length() <= 16 {
            (2, 2)
          } else {
            (words * 4, 4)
          }
        }
        Some(Some(Variant(cases))) => {
          let (tag_size, tag_alignment) = discriminant_layout(cases.length())
          let mut payload_size = 0
          let mut payload_alignment = 1
          for case in cases {
            match case.ty {
              Some(payload) => {
                let (size, alignment) = canonical_memory_layout(
                  payload, types, mem_is_64,
                )
                if size > payload_size {
                  payload_size = size
                }
                if alignment > payload_alignment {
                  payload_alignment = alignment
                }
              }
              None => ()
            }
          }
          let alignment = if tag_alignment > payload_alignment {
            tag_alignment
          } else {
            payload_alignment
          }
          let payload_offset = align_to(tag_size, payload_alignment)
          (align_to(payload_offset + payload_size, alignment), alignment)
        }
        Some(Some(Option(payload))) => {
          let (payload_size, payload_alignment) = canonical_memory_layout(
            payload, types, mem_is_64,
          )
          let payload_offset = align_to(1, payload_alignment)
          (
            align_to(payload_offset + payload_size, payload_alignment),
            payload_alignment,
          )
        }
        Some(Some(Result(ok, err))) => {
          let mut payload_size = 0
          let mut payload_alignment = 1
          for payload in [ok, err] {
            match payload {
              Some(value) => {
                let (size, alignment) = canonical_memory_layout(
                  value, types, mem_is_64,
                )
                if size > payload_size {
                  payload_size = size
                }
                if alignment > payload_alignment {
                  payload_alignment = alignment
                }
              }
              None => ()
            }
          }
          let payload_offset = align_to(1, payload_alignment)
          (
            align_to(payload_offset + payload_size, payload_alignment),
            payload_alignment,
          )
        }
        Some(Some(Own(_)))
        | Some(Some(Borrow(_)))
        | Some(Some(ResourceType(_, _, _, _)))
        | Some(Some(Stream(_)))
        | Some(Some(Future(_))) => (4, 4)
        _ => raise HostCallError("unsupported stream payload type")
      }
  }
}

///|
fn stream_payload_info(
  payload_ty : ValType?,
  types : Array[TypeDef?],
) -> (Int, Int?) raise ComponentRuntimeError {
  // Returns (elem_size_bytes, own_resource_type_id?).
  //
  // Note: `stream.read`/`stream.write` lengths are element counts, not byte counts.
  // For `stream u8` the element size is 1 byte; for `stream (own $R)` it is 4 bytes
  // (an i32 handle index in memory).
  match payload_ty {
    None => (1, None)
    Some(vt) => {
      let (size, alignment) = canonical_memory_layout(vt, types, false)
      let element_size = align_to(size, alignment)
      let own_resource_type_id = match resolve_valtype(vt, types) {
        TypeIdx(idx) =>
          match types.get(idx) {
            Some(Some(Own(resource_tyidx))) =>
              match types.get(resource_tyidx) {
                Some(Some(ResourceType(id, _, _, _))) => Some(id)
                _ => raise HostCallError("unsupported stream payload type")
              }
            _ => None
          }
        _ => None
      }
      (element_size, own_resource_type_id)
    }
  }
}

///|
fn read_i32_le_from_bytes(buf : Array[Byte], off : Int) -> Int {
  // Interpret 4 bytes at `off` as a little-endian i32.
  let b0 = buf[off].to_int() & 0xFF
  let b1 = buf[off + 1].to_int() & 0xFF
  let b2 = buf[off + 2].to_int() & 0xFF
  let b3 = buf[off + 3].to_int() & 0xFF
  b0 | (b1 << 8) | (b2 << 16) | (b3 << 24)
}

///|
fn core_types_for_valtype(
  ty : ValType,
  types : Array[TypeDef?],
  mem_is_64 : Bool,
) -> Array[@types.ValueType] raise ComponentRuntimeError {
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

  match resolve_valtype(ty, types) {
    Prim(p) =>
      match p {
        Bool | S8 | U8 | S16 | U16 | S32 | U32 | Char => [I32]
        S64 | U64 => [I64]
        F32 => [F32]
        F64 => [F64]
        String | ErrorContext => if mem_is_64 { [I64, I64] } else { [I32, I32] }
      }
    TypeIdx(idx) =>
      match types[idx] {
        Some(Tuple(tys)) => {
          let out : Array[@types.ValueType] = []
          for t in tys {
            for vt in core_types_for_valtype(t, types, mem_is_64) {
              out.push(vt)
            }
          }
          out
        }
        Some(Record(fields)) => {
          let out : Array[@types.ValueType] = []
          for f in fields {
            for vt in core_types_for_valtype(f.ty, types, mem_is_64) {
              out.push(vt)
            }
          }
          out
        }
        Some(Variant(cases)) => {
          let payloads : Array[Array[@types.ValueType]] = []
          let mut max_len = 0
          for c in cases {
            let flat = match c.ty {
              None => []
              Some(t) => core_types_for_valtype(t, types, mem_is_64)
            }
            if flat.length() > max_len {
              max_len = flat.length()
            }
            payloads.push(flat)
          }
          let joined : Array[@types.ValueType] = []
          for i in 0..<max_len {
            let mut cur : @types.ValueType? = None
            for p in payloads {
              if i < p.length() {
                cur = match cur {
                  None => Some(p[i])
                  Some(prev) => Some(join_flat(prev, p[i]))
                }
              }
            }
            match cur {
              None => ()
              Some(t) => joined.push(t)
            }
          }
          [I32] + joined
        }
        Some(Option(v)) => [I32] + core_types_for_valtype(v, types, mem_is_64)
        Some(Result(ok, err)) => {
          let ok_flat = match ok {
            None => []
            Some(v) => core_types_for_valtype(v, types, mem_is_64)
          }
          let err_flat = match err {
            None => []
            Some(v) => core_types_for_valtype(v, types, mem_is_64)
          }
          let mut max_len = ok_flat.length()
          if err_flat.length() > max_len {
            max_len = err_flat.length()
          }
          let joined : Array[@types.ValueType] = []
          for i in 0..<max_len {
            let mut cur : @types.ValueType? = None
            if i < ok_flat.length() {
              cur = Some(ok_flat[i])
            }
            if i < err_flat.length() {
              cur = match cur {
                None => Some(err_flat[i])
                Some(prev) => Some(join_flat(prev, err_flat[i]))
              }
            }
            match cur {
              None => ()
              Some(t) => joined.push(t)
            }
          }
          [I32] + joined
        }
        Some(Flags(labels)) => if labels.length() <= 32 { [I32] } else { [I64] }
        Some(Enum(_)) => [I32]
        Some(Own(_)) | Some(Borrow(_)) | Some(ResourceType(_, _, _, _)) => [I32]
        // Stream/future values are represented as i32 handles; the i64
        // representation is used by the `canon stream.new` intrinsic only.
        Some(Stream(_)) | Some(Future(_)) => [I32]
        Some(List(_)) => if mem_is_64 { [I64, I64] } else { [I32, I32] }
        _ => raise InvalidTypeDef(idx)
      }
  }
}

///|
fn func_type_needs_memory(
  func_type : FuncType,
  types : Array[TypeDef?],
) -> Bool raise ComponentRuntimeError {
  fn needs_memory(val_type : ValType) -> Bool raise ComponentRuntimeError {
    match resolve_valtype(val_type, types) {
      Prim(p) =>
        match p {
          String | ErrorContext => true
          _ => false
        }
      _ => false
    }
  }

  for p in func_type.params {
    if needs_memory(p.ty) {
      return true
    }
  }
  match func_type.result {
    Some(r) => needs_memory(r)
    None => false
  }
}

///|
fn resolve_canon_resources(
  opts : Array[CanonOpt],
  state : BuildState,
) -> CanonResources raise ComponentRuntimeError {
  let mut mem : Int? = None
  let mut realloc : CoreFuncRef? = None
  let mut post_return : CoreFuncRef? = None
  let mut encoding = StringEncoding::Utf8
  for opt in opts {
    match opt {
      Memory(idx) => {
        if idx < 0 || idx >= state.core_mems.length() {
          raise InvalidCoreMemoryIndex(idx)
        }
        mem = Some(state.core_mems[idx])
      }
      Realloc(idx) => {
        if idx < 0 || idx >= state.core_funcs.length() {
          raise InvalidCoreFuncIndex(idx)
        }
        realloc = Some(state.core_funcs[idx])
      }
      PostReturn(idx) => {
        if idx < 0 || idx >= state.core_funcs.length() {
          raise InvalidCoreFuncIndex(idx)
        }
        post_return = Some(state.core_funcs[idx])
      }
      StringEncoding(enc) => encoding = enc
      _ => ()
    }
  }
  { mem_addr: mem, realloc, post_return, encoding }
}

///|
fn canon_opt_is_async(opts : Array[CanonOpt]) -> Bool {
  for opt in opts {
    if opt is Async {
      return true
    }
  }
  false
}

///|
fn resolve_canon_callback(
  opts : Array[CanonOpt],
  state : BuildState,
) -> CoreFuncRef? raise ComponentRuntimeError {
  for opt in opts {
    if opt is Callback(idx) {
      if idx < 0 || idx >= state.core_funcs.length() {
        raise InvalidCoreFuncIndex(idx)
      }
      return Some(state.core_funcs[idx])
    }
  }
  None
}

///|
fn core_func_type_from_component(
  func_type : FuncType,
  types : Array[TypeDef?],
  mem_is_64 : Bool,
) -> @types.FuncType raise ComponentRuntimeError {
  let ptr_ty = if mem_is_64 { @types.ValueType::I64 } else { I32 }
  let flat_params : Array[@types.ValueType] = []
  for p in func_type.params {
    for t in core_types_for_valtype(p.ty, types, mem_is_64) {
      flat_params.push(t)
    }
  }
  let flat_results : Array[@types.ValueType] = match func_type.result {
    Some(r) => core_types_for_valtype(r, types, mem_is_64)
    None => []
  }

  // Canonical ABI:
  // - If there are too many flattened parameters, pass a single pointer to a
  //   memory area containing the flattened arguments.
  // - If the flattened result count isn't exactly 1, use an indirect return
  //   pointer parameter (and return nothing).
  let params : Array[@types.ValueType] = if flat_params.length() > 16 {
    [ptr_ty]
  } else {
    flat_params
  }
  let results : Array[@types.ValueType] = if flat_results.length() == 1 {
    flat_results
  } else if flat_results.length() == 0 {
    []
  } else {
    params.push(ptr_ty)
    []
  }
  { params, results }
}

///|
