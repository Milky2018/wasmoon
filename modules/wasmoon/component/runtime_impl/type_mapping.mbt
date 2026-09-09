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
  @component.canonical_discriminant_layout(case_count)
}

///|
fn canonical_memory_layout(
  ty : ValType,
  types : Array[TypeDef?],
  mem_is_64 : Bool,
) -> (Int, Int) raise ComponentRuntimeError {
  match @component.canonical_memory_layout(ty, types, mem_is_64) {
    Some(layout) => layout
    None => raise CanonCallError("invalid or oversized canonical memory layout")
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
    None => (0, None)
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
fn core_types_for_valtype(
  ty : ValType,
  types : Array[TypeDef?],
  mem_is_64 : Bool,
  max_flat? : Int = 2147483647,
) -> Array[@types.ValueType] raise ComponentRuntimeError {
  match @component.canonical_abi_plan(ty, types, mem_is_64, max_flat~) {
    Some(plan) => plan.flat
    None =>
      match ty {
        TypeIdx(idx) => raise InvalidTypeDef(idx)
        _ => raise InvalidTypeDef(-1)
      }
  }
}

///|
fn func_type_needs_memory(
  func_type : FuncType,
  types : Array[TypeDef?],
) -> Bool {
  func_type.params.any(p => {
    @component.canonical_value_contains_memory(p.ty, types)
  }) ||
  (
    func_type.result is Some(ty) &&
    @component.canonical_value_contains_memory(ty, types)
  )
}

///|
fn resolve_canon_resources(
  opts : Array[CanonOpt],
  state : BuildState,
) -> CanonResources raise ComponentRuntimeError {
  let mut mem : Int? = None
  let mut realloc : CanonicalRealloc? = None
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
        realloc = Some({
          func: state.core_funcs[idx],
          async_state: state.async_state,
          owner_component_id: state.resource_table.id,
        })
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
  { mem_addr: mem, realloc, post_return, encoding, }
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
  match @component.canonical_lower_core_func_type(func_type, types, ptr_ty) {
    Some(core_type) => core_type
    None => raise InvalidTypeDef(-1)
  }
}

///|

///|
fn payload_allows_intra_component_transfer(ty : ValType?) -> Bool {
  match ty {
    None => true
    Some(Prim(S8 | U8 | S16 | U16 | S32 | U32 | S64 | U64 | F32 | F64)) => true
    _ => false
  }
}
