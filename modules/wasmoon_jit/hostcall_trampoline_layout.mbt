// Hostcall import trampoline layout planning.
//
// This belongs to Wasmoon JIT glue rather than generic machine-code emission:
// the buffer format is the ABI between JIT-generated Wasm code and
// `wasmoon_jit_hostcall`.

///|
pub(all) struct HostcallImportTrampolineLayout {
  arg_slots : Int
  result_slots : Int
  values_vec_bytes : Int
  int_overflow_count : Int
  float_overflow_types : Array[@types.ValueType]
}

///|
pub fn hostcall_value_slot_count(ty : @types.ValueType) -> Int {
  match ty {
    V128 => 2
    _ => 1
  }
}

///|
pub fn hostcall_value_byte_count(ty : @types.ValueType) -> Int {
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
  param_types : Array[@types.ValueType],
  result_types : Array[@types.ValueType],
  max_int_regs : Int,
  max_float_regs : Int,
) -> HostcallImportTrampolineLayout {
  let mut total_int = 0
  for ty in param_types {
    if is_hostcall_int_class(ty) {
      total_int = total_int + 1
    }
  }
  let int_overflow_count = if total_int > max_int_regs {
    total_int - max_int_regs
  } else {
    0
  }
  let float_overflow_types : Array[@types.ValueType] = []
  let mut float_seen = 0
  for ty in param_types {
    if is_hostcall_int_class(ty) {
      continue
    }
    if float_seen >= max_float_regs {
      float_overflow_types.push(ty)
    }
    float_seen = float_seen + 1
  }
  let mut arg_slots = 0
  for ty in param_types {
    arg_slots = arg_slots + hostcall_value_slot_count(ty)
  }
  let mut result_slots = 0
  for ty in result_types {
    result_slots = result_slots + hostcall_value_slot_count(ty)
  }
  {
    arg_slots,
    result_slots,
    values_vec_bytes: (arg_slots + result_slots) * 8,
    int_overflow_count,
    float_overflow_types,
  }
}
