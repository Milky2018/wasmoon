///|
/// Translate an immutable native snapshot once, preserving Store identity at
/// every subsequent interpreter/native boundary.
pub fn Store::decode_native_exception(
  self : Store,
  reference : Int64,
) -> @types.Value raise RuntimeError {
  if reference == 0L {
    return Null
  }
  if self.native_exception_to_store.get(reference) is Some(index) {
    return ExnRef(index)
  }
  guard self.native_execution.exceptions().snapshot(reference)
    is Some((tag, words)) else {
    raise UndefinedElement
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
      ExnRef | NullExnRef => self.decode_native_exception(raw)
      FuncRef | RefFunc | RefFuncTyped(_) | RefNullFuncTyped(_) | NullFuncRef =>
        if raw == 0L {
          Null
        } else {
          guard self.lookup_jit_funcref_store_addr(
              @wasmoon_jit.untag_funcref_ptr(raw),
            )
            is Some(address) else {
            raise UndefinedElement
          }
          FuncRef(address)
        }
      ExternRef | RefExtern | NullExternRef =>
        if raw == 0L {
          Null
        } else if @wasmoon_jit.decode_externref(raw) is Some(index) {
          ExternRef(index)
        } else {
          self.wrap_as_extern(self.decode_exception_gc_word(raw))
        }
      AnyRef | RefAny | NullRef | RefEq | RefNullEq =>
        self.decode_exception_gc_word(raw)
      V128 => V128(@types.int64_pair_to_v128_le(raw, words[slot + 1]))
      _ => @wasmoon_jit.i64_to_value(raw, ty)
    }
    values.push(value)
    slot = slot + width
  }
  if slot != words.length() {
    raise TypeMismatch
  }
  let index = self.alloc_exn(tag, values)
  self.native_exception_to_store.set(reference, index)
  self.store_exception_to_native.set(index, reference)
  ExnRef(index)
}

///|
fn Store::decode_exception_gc_word(self : Store, raw : Int64) -> @types.Value {
  if raw == 0L {
    Null
  } else if (raw & 1L) != 0L {
    I31((raw >> 1).to_int())
  } else {
    let index = @wasmoon_jit.decode_heap_ref(raw)
    match self.c_heap {
      Some(heap) if heap.is_array(index) => ArrayRef(index)
      _ => StructRef(index)
    }
  }
}

///|
pub fn Store::encode_native_exception(
  self : Store,
  index : Int,
) -> Int64 raise RuntimeError {
  self.ensure_open()
  if self.store_exception_to_native.get(index) is Some(reference) {
    return reference
  }
  let exception = self.get_exn(index)
  if !self.native_execution
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
      ExnRef(index) => words.push(self.encode_native_exception(index))
      FuncRef(address) => {
        guard self.lookup_jit_funcref_ptr(address) is Some(pointer) else {
          raise UndefinedElement
        }
        words.push(@wasmoon_jit.tag_funcref_ptr(pointer))
      }
      ExternRef(_) => {
        let inner = self.unwrap_extern(value)
        words.push(@wasmoon_jit.value_to_i64(inner))
      }
      V128(bytes) => {
        words.push(@types.bytes_to_int64_le(bytes, 0))
        words.push(@types.bytes_to_int64_le(bytes, 8))
      }
      _ => words.push(@wasmoon_jit.value_to_i64(value))
    }
  }
  let heap = match self.c_heap {
    Some(heap) => heap.get_ptr()
    None => 0L
  }
  let reference = self.native_execution
    .exceptions()
    .insert(heap, exception.tag_addr, words)
  if reference == 0L {
    raise OutOfMemory
  }
  self.native_exception_to_store.set(reference, index)
  self.store_exception_to_native.set(index, reference)
  reference
}

///|
/// CHeap's low-level Value codec carries native exception indices; Store APIs
/// always expose interpreter indices and translate at this boundary.
fn Store::encode_heap_exception(
  self : Store,
  value : @types.Value,
) -> @types.Value raise RuntimeError {
  match value {
    ExnRef(index) => ExnRef((self.encode_native_exception(index) >> 1).to_int())
    _ => value
  }
}

///|
fn Store::decode_heap_exception(
  self : Store,
  value : @types.Value,
) -> @types.Value raise RuntimeError {
  match value {
    ExnRef(index) => self.decode_native_exception((index.to_int64() << 1) | 1L)
    _ => value
  }
}
