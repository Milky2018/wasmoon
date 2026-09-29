///|
#borrow(context)
#owned(data, elements)
extern "c" fn bind_segments(
  context : JITContext,
  data : FixedArray[Bytes],
  elements : FixedArray[FixedArray[Int64]],
) -> Bool = "wasmoon_jit_bind_segments"

///|
/// Replace instance segments outside guest execution. Empty payloads represent
/// dropped segments. Snapshot mutable arrays so guest drop is instance-local;
/// immutable data Bytes are shared. Elements are encoded as (value, type) pairs.
pub fn JITContext::set_segments(
  self : JITContext,
  data : Array[Bytes],
  elements : Array[Array[Int64]],
) -> Bool {
  let data = FixedArray::makei(data.length(), i => data[i])
  let elements = FixedArray::makei(elements.length(), i => {
    let source = elements[i]
    // Preserve the legacy API's handling of an incomplete trailing pair.
    FixedArray::makei(source.length() / 2 * 2, j => source[j])
  })
  bind_segments(self, data, elements)
}
