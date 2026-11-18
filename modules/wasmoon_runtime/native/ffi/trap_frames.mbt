///|
extern "c" fn trap_pc() -> Int64 = "wasmoon_jit_get_trap_pc"

///|
extern "c" fn trap_frame_count() -> Int32 = "wasmoon_jit_get_trap_frame_count"

///|
extern "c" fn trap_frame_pc(index : Int32) -> Int64 = "wasmoon_jit_get_trap_frame_pc"

///|
/// Program counters captured by the current native trap activation.
pub fn captured_trap_pcs() -> Array[Int64] {
  guard trap_pc() != 0L else { return [] }
  Array::makei(trap_frame_count(), trap_frame_pc)
}
