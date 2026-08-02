///|
extern "c" fn c_shared_indirect_table_live_count() -> Int64 = "wasmoon_jit_debug_shared_indirect_table_live_count"

///|
pub fn shared_indirect_table_live_count() -> Int64 {
  c_shared_indirect_table_live_count()
}
