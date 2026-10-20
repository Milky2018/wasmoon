///|
// A native Store adopts managed construction state once. Thereafter the native
// descriptor is authoritative for interpreter, host and compiled table access.
fn Store::bind_table_storage(
  self : Store,
  table : Table,
  native : @native_bridge.JITTable,
) -> Unit raise RuntimeError {
  let elem_type = table.elem_type
  let references = self.references
  let storage : NativeTableStorage = { table: native, references, }
  match elem_type {
    FuncRef | RefFunc | RefFuncTyped(_) | RefNullFuncTyped(_) | NullFuncRef =>
      native.raw_ptr().use_store_references()
    _ => ()
  }
  match table.storage {
    Managed(elements) =>
      for index, value in elements {
        let (type_index, word) = references.encode_table_value(value)
        native.set(index, word, type_index)
      }
    Native(_) => raise InvalidHandle
  }
  table.storage = Native(storage)
}

///|
fn StoreReferences::encode_table_value(
  self : StoreReferences,
  value : @types.Value,
) -> (Int32, Int64) raise RuntimeError {
  match value {
    FuncRef(address) => {
      guard address >= 0 else { raise UndefinedElement }
      (-1, 0x3000000000000000L | (address.to_int64() + 1L))
    }
    I31(value) => (-1, ((value & @types.I32_MAX).to_int64() << 1) | 1L)
    ExnRef(index) => (-1, self.encode_native_exception(index))
    ExternRef(index) => {
      let value = self.unwrap_extern(ExternRef(index))
      (
        if index < 0 {
          -1 - index
        } else {
          -1
        },
        match value {
          ExternRef(index) => @native_bridge.encode_externref(index)
          I31(value) => ((value & @types.I32_MAX).to_int64() << 1) | 1L
          StructRef(value) | ArrayRef(value) =>
            @native_bridge.value_to_i64(StructRef(value))
          Null => 0L
          _ => raise TypeMismatch
        },
      )
    }
    _ => (-1, @native_bridge.value_to_i64(value))
  }
}

///|
fn StoreReferences::decode_table_value(
  self : StoreReferences,
  type_ : @types.ValueType,
  metadata : Int32,
  word : Int64,
  root : Bool,
) -> @types.Value raise RuntimeError {
  // A wrapped null has a zero payload but a nonnull external identity.
  if (match type_ {
      ExternRef | RefExtern | NullExternRef => true
      _ => false
    }) &&
    metadata >= 0 {
    guard self.wrapped_externs.contains(metadata) else { raise InvalidHandle }
    return ExternRef(-1 - metadata)
  }
  if word == 0L {
    return Null
  }
  match type_ {
    FuncRef | RefFunc | RefFuncTyped(_) | RefNullFuncTyped(_) | NullFuncRef => {
      guard word > 0L && (word & 0x3000000000000000L) == 0x3000000000000000L else {
        raise InvalidHandle
      }
      FuncRef(((word & 0x0FFFFFFFFFFFFFFFL) - 1L).to_int())
    }
    ExnRef | NullExnRef => self.decode_native_exception(word)
    ContRef
    | RefCont
    | RefContTyped(_)
    | RefNullContTyped(_)
    | NullContRef
    | RefNoCont => @native_bridge.i64_to_value(word, type_)
    ExternRef | RefExtern | NullExternRef =>
      if @native_bridge.decode_externref(word) is Some(index) {
        ExternRef(index)
      } else {
        let value = self.decode_table_gc_word(word)
        if root {
          value
        } else {
          self.wrap_as_extern(value)
        }
      }
    _ => self.decode_table_gc_word(word)
  }
}

///|
fn StoreReferences::decode_table_gc_word(
  self : StoreReferences,
  word : Int64,
) -> @types.Value raise RuntimeError {
  if @native_bridge.decode_externref(word) is Some(index) {
    return ExternRef(index)
  }
  if (word & 1L) != 0L {
    return I31((word >> 1).to_int())
  }
  let index = @native_bridge.decode_heap_ref(word)
  match self.native.c_heap {
    Some(heap) =>
      if heap.is_array(index) {
        ArrayRef(index)
      } else {
        StructRef(index)
      }
    None =>
      match self.heap.get(index) {
        Array(_) => ArrayRef(index)
        Struct(_) => StructRef(index)
      }
  }
}
