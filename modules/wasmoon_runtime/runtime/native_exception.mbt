///|
pub fn Store::decode_native_exception(
  self : Store,
  reference : Int64,
) -> @types.Value raise RuntimeError {
  self.references.decode_native_exception(reference)
}

///|
pub fn Store::encode_native_exception(
  self : Store,
  index : Int32,
) -> Int64 raise RuntimeError {
  self.references.encode_native_exception(index)
}

///|
/// Translate an immutable native snapshot once, preserving Store identity at
/// every subsequent interpreter/native boundary.
fn StoreReferences::decode_native_exception(
  self : StoreReferences,
  reference : Int64,
) -> @types.Value raise RuntimeError {
  if reference == 0L {
    return Null
  }
  if self.native.native_exception_to_store.get(reference) is Some(index) {
    return ExnRef(index)
  }
  let pending = [reference]
  let created : Array[(Int64, Int32)] = []
  errdefer (for (reference, index) in created {
    self.native.native_exception_to_store.remove(reference)
    self.native.store_exception_to_native.remove(index)
    self.exns.remove(index)
  })
  while !pending.is_empty() {
    let reference = pending.pop().unwrap()
    guard self.native.native_execution.exceptions().snapshot(reference)
      is Some((tag, words)) else {
      raise UndefinedElement
    }
    let index = match self.native.native_exception_to_store.get(reference) {
      Some(index) => index
      None => {
        let index = self.alloc_exn(tag, [])
        self.native.native_exception_to_store.set(reference, index)
        self.native.store_exception_to_native.set(index, reference)
        created.push((reference, index))
        index
      }
    }
    let signature = self.get_tag_type(tag)
    let values : Array[@types.Value] = []
    let mut slot = 0
    for ty in signature.params {
      let width = if ty == V128 { 2 } else { 1 }
      if slot + width > words.length() {
        raise TypeMismatch
      }
      let raw = words[slot]
      let value : @types.Value = match ty {
        ExnRef | NullExnRef =>
          if raw == 0L {
            Null
          } else {
            let child = match self.native.native_exception_to_store.get(raw) {
              Some(index) => index
              None => {
                guard self.native.native_execution.exceptions().snapshot(raw)
                  is Some((tag, _)) else {
                  raise UndefinedElement
                }
                let index = self.alloc_exn(tag, [])
                self.native.native_exception_to_store.set(raw, index)
                self.native.store_exception_to_native.set(index, raw)
                created.push((raw, index))
                pending.push(raw)
                index
              }
            }
            ExnRef(child)
          }
        FuncRef
        | RefFunc
        | RefFuncTyped(_)
        | RefNullFuncTyped(_)
        | NullFuncRef =>
          if raw == 0L {
            Null
          } else if @native_bridge.decode_store_funcref(raw) is Some(address) {
            FuncRef(address)
          } else {
            guard self.funcref_registry.lookup_store_addr(
                @native_bridge.untag_funcref_ptr(raw),
              )
              is Some(address) else {
              raise UndefinedElement
            }
            FuncRef(address)
          }
        ExternRef | RefExtern | NullExternRef =>
          if raw == 0L {
            Null
          } else if @native_bridge.decode_externref(raw) is Some(index) {
            ExternRef(index)
          } else {
            self.wrap_as_extern(self.decode_exception_gc_word(raw))
          }
        AnyRef | RefAny | NullRef | RefEq | RefNullEq =>
          self.decode_exception_gc_word(raw)
        V128 => V128(@types.int64_pair_to_v128_le(raw, words[slot + 1]))
        _ => @native_bridge.i64_to_value(raw, ty)
      }
      values.push(value)
      slot = slot + width
    }
    if slot != words.length() {
      raise TypeMismatch
    }
    for value in values {
      self.exns[index].values.push(value)
    }
  }
  ExnRef(self.native.native_exception_to_store.get(reference).unwrap())
}

///|
fn StoreReferences::decode_exception_gc_word(
  self : StoreReferences,
  raw : Int64,
) -> @types.Value {
  if raw == 0L {
    Null
  } else if (raw & 1L) != 0L {
    I31((raw >> 1).to_int())
  } else {
    let index = @native_bridge.decode_heap_ref(raw)
    match self.native.c_heap {
      Some(heap) if heap.is_array(index) => ArrayRef(index)
      _ => StructRef(index)
    }
  }
}

