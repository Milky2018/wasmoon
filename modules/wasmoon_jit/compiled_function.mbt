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
/// Build a compact stackmap blob for allocation safepoints.
/// Format v1:
///   u32 version (=1)
///   u32 safepoint_count
///   u32 root_count[safepoint_count]
fn compiled_build_gc_stackmap_blob(root_counts : Array[Int]) -> Bytes {
  if root_counts.length() == 0 {
    return b""
  }
  let bytes : Array[Byte] = []
  compiled_append_u32_le(bytes, 1)
  compiled_append_u32_le(bytes, root_counts.length())
  for count in root_counts {
    compiled_append_u32_le(bytes, count)
  }
  Bytes::from_array(bytes)
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
fn compiled_has_stackmap_live_ref_indices(
  safepoints : Array[GcSafepoint],
) -> Bool {
  for safepoint in safepoints {
    if safepoint.live_refs.length() > 0 {
      return true
    }
  }
  false
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

///|
/// A compiled function ready for Wasmoon JIT execution.
pub struct CompiledFunction {
  // Function name or identifier.
  name : String
  // The compiled machine code bytes and metadata.
  code : @machv_emit.MachineCode
  // Entry point offset, usually 0.
  entry_offset : Int
  // Size of the code in bytes.
  code_size : Int
  // Stack frame size needed.
  frame_size : Int
  // GC safepoint metadata for this function.
  gc_safepoints : Array[GcSafepoint]
  // Compact stack-map payload for GC roots.
  gc_stackmap_blob : Bytes
  // Whether this function is currently valid.
  mut valid : Bool
}

///|
pub fn CompiledFunction::CompiledFunction(
  name : String,
  code : @machv_emit.MachineCode,
  frame_size : Int,
  gc_safepoints? : Array[GcSafepoint] = [],
  gc_stackmap_blob? : Bytes = b"",
) -> CompiledFunction {
  let derived_root_counts = code.get_gc_safepoint_root_counts()
  let derived_root_indices = code.get_gc_safepoint_root_indices()
  let resolved_gc_safepoints : Array[GcSafepoint] = if gc_safepoints.length() >
    0 {
    gc_safepoints
  } else {
    let derived : Array[GcSafepoint] = []
    let offsets = code.get_gc_safepoint_offsets()
    for i, offset in offsets {
      let metadata = if i < derived_root_counts.length() {
        derived_root_counts[i].to_int64()
      } else {
        0L
      }
      let live_refs = if i < derived_root_indices.length() {
        derived_root_indices[i]
      } else {
        []
      }
      derived.push(GcSafepoint(offset, live_refs, metadata))
    }
    derived
  }
  let stackmap_root_counts = if derived_root_counts.length() > 0 {
    derived_root_counts
  } else if resolved_gc_safepoints.length() > 0 {
    let counts : Array[Int] = []
    for safepoint in resolved_gc_safepoints {
      counts.push(safepoint_metadata_to_root_count(safepoint.metadata))
    }
    counts
  } else {
    []
  }
  let resolved_gc_stackmap_blob = if gc_stackmap_blob.length() > 0 {
    gc_stackmap_blob
  } else if compiled_has_stackmap_live_ref_indices(resolved_gc_safepoints) {
    compiled_build_gc_stackmap_blob_v2(
      resolved_gc_safepoints, stackmap_root_counts,
    )
  } else {
    compiled_build_gc_stackmap_blob(stackmap_root_counts)
  }
  {
    name,
    code,
    entry_offset: 0,
    code_size: code.size(),
    frame_size,
    gc_safepoints: resolved_gc_safepoints,
    gc_stackmap_blob: resolved_gc_stackmap_blob,
    valid: true,
  }
}

///|
/// Invalidate this compiled function and mark it for recompilation.
pub fn CompiledFunction::invalidate(self : CompiledFunction) -> Unit {
  self.valid = false
}

///|
/// Check if the function is still valid.
pub fn CompiledFunction::is_valid(self : CompiledFunction) -> Bool {
  self.valid
}

///|
/// Get the machine code bytes.
pub fn CompiledFunction::get_code(self : CompiledFunction) -> Array[Int] {
  self.code.get_bytes()
}

///|
/// Get direct function address fixups.
pub fn CompiledFunction::get_func_addr_fixups(
  self : CompiledFunction,
) -> Array[@machv_emit.FuncAddrFixup] {
  self.code.get_func_addr_fixups()
}

///|
/// Get direct function call fixups.
pub fn CompiledFunction::get_call_fixups(
  self : CompiledFunction,
) -> Array[@machv_emit.CallFixup] {
  self.code.get_call_fixups()
}

///|
/// Get GC safepoint metadata for this function.
pub fn CompiledFunction::get_gc_safepoints(
  self : CompiledFunction,
) -> Array[GcSafepoint] {
  self.gc_safepoints
}

///|
/// Get GC stack-map payload bytes for this function.
pub fn CompiledFunction::get_gc_stackmap_blob(self : CompiledFunction) -> Bytes {
  self.gc_stackmap_blob
}

///|
fn CompiledFunction::to_string(self : CompiledFunction) -> String {
  let status = if self.valid { "valid" } else { "invalid" }
  "CompiledFunction(\{self.name}, \{self.code_size} bytes, frame=\{self.frame_size}, safepoints=\{self.gc_safepoints.length()}, \{status})"
}

///|
pub impl Show for CompiledFunction with fn output(self, logger) {
  logger.write_string(self.to_string())
}
