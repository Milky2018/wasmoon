///|
/// Store-owned immutable exception snapshots shared by native instances.
type NativeExceptionArena

///|
extern "c" fn NativeExceptionArena::new() -> NativeExceptionArena = "wasmoon_exception_arena_new"

///|
#borrow(self)
extern "c" fn NativeExceptionArena::clear(self : NativeExceptionArena) -> Unit = "wasmoon_exception_arena_clear"

///|
#borrow(context, arena)
extern "c" fn bind_exception_arena(
  context : JITContext,
  arena : NativeExceptionArena,
) -> Unit = "wasmoon_exception_arena_bind"

///|
pub fn NativeJITContext::set_exception_arena(
  self : NativeJITContext,
  arena : NativeExceptionArena,
) -> Unit {
  bind_exception_arena(self.handle, arena)
}

///|
#borrow(self, values)
extern "c" fn NativeExceptionArena::insert_raw(
  self : NativeExceptionArena,
  heap : Int64,
  tag : Int,
  values : FixedArray[Int64],
  count : Int,
) -> Int64 = "wasmoon_exception_arena_insert"

///|
#borrow(self)
extern "c" fn NativeExceptionArena::tag(
  self : NativeExceptionArena,
  reference : Int64,
) -> Int = "wasmoon_exception_arena_tag"

///|
#borrow(self)
extern "c" fn NativeExceptionArena::count(
  self : NativeExceptionArena,
  reference : Int64,
) -> Int = "wasmoon_exception_arena_count"

///|
#borrow(self)
extern "c" fn NativeExceptionArena::value(
  self : NativeExceptionArena,
  reference : Int64,
  index : Int,
) -> Int64 = "wasmoon_exception_arena_value"

///|
pub fn NativeExceptionArena::snapshot(
  self : NativeExceptionArena,
  reference : Int64,
) -> (Int, Array[Int64])? {
  let count = self.count(reference)
  if count < 0 {
    return None
  }
  Some(
    (
      self.tag(reference),
      Array::makei(count, fn(i) { self.value(reference, i) }),
    ),
  )
}

///|
pub fn NativeExceptionArena::insert(
  self : NativeExceptionArena,
  heap : Int64,
  tag : Int,
  values : Array[Int64],
) -> Int64 {
  let buffer = FixedArray::make(values.length(), 0L)
  for i, value in values {
    buffer[i] = value
  }
  self.insert_raw(heap, tag, buffer, buffer.length())
}

///|
#borrow(self, roots)
extern "c" fn NativeExceptionArena::define_tag_raw(
  self : NativeExceptionArena,
  tag : Int,
  roots : FixedArray[Int],
  count : Int,
) -> Int = "wasmoon_exception_arena_define_tag"

///|
/// Describe reference-bearing payload words; scalar and SIMD words are never
/// retained as accidental GC roots.
pub fn NativeExceptionArena::define_tag(
  self : NativeExceptionArena,
  tag : Int,
  params : Array[@types.ValueType],
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
  self.define_tag_raw(tag, buffer, buffer.length()) != 0
}