///|
fn StoreReferences::encode_native_exception(
  self : StoreReferences,
  index : Int32,
  created~ : Array[Int32] = [],
) -> Int64 raise RuntimeError {
  self.ensure_open()
  if self.native.store_exception_to_native.get(index) is Some(reference) {
    return reference
  }
  let checkpoint = created.length()
  errdefer (while created.length() > checkpoint {
    self.release_native_exception(created.pop().unwrap())
  })
  let pending = [(index, false)]
  let visiting : Map[Int32, Bool] = Map([])
  while pending.pop() is Some((current, ready)) {
    if self.native.store_exception_to_native.contains(current) {
      continue
    }
    let exception = self.get_exn(current)
    if ready {
      self.encode_exception_snapshot(current) |> ignore
      created.push(current)
      visiting.remove(current)
    } else {
      // Wasm snapshots are immutable and acyclic. Reject a forged host cycle
      // rather than recursing indefinitely or publishing an incomplete token.
      if visiting.contains(current) {
        raise TypeMismatch
      }
      visiting.set(current, true)
      pending.push((current, true))
      for value in exception.values {
        if value is ExnRef(child) &&
          !self.native.store_exception_to_native.contains(child) {
          pending.push((child, false))
        }
      }
    }
  }
  self.native.store_exception_to_native.get(index).unwrap()
}

///|
fn StoreReferences::encode_exception_snapshot(
  self : StoreReferences,
  index : Int32,
) -> Int64 raise RuntimeError {
  let exception = self.get_exn(index)
  if !self.native.native_execution
    .exceptions()
    .define_tag(
      exception.tag_addr,
      self.get_tag_type(exception.tag_addr).params,
    ) {
    raise OutOfMemory
  }
  let words : Array[Int64] = []
  for value in exception.values {
    match value {
      ExnRef(index) =>
        words.push(self.native.store_exception_to_native.get(index).unwrap())
      FuncRef(address) => {
        guard address >= 0 else { raise UndefinedElement }
        words.push(@native_bridge.encode_store_funcref(address))
      }
      ExternRef(_) => {
        let inner = self.unwrap_extern(value)
        words.push(@native_bridge.value_to_i64(inner))
      }
      V128(bytes) => {
        words.push(@types.bytes_to_int64_le(bytes, 0))
        words.push(@types.bytes_to_int64_le(bytes, 8))
      }
      _ => words.push(@native_bridge.value_to_i64(value))
    }
  }
  let heap = match self.native.c_heap {
    Some(heap) => heap.get_ptr()
    None => @native_bridge.GCHeapHandle::null()
  }
  let reference = self.native.native_execution
    .exceptions()
    .insert(heap, exception.tag_addr, words)
  if reference == 0L {
    match self.native.native_execution.exceptions().quota_denied() {
      25 => raise ResourceLimitExceeded(GcBytes)
      26 => raise ResourceLimitExceeded(GcObjects)
      _ => raise OutOfMemory
    }
  }
  self.native.native_exception_to_store.set(reference, index)
  self.native.store_exception_to_native.set(index, reference)
  reference
}

///|
/// CHeap's low-level Value codec carries native exception indices; Store APIs
/// always expose interpreter indices and translate at this boundary.
fn Store::encode_heap_value(
  self : Store,
  value : @types.Value,
) -> @types.Value raise RuntimeError {
  match value {
    ExnRef(index) => ExnRef((self.encode_native_exception(index) >> 1).to_int())
    ExternRef(index) if index < 0 => self.unwrap_extern(value)
    _ => value
  }
}

///|
fn Store::decode_heap_value(
  self : Store,
  ty : @types.ValueType,
  value : @types.Value,
) -> @types.Value raise RuntimeError {
  let value = match value {
    ExnRef(index) =>
      self.decode_native_exception(@native_bridge.encode_exception_ref(index))
    StructRef(index) =>
      match self.references.native.c_heap {
        Some(heap) if heap.is_array(index) => ArrayRef(index)
        _ => value
      }
    _ => value
  }
  match (ty, value) {
    (ExternRef | RefExtern | NullExternRef, StructRef(_) | ArrayRef(_) | I31(_)) =>
      self.wrap_as_extern(value)
    _ => value
  }
}

///|
fn StoreReferences::release_native_exception(
  self : StoreReferences,
  index : Int32,
) -> Unit {
  if self.native.store_exception_to_native.get(index) is Some(reference) {
    self.native.native_execution.exceptions().release_snapshot(reference)
    self.native.store_exception_to_native.remove(index)
    self.native.native_exception_to_store.remove(reference)
  }
}
