/// Native hostcall scratch-area access.

///|
/// Get the runtime store function address for the current JIT -> hostcall.
///
/// This value is set by `wasmoon_jit_hostcall` right before invoking the
/// MoonBit hostcall callback.
pub fn get_hostcall_func_addr() -> Int {
  c_jit_get_hostcall_func_idx()
}

///|
/// Get the pointer to the hostcall scratch `values_vec` buffer.
fn get_hostcall_values_ptr() -> Int64 {
  c_jit_get_hostcall_values_ptr()
}

///|
pub fn hostcall_value_slot_read(slot : Int) -> Int64 {
  native_value_slot_read(get_hostcall_values_ptr(), slot)
}

///|
pub fn hostcall_value_slot_write(slot : Int, value : Int64) -> Unit {
  native_value_slot_write(get_hostcall_values_ptr(), slot, value)
}

///|
/// Get the number of argument *slots* in `values_vec`.
///
/// Note: slots are 8 bytes each; V128 occupies 2 slots.
pub fn get_hostcall_num_arg_slots() -> Int {
  c_jit_get_hostcall_num_args()
}

///|
/// Get the number of result *slots* in `values_vec`.
///
/// Note: slots are 8 bytes each; V128 occupies 2 slots.
pub fn get_hostcall_num_result_slots() -> Int {
  c_jit_get_hostcall_num_results()
}
