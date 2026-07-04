/// C heap compatibility wrappers.
///
/// The implementation lives in `Milky2018/wasmoon_jit`; this package keeps the
/// historical `Milky2018/wasmoon/jit` API while Wasmoon call sites migrate.

///|
pub type CHeap = @wasmoon_jit.CHeap

///|
pub type CHeapError = @wasmoon_jit.CHeapError

///|
pub fn value_to_i64(value : @types.Value) -> Int64 {
  @wasmoon_jit.value_to_i64(value)
}

///|
pub fn i64_to_value(raw : Int64, ty : @types.ValueType) -> @types.Value {
  @wasmoon_jit.i64_to_value(raw, ty)
}

///|
pub fn gc_debug_set_fail_alloc(fail_at : Int, fail_every? : Int = 0) -> Unit {
  @wasmoon_jit.gc_debug_set_fail_alloc(fail_at, fail_every~)
}
