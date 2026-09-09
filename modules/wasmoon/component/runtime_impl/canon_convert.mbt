///|
fn lift_component_value_from_flat(
  ty : ValType,
  flat_vals : Array[@types.Value],
  types : Array[TypeDef?],
  mem : @runtime.Memory?,
  mem_is_64 : Bool,
  encoding : StringEncoding,
  resource_table : ResourceTable,
  budget? : CanonicalCopyBudget,
  borrow_strings? : Bool = false,
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
          String => {
            let m = match mem {
              Some(m) => m
              None => raise MissingCanonMemory
            }
            let (ptr, len) = if mem_is_64 {
              match (take(vals), take(vals)) {
                (I64(p), I64(l)) => (p, l)
                _ => raise HostCallError("type mismatch")
              }
            } else {
              match (take(vals), take(vals)) {
                (I32(p), I32(l)) =>
                  (p.to_int64() & 0xffffffffL, l.to_int64() & 0xffffffffL)
                _ => raise HostCallError("type mismatch")
              }
            }
            if borrow_strings {
              check_canonical_string_span(m, ptr, len, encoding) |> ignore
              return GuestString({ memory: m, ptr, len, encoding, })
            }
            let s = read_string_from_memory_with_encoding(
              m,
              ptr,
              len,
              encoding,
              budget?,
            )
            if encoding == Utf8 {
              String(s)
            } else {
              EncodedString(s, encoding, len.to_int())
            }
          }
          ErrorContext => {
            guard take(vals) is I32(handle) else {
              raise HostCallError("type mismatch")
            }
            guard resource_table.error_contexts.get(handle) is Some(message) else {
              raise CanonCallError("unknown handle index \{handle}")
            }
            ErrorContext(message)
          }
          _ =>
            match (p, take(vals)) {
              (Bool, I32(n)) => Bool(n != 0)
              (S8, I32(n)) => S8(trunc_s8(n))
              (U8, I32(n)) => U8(trunc_u8(n))
              (S16, I32(n)) => S16(trunc_s16(n))
              (U16, I32(n)) => U16(trunc_u16(n))
              (S32, I32(n)) => S32(n)
              (U32, I32(n)) => U32(trunc_u32(n))
              (Char, I32(n)) => Char(char_from_canon_i32(n))
              (S64, I64(n)) => S64(n)
              (U64, I64(n)) => U64(n)
              (F32, F32(f)) => F32(f)
              (F64, F64(f)) => F64(f)
              _ => raise HostCallError("type mismatch")
            }
        }
      TypeIdx(ti) =>
        match types.get(ti) {
          Some(Some(FixedList(element, length))) => {
            if budget is Some(budget) {
              budget.consume(length, 32)
            }
            let items : Array[ComponentValue] = []
            for _ in 0..<length {
              items.push(lift_inner(element, vals))
            }
            List(items)
          }
          Some(Some(Tuple(tys))) => {
            let items : Array[ComponentValue] = []
            for t in tys {
              items.push(lift_inner(t, vals))
            }
            Tuple(items)
          }
          Some(Some(Record(fields))) => {
            let items : Array[ComponentValue] = []
            for f in fields {
              items.push(lift_inner(f.ty, vals))
            }
            Tuple(items)
          }
          Some(Some(List(elem_ty))) => {
            let m = match mem {
              Some(m) => m
              None => raise MissingCanonMemory
            }
            let (ptr, len) = if mem_is_64 {
              match (take(vals), take(vals)) {
                (I64(p), I64(l)) => (p, l)
                _ => raise HostCallError("type mismatch")
              }
            } else {
              match (take(vals), take(vals)) {
                (I32(p), I32(l)) =>
                  (p.to_int64() & 0xffffffffL, l.to_int64() & 0xffffffffL)
                _ => raise HostCallError("type mismatch")
              }
            }
            let (elem_size, elem_align) = canonical_memory_layout(
              elem_ty, types, mem_is_64,
            )
            let stride = align_to(elem_size, elem_align)
            let offset = ptr
            if len < 0L ||
              offset < 0L ||
              offset > m.byte_len() ||
              (stride != 0 && len > (m.byte_len() - offset) / stride.to_int64()) {
              raise CanonCallError(
                "list pointer/length out of bounds of memory",
              )
            }
            if len > 2147483647L {
              raise CanonCallError("list length exceeds host allocation limit")
            }
            let len = len.to_int()
            if offset % elem_align.to_int64() != 0L {
              raise CanonCallError("unaligned pointer")
            }
            if budget is Some(budget) {
              budget.consume(len, 32)
            }
            let items : Array[ComponentValue] = []
            for i in 0..<len {
              let base = ptr + stride.to_int64() * i.to_int64()
              let elem_vals = load_flat_component_value_from_memory(
                m, base, elem_ty, types, mem_is_64,
              )
              items.push(
                lift_component_value_from_flat(
                  elem_ty,
                  elem_vals,
                  types,
                  mem,
                  mem_is_64,
                  encoding,
                  resource_table,
                  budget?,
                  borrow_strings~,
                ),
              )
            }
            List(items)
          }
          Some(Some(Stream(_))) | Some(Some(Future(_))) =>
            match take(vals) {
              I32(n) => U32(n)
              _ => raise HostCallError("type mismatch")
            }
          Some(Some(Variant(cases))) => {
            let tag = match take(vals) {
              I32(n) => n
              _ => raise HostCallError("type mismatch")
            }
            if tag < 0 || tag >= cases.length() {
              raise CanonCallError(
                "invalid variant discriminant: discriminant \{tag.reinterpret_as_uint()} out of range [0..\{cases.length()})",
              )
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
              None => Variant(tag, None)
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
                  payload_ty,
                  payload_vals,
                  types,
                  mem,
                  mem_is_64,
                  encoding,
                  resource_table,
                  budget?,
                  borrow_strings~,
                )
                Variant(tag, Some(payload))
              }
            }
          }
          Some(Some(Option(payload_ty))) => {
            let tag = match take(vals) {
              I32(n) => n
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
              Variant(0, None)
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
                payload_ty,
                payload_vals,
                types,
                mem,
                mem_is_64,
                encoding,
                resource_table,
                budget?,
                borrow_strings~,
              )
              Variant(1, Some(payload))
            }
          }
          Some(Some(Result(ok_ty, err_ty))) => {
            let tag = match take(vals) {
              I32(n) => n
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
              None => Variant(tag, None)
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
                  pt,
                  payload_vals,
                  types,
                  mem,
                  mem_is_64,
                  encoding,
                  resource_table,
                  budget?,
                  borrow_strings~,
                )
                Variant(tag, Some(payload))
              }
            }
          }
          Some(Some(Flags(labels))) => {
            let nbits = labels.length()
            if nbits <= 32 {
              let raw = match take(vals) {
                I32(n) => n.reinterpret_as_uint()
                _ => raise HostCallError("type mismatch")
              }
              let masked = if nbits == 32 {
                raw
              } else {
                raw & ((1U << nbits) - 1U)
              }
              U32(masked.reinterpret_as_int())
            } else {
              let raw = match take(vals) {
                I64(n) => n.reinterpret_as_uint64()
                _ => raise HostCallError("type mismatch")
              }
              let masked = if nbits == 64 {
                raw
              } else {
                raw & ((1UL << nbits) - 1UL)
              }
              U64(masked.reinterpret_as_int64())
            }
          }
          Some(Some(Enum(labels))) => {
            let n = match take(vals) {
              I32(n) => n
              _ => raise HostCallError("type mismatch")
            }
            if n < 0 || n >= labels.length() {
              raise CanonCallError("invalid variant discriminant")
            }
            U32(n)
          }
          Some(Some(Own(_)))
          | Some(Some(Borrow(_)))
          | Some(Some(ResourceType(_, _, _, _))) =>
            match take(vals) {
              I32(handle) => U32(handle)
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
  if resources.mem_addr is Some(addr) {
    let m = store.get_mem(addr) catch {
      e => raise CanonCallError(e.to_string())
    }
    mem_is_64 = m.is_memory64()
    mem = Some(m)
  }
  // Determine whether we must pass a pointer to the flattened arguments.
  let flat_param_types : Array[@types.ValueType] = []
  for p in func_type.params {
    for t in core_types_for_valtype(p.ty, types, mem_is_64, max_flat=17) {
      flat_param_types.push(t)
    }
  }
  let indirect_params = flat_param_types.length() > 16
  let param_values : Array[Array[@types.Value]] = []
  let flat_vals : Array[@types.Value] = []
  for i, param in func_type.params {
    let val = if i < args.length() {
      args[i]
    } else {
      raise InvalidValueIndex(i)
    }
    let values = lower_component_value_to_flat(
      val,
      param.ty,
      types,
      resources,
      store,
      (caller_table, callee_table),
    )
    param_values.push(values)
    for v in values {
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
  let (offsets, size, struct_align) = canonical_param_layout(
    func_type.params,
    types,
    mem_is_64,
  )
  let ptr = alloc_realloc_area(
    store,
    m,
    realloc,
    mem_is_64,
    size.to_int64(),
    struct_align,
  )
  if ptr % struct_align.to_int64() != 0L {
    raise CanonCallError("unaligned pointer")
  }
  for i, param in func_type.params {
    store_flat_component_value_to_memory(
      m,
      ptr + offsets[i].to_int64(),
      param.ty,
      param_values[i],
      types,
      mem_is_64,
    )
  }
  if mem_is_64 {
    [I64(ptr)]
  } else {
    [I32(ptr.to_int())]
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
  match func_type.result {
    None => []
    Some(ty) =>
      core_args_to_component(
        results,
        [{ label: "result", ty, }],
        types,
        resources,
        store,
        resource_table,
        if results.length() == 1 {
          1
        } else {
          2147483647
        },
        "core result",
      )
  }
}

///|
fn core_args_to_component(
  args : Array[@types.Value],
  params : Array[@component.Param],
  types : Array[TypeDef?],
  resources : CanonResources,
  store : @runtime.Store,
  resource_table : ResourceTable,
  max_flat_params : Int,
  context : String,
  borrow_strings? : Bool = false,
) -> Array[ComponentValue] raise ComponentRuntimeError {
  fn resource_type_info(
    tyidx : Int,
    types : Array[TypeDef?],
  ) -> (Int, ResourceKind) raise ComponentRuntimeError {
    match types.get(tyidx) {
      Some(Some(ResourceType(id, _, _, kind))) => (id, kind)
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
          "\{context}: unknown handle index \{resource_handle_index_text(handle)}; index \{resource_handle_index_text(handle)} is not a resource",
        )
      Some(entry) =>
        if entry.type_id < 0 {
          raise CanonCallError(
            "unknown handle index \{resource_handle_index_text(handle)}; index \{resource_handle_index_text(handle)} is not a resource",
          )
        } else if entry.type_id != expected_type_id {
          let expected_desc = if expected_kind == GuestDefined {
            "guest-defined resource"
          } else {
            "host-defined resource"
          }
          let found_desc = if entry.kind == GuestDefined {
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
            "handle index \{resource_handle_index_text(handle)} used with the wrong type, expected \{expected_desc} but found \{suffix}",
          )
        }
    }
  }

  let mut mem_is_64 = false
  let mut mem : @runtime.Memory? = None
  if resources.mem_addr is Some(addr) {
    let m = store.get_mem(addr) catch {
      e => raise CanonCallError(e.to_string())
    }
    mem_is_64 = m.is_memory64()
    mem = Some(m)
  }
  let flat_param_types : Array[@types.ValueType] = []
  for p in params {
    for t in core_types_for_valtype(p.ty, types, mem_is_64, max_flat=17) {
      flat_param_types.push(t)
    }
  }
  let indirect_params = flat_param_types.length() > max_flat_params
  let arg_limit = args.length()
  let flat_vals : Array[@types.Value] = if indirect_params {
    if arg_limit < 1 {
      raise HostCallError("argument type mismatch")
    }
    let ptr = match args[0] {
      I32(n) => n.to_int64() & 0xffffffffL
      I64(n) => n
      _ => raise HostCallError("argument type mismatch")
    }
    let m = match mem {
      Some(m) => m
      None => raise MissingCanonMemory
    }
    let (offsets, _, struct_align) = canonical_param_layout(
      params, types, mem_is_64,
    )
    if struct_align > 1 && ptr % struct_align.to_int64() != 0L {
      raise CanonCallError("unaligned pointer")
    }
    let out : Array[@types.Value] = []
    for i, param in params {
      for
        value in load_flat_component_value_from_memory(
          m,
          ptr + offsets[i].to_int64(),
          param.ty,
          types,
          mem_is_64,
        ) {
        out.push(value)
      }
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
  for p in params {
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
      resource_table,
      borrow_strings~,
    )
    map_canonical_handles(p.ty, v, types, (definition, value) => {
      match definition {
        Own(resource_tyidx) | Borrow(resource_tyidx) => {
          let (type_id, kind) = resource_type_info(resource_tyidx, types)
          match value {
            U32(handle) | S32(handle) =>
              validate_resource_handle(handle, type_id, kind, resource_table)
            _ => ()
          }
        }
        _ => ()
      }
      value
    })
    |> ignore
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
  retptr : Int64?,
  resource_table : ResourceTable,
) -> Array[@types.Value] raise ComponentRuntimeError {
  guard func_type.result is Some(ty) else { return [] }
  guard results is [value] else {
    raise HostCallError("missing or excess result")
  }
  let mem_is_64 = match resources.mem_addr {
    Some(_) => require_memory(resources, store).is_memory64()
    None => false
  }
  let flat_types = core_types_for_valtype(ty, types, mem_is_64, max_flat=2)
  let values = lower_component_value_to_flat(
    value,
    ty,
    types,
    resources,
    store,
    (resource_table, resource_table),
  )
  if flat_types.length() <= 1 {
    return values
  }
  guard retptr is Some(ptr) else { raise HostCallError("missing retptr") }
  let mem = require_memory(resources, store)
  store_flat_component_value_to_memory(mem, ptr, ty, values, types, mem_is_64)
  []
}

///|
fn lower_component_value_to_flat(
  val : ComponentValue,
  ty : ValType,
  types : Array[TypeDef?],
  resources : CanonResources,
  store : @runtime.Store,
  tables : (ResourceTable, ResourceTable),
) -> Array[@types.Value] raise ComponentRuntimeError {
  let (caller_table, callee_table) = tables
  // Cache memory/realloc handles (if provided) for canonical ABI operations.
  let mut mem : @runtime.Memory? = None
  let mut mem_is_64 = false
  if resources.mem_addr is Some(addr) {
    let m = store.get_mem(addr) catch {
      e => raise CanonCallError(e.to_string())
    }
    mem_is_64 = m.is_memory64()
    mem = Some(m)
  }
  fn lower_value(
    val : ComponentValue,
    ty : ValType,
  ) -> Array[@types.Value] raise ComponentRuntimeError {
    match resolve_valtype(ty, types) {
      Prim(p) =>
        match (p, val) {
          (Bool, Bool(b)) => [I32(if b { 1 } else { 0 })]
          (S8, S8(n))
          | (U8, U8(n))
          | (S16, S16(n))
          | (U16, U16(n))
          | (S32, S32(n))
          | (U32, U32(n)) => [I32(n)]
          (S64, S64(n)) | (U64, U64(n)) => [I64(n)]
          (F32, F32(f)) => [F32(f)]
          (F64, F64(f)) => [F64(f)]
          (Char, Char(c)) => [I32(c.to_int())]
          (ErrorContext, ErrorContext(message)) =>
            [I32(callee_table.alloc_error_context(message))]
          (String, String(_) | EncodedString(_, _, _) | GuestString(_)) => {
            let m = match mem {
              Some(m) => m
              None => raise MissingCanonMemory
            }
            let realloc = match resources.realloc {
              Some(r) => r
              None => raise MissingCanonRealloc
            }
            let (ptr, canon_len) = lower_canonical_string(
              val,
              resources.encoding,
              store,
              m,
              realloc,
              mem_is_64,
            )
            if mem_is_64 {
              [I64(ptr), I64(canon_len.to_int64() & 0xffffffffL)]
            } else {
              [I32(ptr.to_int()), I32(canon_len)]
            }
          }
          _ => raise HostCallError("argument type mismatch")
        }
      TypeIdx(ti) =>
        match types.get(ti) {
          Some(Some(FixedList(element, length))) => {
            guard val is List(items) && items.length() == length else {
              raise HostCallError("argument type mismatch")
            }
            let out : Array[@types.Value] = []
            for item in items {
              for value in lower_value(item, element) {
                out.push(value)
              }
            }
            out
          }
          Some(Some(Tuple(tys))) =>
            match val {
              Tuple(items) =>
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
          Some(Some(Record(fields))) =>
            match val {
              Tuple(items) =>
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
          Some(Some(List(elem_ty))) =>
            match val {
              List(items) => {
                let m = match mem {
                  Some(m) => m
                  None => raise MissingCanonMemory
                }
                let realloc = match resources.realloc {
                  Some(r) => r
                  None => raise MissingCanonRealloc
                }
                let (elem_size, elem_align) = canonical_memory_layout(
                  elem_ty, types, mem_is_64,
                )
                let stride = align_to(elem_size, elem_align)
                let total_size = stride.to_int64() * items.length().to_int64()
                let ptr = alloc_realloc_area(
                  store, m, realloc, mem_is_64, total_size, elem_align,
                )
                for i in 0..<items.length() {
                  let elem_vals = lower_value(items[i], elem_ty)
                  let base = ptr + stride.to_int64() * i.to_int64()
                  store_flat_component_value_to_memory(
                    m, base, elem_ty, elem_vals, types, mem_is_64,
                  )
                }
                let len = items.length()
                if mem_is_64 {
                  [I64(ptr), I64(len.to_int64())]
                } else {
                  [I32(ptr.to_int()), I32(len)]
                }
              }
              _ => raise HostCallError("argument type mismatch")
            }
          Some(Some(Variant(cases))) => {
            let all_flat = core_types_for_valtype(TypeIdx(ti), types, mem_is_64)
            let joined_types : Array[@types.ValueType] = []
            for i in 1..<all_flat.length() {
              joined_types.push(all_flat[i])
            }
            match val {
              Variant(tag, payload_opt) => {
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
                let out : Array[@types.Value] = [I32(tag)]
                for i in 0..<joined_types.length() {
                  if i < payload_vals.length() {
                    let actual = payload_vals[i]
                    let actual_vt = match actual {
                      I32(_) => @types.ValueType::I32
                      I64(_) => I64
                      F32(_) => F32
                      F64(_) => F64
                      _ => I32
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
          Some(Some(Option(payload_ty))) =>
            match val {
              Variant(tag, payload_opt) =>
                if tag == 0 {
                  // none
                  if payload_opt is Some(_) {
                    raise HostCallError("argument type mismatch")
                  }
                  // tag + payload slots (same as payload flat types)
                  let out : Array[@types.Value] = [I32(0)]
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
                  [I32(1)] + payload_vals
                } else {
                  raise HostCallError("invalid variant discriminant")
                }
              _ => raise HostCallError("argument type mismatch")
            }
          Some(Some(Result(ok_ty, err_ty))) =>
            match val {
              Variant(tag, payload_opt) => {
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
                let out : Array[@types.Value] = [I32(tag)]
                for i in 0..<joined_types.length() {
                  if i < payload_vals.length() {
                    let actual = payload_vals[i]
                    let actual_vt = match actual {
                      I32(_) => @types.ValueType::I32
                      I64(_) => I64
                      F32(_) => F32
                      F64(_) => F64
                      _ => I32
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
          Some(Some(Flags(labels))) => {
            let nbits = labels.length()
            if nbits <= 32 {
              let raw = match val {
                U32(n) => n.reinterpret_as_uint()
                S32(n) => n.reinterpret_as_uint()
                _ => raise HostCallError("argument type mismatch")
              }
              let masked = if nbits == 32 {
                raw
              } else {
                raw & ((1U << nbits) - 1U)
              }
              [I32(masked.reinterpret_as_int())]
            } else {
              let raw = match val {
                U64(n) => n.reinterpret_as_uint64()
                S64(n) => n.reinterpret_as_uint64()
                _ => raise HostCallError("argument type mismatch")
              }
              let masked = if nbits == 64 {
                raw
              } else {
                raw & ((1UL << nbits) - 1UL)
              }
              [I64(masked.reinterpret_as_int64())]
            }
          }
          Some(Some(Enum(labels))) => {
            let n = match val {
              U32(n) => n
              S32(n) => n
              _ => raise HostCallError("argument type mismatch")
            }
            if n < 0 || n >= labels.length() {
              raise HostCallError("invalid variant discriminant")
            }
            [I32(n)]
          }
          Some(Some(Borrow(resource_tyidx))) => {
            let expected_type_id = match types.get(resource_tyidx) {
              Some(Some(ResourceType(id, _, _, _))) => id
              _ => raise HostCallError("unsupported param type")
            }
            let handle = match val {
              U32(h) => h
              S32(h) => h
              ResourceValue(rep) => return [I32(rep)]
              _ => raise HostCallError("argument type mismatch")
            }
            match caller_table.get(handle) {
              Some(entry) =>
                if entry.type_id != expected_type_id {
                  raise CanonCallError(
                    "handle index \{resource_handle_index_text(handle)} used with the wrong type",
                  )
                } else if entry.impl_component_id == callee_table.id {
                  [I32(entry.rep)]
                } else {
                  [I32(handle)]
                }
              None =>
                raise CanonCallError(
                  "lower borrow: unknown handle index \{resource_handle_index_text(handle)} in resource table \{caller_table.id}",
                )
            }
          }
          Some(Some(Own(resource_tyidx))) => {
            let expected_type_id = match types.get(resource_tyidx) {
              Some(Some(ResourceType(id, _, _, _))) => id
              _ => raise HostCallError("unsupported param type")
            }
            let handle = match val {
              U32(h) => h
              S32(h) => h
              _ => raise HostCallError("argument type mismatch")
            }
            if caller_table.id == callee_table.id {
              [I32(handle)]
            } else {
              let entry = match caller_table.get(handle) {
                Some(e) => e
                None =>
                  raise CanonCallError(
                    "lower own: unknown handle index \{resource_handle_index_text(handle)} in resource table \{caller_table.id}",
                  )
              }
              if entry.type_id != expected_type_id {
                raise CanonCallError(
                  "handle index \{resource_handle_index_text(handle)} used with the wrong type",
                )
              }
              caller_table.free(handle) |> ignore
              let new_handle = callee_table.alloc(entry)
              [I32(new_handle)]
            }
          }
          Some(Some(ResourceType(_, _, _, _))) =>
            match val {
              U32(handle) => [I32(handle)]
              S32(handle) => [I32(handle)]
              _ => raise HostCallError("argument type mismatch")
            }
          Some(Some(Stream(_))) | Some(Some(Future(_))) =>
            match val {
              U32(handle) => [I32(handle)]
              S32(handle) => [I32(handle)]
              _ => raise HostCallError("argument type mismatch")
            }
          _ => raise HostCallError("unsupported param type")
        }
    }
  }

  lower_value(val, ty)
}
