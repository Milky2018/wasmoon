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

///|
/// Retain the payloads in a stable native descriptor. Bind outside execution;
/// callers must not mutate offsets while they are bound.
#borrow(self, blob, offsets)
pub extern "c" fn JITContext::bind_gc_safepoints(
  self : JITContext,
  function : Int,
  blob : Bytes,
  offsets : FixedArray[Int],
) -> Bool = "wasmoon_jit_bind_gc_safepoints"

///|
/// Retain a function-address snapshot. The snapshot does not own executable code.
/// Bind outside execution and do not mutate the array while it is bound.
#borrow(self, addresses)
pub extern "c" fn JITContext::bind_gc_function_addresses(
  self : JITContext,
  addresses : FixedArray[Int64],
) -> Unit = "wasmoon_jit_bind_gc_function_addresses"

///|
extern "c" fn snapshot_function_addresses(
  table : Int64,
  count : Int,
) -> FixedArray[Int64] = "wasmoon_jit_snapshot_gc_function_addresses"

///|
/// Copy a legacy native pointer table into a typed snapshot and bind it.
/// The source must contain count readable native pointers.
pub fn JITContext::snapshot_gc_function_addresses(
  self : JITContext,
  table : Int64,
  count : Int,
) -> Unit {
  self.bind_gc_function_addresses(snapshot_function_addresses(table, count))
}
