///|
type NativeContinuationArena

///|
extern "c" fn NativeContinuationArena::new() -> NativeContinuationArena = "wasmoon_continuation_arena_new"

///|
#borrow(self)
extern "c" fn NativeContinuationArena::clear(
  self : NativeContinuationArena,
) -> Unit = "wasmoon_continuation_arena_clear"

///|
#borrow(context, arena)
extern "c" fn bind_continuation_arena(
  context : JITContext,
  arena : NativeContinuationArena,
) -> Unit = "wasmoon_continuation_arena_bind"

///|
pub fn NativeJITContext::set_continuation_arena(
  self : NativeJITContext,
  arena : NativeContinuationArena,
) -> Unit {
  bind_continuation_arena(self.handle, arena)
}

///|
#borrow(context, roots)
extern "c" fn define_continuation_type(
  context : JITContext,
  index : Int,
  trampoline : Int64,
  params : Int,
  results : Int,
  roots : FixedArray[Int],
) -> Int = "wasmoon_continuation_define_type"

///|
pub fn NativeJITContext::define_continuation_type(
  self : NativeJITContext,
  index : Int,
  trampoline : Int64,
  params : Array[@types.ValueType],
  results : Array[@types.ValueType],
) -> Bool {
  let roots : Array[Int] = []
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
  define_continuation_type(
    self.handle,
    index,
    trampoline,
    roots.length(),
    count_entry_trampoline_slots(results),
    buffer,
  ) !=
  0
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
