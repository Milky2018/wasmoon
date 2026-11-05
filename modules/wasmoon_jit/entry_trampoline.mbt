///|
pub fn entry_trampoline_value_type_code(ty : @types.ValueType) -> Int32 {
  match ty {
    I32 => 0
    I64 => 1
    F32 => 2
    F64 => 3
    V128 => 4
    FuncRef
    | ExternRef
    | RefFunc
    | RefExtern
    | RefFuncTyped(_)
    | RefNullFuncTyped(_)
    | ContRef
    | RefCont
    | RefContTyped(_)
    | RefNullContTyped(_)
    | NullContRef
    | RefNoCont
    | AnyRef
    | ExnRef
    | NullRef
    | NullFuncRef
    | NullExnRef
    | NullExternRef
    | RefStruct(_)
    | RefNullStruct(_)
    | RefArray(_)
    | RefNullArray(_)
    | RefAny
    | RefEq
    | RefNullEq
    | RefI31
    | RefNullI31
    | RefStructAbs
    | RefArrayAbs
    | StructRef
    | ArrayRef
    | RefNone => 1
  }
}

///|
pub fn entry_trampoline_type_codes(
  types : ArrayView[@types.ValueType],
) -> Array[Int32] {
  let codes : Array[Int32] = []
  for ty in types {
    codes.push(entry_trampoline_value_type_code(ty))
  }
  codes
}

///|
pub fn count_entry_trampoline_slots(
  types : ArrayView[@types.ValueType],
) -> Int32 {
  let mut slots = 0
  for ty in types {
    if ty is V128 {
      slots = slots + 2
    } else {
      slots = slots + 1
    }
  }
  slots
}

///|
pub fn entry_trampoline_signature_hash(
  param_types : ArrayView[@types.ValueType],
  result_types : ArrayView[@types.ValueType],
) -> Int64 {
  let mut hash = 0xcbf29ce484222325L
  let fnv_prime = 0x100000001b3L
  hash = hash ^ param_types.length().to_int64()
  hash = hash * fnv_prime
  for ty in param_types {
    hash = hash ^ entry_trampoline_value_type_code(ty).to_int64()
    hash = hash * fnv_prime
  }
  hash = hash ^ 0xffL
  hash = hash * fnv_prime
  hash = hash ^ result_types.length().to_int64()
  hash = hash * fnv_prime
  for ty in result_types {
    hash = hash ^ entry_trampoline_value_type_code(ty).to_int64()
    hash = hash * fnv_prime
  }
  hash
}
