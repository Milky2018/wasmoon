// Hostcall import trampoline layout planning.
//
// This belongs to Wasmoon JIT glue rather than generic machine-code emission:
// the buffer format is the ABI between JIT-generated Wasm code and
// `wasmoon_jit_hostcall`.

///|
pub(all) struct HostcallImportTrampolineLayout {
  arg_slots : Int32
  result_slots : Int32
  values_vec_bytes : Int32
}

///|
pub fn hostcall_value_slot_count(ty : @types.ValueType) -> Int32 {
  match ty {
    V128 => 2
    _ => 1
  }
}

///|
pub fn hostcall_value_byte_count(ty : @types.ValueType) -> Int32 {
  hostcall_value_slot_count(ty) * 8
}

///|
fn is_hostcall_int_class(ty : @types.ValueType) -> Bool {
  match ty {
    F32 | F64 | V128 => false
    _ => true
  }
}

///|
pub fn plan_hostcall_import_trampoline_layout(
  param_types : ArrayView[@types.ValueType],
  result_types : ArrayView[@types.ValueType],
) -> HostcallImportTrampolineLayout {
  let mut arg_slots = 0
  for ty in param_types {
    arg_slots = arg_slots + hostcall_value_slot_count(ty)
  }
  let mut result_slots = 0
  for ty in result_types {
    result_slots = result_slots + hostcall_value_slot_count(ty)
  }
  { arg_slots, result_slots, values_vec_bytes: (arg_slots + result_slots) * 8, }
}
