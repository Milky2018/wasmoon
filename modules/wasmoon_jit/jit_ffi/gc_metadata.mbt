///|
#borrow(context, types, canonical, functions)
extern "c" fn bind_gc_metadata(
  context : JITContext,
  types : FixedArray[Int],
  canonical : FixedArray[Int],
  functions : FixedArray[Int],
) -> Unit = "wasmoon_jit_bind_gc_metadata"

///|
/// Retain all three GC metadata arrays, replacing even empty mappings.
/// Types use six Int slots per entry, matching the native GC type-cache ABI.
/// Bind outside guest execution and do not mutate arrays while they are bound.
pub fn JITContext::bind_gc_metadata(
  self : JITContext,
  types : FixedArray[Int],
  canonical : FixedArray[Int],
  functions : FixedArray[Int],
) -> Unit {
  guard types.length() % 6 == 0 else {
    abort("invalid GC type metadata stride")
  }
  bind_gc_metadata(self, types, canonical, functions)
}
