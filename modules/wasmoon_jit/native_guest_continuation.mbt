///|
pub fn NativeJITContext::set_continuation_arena(
  self : NativeJITContext,
  arena : NativeContinuationArena,
) -> Unit {
  self.handle.bind_continuation_arena(arena)
}

///|
pub fn NativeJITContext::define_continuation_type(
  self : NativeJITContext,
  index : Int32,
  trampoline : Int64,
  params : ArrayView[@types.ValueType],
  results : ArrayView[@types.ValueType],
) -> Bool {
  let roots : Array[Int32] = []
  for ty in params {
    match ty {
      I32 | I64 | F32 | F64 => roots.push(0)
      V128 => {
        roots.push(0)
        roots.push(0)
      }
      _ => roots.push(1)
    }
  }
  let buffer = FixedArray::make(roots.length(), 0)
  for i, root in roots {
    buffer[i] = root
  }
  self.handle.define_continuation_type(
    index,
    trampoline,
    roots.length(),
    count_entry_trampoline_slots(results),
    buffer,
  )
}

///|
extern "c" fn cont_new_ptr() -> Int64 = "wasmoon_cont_new_ptr"

///|
extern "c" fn cont_bind_ptr() -> Int64 = "wasmoon_cont_bind_ptr"

///|
extern "c" fn cont_suspend_ptr() -> Int64 = "wasmoon_cont_suspend_ptr"

///|
extern "c" fn cont_resume_ptr() -> Int64 = "wasmoon_cont_resume_ptr"

///|
extern "c" fn cont_switch_ptr() -> Int64 = "wasmoon_cont_switch_ptr"
