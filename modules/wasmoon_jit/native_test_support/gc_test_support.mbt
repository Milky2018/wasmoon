///|
extern "c" fn c_gc_environment_is_clear(ctx_ptr : Int64) -> Int = "wasmoon_test_gc_environment_is_clear"

///|
pub fn gc_environment_is_clear(ctx_ptr : Int64) -> Bool {
  c_gc_environment_is_clear(ctx_ptr) == 1
}

///|
extern "c" fn c_shared_indirect_table_live_count() -> Int64 = "wasmoon_jit_debug_shared_indirect_table_live_count"

///|
pub fn shared_indirect_table_live_count() -> Int64 {
  c_shared_indirect_table_live_count()
}
