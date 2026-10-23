///|
/// Invalid native metadata must be rejected before publishing any pointers.
pub suberror GCMetadataError {
  InvalidTypeStride
  PayloadCountMismatch
  PayloadTooLarge
  InvalidSafepointMap
} derive(Debug)

///|
pub extend GCMetadataError with Debug::{to_repr}

///|
pub extend GCMetadataError with Show::{output, to_string}

///|
pub impl Show for GCMetadataError with fn output(self, logger) {
  logger.write_string(@types.compact_show_repr(Repr(self).to_string()))
}

///|
extern "c" fn safepoint_payload_fits(count : Int32) -> Bool = "wasmoon_jit_safepoint_payload_fits"

///|
/// Check the native descriptor's representable size before allocating arrays.
pub fn PreparedSafepoints::check_count(
  count : Int32,
) -> Unit raise GCMetadataError {
  guard safepoint_payload_fits(count) else { raise PayloadTooLarge }
}

///|
#borrow(context, types, canonical, functions)
extern "c" fn bind_gc_metadata(
  context : JITContext,
  types : FixedArray[Int32],
  canonical : FixedArray[Int32],
  functions : FixedArray[Int32],
) -> Unit = "wasmoon_jit_bind_gc_metadata"

///|
/// Retain all three GC metadata arrays, replacing even empty mappings.
/// Types use six Int slots per entry, matching the native GC type-cache ABI.
/// Bind outside guest execution and do not mutate arrays while they are bound.
pub fn JITContext::bind_gc_metadata(
  self : JITContext,
  types : FixedArray[Int32],
  canonical : FixedArray[Int32],
  functions : FixedArray[Int32],
) -> Unit raise GCMetadataError {
  guard types.length() % 6 == 0 else { raise InvalidTypeStride }
  bind_gc_metadata(self, types, canonical, functions)
}

///|
/// Retain the payloads in a stable native descriptor. Bind outside execution;
/// callers must not mutate offsets while they are bound.
#borrow(self, blob, offsets)
pub extern "c" fn JITContext::bind_gc_safepoints(
  self : JITContext,
  function : Int32,
  blob : Bytes,
  offsets : FixedArray[Int32],
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
  count : Int32,
) -> FixedArray[Int64] = "wasmoon_jit_snapshot_gc_function_addresses"

///|
/// Copy a legacy native pointer table into a typed snapshot and bind it.
/// The source must contain count readable native pointers.
pub fn JITContext::snapshot_gc_function_addresses(
  self : JITContext,
  table : Int64,
  count : Int32,
) -> Unit {
  self.bind_gc_function_addresses(snapshot_function_addresses(table, count))
}

///|
/// Immutable native views retaining their MoonBit payloads through a finalizer.
pub type PreparedSafepoints

///|
#borrow(blobs, offsets)
extern "c" fn prepare_safepoints(
  blobs : FixedArray[Bytes],
  offsets : FixedArray[FixedArray[Int32]],
) -> PreparedSafepoints = "wasmoon_jit_prepare_safepoints"

///|
#borrow(prepared)
extern "c" fn prepared_safepoints_valid(prepared : PreparedSafepoints) -> Bool = "wasmoon_jit_prepared_safepoints_valid"

///|
/// Bind outside execution. The context retains the owner independently of callers.
#borrow(self, prepared)
pub extern "c" fn JITContext::bind_prepared_safepoints(
  self : JITContext,
  prepared : PreparedSafepoints,
) -> Bool = "wasmoon_jit_bind_prepared_safepoints"

///|
pub fn PreparedSafepoints::new(
  blobs : FixedArray[Bytes],
  offsets : FixedArray[FixedArray[Int32]],
) -> PreparedSafepoints raise GCMetadataError {
  guard blobs.length() == offsets.length() else { raise PayloadCountMismatch }
  PreparedSafepoints::check_count(blobs.length())
  let snapshot : FixedArray[FixedArray[Int32]] = FixedArray::makei(
    offsets.length(),
    i => {
      let sites = offsets[i]
      if sites.is_empty() {
        []
      } else {
        FixedArray::makei(sites.length(), j => sites[j])
      }
    },
  )
  let prepared = prepare_safepoints(blobs, snapshot)
  guard prepared_safepoints_valid(prepared) else { raise InvalidSafepointMap }
  prepared
}
