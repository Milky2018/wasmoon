///|
extern "c" fn c_gc_environment_is_clear(ctx_ptr : Int64) -> Int = "wasmoon_test_gc_environment_is_clear"

///|
pub fn gc_environment_is_clear(ctx_ptr : Int64) -> Bool {
  c_gc_environment_is_clear(ctx_ptr) == 1
}
