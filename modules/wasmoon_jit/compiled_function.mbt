/// Compiled function lifecycle support owned by Wasmoon JIT.

///|
const STACKMAP_I32_MAX : Int = 0x7FFFFFFF

///|
/// Information about a GC safepoint in generated code.
pub struct GcSafepoint {
  /// Offset in generated machine code where this safepoint is.
  code_offset : Int
  /// Which virtual registers contain live GC references at this point.
  live_refs : Array[Int]
  /// Additional metadata, such as return address for stack unwinding.
  metadata : Int64
} derive(Debug)

///|
pub fn GcSafepoint::GcSafepoint(
  code_offset : Int,
  live_refs : Array[Int],
  metadata : Int64,
) -> GcSafepoint {
  { code_offset, live_refs, metadata }
}

///|
fn compiled_append_u32_le(buf : Array[Byte], value : Int) -> Unit {
  buf.push((value & 0xFF).to_byte())
  buf.push(((value >> 8) & 0xFF).to_byte())
  buf.push(((value >> 16) & 0xFF).to_byte())
  buf.push(((value >> 24) & 0xFF).to_byte())
}

///|
fn safepoint_metadata_to_root_count(metadata : Int64) -> Int {
  if metadata <= 0L {
    return 0
  }
  if metadata > STACKMAP_I32_MAX.to_int64() {
    STACKMAP_I32_MAX
  } else {
    metadata.to_int()
  }
}

///|
fn compiled_encode_stackmap_root_count(root_count : Int) -> Int {
  if root_count <= 0 {
    0
  } else if root_count > STACKMAP_I32_MAX {
    STACKMAP_I32_MAX
  } else {
    root_count
  }
}

///|
/// Build stackmap blob v2 with optional per-safepoint root-index lists.
/// Format v2:
///   u32 version (=2)
///   u32 safepoint_count
///   repeated safepoint_count times:
///     u32 root_count
///     u32 root_index_count
///     u32 root_indices[root_index_count]
fn compiled_build_gc_stackmap_blob_v2(
  safepoints : Array[GcSafepoint],
  default_root_counts : Array[Int],
) -> Bytes {
  if safepoints.length() == 0 {
    return b""
  }
  let bytes : Array[Byte] = []
  compiled_append_u32_le(bytes, 2)
  compiled_append_u32_le(bytes, safepoints.length())
  for i, safepoint in safepoints {
    let default_root_count = if i < default_root_counts.length() {
      default_root_counts[i]
    } else {
      safepoint.live_refs.length()
    }
    let metadata_root_count = safepoint_metadata_to_root_count(
      safepoint.metadata,
    )
    let mut root_count = compiled_encode_stackmap_root_count(
      if metadata_root_count > 0 {
        metadata_root_count
      } else {
        default_root_count
      },
    )
    let valid_indices : Array[Int] = []
    for live_ref in safepoint.live_refs {
      if live_ref >= 0 && live_ref <= STACKMAP_I32_MAX {
        valid_indices.push(live_ref)
      }
    }
    if valid_indices.length() > 0 {
      if root_count <= 0 || root_count > valid_indices.length() {
        root_count = valid_indices.length()
      }
      compiled_append_u32_le(bytes, root_count)
      compiled_append_u32_le(bytes, root_count)
      for idx in 0..<root_count {
        compiled_append_u32_le(bytes, valid_indices[idx])
      }
    } else {
      compiled_append_u32_le(bytes, root_count)
      compiled_append_u32_le(bytes, 0)
    }
  }
  Bytes::from_array(bytes)
}
